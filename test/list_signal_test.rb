# frozen_string_literal: true

# 响应式集合（D）：`Citrine.signal_list([...])` / `include Citrine::Reactive` 后的
# `signal_list(...)`。核心承诺：
#   · 集合自身的每次变更 = 一次通知（内部换新数组，仍只有 Signal#set 这一条触发路径）
#   · 读操作都经 get，因此在 Effect / 块里读会建立依赖
#   · get 返回冻结快照——就地改它当场报错，而不是静默不触发
require "minitest/autorun"
require "citrine"
require "citrine/string_renderer"

class ListSignalTest < Minitest::Test
  def collect(signal)
    seen = []
    Citrine::Effect.create { seen << signal.get }
    seen
  end

  def test_factory_returns_list_signal_with_initial_items
    list = Citrine.signal_list([1, 2])

    assert_instance_of Citrine::ListSignal, list
    assert_equal [1, 2], list.get
    assert_equal 2, list.size
    refute list.empty?
  end

  def test_get_returns_frozen_snapshot
    list = Citrine.signal_list([1])

    assert list.get.frozen?, "快照应冻结——就地改它会静默不更新，必须当场报错"
    assert_raises(FrozenError) { list.get << 2 }
    assert_equal [1], list.get, "失败的改动不应影响原值"
  end

  def test_append_notifies_once_and_keeps_value
    list = Citrine.signal_list([1])
    seen = collect(list)

    list << 2
    list.push(3, 4)

    assert_equal [[1], [1, 2], [1, 2, 3, 4]], seen
    assert_equal [1, 2, 3, 4], list.get
  end

  def test_push_returns_signal_for_chaining
    list = Citrine.signal_list([])
    list.push(1).push(2)

    assert_equal [1, 2], list.get
  end

  def test_removals_follow_array_return_conventions
    list = Citrine.signal_list([1, 2, 3])

    assert_equal 3, list.pop
    assert_equal 1, list.shift
    assert_equal [2], list.get

    assert_equal [2], list.shift(1)
    assert_equal [], list.get

    assert_nil list.pop
    assert_nil list.shift
  end

  def test_delete_delete_at_and_clear
    list = Citrine.signal_list([:a, :b, :c])

    assert_equal :b, list.delete(:b)
    assert_nil list.delete(:zzz)
    assert_equal [:a, :c], list.get

    assert_equal :c, list.delete_at(-1)
    assert_equal [:a], list.get
    assert_nil list.delete_at(5)

    list.clear
    assert_equal [], list.get
  end

  def test_insert_replace_and_index_assign
    list = Citrine.signal_list([1, 3])

    list.insert(1, 2)
    assert_equal [1, 2, 3], list.get

    list[0] = 0
    assert_equal [0, 2, 3], list.get

    list.replace([9, 8])
    assert_equal [9, 8], list.get
  end

  def test_replacing_with_equal_value_does_not_notify
    list = Citrine.signal_list([1, 2])
    seen = collect(list)

    list.replace([1, 2])
    list.delete(:missing)

    assert_equal [[1, 2]], seen, "值没变就不该通知"
  end

  def test_in_place_style_helpers_return_signal
    list = Citrine.signal_list([3, 1, 2])

    assert_same list, list.sort!
    assert_equal [1, 2, 3], list.get
    assert_same list, list.reverse!
    assert_equal [3, 2, 1], list.get
  end

  def test_reads_are_reactive
    list = Citrine.signal_list([1])
    sizes = []
    Citrine::Effect.create { sizes << list.size }

    list << 2
    list.delete_at(0)

    assert_equal [1, 2, 1], sizes
  end

  def test_iteration_in_effect_reacts_to_mutation
    list = Citrine.signal_list([:a])
    rendered = []
    Citrine::Effect.create { rendered << list.map(&:to_s).join(",") }

    list << :b

    assert_equal ["a", "a,b"], rendered
  end

  # B 的集合版本：普通类 include Citrine::Reactive 后也能直接 signal_list
  class Ledger
    include Citrine::Reactive

    def initialize
      @entries = signal_list([])
    end

    def entries = @entries
    def add(entry) = @entries << entry
    def total = @entries.get.sum
  end

  def test_reactive_mixin_offers_signal_list
    ledger = Ledger.new
    totals = []
    Citrine::Effect.create { totals << ledger.total }

    ledger.add(10)
    ledger.add(5)

    assert_equal [0, 10, 15], totals
  end

  # 与渲染器配合：集合变化触发块重跑，keyed 子组件按 key 复用（不重建）
  class CodeRow < Citrine::Component
    prop :code
    def view = label(css_class: "row") { code }
  end

  class ListWidget < Citrine::Component
    components CodeRow

    def initialize
      super
      @codes = Citrine.signal_list(%w[A B])
    end

    def codes = @codes

    def view
      stack do
        codes.each { |code| code_row(code: code, key: code) }
      end
    end
  end

  def test_component_view_rerenders_after_list_mutation
    widget = ListWidget.new
    renderer = Citrine::StringRenderer
    first = renderer.render(widget)

    assert_includes first, "A"
    assert_includes first, "B"

    codes_before = widget.codes.get
    widget.codes << "C"

    assert_equal %w[A B C], widget.codes.get
    assert_equal %w[A B], codes_before, "旧快照不受影响"
    assert_includes renderer.render(widget), "C"
  end
end
