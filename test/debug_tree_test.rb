# frozen_string_literal: true

# M1-4：组件树快照 API（DESIGN-devtools P4）——Citrine.debug_component_tree
# 从渲染器根节点遍历 VDOM，输出组件树快照（props/state/computed 当前值 +
# 三个 effect 计数器 + reuse_key）。纯数据、可 to_json；不新埋点，
# 不依赖 debug_tracking 开关；SSR（StringRenderer，无 Effect）降级输出结构信息。
require "minitest/autorun"
require "json"
require "citrine"
require "citrine/string_renderer"
require "citrine/debug"

class DebugTreeEl
  attr_reader :children
  attr_accessor :parent, :class_name

  def initialize
    @children = []
  end
end

class DebugTreeRenderer < Citrine::Renderer
  private

  def setup_root(root, element)
    root.dom = element
  end

  def create_dom(_node)
    DebugTreeEl.new
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
    node.text = text
  end
end

# ── 被测组件 ────────────────────────────────────────────────

class DebugTreeGauge < Citrine::Component
  state :level, default: 1
  computed(:double) { level * 2 }
  watch { level }
  effect { }

  def view
    box(css_class: "gauge") { label { "L#{level}/#{double}" } }
  end
end

class DebugTreeLeaf < Citrine::Component
  prop :title, type: String, default: "leaf"
  state :clicks, default: 0
  computed(:shout) { title.upcase }

  def view
    box(css_class: "leaf") { label { "#{title}:#{clicks}" } }
  end
end

class DebugTreeParent < Citrine::Component
  components DebugTreeLeaf => :leaf
  prop :name, type: String
  state :tick, default: 0

  def view
    stack(css_class: "parent") do
      label { "tick=#{tick}" }
      leaf(title: "a", key: :one)
      leaf(title: "b", key: :two)
    end
  end
end

class DebugTreeRow < Citrine::Component
  prop :code, type: String
  prop :on_pick

  def view
    box(css_class: "row", on_click: -> { handle_event(on_pick, code) }) { label { code } }
  end
end

class DebugTreeList < Citrine::Component
  components DebugTreeRow => :tree_row
  state :codes, default: %w[A B C]
  state :picked, default: nil

  def view
    stack(css_class: "list") do
      codes.each { |code| tree_row(code: code, on_pick: ->(c) { self.picked = c }, key: code) }
    end
  end
end

# ── 测试 ────────────────────────────────────────────────────

