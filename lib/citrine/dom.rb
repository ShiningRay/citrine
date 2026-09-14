# backtick_javascript: true
# frozen_string_literal: true

require "native"
require "citrine"
require "citrine/renderer"

module Citrine
  # Web DOM 渲染器（Opal 环境）：实现 Renderer 的平台钩子。
  class DomRenderer < Renderer
    def initialize
      @document = Native(`window.document`)
      super()
    end

    def self.mount_at(element_id, component)
      # F2：一页多根时复用同一渲染器实例（"最后挂载者胜出"会清空先挂载的组件）
      unless Citrine.renderer.is_a?(DomRenderer)
        Citrine.renderer = new
      end
      Citrine.mount(component, Citrine.renderer.document_element(element_id))
    end

    def document_element(element_id)
      @document.getElementById(element_id)
    end

    private

    def setup_root(root, element)
      root.dom = element.is_a?(Native::Object) ? element : Native(element)
    end

    def create_dom(node)
      @document.createElement(TAGS[node.type] || node.type.to_s)
    end

    def attach(node, parent)
      parent.dom.appendChild(node.dom)
    end

    def detach(node)
      parent_dom = node.dom[:parentElement]
      parent_dom.removeChild(node.dom) if parent_dom
    end

    # 幂等：响应式属性重跑时会再次调用（见 Renderer#mount）
    def apply_props(node)
      el = node.dom
      if node.props.key?(:css_class)
        el[:className] = prop_value(node, node.props[:css_class]).to_s
      end
      el[:placeholder] = prop_value(node, node.props[:placeholder]).to_s if node.props.key?(:placeholder)

      style = resolve_style(node)
      # 响应式 style 换掉整份内联样式：先清掉本次不再出现的旧键（错误态高亮必须能消失）
      track_style_keys(node, style.keys).each { |key| el[:style][Style.camel(key)] = "" }
      style.each { |key, value| el[:style][Style.camel(key)] = value.to_s }
    end

    # 事件监听只在挂载时绑定一次（不参与响应式属性重跑）。
    # 注意：每个处理器用独立局部变量——block 捕获的是变量本身，复用变量会让先绑定的
    # 回调读到后来被覆盖的值（桩验收抓过一次真 bug）。
    def bind_events(node)
      owner = node.owner

      on_click = node.props[:on_click]
      if on_click
        node.dom.addEventListener("click", ->(event) { owner.handle_event(on_click, Native(event)) })
      end

      on_key = node.props[:on_key]
      if on_key
        node.dom.addEventListener("keydown", ->(event) { owner.handle_key(on_key, key_event(event)) })
      end

      on_focus = node.props[:on_focus]
      if on_focus
        node.dom.addEventListener("focus", ->(event) { owner.handle_event(on_focus, Native(event)) })
      end

      on_blur = node.props[:on_blur]
      if on_blur
        node.dom.addEventListener("blur", ->(event) { owner.handle_event(on_blur, Native(event)) })
      end
    end

    # 全局键盘（G-9）：window 级 keydown，绑定组件生命周期（卸载时由 unmount_component 解绑）
    def register_window_key(component, handler)
      win = Native(`window`)
      listener = ->(event) { component.handle_key(handler, key_event(event)) }
      win.addEventListener("keydown", listener)
      @window_keys ||= {}
      (@window_keys[component] ||= []) << listener
    end

    def unregister_window_keys(component)
      listeners = @window_keys && @window_keys.delete(component)
      return unless listeners

      win = Native(`window`)
      listeners.each { |listener| win.removeEventListener("keydown", listener) }
    end

    # 原生事件 → Citrine::KeyEvent（平台无关视图；需要的原生细节走 #raw）
    def key_event(event)
      ev = Native(event)
      KeyEvent.new(ev[:key],
                   shift: ev[:shiftKey] == true, meta: ev[:metaKey] == true,
                   ctrl: ev[:ctrlKey] == true, alt: ev[:altKey] == true,
                   raw: ev, prevent_default: -> { ev.preventDefault })
    end

    def set_text(node, text)
      node.dom[:textContent] = text.to_s
    end

    def setup_widget(node)
      case node.type
      when :text_input then setup_text_input(node)
      when :check_box  then setup_check_box(node)
      end
    end

    def setup_text_input(node)
      el = node.dom
      el[:type] = "text"
      value = node.props[:value]
      if value.is_a?(Signal)
        node.owned_effects << Effect.create { el[:value] = value.get.to_s }
        el.addEventListener("input", ->(_event) { value.set(el[:value]) })
      elsif value.is_a?(String)
        # F20：字面量初值也要落到 DOM，保持与 SSR 输出一致
        el[:value] = value
      end
      handler = node.props[:on_enter]
      return unless handler

      el.addEventListener("keydown", ->(event) {
        ev = Native(event)
        node.owner.handle_event(handler, ev) if ev[:key] == "Enter"
      })
    end

    def setup_check_box(node)
      el = node.dom
      el[:type] = "checkbox"
      checked = node.props[:checked]
      if checked.is_a?(Signal)
        # F19：Signal 驱动的勾选态要读信号并保持响应，而不是把对象当 truthy
        node.owned_effects << Effect.create { el[:checked] = checked.get ? true : false }
      else
        el[:checked] = checked ? true : false
      end
      handler = node.props[:on_change]
      return unless handler

      el.addEventListener("change", ->(_event) {
        node.owner.handle_event(handler, el[:checked])
      })
    end
  end
end
