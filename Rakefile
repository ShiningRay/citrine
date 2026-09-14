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
    %w[counter todo reactive_props canvas_counter canvas_todo].each do |name|
      sh "opal -c -I../lib -I. -o #{name}.js #{name}.rb"
    end
    sh "node stub_check.js counter"
    sh "node stub_check.js todo"
    sh "node stub_check.js reactive_props"
    sh "node canvas_stub_check.js counter"
    sh "node canvas_stub_check.js todo"
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

