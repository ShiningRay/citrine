# frozen_string_literal: true

# ListSignal 的增补（D 后续）：Enumerable 读 API、dup、有上限的追加、Hash 守卫，
# 以及 Signal#peek（读值但不订阅）。
require "minitest/autorun"
require "citrine"

class ListSignalFollowupTest < Minitest::Test
  def setup
    @list = Citrine.signal_list([1, 2, 3])
  end

  # ── Enumerable：带条件的查询不必回落 get ───────────────────────
  def test_enumerable_read_api
    assert_equal 2, @list.find { |x| x > 1 }
    assert_equal [1, 3], @list.select(&:odd?)
    assert_equal [2], @list.reject(&:odd?)
    assert_equal 6, @list.sum
    assert_equal 1, @list.min
    assert_equal 3, @list.max
    assert_equal 3, @list.count
    assert_equal [3, 2, 1], @list.sort_by { |x| -x }
    assert_equal [[1, 0], [2, 1]], @list.each_with_index.to_a.first(2)
    assert @list.any?(&:even?)
    assert @list.all? { |x| x > 0 }
  end

  def test_enumerable_queries_are_reactive
    sizes = []
    Citrine::Effect.create { sizes << @list.count(&:odd?) }

    @list << 4
    @list << 5

    assert_equal [2, 2, 3], sizes
  end

  # ── dup / clone：复制集合而不是克隆信号对象 ─────────────────────
  def test_dup_returns_independent_collection_copy
    copy = @list.dup

    assert_instance_of Citrine::ListSignal, copy
    assert_equal [1, 2, 3], copy.get

    copy << 4
    assert_equal [1, 2, 3], @list.get, "副本改动不影响原集合"
    assert_equal [1, 2, 3, 4], copy.get
  end

  # ── 有上限的追加：一次通知 ─────────────────────────────────────
  def test_push_bounded_keeps_last_n_with_single_notification
    runs = 0
    Citrine::Effect.create do
      @list.get
      runs += 1
    end

    @list.push_bounded(4, 3)
    assert_equal [2, 3, 4], @list.get
    assert_equal 2, runs, "首次订阅跑一次 + 变更跑一次（而不是两次）"
  end

  def test_unshift_bounded_keeps_first_n
    @list.unshift_bounded(0, 3)
    assert_equal [0, 1, 2], @list.get
  end

  # ── 类型守卫：Hash 不再被静默拆成键值对 ─────────────────────────
  def test_hash_is_rejected_with_clear_error
    error = assert_raises(ArgumentError) { Citrine.signal_list({ a: 1 }) }
    assert_match(/需要数组/, error.message)
    assert_match(/Citrine\.signal/, error.message, "错误信息应给出替代写法")
  end

  def test_non_array_is_rejected
    assert_raises(ArgumentError) { Citrine.signal_list(42) }
    assert_equal [], Citrine.signal_list(nil).get, "nil 视为空集合"
  end

  # ── peek：读值但不订阅 ────────────────────────────────────────
  def test_peek_does_not_subscribe
    signal = Citrine.signal(1)
    seen = []
    Citrine::Effect.create { seen << signal.peek }

    signal.set(2)
    assert_equal [1], seen, "peek 不该建立依赖"
    assert_equal 2, signal.peek, "但能读到最新值"
  end

  def test_list_peek_returns_frozen_snapshot_without_subscribing
    seen = []
    Citrine::Effect.create { seen << @list.peek }

    @list << 4

    assert_equal [[1, 2, 3]], seen
    assert @list.peek.frozen?
    assert_equal [1, 2, 3, 4], @list.get
  end
end