class DebugTreeTest < Minitest::Test
  def setup
    Citrine.debug_tracking = false # P4 是纯自省 API：埋点总开关关闭也必须可用
  end

  def mount(widget)
    DebugTreeRenderer.new.mount_component(widget, DebugTreeEl.new)
  end

  def test_snapshot_captures_component_values_and_effect_counters
    root = mount(DebugTreeGauge.new)
    tree = Citrine.debug_component_tree(root)

    assert_equal "DebugTreeGauge", tree[:component]
    assert_equal({}, tree[:props])
    assert_equal({ level: 1 }, tree[:state])
    assert_equal({ double: 2 }, tree[:computed])
    assert_equal 1, tree[:watch_effect_count]
    assert_equal 1, tree[:effect_count]
    assert_equal 1, tree[:computation_effect_count]
    assert_nil tree[:reuse_key]
    assert_empty tree[:children]
  end

  def test_nested_components_appear_as_children
    root = mount(DebugTreeParent.new(name: "root"))
    tree = Citrine.debug_component_tree(root)

    assert_equal "DebugTreeParent", tree[:component]
    assert_equal({ name: "root" }, tree[:props])
    assert_equal({ tick: 0 }, tree[:state])

    children = tree[:children]
    assert_equal %w[DebugTreeLeaf DebugTreeLeaf], children.map { |c| c[:component] }
    assert_equal [{ title: "a" }, { title: "b" }], children.map { |c| c[:props] }
    assert_equal [{ clicks: 0 }, { clicks: 0 }], children.map { |c| c[:state] }
    assert_equal [{ shout: nil }, { shout: nil }], children.map { |c| c[:computed] },
                 "声明过但未求值的 computed 列出为 nil（快照不得触发惰性求值）"
    assert_equal %i[one two], children.map { |c| c[:reuse_key] }

    boundaries = component_roots(root)
    assert_equal boundaries.map(&:object_id), children.map { |c| c[:node_id] },
                 "node_id 应是组件边界节点的 object_id（highlight_node 锚点）"
  end

  def test_snapshot_reflects_current_values
    parent = DebugTreeParent.new(name: "root")
    root = mount(parent)
    leaf = component_roots(root).first.rendered_component
    leaf.clicks = 3
    parent.tick = 1

    tree = Citrine.debug_component_tree(root)

    assert_equal 1, tree[:state][:tick]
    assert_equal 3, tree[:children].first[:state][:clicks], "快照是调用时刻的现读，不是渲染时的旧值"
  end

  def test_keyed_list_snapshot_tracks_reuse
    list = DebugTreeList.new
    root = mount(list)
    before = Citrine.debug_component_tree(root)[:children]
    ids_by_key = before.to_h { |c| [c[:reuse_key], c[:node_id]] }
    assert_equal %w[A B C], before.map { |c| c[:props][:code] }

    list.codes = %w[C A]

    after = Citrine.debug_component_tree(root)[:children]
    assert_equal 2, after.size
    assert_equal %w[C A], after.map { |c| c[:props][:code] }
    after.each do |c|
      assert_equal ids_by_key[c[:reuse_key]], c[:node_id],
                   "key #{c[:reuse_key].inspect} 命中的行应复用同一节点（node_id 不变）"
    end
  end

  def test_callback_props_are_sanitized_for_transport
    root = mount(DebugTreeList.new)
    row = Citrine.debug_component_tree(root)[:children].first

    assert_equal "A", row[:props][:code]
    assert_equal "(proc)", row[:props][:on_pick], "事件回调 Proc 不可序列化，应记占位串"

    assert_equal "(proc)", JSON.parse(JSON.generate(row))["props"]["on_pick"]
  end

  def test_ssr_string_renderer_degrades_to_structure_info
    root = Citrine::StringRenderer.new.mount_component(DebugTreeGauge.new, nil)
    tree = Citrine.debug_component_tree(root)

    assert_equal "DebugTreeGauge", tree[:component]
    assert_equal({ level: 1 }, tree[:state])
    assert_equal({ double: 2 }, tree[:computed])
    assert_equal 0, tree[:watch_effect_count], "SSR 不建 watch Effect"
    assert_equal 0, tree[:effect_count], "SSR 不建 effect 宏实例"
    assert_equal 1, tree[:computation_effect_count], "computed 无 Effect 环境也照常求值一次"
  end

  def test_snapshot_is_json_serializable
    root = mount(DebugTreeParent.new(name: "root"))
    parsed = JSON.parse(JSON.generate(Citrine.debug_component_tree(root)))

    assert_equal "DebugTreeParent", parsed["component"]
    assert_equal "root", parsed["props"]["name"]
    leaf = parsed["children"].first
    assert_equal "DebugTreeLeaf", leaf["component"]
    assert_equal "a", leaf["props"]["title"]
    assert_equal({ "clicks" => 0 }, leaf["state"])
    assert_equal "one", leaf["reuse_key"]
  end

  def test_invalid_root_raises
    assert_nil Citrine.debug_component_tree(nil)

    error = assert_raises(ArgumentError) { Citrine.debug_component_tree(Object.new) }
    assert_match(/根节点/, error.message)
  end

  private

  # 子组件的边界节点：带 rendered_component 标记的真实节点
  def component_roots(node, acc = [])
    acc << node if node.rendered_component
    node.children.each { |child| component_roots(child, acc) }
    acc
  end
end
