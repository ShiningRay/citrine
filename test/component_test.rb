# frozen_string_literal: true

# 组件级行为（纯 CRuby）：生命周期（G-10）、键盘分发（G-9）、KeyEvent。
# 渲染器相关回归在 render_test.rb。
require "minitest/autorun"
require "citrine"
require "citrine/string_renderer"

class FakeElement
  attr_reader :children
  attr_accessor :parent

  def initialize
    @children = []
  end
end

# 最小渲染器：只关心生命周期与句柄登记，不模拟 DOM
class LifecycleRenderer < Citrine::Renderer
  private

  def setup_root(root, element)
    root.dom = element
  end

  def create_dom(_node)
    FakeElement.new
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

class LifecycleWidget < Citrine::Component
  state :draft, default: "x"

  on_mount :mark_mounted
  on_unmount { events << :unmounted }

  def events
    @events ||= []
  end

  def mark_mounted
    events << :mounted
  end

  def view
    stack do
      text_input(value: signal(:draft), ref: :editor)
      label { "draft=#{draft}" }
    end
  end
end

class ChildLifecycleWidget < LifecycleWidget
  on_mount { events << :child_mounted }
end

class KeyDispatchWidget < Citrine::Component
  state :log, default: []

  def view
    label { "x" }
  end

  def typed(ev)
    self.log = log + ["typed:#{ev.key}"]
  end

  def fallback(ev)
    self.log = log + ["fallback:#{ev.key}"]
  end
end

class ComponentLifecycleTest < Minitest::Test
  def test_on_mount_runs_after_mount_and_registers_refs
    w = LifecycleWidget.new
    root = LifecycleRenderer.new.mount_component(w, FakeElement.new)

    assert_equal [:mounted], w.events
    assert_instance_of FakeElement, w.refs[:editor], "ref: 应登记平台句柄"
    assert_same root, w.root
    assert_equal "draft=x", root.children.first.children[1].text
  end

  def test_hooks_are_inherited_in_declaration_order
    w = ChildLifecycleWidget.new
    LifecycleRenderer.new.mount_component(w, FakeElement.new)

    assert_equal %i[mounted child_mounted], w.events
  end

  def test_unmount_runs_hooks_disposes_effects_and_clears_refs
    w = LifecycleWidget.new
    root = LifecycleRenderer.new.mount_component(w, FakeElement.new)

    Citrine.unmount(w)

    assert_includes w.events, :unmounted
    assert_empty w.refs
    assert_empty root.children, "卸载后子树应清空"
    assert_empty root.owned_effects, "卸载后 Effect 应全部 dispose"

    w.draft = "y" # 卸载后改信号不应再触发任何重渲染（不抛异常、无残留订阅）
  end

  def test_unmount_without_mount_raises
    error = assert_raises(ArgumentError) { Citrine.unmount(LifecycleWidget.new) }
    assert_match(/尚未挂载/, error.message)
  end
end

class KeyDispatchTest < Minitest::Test
  def test_symbol_handler_receives_event_when_it_takes_an_argument
    w = KeyDispatchWidget.new
    w.handle_key(:typed, Citrine::KeyEvent.new("Enter"))

    assert_equal ["typed:Enter"], w.log
  end

  def test_hash_handler_dispatches_by_key_with_else_fallback
    w = KeyDispatchWidget.new
    table = { "Enter" => :typed, else: :fallback }

    w.handle_key(table, Citrine::KeyEvent.new("Enter"))
    w.handle_key(table, Citrine::KeyEvent.new("ArrowDown"))

    assert_equal ["typed:Enter", "fallback:ArrowDown"], w.log
  end

  def test_hash_handler_without_else_ignores_unmapped_key
    w = KeyDispatchWidget.new
    w.handle_key({ "Enter" => :typed }, Citrine::KeyEvent.new("Escape"))

    assert_empty w.log
  end

  def test_proc_handler_with_arity_one_receives_event
    w = KeyDispatchWidget.new
    # 事件 Proc 保持闭包 self（与 G-2 的划分一致：值在 owner 求值、行为在定义处执行），
    # 跨组件回调应捕获目标对象，而不是依赖重绑
    w.handle_key(->(ev) { w.log = w.log + ["proc:#{ev.key}"] }, Citrine::KeyEvent.new("Tab"))

    assert_equal ["proc:Tab"], w.log
  end
end

class KeyEventTest < Minitest::Test
  def test_modifiers_and_command_alias
    ev = Citrine::KeyEvent.new("s", meta: true, shift: true)

    assert ev.meta?
    assert ev.shift?
    refute ev.ctrl?
    assert ev.command?, "⌘ 与 Ctrl 都算 command"
    assert_equal "s", ev.to_s
  end

  def test_prevent_default_calls_platform_callback_once
    calls = 0
    ev = Citrine::KeyEvent.new("Enter", prevent_default: -> { calls += 1 })

    ev.prevent_default

    assert_equal 1, calls
  end

  def test_prevent_default_without_platform_callback_is_safe
    ev = Citrine::KeyEvent.new("Enter")

    assert_same ev, ev.prevent_default, "无平台回调时应静默返回自身，便于链式调用"
  end

  def test_key_is_coerced_to_string
    assert_equal "", Citrine::KeyEvent.new(nil).key
    assert_equal "ArrowUp", Citrine::KeyEvent.new(:ArrowUp).key
  end
end
