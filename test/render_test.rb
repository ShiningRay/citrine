# frozen_string_literal: true

# StringRenderer 单测（纯 CRuby）
require "minitest/autorun"
require "citrine"
require "citrine/string_renderer"

class RenderWidget < Citrine::Component
  prop    :name, type: String, default: "world"
  state   :n, default: 3
  computed(:sq) { n * n }

  def view
    box(direction: :column, gap: 8) do
      label { "hello <#{name}>" }
      label { "n=#{n} sq=#{sq}" }
      button(on_click: :noop) { "go" }
      check_box(checked: false)
    end
  end

  def noop; end
end

class CheckedWidget < Citrine::Component
  state :draft, default: "预填文字"

  def view
    box do
      text_input(value: signal(:draft), placeholder: "ph")
      check_box(checked: true)
    end
  end
end

# ── 内存渲染器：验证 Renderer 基类的块级更新语义（回归防护）──────────
# 背景：曾因 mount 丢失 per-node Effect 包装，导致任何状态变化整树重建、
# 输入框等节点身份丢失。此测试锁定"更新只影响订阅了该信号的 block"。
class FakeDom
  attr_reader :children
  attr_accessor :parent

  def initialize
    @children = []
  end
end

class MemoryRenderer < Citrine::Renderer
  private

  def setup_root(root, element)
    root.dom = element
  end

  def create_dom(_node)
    FakeDom.new
  end

  def attach(node, parent)
    node.dom.parent = parent.dom
    parent.dom.children << node.dom
  end

  def detach(node)
    return unless node.dom.parent

    node.dom.parent.children.delete(node.dom)
    node.dom.parent = nil
  end

  def apply_props(_node); end

  def set_text(node, text)
    node.text = text
  end
end

class TwoStateWidget < Citrine::Component
  state :a, default: 1
  state :b, default: 1

  def view
    box do
      label { "a=#{a}" }
      label { "b=#{b}" }
    end
  end
end

class MemoryRenderTest < Minitest::Test
  def test_block_level_update_preserves_sibling_identity
    w = TwoStateWidget.new
    root = MemoryRenderer.new.mount_component(w, FakeDom.new)
    labels = root.children.first.children
    doms_before = labels.map(&:dom)

    w.b = 2

    assert_equal "b=2", labels[1].text
    assert_equal "a=1", labels[0].text
    assert_same doms_before[1], labels[1].dom
    assert_same doms_before[0], labels[0].dom
  end
end

class CamelCompatWidget < Citrine::Component
  def view
    box(style: { padding: "4px" }) do
      label(style: { fontSize: "18px", fontWeight: "600", textDecoration: :line_through }) { "hi" }
    end
  end
end

class RenderTest < Minitest::Test
  def test_camelcase_style_and_symbol_value_compat
    html = Citrine.render(CamelCompatWidget.new)
    assert_includes html, "font-size:18px"
    assert_includes html, "font-weight:600"
    assert_includes html, "text-decoration:line-through"
  end

  def test_css_class_rendered
    widget = Class.new(Citrine::Component) do
      def view
        box(css_class: "card") { label(css_class: "t") { "x" } }
      end
    end
    html = Citrine.render(widget.new)
    assert_includes html, '<div class="card"'
    assert_includes html, '<p class="t">'
  end

  def test_structure_and_style
    html = Citrine.render(RenderWidget.new)
    assert_includes html, '<div style="display:flex;flex-direction:column;gap:8px">'
    assert_includes html, "<p>hello &lt;world&gt;</p>"
    assert_includes html, "<p>n=3 sq=9</p>"
    assert_includes html, "<button>go</button>"
  end

  def test_void_elements_and_handler_omission
    html = Citrine.render(RenderWidget.new)
    assert_includes html, '<input type="checkbox">'
    refute_includes html, "on_click"
    refute_includes html, "</input>"
  end

  def test_state_and_computed_reflect_changes
    w = RenderWidget.new
    w.n = 5
    assert_includes Citrine.render(w), "n=5 sq=25"
  end

  def test_widget_attributes
    html = Citrine.render(CheckedWidget.new)
    assert_includes html, 'type="text"'
    assert_includes html, 'placeholder="ph"'
    assert_includes html, 'value="预填文字"'
    assert_includes html, "<input type=\"checkbox\" checked"
  end

  def test_html_escaping_in_attributes
    html = Citrine.render(CheckedWidget.new)
    # 预填文字不含特殊字符，用临时组件验证转义
    w = RenderWidget.new(name: 'a"b')
    assert_includes Citrine.render(w), "&lt;a&quot;b&gt;"
  end
end
