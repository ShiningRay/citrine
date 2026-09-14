# backtick_javascript: true
# frozen_string_literal: true

# Citrine 官网 — 一个最小的"用框架自己写"演示：
# 页尾的构建徽章由 Citrine 组件渲染（同样的信号机制在驱动）
require "citrine/browser"

class BuildBadge < Citrine::Component
  state :version, default: "v0.1.0"
  state :ruby, default: "Ruby ≥ 3.0"

  def view
    box(direction: :row, gap: 8, style: {
      display: "flex", align_items: "center"
    }) do
      box(style: {
        background: "#16181d", color: "#fff", border_radius: 6,
        padding: "3px 10px", font_size: "12px"
      }) { label(style: { color: "#fff", font_size: "12px" }) { "citrine | #{version}" } }
      box(style: {
        background: "linear-gradient(135deg,#667eea,#764ba2)", color: "#fff",
        border_radius: 6, padding: "3px 10px"
      }) { label(style: { color: "#fff", font_size: "12px" }) { ruby } }
    end
  end
end

# 挂到页脚（元素由静态 HTML 提供）
el = Native(`window.document`).getElementById("badge")
if el
  renderer = Citrine::DomRenderer.new
  renderer.mount_component(BuildBadge.new, el)
end
