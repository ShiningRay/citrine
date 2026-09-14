# frozen_string_literal: true

# Citrine 开发服务器（T-B1 瘦身版：Rack + Puma + Listen 替代手写 socket 服务）。
#
# 功能（与旧版行为等价）：
#   - 静态服务指定目录（html/css/…），"/" 提供目录索引
#   - *.js 请求按对应 *.rb 现场编译（Opal CLI），带失效缓存
#   - 监听 lib/ 与目录下 .rb/.css 变更，经 SSE 通知浏览器整页刷新
#   - 编译失败时返回错误浮层脚本（页面不再白屏）
#   - 样式资产注入（Citrine.css → <link>；Citrine.css_text → <style>）
#
# 用法：bin/citrine dev [目录] [-p 端口] [-I 加载路径]
#
# 旧版自建五件事（socket 静态服务 / 轮询监听 / 缓存失效 / SSE / 浮层），
# 瘦身后 HTTP 交给 Rack + Puma、文件监听交给 Listen，只保留应用语义
# （现场编译、错误浮层、样式资产注入）。
require "rack"
require "puma"
require "puma/server"
require "listen"
require "json"
require "open3"
require "tmpdir"

require "citrine/theme" # 样式资产注册表（Citrine.css / css_text）

module Citrine
  class DevServer
    CONTENT_TYPES = {
      "html" => "text/html; charset=utf-8",
      "js"   => "application/javascript",
      "css"  => "text/css",
      "png"  => "image/png",
      "svg"  => "image/svg+xml",
      "map"  => "application/json"
    }.freeze

    CLIENT_JS = <<~'JS'
      (function () {
        var overlay = null;
        window.__rvShowError = function (msg) {
          if (!overlay) {
            overlay = document.createElement("pre");
            overlay.style.cssText =
              "position:fixed;z-index:99999;top:0;left:0;right:0;margin:0;padding:12px;" +
              "background:#b91c1c;color:#fff;font:13px/1.5 monospace;white-space:pre-wrap;" +
              "max-height:60vh;overflow:auto;";
            document.documentElement.appendChild(overlay);
          }
          overlay.textContent = "⚠ Citrine 编译错误（修正并保存即自动恢复）\n\n" + msg;
        };
        window.__rvClearError = function () {
          if (overlay) { overlay.remove(); overlay = null; }
        };
        var es = new EventSource("/__rv_reload");
        es.onmessage = function (e) {
          if (e.data === "reload") { window.__rvClearError(); location.reload(); }
        };
      })();
    JS

    # 命令行解析（纯函数，便于单测）：返回 [目录, 端口, 额外加载路径]
    def self.parse_args(args)
      dir = nil
      port = 4402
      extra_libs = []
      i = 0
      while i < args.length
        arg = args[i]
        if arg == "-p"
          port = args[i + 1].to_i
          i += 2
        elsif arg == "-I"
          value = args[i + 1]
          raise ArgumentError, "-I 需要一个加载路径参数（如 -I ../some-lib/lib）" if value.nil? || value.start_with?("-")

          extra_libs << value
          i += 2
        elsif arg.start_with?("-I")
          extra_libs << arg[2..]
          i += 1
        elsif arg !~ /\A-/
          dir = arg
          i += 1
        else
          i += 1
        end
      end
      [dir || "examples", port, extra_libs]
    end

    def self.run!(args)
      dir, port, extra_libs = parse_args(args)
      new(dir, port, extra_libs).start
    end

    def initialize(dir, port, extra_libs = [])
      @dir = File.expand_path(dir)
      @root = File.expand_path("../..", __dir__) # 项目根（dev_server.rb 位于 lib/citrine/）
      # 额外加载路径（-I 可重复）：跨仓库示例（如组件库的 examples/）编译时
      # 需要补上那个仓库的 lib；转绝对路径——编译 cwd 是源文件所在目录
      @extra_libs = extra_libs.map { |p| File.expand_path(p) }
      @port = port
      @clients = [] # 每个 SSE 连接一个 Queue
      @cache = {}   # js 路径 => body（Listen 事件触发时整体清空）
      @mutex = Mutex.new
    end

    def start
      raise "目录不存在: #{@dir}" unless File.directory?(@dir)

      watch
      puma = Puma::Server.new(rack_app)
      puma.add_tcp_listener "127.0.0.1", @port
      puts "Citrine dev server → http://localhost:#{@port}/"
      puts "  目录: #{@dir}；监听 lib/**/*.rb 与该目录 **/*.{rb,css}"
      puma.run
      sleep # Puma 在后台线程受理连接，主线程挂起
    end

    private

    # ── 文件监听（Listen 替代 0.3s 轮询）──────────────────────

    def watch
      sources = [File.join(@root, "lib"), @dir].select { |p| File.directory?(p) }
      listener = Listen.to(*sources, only: /\.(rb|css)$/) do |modified, added, _removed|
        @mutex.synchronize { @cache.clear }
        names = (modified + added).map { |f| f.delete_prefix("#{@root}/") }
        puts "[citrine] 变更: #{names.join(', ')} → 通知刷新"
        broadcast("reload")
      end
      listener.start
    end

    def broadcast(message)
      @mutex.synchronize { @clients.dup }.each { |queue| queue << message }
    end

    # ── Rack 应用 ──────────────────────────────────────────

    def rack_app
      @rack_app ||= ->(env) { route(env) }
    end

    def route(env)
      path = Rack::Request.new(env).path
      return sse(env) if path == "/__rv_reload"
      return respond(200, "application/javascript", CLIENT_JS) if path == "/__rv_client.js"
      return index if path == "/"

      route_file(path)
    rescue StandardError => e
      respond(500, "text/plain; charset=utf-8", "#{e.class}: #{e.message}")
    end

    def route_file(path)
      full = File.expand_path(File.join(@dir, path.delete_prefix("/")))
      unless full.start_with?(@dir) && File.file?(full)
        return respond(404, "text/plain; charset=utf-8", "not found: #{path}")
      end

      if path.end_with?(".js")
        rb = full.sub(/\.js$/, ".rb")
        return serve_compiled(path, rb) if File.exist?(rb)
      end

      body = File.binread(full)
      type = CONTENT_TYPES[full.split(".").last] || "application/octet-stream"
      if full.end_with?(".html")
        body = inject_client(body)
        type = CONTENT_TYPES["html"]
      end
      respond(200, type, body)
    end

    def serve_compiled(path, rb_full)
      cached = @cache[path]
      return respond(200, "application/javascript", cached) if cached

      tmp = File.join(Dir.tmpdir, "rv_dev_#{Process.pid}_#{rand(1_000_000)}.js")
      # 与手工编译完全一致的形态：cwd = 源文件所在目录，-I附着式传参
      includes = ["-I#{File.join(@root, 'lib')}", "-I."] + @extra_libs.map { |p| "-I#{p}" }
      out, err, status = Open3.capture3(
        "opal", "-c", *includes,
        "-o", tmp, File.basename(rb_full),
        chdir: File.dirname(rb_full)
      )
      if status.success?
        body = File.binread(tmp)
        @mutex.synchronize { @cache[path] = body }
        respond(200, "application/javascript", body)
      else
        message = (out + "\n" + err).strip.to_json
        respond(200, "application/javascript",
                "window.__rvShowError(#{message});")
      end
    ensure
      File.unlink(tmp) if tmp && File.exist?(tmp)
    end

    def index
      pages = Dir.glob(File.join(@dir, "*.html")).map { |f| File.basename(f) }.sort
      links = pages.map { |p| %(<li><a href="/#{p}">#{p}</a></li>) }.join("\n")
      body = <<~HTML
        <!DOCTYPE html>
        <html lang="zh"><head><meta charset="utf-8"><title>Citrine dev</title></head>
        <body style="font-family:sans-serif;padding:24px;line-height:1.8">
          <h2>Citrine dev server</h2>
          <p>修改 lib/ 或本目录下的 .rb / .css 文件并保存，浏览器将自动刷新。</p>
          <ul>#{links}</ul>
        </body></html>
      HTML
      respond(200, CONTENT_TYPES["html"], body)
    end

    def inject_client(html)
      # S2-5：先把声明的样式资产（<link> / <style>）注入 <head>
      html = inject_head_assets(html)
      # CITRINE_DEV：开发模式标志（布局提醒等只在开发期输出；生产构建不注入）
      script = %(<script>window.CITRINE_DEV = true;</script>\n<script src="/__rv_client.js"></script>)
      return html.sub("</head>", "#{script}</head>") if html.include?("</head>")

      html.sub("</body>", "#{script}</body>")
    end

    # S2-5：样式资产注入——Citrine.css 声明的样式表（<link>）与
    # Citrine.css_text 自定义样式文本（<style>，媒体查询/伪类的逃生舱）。
    # 纯函数（便于单测）：只改传入的 html，不读文件系统。
    def inject_head_assets(html)
      assets = Citrine.css_files.map { |f| %(<link rel="stylesheet" href="/#{f}">) }
      assets << "<style>#{Citrine.css_text}</style>" if Citrine.css_text && !Citrine.css_text.empty?
      return html if assets.empty?

      block = assets.join("\n")
      return html.sub("</head>", "#{block}\n</head>") if html.include?("</head>")

      html.sub("</body>", "#{block}\n</body>")
    end

    # ── SSE 热刷新（rack.hijack 接管连接）────────────────────

    def sse(env)
      io = env["rack.hijack"].call
      io.write "HTTP/1.1 200 OK\r\n" \
               "Content-Type: text/event-stream\r\n" \
               "Cache-Control: no-cache\r\n" \
               "Connection: keep-alive\r\n\r\n"
      queue = Queue.new
      @mutex.synchronize { @clients << queue }
      Thread.new do
        loop do
          message = queue.pop
          io.write "data: #{message}\n\n"
        end
      rescue StandardError
        @mutex.synchronize { @clients.delete(queue) } # 连接断开时清理
      end
      [-1, {}, []] # 已劫持连接，Rack 不再处理响应
    end

    def respond(status, type, body)
      [status, {"Content-Type" => type, "Content-Length" => body.bytesize.to_s}, [body]]
    end
  end
end
