# frozen_string_literal: true

# 组件级行为（纯 CRuby）：生命周期（G-10）、键盘分发（G-9）、KeyEvent、
# 宏声明校验（A1：prop/state/computed/context 与元素 DSL 同名即报错）、
# prop 可空校验（A2）。渲染器相关回归在 render_test.rb。
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

class MacroNameConflictTest < Minitest::Test
  # A1：state / computed 宏补上了与 prop 同口径的 DSL 方法名冲突检查——
  # 这些宏定义的读访问器会静默覆盖同名元素方法（label { … } / a(href:) { … }），
  # 必须声明期就报错。

  def test_prop_rejects_dsl_method_names
    error = assert_raises(ArgumentError) do
      Class.new(Citrine::Component) { prop :label }
    end
    assert_match(/prop :label/, error.message)
    assert_match(/元素 DSL 方法同名/, error.message)
  end

  def test_state_rejects_dsl_method_names
    error = assert_raises(ArgumentError) do
      Class.new(Citrine::Component) { state :label }
    end
    assert_match(/state :label/, error.message)
    assert_match(/元素 DSL 方法同名/, error.message)
  end

  def test_state_rejects_html_tag_names
    # :a 是锚点元素 a(href:) { … }——与 label 同属元素 DSL，同口径拦截
    error = assert_raises(ArgumentError) do
      Class.new(Citrine::Component) { state :a }
    end
    assert_match(/state :a/, error.message)
  end

  def test_computed_rejects_dsl_method_names
    error = assert_raises(ArgumentError) do
      Class.new(Citrine::Component) { computed(:button) { 1 } }
    end
    assert_match(/computed :button/, error.message)
    assert_match(/元素 DSL 方法同名/, error.message)
  end

  def test_context_rejects_dsl_method_names
    error = assert_raises(ArgumentError) do
      Class.new(Citrine::Component) { context :label }
    end
    assert_match(/context :label/, error.message)
    assert_match(/元素 DSL 方法同名/, error.message)
  end

  def test_plain_names_still_work_for_all_macros
    widget = Class.new(Citrine::Component) do
      prop :title, type: String, default: "t"
      state :count, default: 1
      computed(:double) { count * 2 }
      context :theme, default: :light

      def view = label { "x" }
    end

    instance = widget.new
    assert_equal "t", instance.title
    assert_equal 1, instance.count
    assert_equal 2, instance.double
    assert_equal :light, instance.theme
  end
end

class NullablePropTest < Minitest::Test
  # A2：声明 type 的 prop 是可空的——nil 与 type 实例都合法。
  # default 缺省为 nil，`prop :foo, type: String` 不再要求显式 default: nil。

  def widget_class
    Class.new(Citrine::Component) do
      prop :subtitle, type: String

      def view = label { "x" }
    end
  end

  def test_typed_prop_defaults_to_nil_without_type_error
    assert_nil widget_class.new.subtitle, "未传时 default nil：可空 prop 不再报 TypeError"
    assert_nil widget_class.new(subtitle: nil).subtitle
    assert_equal "hi", widget_class.new(subtitle: "hi").subtitle
  end

  def test_typed_prop_still_rejects_wrong_type
    error = assert_raises(TypeError) { widget_class.new(subtitle: 123) }
    assert_match(/subtitle/, error.message)
    assert_match(/String/, error.message)
  end

  def test_update_props_accepts_nil_and_rejects_wrong_type
    w = widget_class.new(subtitle: "a")

    w.update_props(subtitle: nil)
    assert_nil w.subtitle, "重传 nil 合法：响应式通道同步为 nil"

    w.update_props(subtitle: "b")
    assert_equal "b", w.subtitle

    assert_raises(TypeError) { w.update_props(subtitle: 42) }
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
