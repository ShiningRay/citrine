# frozen_string_literal: true

# 单测公共入口（D4）：由 Rakefile 的 `ruby_opts << "-rtest_helper"` 在所有
# 测试文件之前加载——simplecov 必须先于框架代码 require 才能统计覆盖率。
# 覆盖率摘要输出到控制台即可（不上传外部服务，保持零外部依赖门禁）。
begin
  require "simplecov"
  SimpleCov.start do
    skip "/test/"
    skip "/lib/rubocop/"
    skip "/examples/"
  end
rescue LoadError
  # 并行开发或未 bundle install 时缺 simplecov：跳过覆盖率，不阻断测试
  warn "simplecov 未安装，跳过覆盖率统计（bundle install 后可用）"
end

require "minitest/autorun"
