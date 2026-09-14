# M3 可移植性演示 1：Counter 画到 Canvas——组件代码与 DOM 版零差异
require_relative "components"
require "citrine/canvas"

Citrine::CanvasRenderer.mount_at("app", Counter.new(title: "Canvas · Counter"))
