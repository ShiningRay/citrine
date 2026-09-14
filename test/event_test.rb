# frozen_string_literal: true

# S2-3：统一事件对象（平台无关视图）与 window_key 焦点作用域的注册语义。
# DOM 侧行为（真实焦点 / 传播）由 examples/props_widgets + Node 桩验收。
require "minitest/autorun"
require "citrine"

class ScopeEl
  attr_reader :children
  attr_accessor :parent, :text

  def initialize
    @children = []
  end
end

class ScopeRenderer < Citrine::Renderer
  attr_reader :window_keys

  def initialize
    super
    @window_keys = []
  end

  private

  def setup_root(root, element)
    root.dom = element
  end

  def create_dom(_node)
    ScopeEl.new
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

  def register_window_key(component, handler)
    @window_keys << [component, handler]
  end

  def unregister_window_keys(component)
    @window_keys.reject! { |(c, _)| c.equal?(component) }
  end
end

class EventViewTest < Minitest::Test
  def test_event_carries_type_and_platform_callbacks
    prevented = false
    stopped = false
    ev = Citrine::Event.new("click",
                            prevent_default: -> { prevented = true },
                            stop_propagation: -> { stopped = true })

    assert_equal "click", ev.type
    refute prevented
    refute stopped

    ev.prevent_default
    ev.stop_propagation

    assert prevented, "prevent_default 接到平台回调"
    assert stopped, "stop_propagation 接到平台回调"
  end

  def test_event_is_nil_safe_without_platform
    ev = Citrine::Event.new("wheel")

    assert_same ev, ev.prevent_default # 无平台回调时静默忽略（仍可链式）
    assert_same ev, ev.stop_propagation
    assert_equal "#<Citrine::Event wheel>", ev.inspect
  end
end

class ScopedWindowKeyTest < Minitest::Test
  def mount(widget)
    renderer = ScopeRenderer.new
    renderer.mount_component(widget, ScopeEl.new)
    renderer
  end

  def test_scoped_window_key_registers_and_unregisters
    widget = Class.new(Citrine::Component) do
      window_key :on_arrow, scope: :focused

      def on_arrow(_ev); end

      def view = label { "x" }
    end.new
    renderer = mount(widget)

    assert_equal 1, renderer.window_keys.size
    entry = renderer.window_keys.first.last
    assert_kind_of Citrine::Component::WindowKey, entry, "带作用域的处理器登记为 WindowKey 包装"
    assert_equal :focused, entry.scope
    assert_equal :on_arrow, entry.handler

    Citrine.unmount(widget)

    assert_empty renderer.window_keys, "卸载照常解绑"
  end

  def test_unscoped_window_key_stays_plain
    widget = Class.new(Citrine::Component) do
      window_key :on_key

      def on_key(_ev); end

      def view = label { "x" }
    end.new
    renderer = mount(widget)

    assert_equal 1, renderer.window_keys.size
    assert_equal :on_key, renderer.window_keys.first.last, "不带作用域时登记形式不变（兼容既有代码）"
  end
end
