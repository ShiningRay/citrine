# frozen_string_literal: true

# S1-11：集合深响应——位置读取（list[i]）返回元素代理，读取即订阅该位置；
# 经代理就地改写只通知订阅该位置的块（不整表重建）；集合结构变更走集合级通知；
# get 仍返回冻结快照（防呆不回归）。
require "minitest/autorun"
require "citrine"

class ListDeepTest < Minitest::Test
  def test_element_write_notifies_only_that_position
    list = Citrine.signal_list([{ n: 0 }, { n: 0 }])
    reads = Hash.new(0)
    effect0 = Citrine::Effect.create { list[0][:n]; reads[0] += 1 }
    effect1 = Citrine::Effect.create { list[1][:n]; reads[1] += 1 }
    assert_equal({ 0 => 1, 1 => 1 }, reads)

    list[0][:n] = 1

    assert_equal({ 0 => 2, 1 => 1 }, reads, "读取该位置的块重跑 1 次，其他位置 0 次")
    assert_equal 1, list[0][:n], "重跑读取到新值"
    assert_equal({ n: 1 }, list.get[0], "快照中的活元素已是新内容")

    effect0.dispose
    effect1.dispose
  end

  def test_element_write_does_not_rerun_collection_readers
    list = Citrine.signal_list([{ n: 0 }])
    runs = 0
    effect = Citrine::Effect.create do
      list.each { } # 集合级读：只订阅集合信号
      runs += 1
    end
    assert_equal 1, runs

    list[0][:n] = 5

    assert_equal 1, runs, "元素级写入不触发整表读者（不整表重建）"

    list << { n: 9 }

    assert_equal 2, runs, "结构变更仍走集合级通知"
    effect.dispose
  end

  def test_structural_changes_refresh_positional_readers
    list = Citrine.signal_list([{ id: "A" }, { id: "B" }])
    seen = nil
    effect = Citrine::Effect.create { seen = list[0][:id] }
    assert_equal "A", seen

    list.delete_at(0)

    assert_equal "B", seen, "位置平移后元素读者拿到新元素"

    list << { id: "C" }

    assert_equal "B", seen, "尾部追加不影响位置 0 的读者（内容没变不误报）"
    effect.dispose
  end

  def test_element_writes_participate_in_batching
    list = Citrine.signal_list([{ n: 0, m: 0 }])
    runs = 0
    effect = Citrine::Effect.create { list[0][:n]; list[0][:m]; runs += 1 }
    runs_after_mount = runs

    Citrine.batch do
      list[0][:n] = 1
      list[0][:m] = 2
    end

    assert_equal runs_after_mount + 1, runs, "批量窗口内多次元素写入合并为一轮"
    assert_equal({ n: 1, m: 2 }, list.get[0])
    effect.dispose
  end

  def test_proxy_forwards_reads_and_keeps_equality
    list = Citrine.signal_list([{ n: 1, tag: "a" }])
    row = list[0]

    assert_equal 1, row[:n]
    assert_equal "a", row[:tag]
    assert_equal({ n: 1, tag: "a" }, row, "代理与裸元素相等（== 转发）")
    assert row.key?(:tag)
    assert_kind_of Citrine::ListSignal::ElementProxy, row
  end

  def test_get_snapshot_stays_frozen
    list = Citrine.signal_list([{ n: 0 }])

    assert list.get.frozen?
    error = assert_raises(FrozenError) { list.get << { n: 1 } }
    assert error, "就地改快照仍当场 FrozenError"
  end

  def test_in_place_write_through_get_stays_silent
    # 语义边界（与 v1 一致）：绕过代理经 get 拿到裸元素改写，不触发更新
    list = Citrine.signal_list([{ n: 0 }])
    reads = 0
    effect = Citrine::Effect.create { list[0][:n]; reads += 1 }
    reads_after_mount = reads

    list.get[0][:n] = 9

    assert_equal reads_after_mount, reads, "裸元素改写不走代理，保持静默（文档化边界）"
    assert_equal 9, list[0][:n], "但读到的确实是改过的活元素"
    effect.dispose
  end
end
