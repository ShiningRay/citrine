# frozen_string_literal: true

# 生命周期钩子的声明形式（G-12）：一次可声明多个，且各平台语义一致。
#
# 背景：Opal 下给固定 arity 的方法多传实参**不会报错**，只是静默丢弃——
# 于是 `on_mount :a, :b` 在 CRuby 抛 ArgumentError、在 Opal 只跑 a，
# 表现为"某个副作用凭空消失"（dogfooding 实测：网格 ticker 消失 → 闪烁永不清零）。
require "minitest/autorun"
require "citrine"

class MultiHookTest < Minitest::Test
  def test_on_mount_accepts_multiple_symbols
    ran = []
    klass = Class.new(Citrine::Component) do
      on_mount :first_hook, :second_hook
      define_method(:first_hook) { ran << :first }
      define_method(:second_hook) { ran << :second }
    end

    assert_equal 2, klass.mount_hooks.size
    klass.new.run_mount_hooks
    assert_equal %i[first second], ran
  end

  def test_on_unmount_accepts_multiple_symbols
    ran = []
    klass = Class.new(Citrine::Component) do
      on_unmount :first_hook, :second_hook
      define_method(:first_hook) { ran << :first }
      define_method(:second_hook) { ran << :second }
    end

    assert_equal 2, klass.unmount_hooks.size
    klass.new.run_unmount_hooks
    assert_equal %i[first second], ran
  end

  def test_mixed_symbol_proc_and_block
    ran = []
    klass = Class.new(Citrine::Component) do
      on_mount :sym, -> { ran << :proc } do
        ran << :block
      end
      define_method(:sym) { ran << :sym }
    end

    assert_equal 3, klass.mount_hooks.size
    klass.new.run_mount_hooks
    assert_equal %i[sym proc block], ran
  end

  def test_mount_hooks_are_inherited_and_appended
    base = Class.new(Citrine::Component) do
      on_mount :base_hook
      define_method(:base_hook) {}
    end
    child = Class.new(base) { on_mount :child_hook }
    child.define_method(:child_hook) {}

    assert_equal 2, child.mount_hooks.size
    assert_equal 1, base.mount_hooks.size
  end

  def test_on_mount_without_any_handler_raises
    error = assert_raises(ArgumentError) { Class.new(Citrine::Component) { on_mount } }
    assert_match(/至少一个处理器/, error.message)
  end

  def test_on_mount_rejects_non_symbol_non_proc
    error = assert_raises(ArgumentError) { Class.new(Citrine::Component) { on_mount "not a hook" } }
    assert_match(/只能是 Symbol 或 Proc/, error.message)
  end
end
