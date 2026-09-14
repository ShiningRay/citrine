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
    %w[counter todo canvas_counter canvas_todo].each do |name|
      sh "opal -c -I../lib -I. -o #{name}.js #{name}.rb"
    end
    sh "node stub_check.js counter"
    sh "node stub_check.js todo"
    sh "node canvas_stub_check.js counter"
    sh "node canvas_stub_check.js todo"
  end
end

task default: :test
