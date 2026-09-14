# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new do |t|
  t.libs << "test"
  t.test_files = FileList["test/*_test.rb"]
  t.warning = false
end

desc "编译示例并运行 Node 桩验收"
task :stubs do
  Dir.chdir("examples") do
    # T-A1：产物默认不带内联 source map（约占体积 63%）；调试用 `opal -c -P` 产外置 map
    %w[counter todo reactive_props keyed_list props_widgets canvas_counter canvas_todo].each do |name|
      sh "opal -c --no-source-map -I../lib -I. -o #{name}.js #{name}.rb"
    end
    sh "node stub_check.js counter"
    sh "node stub_check.js todo"
    sh "node stub_check.js reactive_props"
    sh "node stub_check.js keyed_list"
    sh "node stub_check.js props_widgets"
    sh "node canvas_stub_check.js counter"
    sh "node canvas_stub_check.js todo"
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

