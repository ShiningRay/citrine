# frozen_string_literal: true

# T-B3：DevTools 依赖图数据层——signal→effect 边与重跑计数可导出（JSON 可序列化）。
# 埋点默认关闭零开销；Sentry / Cytoscape UI 为后续工作（需外部资源）。
require "minitest/autorun"
require "json"
require "citrine"

class DebugGraphWidget < Citrine::Component
  state :n, default: 1
  computed(:sq) { n * n }

  def view
    box do
      label { "n=#{n} sq=#{sq}" }
      button(on_click: :inc) { "+1" }
    end
  end

  def inc
    self.n += 1
  end
end

class DebugGraphTest < Minitest::Test
  def setup
    citrine_signal = Citrine::Signal
    citrine_effect = Citrine::Effect
    citrine_signal.debug_tracking = true
    citrine_effect.debug_tracking = true
    citrine_signal.all.clear
    citrine_effect.all.clear
  end

  def teardown
    Citrine::Signal.debug_tracking = false
    Citrine::Effect.debug_tracking = false
    Citrine::Signal.all.clear
    Citrine::Effect.all.clear
  end

  def graph(widget)
    require "citrine/string_renderer"
    Class.new(Citrine::Renderer) do
      def setup_root(root, element)
        root.dom = element
      end

      def create_dom(_node)
        Class.new do
          attr_accessor :parent, :text, :class_name
          def children = (@c ||= [])
        end.new
      end

      def attach(node, parent)
        node.dom.parent = parent.dom
        parent.dom.children << node.dom
      end

      def detach(node)
        node.dom.parent&.children&.delete(node.dom)
      end

      def apply_props(_node); end

      def set_text(node, text)
        node.text = text
      end
    end.new.mount_component(widget, Class.new do
      attr_accessor :parent, :text, :class_name
      def children = (@c ||= [])
    end.new)
    Citrine.debug_dependency_graph
  end

  def test_dependency_graph_export_includes_edges_and_run_counts
    graph = graph(DebugGraphWidget.new)

    assert graph[:signals].size >= 1, "n 与 sq 的信号应被记录"
    assert graph[:effects].size >= 1, "view 块与 computed Effect 应被记录"

    signal_ids = graph[:signals].map { |s| s[:id] }
    effect_with_deps = graph[:effects].find { |e| !e[:deps].empty? }
    assert effect_with_deps, "至少有一个 Effect 依赖了信号（signal→effect 边）"
    assert effect_with_deps[:deps].all? { |d| signal_ids.include?(d) }, "边必须指向已记录的信号"
    assert_equal 1, effect_with_deps[:runs], "首轮渲染重跑计数为 1"
  end

  def test_run_count_increments_across_updates
    w = DebugGraphWidget.new
    graph(w)
    # 选单依赖的 Effect（computed sq 只依赖 n）：计数确定性不受级联影响
    effect = Citrine::Effect.all.find { |e| !e.disposed? && e.debug_info[:deps].size == 1 }

    w.n = 2

    assert_equal 2, effect.debug_info[:runs], "信号变化后该 Effect 重跑计数 +1"
  end

  def test_export_is_json_serializable
    graph = graph(DebugGraphWidget.new)

    json = JSON.generate(graph)
    parsed = JSON.parse(json)

    assert parsed["signals"].is_a?(Array)
    assert parsed["effects"].first.key?("runs")
  end

  def test_tracking_disabled_records_nothing
    # 专门验证关闭态：埋点关闭期间新建的 Effect 不进入记录（生产零开销）
    Citrine::Signal.debug_tracking = false
    Citrine::Effect.debug_tracking = false
    before = Citrine::Effect.all.size

    w = DebugGraphWidget.new
    graph(w)

    assert_equal before, Citrine::Effect.all.size, "埋点关闭期间创建的 Effect 不进入记录"
  end
end
