# frozen_string_literal: true

# S1-1：批量更新——同一同步窗口内的多次 Signal#set 合并为一轮 Effect 重跑；
# 中间态不入 DOM（flush 前是旧值）；两次独立事件各自成一轮。
require "minitest/autorun"
require "citrine"

class BatchEl
  attr_reader :children
  attr_accessor :parent, :class_name, :text

  def initialize
    @children = []
  end
end

class BatchRenderer < Citrine::Renderer
  private

  def setup_root(root, element)
    root.dom = element
  end

  def create_dom(_node)
    BatchEl.new
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

class BatchWidget < Citrine::Component
  state :a, default: 0
  state :b, default: 0

  class << self
    attr_accessor :block_runs
  end
  self.block_runs = 0

  def view
    box do
      label do
        self.class.block_runs += 1
        "a=#{a} b=#{b}" # 一个块同时读两个信号：同步广播下会被连打两次
      end
      button(on_click: :bump)
    end
  end

  def bump
    self.a = a + 1
    self.b = b + 1
  end
end

class BatchingTest < Minitest::Test
  def setup
    BatchWidget.block_runs = 0
  end

  def mount(widget)
    BatchRenderer.new.mount_component(widget, BatchEl.new)
  end

  def texts(node, acc = [])
    acc << node.text if node.text
    node.children.each { |child| texts(child, acc) }
    acc
  end

  def test_handler_sets_multiple_signals_are_one_rerun
    w = BatchWidget.new
    root = mount(w)
    runs_after_mount = BatchWidget.block_runs

    w.handle_event(:bump)

    assert_equal runs_after_mount + 1, BatchWidget.block_runs,
                 "handler 内两次 set 合并为一轮重跑（此前是 2）"
    assert_includes texts(root), "a=1 b=1"
  end

  def test_intermediate_state_not_in_dom_before_flush
    w = BatchWidget.new
    root = mount(w)

    Citrine.batch do
      w.a = 1
      w.b = 2
      assert_includes texts(root), "a=0 b=0", "flush 之前目标节点仍是旧值（中间态不入 DOM）"
    end

    assert_includes texts(root), "a=1 b=2", "flush 之后一次到新值"
  end

  def test_two_independent_events_are_two_rounds
    w = BatchWidget.new
    root = mount(w)
    runs_after_mount = BatchWidget.block_runs

    w.handle_event(:bump)
    w.handle_event(:bump)

    assert_equal runs_after_mount + 2, BatchWidget.block_runs,
                 "跨事件边界不合并：两次独立点击各自成一轮"
    assert_includes texts(root), "a=2 b=2"
  end

  def test_repeated_writes_to_same_signal_collapse
    w = BatchWidget.new
    root = mount(w)
    runs_after_mount = BatchWidget.block_runs

    Citrine.batch do
      w.a = 1
      w.a = 2
      w.b = 9
    end

    assert_equal runs_after_mount + 1, BatchWidget.block_runs, "去重：同块只跑一次"
    assert_includes texts(root), "a=2 b=9", "且读到的是最终值"
  end

  def test_explicit_batch_can_be_nested
    w = BatchWidget.new
    root = mount(w)
    runs_after_mount = BatchWidget.block_runs

    Citrine.batch do
      w.a = 1
      Citrine.batch { w.b = 2 } # 内层不 flush
      assert_includes texts(root), "a=0 b=0"
    end

    assert_equal runs_after_mount + 1, BatchWidget.block_runs
    assert_includes texts(root), "a=1 b=2"
  end
end
