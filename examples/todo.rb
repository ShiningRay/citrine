# M1 示例 2：Todo —— 列表（v1 整体替换语义）、受控输入、checkbox、删除
require_relative "components"
require "citrine/browser"

Citrine::DomRenderer.mount_at("app", TodoApp.new)
