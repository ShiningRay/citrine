# M3 可移植性演示 2：Todo 画到 Canvas（列表/勾选/删除/prompt 输入）
require_relative "components"
require "citrine/canvas"

todo = TodoApp.new
todo.items = [
  { text: "画布上的待办", done: false },
  { text: "已完成的一条", done: true }
]
Citrine::CanvasRenderer.mount_at("app", todo)
