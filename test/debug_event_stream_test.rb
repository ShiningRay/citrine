# frozen_string_literal: true

# M1-3：事件流探针（DESIGN-devtools P3）——Component#handle_event 前后对比
# flush_id 计数，记录 {t, event_type, target_component, handler_name, flush_ids}。
# flush_id 分配属 FlushTrace（M1-2），本测试按共享契约直接驱动
# Debug.flush_counter 模拟 flush，使差集断言不依赖 M1-2 是否已落地。
require "minitest/autorun"
require "json"
require "citrine"
require "citrine/debug"

class DebugEventStreamEl
  attr_reader :children
  attr_accessor :parent, :class_name, :text

  def initialize
    @children = []
  end
end

class DebugEventStreamRenderer < Citrine::Renderer
  private

  def setup_root(root, element)
    root.dom = element
  end

  def create_dom(_node)
    DebugEventStreamEl.new
  end

  def attach(node, parent)
    node.dom.parent = parent.dom
    parent.dom.children << node.dom
  end

  def detach(node)
    return unless node.dom.parent

    node.dom.parent.children.delete(node.dom)
    node.dom.parent = nil
  end

  def apply_props(_node); end

  def set_text(node, text)
    node.dom.text = text
    node.text = text
  end
end

class DebugEventStreamWidget < Citrine::Component
  state :count, default: 0

  def view
    box do
      label { "count=#{count}" }
      button(on_click: :inc) { "+1" }
    end
  end

  def inc
    self.count += 1
    :done
  end

  def bump_twice
    Citrine::Debug.flush_counter.next!
    Citrine::Debug.flush_counter.next!
  end

  def boom
    raise "事件处理器爆炸"
  end
end

class DebugEventStreamTest < Minitest::Test
  def setup
    Citrine.debug_tracking = true
    Citrine.debug_event_stream.clear
    Citrine.debug_event_stream.capacity = 500
  end

  def teardown
    Citrine.debug_tracking = false
    Citrine.debug_event_stream.clear
    Citrine.debug_event_stream.capacity = 500
  end

  def mount(widget)
    DebugEventStreamRenderer.new.mount_component(widget, DebugEventStreamEl.new)
  end

  def texts(node, acc = [])
    acc << node.text if node.text
    node.children.each { |child| texts(child, acc) }
    acc
  end

  def test_entry_point_returns_shared_ring
    assert_same Citrine::Debug.event_stream_ring, Citrine.debug_event_stream
    assert_equal 500, Citrine.debug_event_stream.capacity
  end

  def test_handle_event_records_event_metadata
    w = DebugEventStreamWidget.new
    mount(w)

    before = Citrine::Debug.flush_counter.current
    w.handle_event(:inc, Citrine::Event.new("click"))

    entries = Citrine.debug_event_stream.to_a
    assert_equal 1, entries.size
    entry = entries.first
    assert_kind_of Float, entry[:t]
    assert_equal "click", entry[:event_type]
    assert_equal "DebugEventStreamWidget", entry[:target_component]
    assert_equal w.object_id, entry[:component_id]
    assert_equal :inc, entry[:handler_name]
    assert_equal [before + 1], entry[:flush_ids],
                 ":inc 的写入在 batch ensure 触发一次真实 flush，flush_id 由 FlushTrace（M1-2）分配"
  end

  def test_flush_ids_are_counter_diff_around_dispatch
    w = DebugEventStreamWidget.new
    mount(w)
    before = Citrine::Debug.flush_counter.current

    w.handle_event(:bump_twice)

    entry = Citrine.debug_event_stream.to_a.first
    assert_equal [before + 1, before + 2], entry[:flush_ids],
                 "flush_ids 为 handle_event 前后 flush_id 计数的差集"
  end

  def test_proc_handler_records_source_location
    w = DebugEventStreamWidget.new
    mount(w)
    handler = -> { :noop }

    w.handle_event(handler, Citrine::Event.new("wheel"))

    entry = Citrine.debug_event_stream.to_a.first
    assert_match(/debug_event_stream_test\.rb:\d+/, entry[:handler_name])
  end

  def test_nil_event_records_none_and_key_event_records_key
    w = DebugEventStreamWidget.new
    mount(w)

    w.handle_event(:inc)
    w.handle_event(:inc, Citrine::KeyEvent.new("Enter"))

    entries = Citrine.debug_event_stream.to_a
    assert_equal :none, entries[0][:event_type]
    assert_equal "key", entries[1][:event_type]
  end

  def test_handle_key_hash_resolves_to_single_record
    w = DebugEventStreamWidget.new
    mount(w)

    w.handle_key({ "Enter" => :inc }, Citrine::KeyEvent.new("Enter"))
    w.handle_key({ "Enter" => :inc }, Citrine::KeyEvent.new("Escape"))

    entries = Citrine.debug_event_stream.to_a
    assert_equal 1, entries.size, "键表命中只记录一次（未命中不记录）"
    assert_equal :inc, entries.first[:handler_name]
  end

  def test_events_record_in_dispatch_order
    w = DebugEventStreamWidget.new
    mount(w)

    3.times { |i| w.handle_event(:inc, Citrine::Event.new("click-#{i}")) }

    types = Citrine.debug_event_stream.to_a.map { |e| e[:event_type] }
    assert_equal %w[click-0 click-1 click-2], types
  end

  def test_ring_overflow_drops_oldest
    Citrine.debug_event_stream.capacity = 3
    w = DebugEventStreamWidget.new
    mount(w)

    4.times { |i| w.handle_event(:inc, Citrine::Event.new("click-#{i}")) }

    ring = Citrine.debug_event_stream
    assert_equal 3, ring.size
    assert_equal %w[click-1 click-2 click-3], ring.to_a.map { |e| e[:event_type] }
  end

  def test_tracking_disabled_records_nothing
    Citrine.debug_tracking = false
    w = DebugEventStreamWidget.new
    mount(w)

    w.handle_event(:inc, Citrine::Event.new("click"))

    assert_empty Citrine.debug_event_stream.to_a
  end

  def test_raising_handler_still_records_and_reraises
    w = DebugEventStreamWidget.new
    mount(w)

    error = assert_raises(RuntimeError) do
      w.handle_event(:boom, Citrine::Event.new("click"))
    end
    assert_equal "事件处理器爆炸", error.message

    entries = Citrine.debug_event_stream.to_a
    assert_equal 1, entries.size, "异常事件也留痕（batch ensure 的 flush 链仍发生）"
    assert_equal :boom, entries.first[:handler_name]
  end

  def test_dispatch_semantics_unchanged_when_tracking_on
    w = DebugEventStreamWidget.new
    root = mount(w)

    result = w.handle_event(:inc, Citrine::Event.new("click"))

    assert_equal :done, result, "handle_event 返回值不被埋点改变"
    assert_includes texts(root), "count=1", "batch 内 state 写入照常触发重渲染"
  end

  def test_records_are_json_serializable
    w = DebugEventStreamWidget.new
    mount(w)
    w.handle_event(:inc, Citrine::Event.new("click"))
    w.handle_event(-> { :noop })

    parsed = JSON.parse(JSON.generate(Citrine.debug_event_stream.to_a))

    assert_equal "click", parsed[0]["event_type"]
    assert_equal "inc", parsed[0]["handler_name"]
    assert_equal "none", parsed[1]["event_type"]
    assert_equal [Citrine.debug_flush_trace.to_a.last[:flush_id]], parsed[0]["flush_ids"],
                 ":inc 引发的 flush 经 flush_id 与事件关联（M1-2）；无写入的事件才记空数组"
  end
end
