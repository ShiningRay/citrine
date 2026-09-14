# frozen_string_literal: true

# 信号创建的三个人体工学入口（A/B/C）：
#   A. `Citrine.signal(value)` / `Citrine.signal { ... }`  —— 到处可用，且不必写出裸 `Signal`
#   B. `include Citrine::Reactive` → 普通类的 `signal(value)`
#   C. `Component#keyed_signal(name, key) { ... }`        —— 组件内按 key 记忆的信号表
# 背景见 citrine-market-terminal / citrine-sheets 的 FRICTION F14：裸写 `Signal` 会撞
# stdlib 的 `::Signal`，错误信息完全不指向真因。
require "minitest/autorun"
require "citrine"

class SignalErgonomicsTest < Minitest::Test
  # ── A ────────────────────────────────────────────────────
  def test_module_factory_creates_signal
    s = Citrine.signal(0)
    assert_instance_of Citrine::Signal, s
    assert_equal 0, s.get

    s.set(1)
    assert_equal 1, s.get
  end

  def test_module_factory_block_is_lazy_and_runs_once
    calls = 0
    s = Citrine.signal do
      calls += 1
      "computed-#{calls}"
    end

    assert_equal 0, calls, "块在创建时不应求值"
    assert_equal "computed-1", s.get
    assert_equal 1, calls
    assert_equal "computed-1", s.get
    assert_equal 1, calls, "只求值一次"
  end

  def test_lazy_signal_set_before_first_read_wins
    calls = 0
    s = Citrine.signal { calls += 1; :from_block }
    s.set(:explicit)

    assert_equal :explicit, s.get
    assert_equal 0, calls, "显式写入后不再跑惰性初值"
  end

  def test_factory_signal_is_reactive
    s = Citrine.signal(1)
    seen = []
    Citrine::Effect.create { seen << s.get }

    s.set(2)
    assert_equal [1, 2], seen
  end

  # ── B ────────────────────────────────────────────────────
  class TinyEngine
    include Citrine::Reactive

    attr_reader :quote_calls

    def initialize
      @quote_calls = 0
      @tick_signal = signal(0)
      @quote_signals = {}
    end

    def tick = @tick_signal.get
    def tick!(value) = @tick_signal.set(value)
    def tick_signal = @tick_signal

    def quote_signal(code)
      @quote_signals[code] ||= signal do
        @quote_calls += 1
        "quote-#{code}"
      end
    end
  end

  def test_reactive_mixin_gives_plain_classes_signal
    engine = TinyEngine.new
    assert_equal 0, engine.tick

    seen = []
    Citrine::Effect.create { seen << engine.tick }
    engine.tick!(1)
    assert_equal [0, 1], seen
  end

  def test_reactive_mixin_memoizes_lazily
    engine = TinyEngine.new
    first = engine.quote_signal("600519")

    assert_equal 0, engine.quote_calls, "取用时不求值"
    assert_equal "quote-600519", first.get
    assert_equal 1, engine.quote_calls

    assert_same first, engine.quote_signal("600519"), "同一 key 复用同一信号"
    refute_same first, engine.quote_signal("000858"), "不同 key 各自一个信号"
    assert_equal "quote-000858", engine.quote_signal("000858").get
    assert_equal 2, engine.quote_calls
  end

  # ── C ────────────────────────────────────────────────────
  class KeyedWidget < Citrine::Component
    state :prefix, default: "p"

    def cell(row, col) = keyed_signal(:cell, [row, col]) { "#{prefix}-#{row}#{col}" }
    def flag(row) = keyed_signal(:flag, row) { false }
  end

  def test_keyed_signal_memoizes_per_key
    w = KeyedWidget.new

    assert_same w.cell(1, 1), w.cell(1, 1), "同 key 同信号"
    refute_same w.cell(1, 1), w.cell(1, 2), "不同 key 各自信号"
    refute_same w.cell(1, 1), w.flag(1), "不同 name 的表互不干扰"
  end

  def test_keyed_signal_init_runs_in_component_context
    w = KeyedWidget.new
    assert_equal "p-23", w.cell(2, 3).get
  end

  def test_keyed_signal_is_reactive
    w = KeyedWidget.new
    seen = []
    Citrine::Effect.create { seen << w.cell(1, 1).get }

    w.cell(1, 1).set("changed")
    assert_equal ["p-11", "changed"], seen
  end

  def test_keyed_signal_without_block_defaults_to_nil
    w = KeyedWidget.new
    assert_nil w.keyed_signal(:empty, :k).get
  end
end
