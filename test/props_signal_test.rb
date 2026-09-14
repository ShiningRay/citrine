# frozen_string_literal: true

# S1-2：props 响应式传播——prop 升级为信号，**读它的块才重跑**；
# 父重传不再重建子组件，实例与 state 原地保留；没读该 prop 的兄弟块计数为 0。
require "minitest/autorun"
require "citrine"
require "citrine/string_renderer"

# ── 内存渲染器（平台无关断言用）─────────────────────────────
class PropEl
  attr_reader :children
  attr_accessor :parent, :class_name, :text

  def initialize
    @children = []
  end
end

class PropRenderer < Citrine::Renderer
  private

  def setup_root(root, element)
    root.dom = element
  end

  def create_dom(_node)
    PropEl.new
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

  def apply_props(node)
    node.dom.class_name = prop_value(node, node.props[:css_class]) if node.props.key?(:css_class)
  end

  def set_text(node, text)
    node.text = text
  end
end

# ── 被测组件 ────────────────────────────────────────────────

# 读 title 的子组件：view 体不读任何信号，文案块读 title + clicks
class SignalChild < Citrine::Component
  prop :title, type: String, default: "t"
  state :clicks, default: 0

  class << self
    attr_accessor :mounts, :view_runs, :label_runs
  end
  self.mounts = 0
  self.view_runs = 0
  self.label_runs = 0

  on_mount { self.class.mounts += 1 }

  def view
    self.class.view_runs += 1
    box(css_class: "child") do
      label(css_class: "child-label") do
        self.class.label_runs += 1
        "#{title}:#{clicks}"
      end
    end
  end
end

# 同层的另一类子组件：不读变化中的 prop，label 块不应被牵连重跑
class QuietChild < Citrine::Component
  prop :tag_name, type: String, default: "q"

  class << self
    attr_accessor :label_runs
  end
  self.label_runs = 0

  def view
    box do
      label do
        self.class.label_runs += 1
        "q:#{tag_name}"
      end
    end
  end
end

class SignalParent < Citrine::Component
  components SignalChild, QuietChild
  state :label_text, default: "a"

  def view
    stack do
      signal_child(title: label_text, key: :one)
      quiet_child(tag_name: "static", key: :two)
    end
  end
end

# ── 测试 ────────────────────────────────────────────────────

class PropsSignalTest < Minitest::Test
  def setup
    SignalChild.mounts = 0
    SignalChild.view_runs = 0
    SignalChild.label_runs = 0
    QuietChild.label_runs = 0
  end

  def mount(widget)
    PropRenderer.new.mount_component(widget, PropEl.new)
  end

  def texts(node, acc = [])
    acc << node.text if node.text
    node.children.each { |child| texts(child, acc) }
    acc
  end

  def component_roots(node, acc = [])
    acc << node if node.rendered_component
    node.children.each { |child| component_roots(child, acc) }
    acc
  end

  def test_prop_change_keeps_instance_and_state
    parent = SignalParent.new
    root = mount(parent)
    child = component_roots(root).first.rendered_component
    child.clicks = 5

    parent.label_text = "b"

    assert_equal 1, SignalChild.mounts, "props 变化不重建子组件"
    assert_same child, component_roots(root).first.rendered_component, "实例原样保留"
    assert_includes texts(root), "b:5", "读 title 的块重跑出新文案，且 clicks 未被重置"
  end

  def test_only_blocks_reading_the_prop_rerun
    parent = SignalParent.new
    mount(parent)
    child_runs_after_mount = SignalChild.label_runs
    quiet_runs_after_mount = QuietChild.label_runs
    view_runs_after_mount = SignalChild.view_runs

    parent.label_text = "b"

    assert_equal child_runs_after_mount + 1, SignalChild.label_runs,
                 "读了 title 的块应重跑 1 次"
    assert_equal quiet_runs_after_mount, QuietChild.label_runs,
                 "没读 title 的兄弟块重跑计数必须为 0"
    assert_equal view_runs_after_mount, SignalChild.view_runs,
                 "子组件 view 体不应因 prop 重传而整体重跑"
  end

  def test_callback_prop_swap_does_not_rerun_blocks
    # 回调每次重传都是新 Proc：只换引用不算变更（与 keyed 复用忽略 Proc 同口径）
    runs = 0
    child = Class.new(Citrine::Component) do
      prop :on_pick

      define_method(:view) do
        box { label { runs += 1; "row" } }
      end
    end
    parent = Class.new(Citrine::Component) do
      components child => :row_c
      state :tick, default: 0

      define_method(:view) do
        stack do
          tick # 父块重跑的扳机
          row_c(on_pick: ->(_c) { self.tick += 1 })
        end
      end
    end.new
    mount(parent)
    runs_after_mount = runs

    parent.tick = 1 # 重传一个新的 on_pick Proc

    assert_equal runs_after_mount, runs, "回调换引用不应触发读了它的块重跑"
  end

  def test_unread_prop_updates_plain_channel
    # 从未在 view 里读的 prop：走明值通道（不建订阅），重传后实例上读到新值
    child = Class.new(Citrine::Component) do
      prop :mode, type: Symbol, default: :off

      def view = label { "static" }
    end
    parent = Class.new(Citrine::Component) do
      components child => :mode_c
      state :flag, default: :off

      define_method(:view) do
        stack { mode_c(mode: flag) }
      end
    end.new
    root = mount(parent)
    instance = component_roots(root).first.rendered_component

    parent.flag = :on

    assert_equal :on, instance.mode, "未读的 prop 走明值通道，重传后实例上读到新值"
  end

  def test_ssr_reads_initial_prop_values
    html = Citrine.render(SignalParent.new)
    assert_includes html, "a:0"
    assert_includes html, "q:static"
  end
end
