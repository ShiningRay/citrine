# 响应式属性示例（G-2）：props 传 Proc，订阅收敛到节点本身
require_relative "components"
require "citrine/browser"

Citrine::DomRenderer.mount_at("app", SelectionGrid.new)
