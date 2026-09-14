# frozen_string_literal: true

# M3 演示：同一份组件代码（examples/components.rb），在 CRuby 下
# render-to-string——与浏览器（Opal + DomRenderer）共用同一组件定义。
require_relative "components"
require "citrine/string_renderer"

puts Citrine::StringRenderer.render(Counter.new(title: "SSR · Counter"))
puts

todo = TodoApp.new
todo.items = [
  { text: "来自 CRuby 的 SSR", done: false },
  { text: "第二个待办（已完成）", done: true }
]
puts Citrine::StringRenderer.render(todo)
