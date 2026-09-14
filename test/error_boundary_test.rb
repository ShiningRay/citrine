# frozen_string_literal: true

# S1-6：错误边界——组件可声明 error_fallback；子组件 view / 块在其块里抛错时，
# 以异常对象渲染兜底内容，失败那一轮不留半更新；
# 未声明兜底时异常照常穿出（对照）。
require "minitest/autorun"
require "citrine"
require "citrine/string_renderer"

class BoundaryEl
  attr_reader :children
  attr_accessor :parent, :class_name, :text

  def initialize
    @children = []
  end
end

class BoundaryRenderer < Citrine::Renderer
  private

  def setup_root(root, element)
    root.dom = element
  end

  def create_dom(_node)
    BoundaryEl.new
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

class BombChild < Citrine::Component
  prop :mode, type: Symbol, default: :boom

  class << self
    attr_accessor :mounts, :unmounts
  end
  self.mounts = 0
  self.unmounts = 0

  on_mount { self.class.mounts += 1 }
  on_unmount { self.class.unmounts += 1 }

  def view
    box(css_class: "bomb") { label { raise "子组件渲染失败" if mode == :boom } }
  end
end

class BoundaryParent < Citrine::Component
  components BombChild
  state :mode, default: :calm

  error_fallback :fallback

  def fallback(err)
    label(css_class: "fallback") { "兜底：#{err.message}" }
  end

  def view
    stack do
      label { "外围内容" }
      bomb_child(key: :bomb) if mode == :bomb
    end
  end
end

class ErrorBoundaryTest < Minitest::Test
  def setup
    BombChild.mounts = 0
    BombChild.unmounts = 0
  end

  def mount(widget)
    BoundaryRenderer.new.mount_component(widget, BoundaryEl.new)
  end

  def texts(node, acc = [])
    acc << node.text if node.text
    node.children.each { |child| texts(child, acc) }
    acc
  end

  def test_child_view_error_renders_fallback_without_residue
    parent = BoundaryParent.new
    parent.mode = :bomb
    root = mount(parent)

    assert_includes texts(root), "兜底：子组件渲染失败", "父组件应渲染出兜底文案（替换该块本轮内容）"
    assert_empty find_all(root, "bomb"), "子组件 DOM 不残留"
    assert_equal 0, BombChild.unmounts, "错误路径不应伪装成正常卸载（不跑 on_unmount）"
    assert_equal 0, BombChild.mounts, "渲染失败的子组件不该跑 on_mount"

    parent.mode = :calm

    assert_includes texts(root), "外围内容", "下一轮块正常执行后内容恢复"
    refute_includes texts(root), "兜底"
  end

  def test_error_is_delivered_to_fallback_branch
    seen = nil
    parent = Class.new(Citrine::Component) do
      error_fallback ->(err) { seen = err; label { "err:#{err.class}" } }

      define_method(:view) do
        stack { render(BombChild, key: "b") }
      end
    end.new
    mount(parent)

    assert_instance_of RuntimeError, seen, "异常对象应交给兜底分支"
    assert_includes texts(root_of(parent)), "err:RuntimeError"
  end

  def test_error_without_boundary_still_propagates
    parent = Class.new(Citrine::Component) do
      components BombChild

      def view
        stack { bomb_child(key: "b") }
      end
    end.new

    error = assert_raises(RuntimeError) { mount(parent) }
    assert_match(/子组件渲染失败/, error.message, "无边界时异常仍按现状穿出")
  end

  private

  def root_of(widget)
    widget.root
  end

  def find_all(node, class_name, acc = [])
    acc << node if node.props[:css_class].to_s.split(" ").include?(class_name)
    node.children.each { |child| find_all(child, class_name, acc) }
    acc
  end
end
