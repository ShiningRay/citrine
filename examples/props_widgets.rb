# S2-2 / S2-4 / S2-1 / S2-3 / S2-6 示例：
# 属性透传（id / disabled / aria-* / data-*）、受控 check_box、IME、
# 元素词表 + 逃生舱、统一事件对象 + stop_propagation + window_key 焦点作用域、autofocus
require "citrine/browser"

# 焦点作用域演示：只有焦点落在本面板内，← → 才驱动计数
class FocusPanel < Citrine::Component
  state :keys, default: 0

  window_key :on_arrow, scope: :focused

  def on_arrow(ev)
    self.keys += 1 if ev.key == "ArrowDown"
  end

  def view
    box(css_class: "panel", id: "panel") do
      text_input(placeholder: "面板内输入", id: "panel-input")
      label(css_class: "panel-keys") { "面板按键 #{keys}" }
    end
  end
end

class PropsWidgets < Citrine::Component
  state :agreed, default: false
  state :draft, default: ""
  state :last, default: "-"
  state :show_zone, default: false

  components FocusPanel

  def view
    stack(gap: 10) do
      button(id: "ok-btn", disabled: !agreed, aria_label: "提交",
             data_role: "primary", on_click: :clear_draft) { "提交" }
      check_box(checked: signal(:agreed), on_change: :noop, id: "agree")
      text_input(value: signal(:draft), on_enter: :clear_draft,
                 id: "draft", placeholder: "写点什么")
      # S2-1：元素词表 + 逃生舱
      ul(id: "lang-list") do
        li(on_click: :clear_draft, id: "lang-ruby") { "Ruby" }
        li { "Opal" }
      end
      a(href: "https://example.com", id: "home-link") { "官网" }
      img(src: "/logo.png", alt: "标志", id: "logo")
      element(:my_widget, id: "custom-one") { label { "自定义标签" } }
      # S2-3：事件面 + 统一事件对象 + stop_propagation
      box(css_class: "probe", id: "probe",
          on_dblclick: ->(_ev) { note "dblclick" },
          on_contextmenu: ->(_ev) { note "contextmenu" },
          on_mouse_enter: ->(_ev) { note "mouseenter" },
          on_wheel: ->(_ev) { note "wheel" },
          on_submit: ->(_ev) { note "submit" },
          on_paste: ->(_ev) { note "paste" },
          on_touch_start: ->(_ev) { note "touchstart" },
          on_pointer_down: ->(_ev) { note "pointerdown" }) do
        label(css_class: "probe-label") { last }
      end
      span(css_class: "event-check", on_click: ->(ev) {
        self.last = ev.is_a?(Citrine::Event) ? "event-view" : "raw"
      }) { "事件对象" }
      span(css_class: "stopper", on_click: ->(ev) {
        ev.stop_propagation
        note "stopped"
      }) { "拦截" }
      # S2-6：焦点原语
      button(on_click: :toggle_zone) { show_zone ? "移除区" : "聚焦区" }
      if show_zone
        box(css_class: "focus-zone", id: "zone", tabindex: "0",
            autofocus: true, aria_label: "区域") do
          label { "聚焦区" }
        end
      end
      focus_panel
    end
  end

  def noop; end

  def clear_draft
    self.draft = ""
  end

  def note(name)
    self.last = name
  end

  def toggle_zone
    self.show_zone = !show_zone
  end
end

Citrine::DomRenderer.mount_at("app", PropsWidgets.new)
