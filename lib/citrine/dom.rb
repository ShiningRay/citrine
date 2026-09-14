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
      Citrine.renderer = new
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

    def apply_props(node)
      el = node.dom
      el[:className] = node.props[:css_class] if node.props[:css_class]
      el[:placeholder] = node.props[:placeholder] if node.props[:placeholder]
      resolve_style(node).each { |key, value| el[:style][Style.camel(key)] = value.to_s }

      handler = node.props[:on_click]
      return unless handler

      el.addEventListener("click", ->(event) {
        node.owner.handle_event(handler, Native(event))
      })
    end

    def set_text(node, text)
      node.dom[:textContent] = text
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
      signal = node.props[:value]
      if signal.is_a?(Signal)
        node.owned_effects << Effect.create { el[:value] = signal.get }
        el.addEventListener("input", ->(_event) { signal.set(el[:value]) })
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
      el[:checked] = node.props[:checked] ? true : false
      handler = node.props[:on_change]
      return unless handler

      el.addEventListener("change", ->(_event) {
        node.owner.handle_event(handler, el[:checked])
      })
    end
  end
end
