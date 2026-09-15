# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# 框架专属 lint（T-A4）：rubocop + 自定义 cop（见 .rubocop.yml / lib/rubocop）
gem "rubocop", require: false

# 测试覆盖率（D4）：rake 时控制台输出覆盖率摘要（不上传外部服务，保持零外部依赖门禁）
group :test, :development do
  gem "simplecov", require: false
end
