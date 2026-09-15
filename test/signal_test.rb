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

  # 回归（RubyWorld 实测发现）：广播遍历 @subs.dup 快照时，
  # 前序 effect 的重跑可能 dispose 快照中尚未执行的同源 effect，
  # 此时 run/release_deps 不得在 nil（已清空的依赖表）上崩溃。
  def test_disposing_sibling_effect_during_broadcast_is_safe
    s = Citrine::Signal.new(0)
    victim = nil
    log = []
    executioner = Citrine::Effect.create { s.get; victim&.dispose }
    victim = Citrine::Effect.create { s.get; log << 'v' }

    s.set(1) # executioner 重跑时 dispose victim；victim 仍在广播快照里
    assert_equal ['v'], log

    s.set(2) # victim 已订阅解除，不再触发；executioner 幂等 dispose 亦不崩溃
    assert_equal ['v'], log
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

  # C4 回归：batch flush 时一个 effect 抛错，同批其余 effect 不得被丢弃；
  # 队列排空后重新抛出第一个错误（warn 记录全部），队列状态清理干净。
  def test_flush_rescues_each_effect_and_reraises_first_error
    a = Citrine::Signal.new(0)
    b = Citrine::Signal.new(0)
    log = []
    Citrine::Effect.create { a.get; log << :first }
    boom = RuntimeError.new("第一个错误")
    Citrine::Effect.create { raise boom if a.get >= 1 } # 重跑时才抛
    Citrine::Effect.create { log << b.get }

    error = nil
    _out, err = capture_io do
      error = assert_raises(RuntimeError) do
        Citrine.batch do
          a.set(1)
          b.set(5)
        end
      end
    end

    assert_same boom, error, "队列排空后重新抛出第一个 effect 错误"
    assert_match(/第一个错误/, err, "失败的 effect 有 warn 记录")
    assert_equal [:first, 0, :first, 5], log, "抛错的 effect 之后的队列项照常执行"
    assert_equal 5, b.peek, "块内写入在抛出前已生效"

    b.set(6)
    assert_equal [:first, 0, :first, 5, 6], log, "队列状态已清理，后续写入照常触发"
  end

  # C4 回归：用户块自己抛异常时，ensure 里 flush 的调度错误不得替换原始异常。
  def test_batch_flush_error_does_not_replace_block_error
    a = Citrine::Signal.new(0)
    Citrine::Effect.create { raise "effect 错误" if a.get >= 1 } # 重跑时才抛

    user_error = RuntimeError.new("用户原始错误")
    raised = assert_raises(RuntimeError) do
      Citrine.batch do
        a.set(1)
        raise user_error
      end
    end

    assert_same user_error, raised, "ensure 路径抛出的应是用户块的原始异常"
  end

  # C5 回归：effect 的块在运行中 dispose 自己后继续读信号（depend），
  # 不得在已清空的 @deps（nil）上崩溃；且自 dispose 后不再重跑。
  def test_depend_after_self_dispose_mid_run_is_safe
    s = Citrine::Signal.new(0)
    log = []
    Citrine::Effect.create do
      s.get
      Citrine::Effect.current.dispose # 运行中自 dispose：@deps 已置 nil
      s.get                           # 继续读 → depend 遇到 nil 依赖表
      log << :ran
    end

    assert_equal [:ran], log

    s.set(1)
    assert_equal [:ran], log, "自 dispose 后订阅已解除，不再重跑"
  end

  def test_disposed_effect_in_broadcast_snapshot_is_safe
    # F1 回归（citrine-market-terminal 摩擦记录）：
    # 祖先 Effect 重跑时销毁后代 Effect，后代仍在信号的通知快照里被迭代。
    # 修复前：对已 dispose 的 effect 调 run → release_deps 对 nil 调 each → NoMethodError
    q = Citrine::Signal.new("")
    outer_log = []

    outer = Citrine::Effect.create { outer_log << q.get }
    inner = Citrine::Effect.create { q.get } # 后创建，订阅排在通知快照后面

    # 祖先重跑时销毁后代（渲染器块级重建即此模式）
    outer.instance_variable_set(:@block, -> {
      inner.dispose
      outer_log << "outer:#{q.get}"
    })

    q.set("x") # 通知快照 [outer, inner]：inner 在 dispose 后仍被迭代到

    assert_includes outer_log, "outer:x"
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
  # 回归：事件回调 Proc 必须保持闭包 self。嵌套组件（P0-1）里回调由父组件传入，
  # instance_exec 重绑到 emit 的 owner 会让父组件回调里的方法调用落到子组件上。
  def test_proc_event_handler_keeps_closure_self
    captured = nil
    handler = ->(ev) { captured = [self, ev] }
    TestWidget.new.handle_event(handler, 42)
    assert_equal self, captured[0]
    assert_equal 42, captured[1]
  end

  def test_proc_event_handler_without_event_keeps_closure_self
    captured = nil
    TestWidget.new.handle_event(-> { captured = self })
    assert_equal self, captured
  end
end
