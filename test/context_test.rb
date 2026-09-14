# frozen_string_literal: true

# S1-3：Context 依赖注入——祖先声明的值可在任意后代读取（中间层不声明不转发）；
# 值变化只有读它的后代重跑；SSR 读到同一初值；缺 provider 显式报错。
require "minitest/autorun"
require "citrine"
require "citrine/string_renderer"

class ContextEl
  attr_reader :children
  attr_accessor :parent, :class_name, :text

  def initialize
    @children = []
  end
end

class ContextRenderer < Citrine::Renderer
  private

  def setup_root(root, element)
    root.dom = element
  end

  def create_dom(_node)
    ContextEl.new
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

class ContextDeep < Citrine::Component
  class << self
    attr_accessor :block_runs, :mounts
  end
  self.block_runs = 0
  self.mounts = 0

  on_mount { self.class.mounts += 1 }

  def view
    label do
      self.class.block_runs += 1
      "mode=#{use_context(:theme)[:mode]}"
    end
  end
end

class ContextMiddle < Citrine::Component
  components ContextDeep

  class << self
    attr_accessor :block_runs
  end
  self.block_runs = 0

  def view
    box do
      label do
        self.class.block_runs += 1
        "middle"
      end
      context_deep
    end
  end
end

class ThemeProvider < Citrine::Component
  context :theme, default: { mode: "light" }
  state :dark, default: false

  components ContextMiddle

  def view
    stack do
      self.theme = { mode: dark ? "dark" : "light" }
      context_middle
    end
  end
end

class ContextTest < Minitest::Test
  def setup
    ContextMiddle.block_runs = 0
    ContextDeep.block_runs = 0
    ContextDeep.mounts = 0
  end

  def mount(widget)
    ContextRenderer.new.mount_component(widget, ContextEl.new)
  end

  def texts(node, acc = [])
    acc << node.text if node.text
    node.children.each { |child| texts(child, acc) }
    acc
  end

  def test_three_layers_read_ancestor_value_without_forwarding
    root = mount(ThemeProvider.new)

    assert_includes texts(root), "mode=light", "末层读到祖先值（中间层不声明不转发）"
    assert_equal 1, ContextDeep.mounts
  end

  def test_provider_change_reruns_only_reading_blocks
    widget = ThemeProvider.new
    root = mount(widget)
    middle_runs = ContextMiddle.block_runs
    deep_runs = ContextDeep.block_runs

    widget.dark = true

    assert_includes texts(root), "mode=dark", "末层读到新值"
    assert_equal middle_runs, ContextMiddle.block_runs, "中间层块重跑计数为 0"
    assert_equal deep_runs + 1, ContextDeep.block_runs, "末层读 context 的块重跑 1 次"
    assert_equal 1, ContextDeep.mounts, "context 变化不重建组件"
  end

  def test_missing_provider_raises
    orphan = Class.new(Citrine::Component) do
      def view = label { use_context(:nothing) }
    end

    error = assert_raises(ArgumentError) { Citrine.render(orphan.new) }
    assert_match(/use_context\(:nothing\)/, error.message)
  end

  def test_unread_context_is_not_required
    # 不声明 context 的普通组件不受影响（无隐式行为）
    plain = Class.new(Citrine::Component) do
      def view = label { "plain" }
    end

    assert_includes Citrine.render(plain.new), "plain"
  end
end

class ContextSSRTest < Minitest::Test
  def test_ssr_reads_same_initial_value
    html = Citrine.render(ThemeProvider.new)

    assert_includes html, "mode=light"
    assert_includes html, "middle"
  end
end
