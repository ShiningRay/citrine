# M1 示例 1：Counter —— state / computed / 事件绑定 / block 级更新
require_relative "components"
require "citrine/browser"

Citrine::DomRenderer.mount_at("app", Counter.new(title: "M1 · Counter"))
