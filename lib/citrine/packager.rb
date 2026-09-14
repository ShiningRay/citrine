# frozen_string_literal: true

# Citrine 打包器（macOS v1）：把示例打成双击可运行的 .app
# 结构：build/<Name>.app/{MacOS/<Name>, Resources/{index.html, <name>.js}, Info.plist}
require "open3"
require "fileutils"

module Citrine
  class Packager
    def self.run!(args)
      if args.empty?
        abort <<~USAGE
          用法: bin/citrine package <示例名>
          示例: bin/citrine package counter   # 打包 examples/counter
        USAGE
      end
      new(args.first).package
    end

    def initialize(name, dir: "examples")
      @name = name
      @dir = File.expand_path(dir)
      @root = File.expand_path("../..", __dir__)
      @app_name = "Citrine" + @name.split("_").map(&:capitalize).join
    end

    def package
      rb = File.join(@dir, "#{@name}.rb")
      html_path = File.join(@dir, "#{@name}.html")
      abort "找不到 #{rb} 或 #{html_path}" unless File.exist?(rb) && File.exist?(html_path)

      app_dir = File.join(@root, "build", "#{@app_name}.app")
      FileUtils.rm_rf(app_dir)
      macos_dir = File.join(app_dir, "Contents", "MacOS")
      res_dir = File.join(app_dir, "Contents", "Resources")
      FileUtils.mkdir_p([macos_dir, res_dir])

      puts "[package] 编译 #{@name}.rb …"
      js = File.join(res_dir, "#{@name}.js")
      compile_js(rb, js)

      puts "[package] 复制资源 …"
      FileUtils.cp(html_path, File.join(res_dir, "index.html"))

      puts "[package] 编译 Swift 壳 …"
      exe = File.join(macos_dir, @app_name)
      swift_build(exe)

      File.write(File.join(app_dir, "Contents", "Info.plist"), info_plist)
      puts "[package] 完成 → #{app_dir}"
      puts "  运行: open #{app_dir}"
      puts "  开发模式: #{exe} --dev http://localhost:4402/#{@name}.html（需先 bin/citrine dev）"
      app_dir
    end

    private

    def compile_js(rb, output)
      out, err, status = Open3.capture3(
        "opal", "-c",
        "-I#{File.join(@root, 'lib')}", "-I#{@dir}",
        "-o", output, File.basename(rb),
        chdir: @dir
      )
      return if status.success?

      abort "编译失败:\n#{out}\n#{err}"
    end

    def swift_build(output)
      out, err, status = Open3.capture3(
        "swiftc", "-framework", "Cocoa", "-framework", "WebKit",
        "-o", output, File.join(@root, "desktop", "main.swift")
      )
      return if status.success?

      abort "Swift 编译失败:\n#{out}\n#{err}"
    end

    def info_plist
      <<~PLIST
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>CFBundleName</key>
          <string>#{@app_name}</string>
          <key>CFBundleDisplayName</key>
          <string>#{@app_name}</string>
          <key>CFBundleIdentifier</key>
          <string>dev.rubyreact.#{@app_name.downcase}</string>
          <key>CFBundleVersion</key>
          <string>0.1.0</string>
          <key>CFBundleShortVersionString</key>
          <string>0.1.0</string>
          <key>CFBundlePackageType</key>
          <string>APPL</string>
          <key>CFBundleExecutable</key>
          <string>#{@app_name}</string>
          <key>LSMinimumSystemVersion</key>
          <string>11.0</string>
          <key>NSHighResolutionCapable</key>
          <true/>
          <key>NSPrincipalClass</key>
          <string>NSApplication</string>
        </dict>
        </plist>
      PLIST
    end
  end
end
