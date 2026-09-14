# S2-2 / S2-4 示例：属性透传（id / disabled / aria-* / data-*）、
# 受控 check_box（Signal 双向绑定）、IME 组合期 Enter 不触发 on_enter
require "citrine/browser"

class PropsWidgets < Citrine::Component
  state :agreed, default: false
  state :draft, default: ""

  def view
    stack(gap: 10) do
      button(id: "ok-btn", disabled: !agreed, aria_label: "提交",
             data_role: "primary", on_click: :clear_draft) { "提交" }
      check_box(checked: signal(:agreed), on_change: :noop, id: "agree")
      text_input(value: signal(:draft), on_enter: :clear_draft,
                 id: "draft", placeholder: "写点什么")
    end
  end

  def noop; end

  def clear_draft
    self.draft = ""
  end
end

Citrine::DomRenderer.mount_at("app", PropsWidgets.new)
