# frozen_string_literal: true

require_relative "lib/citrine/version"

Gem::Specification.new do |spec|
  spec.name = "citrine"
  spec.version = Citrine::VERSION
  spec.authors = ["ShiningRay"]
  spec.email = ["shiningray@users.noreply.github.com"]

  spec.summary = "Signal-based reactive UI framework for Ruby, powered by Opal"
  spec.description = "Citrine（黄水晶）：信号式响应 UI 框架。用纯 Ruby 写组件" \
    "（state / computed 宏 + 赋值即更新），经 Opal 编译后渲染到浏览器 DOM、" \
    "Canvas 与桌面（macOS .app）。水晶振荡器是信号的源头——名字致敬 Opal " \
    "开启的 Ruby→Web 宝石谱系。"

  spec.homepage = "https://github.com/ShiningRay/citrine"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.files = Dir["lib/**/*.rb"] + %w[bin/citrine desktop/main.swift README.md LICENSE]
  spec.bindir = "bin"
  spec.executables = ["citrine"]
  spec.require_paths = ["lib"]

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/GOALS.md"

  spec.add_development_dependency "opal", "~> 1.8"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
