# frozen_string_literal: true

# M1-2：flush 轨迹探针（DESIGN-devtools P2）——Scheduler.flush 记录
# {flush_id, t, effects:[{effect_id, runs, duration_ms}], trigger_signal_ids}；
# flush_id 经共享契约 Debug.flush_counter 分配（进程内单调递增），与事件流
# （M1-3）的 flush_ids 差集归因挂同一计数器。空 batch 不留痕也不消耗
# flush_id；effect 抛错（内核逐 effect rescue）时轨迹仍完整落缓冲。
require "minitest/autorun"
require "json"
require "citrine"
require "citrine/debug"

class DebugFlushTraceTest < Minitest::Test
  def setup
    Citrine.debug_tracking = true
    Citrine.debug_flush_trace.clear
    Citrine.debug_flush_trace.capacity = 500
  end

  def teardown
    Citrine.debug_tracking = false
    Citrine.debug_flush_trace.clear
    Citrine.debug_flush_trace.capacity = 500
  end

  def test_entry_point_returns_shared_ring
    assert_same Citrine::Debug.flush_trace_ring, Citrine.debug_flush_trace
    assert_equal 500, Citrine.debug_flush_trace.capacity
  end

  def test_single_write_triggers_one_flush_with_trigger_and_effect_stats
    s = Citrine.signal(0)
    effect = Citrine::Effect.create { s.get }
    Citrine.debug_flush_trace.clear
    before = Citrine::Debug.flush_counter.current

    Citrine.batch { s.set(1) }

    traces = Citrine.debug_flush_trace.to_a
    assert_equal 1, traces.size, "batch 窗口内的一次写入合并为一轮 flush"
    trace = traces.first
    assert_equal before + 1, trace[:flush_id]
    assert_kind_of Float, trace[:t]
    assert_includes trace[:trigger_signal_ids], s.object_id, "trigger 归因到写入的信号"

    assert_equal 1, trace[:effects].size
    entry = trace[:effects].first
    assert_equal effect.object_id, entry[:effect_id]
    assert_equal 2, entry[:runs], "Effect.create 已跑 1 次，flush 重跑后计 2"
    assert_operator entry[:duration_ms], :>=, 0.0
    assert_equal effect.debug_info[:runs], entry[:runs], "轨迹 runs 与 debug_info 同口径"
  end

  def test_sync_write_outside_batch_records_no_flush
    s = Citrine.signal(0)
    Citrine::Effect.create { s.get }
    Citrine.debug_flush_trace.clear

    s.set(1) # 窗口外同步广播：不入队、不 flush

    assert_empty Citrine.debug_flush_trace.to_a
  end

  def test_multiple_writes_in_one_batch_merge_into_single_flush
    a = Citrine.signal(0)
    b = Citrine.signal(0)
    Citrine::Effect.create { a.get + b.get }
    Citrine.debug_flush_trace.clear

    Citrine.batch { a.set(1); b.set(2) }

    traces = Citrine.debug_flush_trace.to_a
    assert_equal 1, traces.size
    assert_equal [a.object_id, b.object_id], traces.first[:trigger_signal_ids]
    assert_equal 1, traces.first[:effects].size, "同一 Effect 去重后只重跑一次"
  end

  def test_nested_batch_flushes_once_at_outer_boundary
    a = Citrine.signal(0)
    b = Citrine.signal(0)
    Citrine::Effect.create { a.get + b.get }
    Citrine.debug_flush_trace.clear

    Citrine.batch { a.set(1); Citrine.batch { b.set(2) } }

    traces = Citrine.debug_flush_trace.to_a
    assert_equal 1, traces.size, "嵌套 batch 只在外层边界 flush 一次"
    assert_equal [a.object_id, b.object_id], traces.first[:trigger_signal_ids]
  end

  def test_flush_ids_are_monotonic
    s = Citrine.signal(0)
    Citrine::Effect.create { s.get }
    Citrine.debug_flush_trace.clear

    Citrine.batch { s.set(1) }
    Citrine.batch { s.set(2) }

    ids = Citrine.debug_flush_trace.to_a.map { |t| t[:flush_id] }
    assert_equal ids.sort, ids, "flush_id 进程内单调递增"
    assert_equal 2, ids.uniq.size
  end

  def test_empty_batch_consumes_no_flush_id_and_records_nothing
    before = Citrine::Debug.flush_counter.current

    Citrine.batch {}

    assert_equal before, Citrine::Debug.flush_counter.current,
                 "空 batch 不留痕也不消耗 flush_id（事件流差集契约不被污染）"
    assert_empty Citrine.debug_flush_trace.to_a
  end

  def test_raising_effect_still_leaves_complete_trace
    s = Citrine.signal(0)
    effect = Citrine::Effect.create { raise "重跑爆炸" if s.get >= 1 }
    Citrine.debug_flush_trace.clear

    error = assert_raises(RuntimeError) { Citrine.batch { s.set(1) } }
    assert_equal "重跑爆炸", error.message

    traces = Citrine.debug_flush_trace.to_a
    assert_equal 1, traces.size, "effect 抛错（内核逐 effect rescue 后重抛）轨迹仍完整"
    trace = traces.first
    assert_includes trace[:trigger_signal_ids], s.object_id
    entry = trace[:effects].first
    assert_equal effect.object_id, entry[:effect_id]
    assert_equal 1, entry[:runs], "抛错的 run 不计数（与 debug_info 一致）"
    assert_equal effect.debug_info[:runs], entry[:runs]
  end

  def test_nested_flush_inside_effect_rerun_gets_own_capture
    inner_source = Citrine.signal(0)
    inner = Citrine::Effect.create { inner_source.get }
    outer_source = Citrine.signal(0)
    Citrine::Effect.create do
      outer_source.get
      Citrine.batch { inner_source.set(1) } if outer_source.peek == 1
    end
    Citrine.debug_flush_trace.clear

    outer_source.set(1) # 同步广播 → outer 重跑 → 内部 batch → 嵌套 flush

    traces = Citrine.debug_flush_trace.to_a
    assert_equal 1, traces.size
    assert_equal [inner.object_id], traces.first[:effects].map { |e| e[:effect_id] },
                 "嵌套 flush 的计时归嵌套采集，不混入 outer"
    assert_includes traces.first[:trigger_signal_ids], inner_source.object_id
  end

  def test_tracking_disabled_records_nothing
    Citrine.debug_tracking = false
    s = Citrine.signal(0)
    Citrine::Effect.create { s.get }

    Citrine.batch { s.set(1) }

    assert_empty Citrine.debug_flush_trace.to_a
  end

  def test_ring_overflow_drops_oldest
    Citrine.debug_flush_trace.capacity = 2
    s = Citrine.signal(0)
    Citrine::Effect.create { s.get }

    3.times { |i| Citrine.batch { s.set(i + 1) } }

    ring = Citrine.debug_flush_trace
    assert_equal 2, ring.size
    ids = ring.to_a.map { |t| t[:flush_id] }
    assert_equal ids.first + 1, ids.last, "保留最近两轮 flush"
  end

  def test_records_are_json_serializable
    s = Citrine.signal(0)
    Citrine::Effect.create { s.get }
    Citrine.batch { s.set(1) }

    parsed = JSON.parse(JSON.generate(Citrine.debug_flush_trace.to_a))

    trace = parsed.last
    assert_kind_of Integer, trace["flush_id"]
    assert_equal [s.object_id], trace["trigger_signal_ids"]
    assert_equal 2, trace["effects"].first["runs"]
  end
end
