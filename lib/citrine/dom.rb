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

    # 事件监听只在挂载时绑定一次（不参与响应式属性重跑）
    def bind_events(node)
      handler = node.props[:on_click]
      return unless handler

      node.dom.addEventListener("click", ->(event) {
        node.owner.handle_event(handler, Native(event))
      })
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
