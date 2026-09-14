# frozen_string_literal: true

# 声明式订阅 `watch`：挂载后跑一次，之后依赖的信号变化就重跑，卸载时自动 dispose。
#
# 测试用两种渲染器走真实路径：
#   · ReactiveString —— StringRenderer 但 reactive? = true（建 Effect，等价 DOM/Canvas）
#   · Citrine.render —— 真 SSR（不建 Effect，watcher 不该被创建）
require "minitest/autorun"
require "citrine"
require "citrine/string_renderer"

class WatchTest < Minitest::Test
  class ReactiveString < Citrine::StringRenderer
    private

    def reactive? = true
  end

  class Counter < Citrine::Component
    state :n, default: 0
    state :tag, default: "a"

    attr_reader :seen, :second_seen

    def initialize(...)
      super
      @seen = []
      @second_seen = []
    end

    watch :collect
    watch { second_seen << tag }

    def view = label { "n=#{n}" }

    def collect = seen << n
  end

  def mount(counter)
    ReactiveString.render(counter)
    counter
  end

  def test_watcher_runs_once_on_mount_and_reruns_on_dependency_change
    c = mount(Counter.new)

    assert_equal 2, c.watch_effect_count, "两个 watch 声明各自一个 Effect"
    assert_equal [0], c.seen

    c.n = 1
    c.n = 2
    assert_equal [0, 1, 2], c.seen, "读到的信号变化应重跑"
  end

  def test_each_watcher_has_its_own_effect
    c = mount(Counter.new)

    assert_equal ["a"], c.second_seen

    c.tag = "b"
    assert_equal ["a", "b"], c.second_seen
    assert_equal [0], c.seen, "另一个 watcher 不该被牵连"
  end

  def test_unmount_disposes_watchers
    c = mount(Counter.new)
    c.run_unmount_hooks

    assert_equal 0, c.watch_effect_count

    c.n = 5
    assert_equal [0], c.seen, "卸载后不该再被信号打回来"
  end

  def test_remount_after_unmount_creates_watchers_again
    c = mount(Counter.new)
    c.run_unmount_hooks
    mount(c)

    assert_equal 2, c.watch_effect_count
    assert_equal [0, 0], c.seen
  end

  class Inherited < Counter
    watch :extra

    attr_reader :extra_seen

    def initialize(...)
      super
      @extra_seen = []
    end

    def extra = extra_seen << n
  end

  def test_watchers_are_inherited_from_superclass
    c = mount(Inherited.new)

    assert_equal 3, c.watch_effect_count
    assert_equal [0], c.extra_seen
    assert_equal [0], c.seen, "父类声明的 watcher 也要跑"
  end

  def test_watch_requires_a_handler
    error = assert_raises(ArgumentError) { Class.new(Citrine::Component) { watch } }
    assert_match(/至少一个处理器/, error.message)
  end

  # SSR：不建 Effect（reactive? = false）→ watcher 不该被创建，副作用不该发生
  def test_ssr_does_not_run_watchers
    c = Counter.new
    html = Citrine.render(c)

    assert_equal 0, c.watch_effect_count
    assert_equal [], c.seen
    refute_empty html
  end
end
