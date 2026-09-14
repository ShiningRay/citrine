# frozen_string_literal: true

# 核心机制单测（纯 CRuby，不依赖 Opal/DOM）
require "minitest/autorun"
require "citrine"

class SignalTest < Minitest::Test
  def test_effect_reruns_on_dependency_change
    s = Citrine::Signal.new(0)
    log = []
    Citrine::Effect.create { log << s.get }
    assert_equal [0], log

    s.set(1)
    s.set(2)
    assert_equal [0, 1, 2], log
  end

  def test_only_actual_deps_trigger
    a = Citrine::Signal.new(0)
    b = Citrine::Signal.new(0)
    log = []
    Citrine::Effect.create { log << a.get }
    b.set(5)
    assert_equal [0], log
  end

  def test_stale_deps_are_released_after_branch_switch
    switch = Citrine::Signal.new(true)
    a = Citrine::Signal.new(1)
    b = Citrine::Signal.new(10)
    log = []
    Citrine::Effect.create { log << (switch.get ? a.get : b.get) }
    assert_equal [1], log

    switch.set(false)
    assert_equal [1, 10], log

    a.set(99) # 旧依赖已解除，不应触发
    assert_equal [1, 10], log

    b.set(11) # 新依赖应触发
    assert_equal [1, 10, 11], log
  end

  def test_dispose_stops_execution
    s = Citrine::Signal.new(0)
    log = []
    effect = Citrine::Effect.create { log << s.get }
    effect.dispose
    s.set(1)
    assert_equal [0], log
  end

  def test_set_same_value_skips_notification
    s = Citrine::Signal.new(1)
    runs = 0
    Citrine::Effect.create { s.get; runs += 1 }
    s.set(1)
    assert_equal 1, runs
  end

  def test_nested_effect_cascade
    source = Citrine::Signal.new(1)
    derived = Citrine::Signal.new(nil)
    Citrine::Effect.create { derived.set(source.get * 10) }
    log = []
    Citrine::Effect.create { log << derived.get }
    assert_equal [10], log

    source.set(2)
    assert_equal [10, 20], log
  end
end

class TestWidget < Citrine::Component
  prop    :title, type: String, default: "t"
  state   :count, default: 1
  computed(:double) { count * 2 }
end

class ComponentTest < Minitest::Test
  def test_state_writer_triggers_computed_invalidation
    w = TestWidget.new
    assert_equal 1, w.count
    assert_equal 2, w.double

    w.count = 5
    assert_equal 5, w.count
    assert_equal 10, w.double
  end

  def test_prop_defaults_and_validation
    assert_equal "t", TestWidget.new.title
    assert_equal "hi", TestWidget.new(title: "hi").title

    assert_raises(ArgumentError) { TestWidget.new(bogus: 1) }
    assert_raises(TypeError) { TestWidget.new(title: 123) }
  end

  def test_undeclared_state_signal_raises
    assert_raises(ArgumentError) { TestWidget.new.signal(:nope) }
  end
end
