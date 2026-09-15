# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# 框架专属 lint（T-A4）：rubocop + 自定义 cop（见 .rubocop.yml / lib/rubocop）
gem "rubocop", require: false

# 测试覆盖率（D4）：rake 时控制台输出覆盖率摘要（不上传外部服务，保持零外部依赖门禁）
group :test, :development do
  gem "simplecov", ">= 0.21", require: false
end

# Windows 下 listen 的原生文件监听适配器：没有它 listen 退化为轮询，
# dev server 热刷新常驻空转 CPU（macOS/Linux 用系统事件，不需要此 gem）
gem "wdm", ">= 0.1.0", platforms: [:mswin, :windows], require: false if Gem.win_platform?
