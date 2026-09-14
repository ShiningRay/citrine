# frozen_string_literal: true

require "rake/testtask"
require "json"
require "bundler/gem_tasks" # rake build / rake release（T-A3 发布路径；发布走 Trusted Publishing）

Rake::TestTask.new do |t|
  t.libs << "test"
  t.test_files = FileList["test/*_test.rb"]
  t.warning = false
end

desc "编译示例并运行 Node 桩验收"
task :stubs do
  Dir.chdir("examples") do
    # T-A1：产物默认不带内联 source map（约占体积 63%）；调试用 `opal -c -P` 产外置 map
    %w[counter todo reactive_props keyed_list props_widgets canvas_wrap canvas_counter canvas_todo].each do |name|
      sh "opal -c --no-source-map -I../lib -I. -o #{name}.js #{name}.rb"
    end
    sh "node stub_check.js counter"
    sh "node stub_check.js todo"
    sh "node stub_check.js reactive_props"
    sh "node stub_check.js keyed_list"
    sh "node stub_check.js props_widgets"
    sh "node canvas_stub_check.js counter"
    sh "node canvas_stub_check.js todo"
    sh "node canvas_stub_check.js wrap"
  end
end

desc "Lint（T-A4）：框架专属 cop 门禁（组件内裸 @ivar 赋值绕过信号追踪）"
task :lint do
  sh "bundle exec rubocop --format simple"
end

desc "产物体积守卫（T-A1）：无 map 编译 + esbuild 压缩，gzip 后 ≤ 300KB（GOALS P1 目标）"
task :size do
  Dir.chdir("examples") do
    sh "opal -c --no-source-map -I../lib -I. -o counter.js counter.rb"
    if system("npx --no-install esbuild --version > /dev/null 2>&1")
      sh "npx --no-install esbuild counter.js --minify --target=es2015 --allow-overwrite --outfile=counter.min.js"
    else
      warn "  (esbuild 不可用，跳过压缩，仅校验未压缩体积)"
    end
    checked = File.exist?("counter.min.js") ? "counter.min.js" : "counter.js"
    gz = `gzip -c #{checked} | wc -c`.to_i
    puts "  #{checked} gzip = #{gz} bytes（预算 300_000）"
    raise "产物 gzip 体积 #{gz} 超过 300KB 预算" if gz > 300_000
  ensure
    File.delete("counter.min.js") if File.exist?("counter.min.js")
  end
end

desc "source map 断言（T-A1）：带 map 编译时 sources 必须指回 .rb（线上错误可还原到 Ruby 行号的根基）"
task :map_check do
  Dir.chdir("examples") do
    sh "opal -c -I../lib -I. -o counter.js counter.rb"
    body = File.read("counter.js")
    match = body.match(/sourceMappingURL=data:application\/json;base64,([A-Za-z0-9+\/=]+)/)
    raise "产物里没有内联 source map（--no-source-map 不适用于本任务）" unless match

    require "json"
    require "base64"
    map = JSON.parse(Base64.decode64(match[1]))
    # Opal 可能产出 indexed source map（sections 内嵌各段 map）
    sources = map["sources"] ||
              map["sections"].to_a.flat_map { |sec| sec.dig("map", "sources") }.compact
    raise "source map 的 sources 不含 .rb：#{sources.first(3).inspect}" unless sources.any? { |s| s.end_with?(".rb") }

    puts "  source map sources 指回 .rb ✓（#{sources.grep(/\.rb\z/).size} 项）"
  end
end

desc "真实浏览器布局守卫（T-A2）：headless Chrome 打开守卫页，量尺寸断言"
task :browser do
  chrome = ENV["CHROME_BIN"] || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  raise "找不到 Chrome（可用 CHROME_BIN 指定路径）" unless File.exist?(chrome)

  Dir.chdir("examples") do
    sh "opal -c --no-source-map -I../lib -I. -o browser_check.js browser_check.rb"
  end

  page = File.expand_path("examples/browser_check.html")
  dom = `"#{chrome}" --headless=new --disable-gpu --no-first-run --virtual-time-budget=3000 --dump-dom "file://#{page}"`
  match = dom.match(%r{<pre id="browser-report">([^<]+)</pre>})
  raise "浏览器没有产出布局报告（页面加载失败？）" unless match

  report = JSON.parse(match[1])
  raise "容器塌陷：stack 宽度为 0" unless report["stack_width"] > 0
  raise "容器塌陷：stack 高度为 0" unless report["stack_height"] > 0
  raise "同层兄弟 top 相等（应纵向排列）" unless report["top_distinct"]

  puts "  布局守卫通过：#{report.inspect}"
end

desc "生产产物断言（T-B3）：不 require citrine/debug 的产物不含埋点字符串"
task :prod_check do
  Dir.chdir("examples") do
    sh "opal -c --no-source-map -I../lib -I. -o counter.js counter.rb"
  end
  body = File.read("examples/counter.js")
  needles = ["debug_dependency_graph", "debug_tracking", "citrine/debug"]
  needles.each do |needle|
    raise "生产产物包含 DevTools 埋点字符串: #{needle}" if body.include?(needle)
  end
  puts "  生产产物无埋点字符串 ✓（#{needles.join(', ')}）"
end

desc "DOM/Canvas 等价断言（T-B2）：同一 Counter 组件双渲染器输出，文本序列与布局守卫"
task :canvas_parity do
  chrome = ENV["CHROME_BIN"] || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  raise "找不到 Chrome（可用 CHROME_BIN 指定路径）" unless File.exist?(chrome)

  Dir.chdir("examples") do
    sh "opal -c --no-source-map -I../lib -I. -o canvas_dom_parity.js canvas_dom_parity.rb"
  end

  page = File.expand_path("examples/canvas_dom_parity.html")
  dom = `"#{chrome}" --headless=new --disable-gpu --no-first-run --virtual-time-budget=3000 --dump-dom "file://#{page}"`
  match = dom.match(%r{<pre id="parity-report">([^<]+)</pre>})
  raise "等价页没有产出报告（页面加载失败？）" unless match

  report = JSON.parse(match[1])
  raise "文本序列不等价：DOM=#{report['dom_texts'].inspect} Canvas=#{report['canvas_texts'].inspect}" unless report["texts_equal"]
  raise "DOM 容器尺寸下限不满足" unless report["dom_ok"]
  raise "Canvas 容器尺寸下限不满足" unless report["canvas_ok"]
  raise "列向兄弟 top 未递增" unless report["column_y_increasing"]
  raise "text_input 覆盖层缺失" unless report["overlay_input_present"]
  raise "覆盖层输入未写回 Signal" unless report["input_synced"]

  puts "  DOM/Canvas 等价断言通过（文本序列 / 尺寸下限 / top 递增 / 输入覆盖层）"
end

task default: :test

desc "数值工具跨平台一致性：CRuby 与 Opal 输出逐字节比对（G-11）"
task :parity do
  mkdir_p "tmp"
  cruby = "tmp/num_cruby.txt"
  opal = "tmp/num_opal.txt"
  sh "ruby -Ilib examples/num_parity.rb > #{cruby}"
  sh "opal -c -Ilib -o tmp/num_parity.js examples/num_parity.rb"
  sh "node tmp/num_parity.js > #{opal}"

  next puts "parity OK：两侧输出一致（#{File.readlines(cruby).size} 行）" if File.read(cruby) == File.read(opal)

  sh "diff -u #{cruby} #{opal}" do |ok, _|
    ok # diff 的退出码非 0 不代表 Rake 失败，下面统一 abort
  end
  abort "parity 失败：数值工具在 CRuby 与 Opal 下输出不一致（见上）"
end

