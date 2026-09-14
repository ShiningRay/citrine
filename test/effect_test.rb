# frozen_string_literal: true

# S1-8：effect 宏 + Effect cleanup——块返回 Proc 即清理回调，
# 每次重跑前与组件卸载时各执行一次；SSR 不创建（与 watch 同构）。
require "minitest/autorun"
require "citrine"
require "citrine/string_renderer"

class CleanupEl
  attr_reader :children
  attr_accessor :parent, :text

  def initialize
    @children = []
  end
end

class CleanupRenderer < Citrine::Renderer
  private

  def setup_root(root, element)
    root.dom = element
  end

  def create_dom(_node)
    CleanupEl.new
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

class EffectWidget < Citrine::Component
  state :n, default: 0

  class << self
    attr_accessor :setups, :cleanups
  end
  self.setups = 0
  self.cleanups = 0

  effect do
    self.class.setups += 1
    n # 订阅：n 变化触发重跑
    -> { self.class.cleanups += 1 }
  end

  def view = label { "n=#{n}" }
end

class EffectTest < Minitest::Test
  def setup
    EffectWidget.setups = 0
    EffectWidget.cleanups = 0
  end

  def mount(widget)
    CleanupRenderer.new.mount_component(widget, CleanupEl.new)
  end

  def test_effect_runs_once_on_mount_with_cleanup_declared
    w = EffectWidget.new
    mount(w)

    assert_equal 1, EffectWidget.setups
    assert_equal 0, EffectWidget.cleanups, "首轮没有可清理的"
    assert_equal 1, w.effect_count
  end

  def test_cleanup_runs_before_each_rerun
    w = EffectWidget.new
    mount(w)

    w.n = 1

    assert_equal 2, EffectWidget.setups, "依赖变化触发重跑"
    assert_equal 1, EffectWidget.cleanups, "重跑前先执行上一轮 cleanup"
  end

  def test_cleanup_runs_on_unmount_and_stops_reruns
    w = EffectWidget.new
    mount(w)
    w.n = 1
    setups_after_rerun = EffectWidget.setups

    Citrine.unmount(w)

    assert_equal 2, EffectWidget.cleanups, "卸载时执行最后一轮 cleanup"
    assert_equal 0, w.effect_count

    w.n = 9

    assert_equal setups_after_rerun, EffectWidget.setups, "卸载后不再被信号打回来"
  end

  def test_ssr_does_not_create_effects
    Citrine.render(EffectWidget.new)

    assert_equal 0, EffectWidget.setups, "SSR 不建 Effect（与 watch 同构）"
  end
end
