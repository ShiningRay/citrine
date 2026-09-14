# frozen_string_literal: true

require "citrine"
require "citrine/renderer"

module Citrine
  # render-to-string 渲染器：纯 CRuby 可用（SSR / 单测 / 快照）。
  #
  # 一次性渲染：不建立 Effect 订阅（reactive? = false）；
  # 事件处理器不序列化（SSR 交互不在本渲染器范围）。
  class StringRenderer < Renderer
    class << self
      def render(component)
        new.mount_component(component, nil).children.map(&:dom).join
      end
    end

    private

    def reactive?
      false
    end

    def setup_root(root, _element)
      root.dom = ""
    end

    def create_dom(_node)
      ""
    end

    def apply_props(_node); end

    def attach(_node, _parent); end

    def detach(_node); end

    def set_text(node, text)
      node.text = text
    end

    def setup_widget(_node); end

    # SSR 无宿主概念：portal 内容按逻辑位置内联输出
    def resolve_portal_host(_target)
      ""
    end

    def finalize(node)
      if node.type == :fragment || node.type == :portal || node.type == :suspense
        # 透明容器（S1-4 / S1-5 / S1-10）：SSR 侧都按子根依次拼接
        #（SSR 无宿主概念，portal 内容按逻辑位置内联输出；suspense 只输出当前分支）
        node.dom = node.children.map(&:dom).join
        node.dom += escape_html(node.text) if node.text
        return
      end
      return if node.type == :root

      node.dom = serialize(node)
    end

    def serialize(node)
      tag = TAGS[node.type] || node.type.to_s
      attrs = attributes(node)
      return "<#{tag}#{attrs}>" if VOID.include?(node.type)

      inner = node.children.map(&:dom).join
      inner += escape_html(node.text) if node.text
      "<#{tag}#{attrs}>#{inner}</#{tag}>"
    end

    def attributes(node)
      out = []
      # 响应式属性在 SSR 侧只求值一次（无订阅、无重跑，与 DOM 输出保持一致）
      css_class = prop_value(node, node.props[:css_class])
      # 属性值必须转义：值里出现引号会提前闭合属性，把数据变成新属性（属性注入）。
      out << %(class="#{escape_html(css_class)}") if css_class
      case node.type
      when :text_input
        out << %(type="#{escape_html(node.props[:type] || "text")}")
        if (placeholder = prop_value(node, node.props[:placeholder]))
          out << %(placeholder="#{escape_html(placeholder)}")
        end
        value = node.props[:value]
        value = value.get if value.is_a?(Signal)
        out << %(value="#{escape_html(value)}") if value && value != ""
      when :check_box
        out << 'type="checkbox"'
        checked = node.props[:checked]
        checked = checked.get if checked.is_a?(Signal)
        out << "checked" if checked
      end
      # S2-2：未消费属性原样透传，口径与 DOM 一致（kebab-case；true → 空值属性；
      # false / nil 不输出）。值同样要转义——理由与 class 相同。
      passthrough_props(node).each do |name, value|
        out << (value.empty? ? name : %(#{name}="#{escape_html(value)}"))
      end
      style = resolve_style(node)
      out << %(style="#{style_css(style)}") unless style.empty?
      out.empty? ? "" : " #{out.join(' ')}"
    end

    def style_css(style)
      # 样式键为 snake_case（决策 #10）；内联 CSS 属性必须是 kebab-case。
      # 值同样要转义——理由与 class 相同：属性值里的引号会提前闭合 style 属性。
      style.map { |key, value| "#{Style.kebab(key)}:#{escape_html(value)}" }.join(";")
    end

    def escape_html(text)
      text.to_s.gsub("&", "&amp;").gsub("<", "&lt;")
             .gsub(">", "&gt;").gsub('"', "&quot;")
    end
  end
end
