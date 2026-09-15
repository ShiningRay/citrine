# frozen_string_literal: true

# M1-1：信号写入日志探针（DESIGN-devtools P1）——Signal#set / #set! / #replace
# 经统一收口 #broadcast（replace 静默换值单独记录）落 {t, signal_id, old, new,
# source} 到固定容量环形缓冲；source 为 Effect.current 的 object_id，
# Effect 上下文之外记 :external。仅在 debug_tracking 开启时记录。
require "minitest/autorun"
require "json"
require "citrine"
require "citrine/debug"

class DebugWriteLogTest < Minitest::Test
  def setup
    Citrine.debug_tracking = true
    Citrine.debug_write_log.clear
    Citrine.debug_write_log.capacity = 500
  end

  def teardown
    Citrine.debug_tracking = false
    Citrine.debug_write_log.clear
    Citrine.debug_write_log.capacity = 500
  end

  def test_entry_point_returns_shared_ring
    assert_same Citrine::Debug.write_log_ring, Citrine.debug_write_log
    assert_equal 500, Citrine.debug_write_log.capacity
  end

  def test_write_produces_record_with_snapshot_values
    s = Citrine.signal(41)
    Citrine.debug_write_log.clear

    s.set(42)

    entry = Citrine.debug_write_log.to_a.last
    assert_kind_of Float, entry[:t]
    assert_equal s.object_id, entry[:signal_id]
    assert_equal 41, entry[:old]
    assert_equal 42, entry[:new]
    assert_equal :external, entry[:source], "无 Effect 上下文时记 :external"
  end

  def test_source_is_effect_id_when_written_inside_effect
    s = Citrine.signal(0)
    Citrine.debug_write_log.clear

    effect = Citrine::Effect.create { s.set(7) }

    entry = Citrine.debug_write_log.to_a.last
    assert_equal effect.object_id, entry[:source], "Effect 内写入归因到该 Effect"
  end

  def test_order_within_batch_follows_write_sequence
    a = Citrine.signal(0)
    b = Citrine.signal(0)
    Citrine.debug_write_log.clear

    Citrine.batch do
      a.set(1)
      b.set(2)
    end

    entries = Citrine.debug_write_log.to_a
    assert_equal [a.object_id, b.object_id], entries.map { |e| e[:signal_id] },
                 "记录先于效果执行落缓冲，batch 内顺序即写入时序"
    assert entries[0][:t] <= entries[1][:t]
  end

  def test_equal_shortcircuit_writes_nothing_but_set_bang_records
    s = Citrine.signal(0)
    Citrine.debug_write_log.clear

    s.set(0)
    assert_empty Citrine.debug_write_log.to_a, "相等短路不触发 broadcast，不留记录"

    s.set!(0)
    assert_equal 1, Citrine.debug_write_log.size, "set! 强制广播，相等也记录"
  end

  def test_replace_records_silent_swap
    s = Citrine.signal(1)
    Citrine.debug_write_log.clear

    s.replace(2)

    entry = Citrine.debug_write_log.to_a.last
    assert_equal 1, entry[:old]
    assert_equal 2, entry[:new]
  end

  def test_values_are_truncated_for_transport_safety
    s = Citrine.signal("x" * 300)
    Citrine.debug_write_log.clear

    s.set("y" * 300)

    entry = Citrine.debug_write_log.to_a.last
    assert_equal 200, entry[:old].length, "大对象 to_s 限 200 字符，防缓冲爆炸"
    assert_equal "y" * 200, entry[:new]
  end

  def test_scalar_values_keep_native_types
    s = Citrine.signal(nil)
    Citrine.debug_write_log.clear

    s.set(3)

    entry = Citrine.debug_write_log.to_a.last
    assert_nil entry[:old]
    assert_equal 3, entry[:new], "标量原样记录（JSON 直出），不强制 to_s"
  end

  def test_list_signal_changes_flow_through_same_channel
    list = Citrine.signal_list([1])
    Citrine.debug_write_log.clear

    list << 2

    entry = Citrine.debug_write_log.to_a.last
    assert_equal list.object_id, entry[:signal_id]
    assert_equal "[1, 2]", entry[:new], "ListSignal 继承同一 broadcast 通道"
  end

  def test_ring_overflow_drops_oldest
    Citrine.debug_write_log.capacity = 3
    s = Citrine.signal(0)

    4.times { |i| s.set(i + 1) }

    ring = Citrine.debug_write_log
    assert_equal 3, ring.size
    assert_equal [2, 3, 4], ring.to_a.map { |e| e[:new] }
  end

  def test_tracking_disabled_records_nothing
    Citrine.debug_tracking = false
    s = Citrine.signal(0)

    s.set(1)
    s.set!(2)
    s.replace(3)

    assert_empty Citrine.debug_write_log.to_a
  end

  def test_broadcast_stays_private_with_probe_loaded
    assert Citrine::Signal.private_method_defined?(:broadcast)
    refute Citrine::Signal.public_method_defined?(:broadcast)
    assert_raises(NoMethodError) { Citrine.signal(0).broadcast }
  end

  def test_records_are_json_serializable
    s = Citrine.signal("a")
    s.set("b")

    parsed = JSON.parse(JSON.generate(Citrine.debug_write_log.to_a))

    entry = parsed.last
    assert_equal "b", entry["new"]
    assert_equal "external", entry["source"]
    assert_kind_of Float, entry["t"]
  end
end
