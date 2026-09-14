# frozen_string_literal: true

# 组件嵌套 + keyed 复用（P0-1 / FRICTION F5+F6）的语义回归。
# 平台无关部分用最小渲染器在 CRuby 下验证，DOM 细节由 Node 桩与真机验收覆盖。
require "minitest/autorun"
require "citrine"
require "citrine/string_renderer"

class FakeEl
  attr_reader :children
  attr_accessor :parent, :class_name

  def initialize(tag = "el")
    @tag = tag
    @children = []
    @style = {}
  end

  def style = @style
end

# 记录挂载/解绑全局键盘，便于断言嵌套组件的生命周期
class NestingRenderer < Citrine::Renderer
  attr_reader :window_keys

  def initialize
    super
    @window_keys = []
  end

  private

  def setup_root(root, element)
    root.dom = element
  end

  def create_dom(_node)
    FakeEl.new
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

  def apply_props(node)
    node.dom.class_name = prop_value(node, node.props[:css_class]) if node.props.key?(:css_class)
  end

  def set_text(node, text)
    node.text = text
  end

  def register_window_key(component, handler)
    @window_keys << [component, handler]
  end

  def unregister_window_keys(component)
    @window_keys.reject! { |(c, _)| c.equal?(component) }
  end
end

# ── 被测组件 ────────────────────────────────────────────────

class NestedChild < Citrine::Component
  prop :title, type: String, default: "child"
  state :clicks, default: 0

  class << self
    attr_accessor :mounts, :unmounts
  end
  self.mounts = 0
  self.unmounts = 0

  on_mount { self.class.mounts += 1 }
  on_unmount { self.class.unmounts += 1 }

  def view
    stack(css_class: "child") do
      label(css_class: "child-label") { "#{title}:#{clicks}" }
    end
  end
end

class NestingParent < Citrine::Component
  components NestedChild
  state :tick, default: 0

  def view
    stack(css_class: "parent") do
      label(css_class: "tick") { "tick=#{tick}" }
      nested_child(title: "a", key: :one)
      box(key: :plain) { label { "plain-#{tick}" } }
    end
  end
end

class UnkeyedParent < Citrine::Component
  components NestedChild
  state :tick, default: 0

  def view
    stack(css_class: "parent") do
      label(css_class: "tick") { "tick=#{tick}" } # 父块读了信号 → tick 变化时父块重跑
      nested_child(title: "a")                     # 无 key → 每次重跑都新建
    end
  end
end

class ListRow < Citrine::Component
  prop :code, type: String
  prop :on_pick

  class << self
    attr_accessor :unmounts
  end
  self.unmounts = 0

  on_unmount { self.class.unmounts += 1 }

  def view
    box(css_class: "row", on_click: -> { handle_event(on_pick, code) }) { label { code } }
  end
end

class ListParent < Citrine::Component
  components ListRow
  state :codes, default: %w[A B C]
  state :picked, default: nil

  def view
    stack(css_class: "list") do
      codes.each do |code|
        list_row(code: code, on_pick: ->(c) { self.picked = c }, key: code)
      end
    end
  end
end

class ConflictParent < Citrine::Component
  # `row` 已经是布局语法糖 → 组件名 Row 会撞名，必须显式改名
  class Row < Citrine::Component
    def view = label { "x" }
  end
  components Row => :data_row

  def view = data_row
end

class BareComponent < Citrine::Component
  def view = label { "x" }
end

class StringViewChild < Citrine::Component
  def view = "纯文本"
end

class StringViewParent < Citrine::Component
  components StringViewChild

  def view
    stack { string_view_child }
  end
end

# ── 测试 ────────────────────────────────────────────────────

class NestingTest < Minitest::Test
  def setup
    NestedChild.mounts = 0
    NestedChild.unmounts = 0
    ListRow.unmounts = 0
  end

  def mount(widget)
    NestingRenderer.new.mount_component(widget, FakeEl.new)
  end

  def test_child_view_is_rendered_inline
    root = mount(NestingParent.new)
    texts = collect_texts(root)

    assert_includes texts, "tick=0"
    assert_includes texts, "a:0"
    assert_includes texts, "plain-0"
  end

  def test_keyed_child_keeps_instance_and_state_across_parent_rerun
    parent = NestingParent.new
    root = mount(parent)
    child_el = find_first(root, "child")
    labels_before = find_all(root, "child-label").map(&:dom)

    parent.tick = 1 # 父块重跑

    assert_equal 1, NestedChild.mounts, "keyed 子组件不应被重建（on_mount 只跑一次）"
    assert_same child_el, find_first(root, "child"), "子组件子树应沿用同一批节点"
    assert_equal labels_before, find_all(root, "child-label").map(&:dom)
    assert_includes collect_texts(root), "tick=1", "父块自身的内容照常更新"
  end

def test_unkeyed_child_is_reused_by_position
  parent = UnkeyedParent.new
  mount(parent)
  assert_equal 1, NestedChild.mounts

  parent.tick = 1 # 父 view 重跑（marker 在 view 体里读）

  assert_equal 1, NestedChild.mounts, "没有 key 时按位置复用（React 的隐含位置 key）"
  assert_equal 0, NestedChild.unmounts
end

  def test_reorder_reuses_same_nodes_and_applies_new_order
    parent = ListParent.new
    root = mount(parent)
    rows_before = find_all(root, "row")
    labels_before = rows_before.map(&:dom)

    parent.codes = %w[C A B]

    rows_after = find_all(root, "row")
    assert_equal labels_before.sort_by(&:object_id), rows_after.map(&:dom).sort_by(&:object_id),
                 "重排应复用同一批行节点（只是换了位置）"
    assert_equal %w[C A B], rows_after.map { |row| row.children.first.text }
  end

  def test_removed_row_runs_unmount_hook_and_detaches
    parent = ListParent.new
    root = mount(parent)
    rows = find_all(root, "row")
    removed_dom = rows[1].dom

    parent.codes = %w[A C]

    assert_equal 1, ListRow.unmounts, "被移除的行应跑 on_unmount"
    refute_includes find_all(root, "row").map(&:dom), removed_dom
    assert_equal 0, root.children.first.children.count(removed_dom), "DOM 应被摘除"
  end

  def test_removed_whole_parent_runs_nested_unmount
    parent = ListParent.new
    root = mount(parent)

    Citrine.unmount(parent)

    assert_equal 3, ListRow.unmounts
    assert_empty root.children
  end

  def test_child_callback_reaches_parent
    parent = ListParent.new
    root = mount(parent)
    row = find_all(root, "row").last
    # 通过边界节点拿到子组件实例，再走它的回调路径（DOM 事件本身由桩/真机覆盖）
    child = boundaries(root).last.rendered_component

    child.handle_event(child.props[:on_pick], "C")

    assert_equal "C", parent.picked
    assert_same row.children.first.dom, find_all(root, "row").last.children.first.dom
  end

  def test_duplicate_key_raises
    klass = Class.new(Citrine::Component) do
      components ListRow

      def view
        stack do
          list_row(code: "A", key: :dup)
          list_row(code: "B", key: :dup)
        end
      end
    end

    error = assert_raises(RuntimeError) { mount(klass.new) }
    assert_match(/重复 key/, error.message)
  end

  def test_props_change_rebuilds_keyed_child
    parent = ListParent.new
    mount(parent)
    before = NestedChild.mounts

    # 同一 key、不同 props → S1 语义：重建（S2 会改为原地更新）
    klass = Class.new(Citrine::Component) do
      components NestedChild
      state :label_text, default: "a"

      def view = stack { nested_child(title: label_text, key: :one) }
    end
    widget = klass.new
    mount(widget)
    first_mounts = NestedChild.mounts

    widget.label_text = "b"

    assert_equal first_mounts + 1, NestedChild.mounts, "props 变化时 keyed 子组件应重建"
    assert_operator before, :<=, NestedChild.mounts
  end

  def test_element_keys_are_reused_too
    parent = NestingParent.new
    root = mount(parent)
    plain_before = find_all(root, "plain-0").map(&:dom)

    parent.tick = 2

    # key: :plain 的元素被复用（其 block 重跑与否取决于它读了什么信号）
    assert_equal plain_before, find_all(root, "plain-2").map(&:dom)
  end

def test_components_keyword_conflict_raises_with_hint
  error = assert_raises(ArgumentError) do
    Class.new(Citrine::Component) do
      components BareComponent => :row # row 已被布局语法糖占用
    end
  end

  assert_match(/重名/, error.message)
end

def test_components_with_anonymous_class_needs_explicit_keyword
  error = assert_raises(ArgumentError) do
    Class.new(Citrine::Component) { components Class.new(Citrine::Component) }
  end

  assert_match(/具名/, error.message)
end

  def test_components_keyword_can_be_renamed
    root = mount(ConflictParent.new)

    assert_includes collect_texts(root), "x"
  end

  def test_nested_view_must_render_elements
    error = assert_raises(RuntimeError) { mount(StringViewParent.new) }
    assert_match(/必须渲染元素节点/, error.message)
  end

  def test_render_outside_view_raises
    widget = Class.new(Citrine::Component) do
      def view = label { "x" }
    end.new

    error = assert_raises(RuntimeError) { widget.render(ListRow, code: "A") }
    assert_match(/没有父节点/, error.message)
  end

  def test_render_with_block_is_not_supported_yet
    widget = Class.new(Citrine::Component) do
      components ListRow

      def view
        stack { list_row(code: "A") { label { "slot" } } }
      end
    end.new

    error = assert_raises(ArgumentError) { mount(widget) }
    assert_match(/插槽/, error.message)
  end

  def test_nested_window_key_is_registered_and_unregistered
    renderer = NestingRenderer.new
    widget = Class.new(Citrine::Component) do
      window_key :on_key

      def view = label { "x" }
    end.new
    renderer.mount_component(widget, FakeEl.new)

    assert_equal 1, renderer.window_keys.size
    Citrine.unmount(widget)
    assert_empty renderer.window_keys
  end

  def test_ssr_renders_nested_components_inline
    html = Citrine.render(NestingParent.new)

    assert_includes html, 'class="parent"'
    assert_includes html, 'class="child"'
    assert_includes html, "a:0"
  end

  private

  def collect_texts(node, acc = [])
    acc << node.text if node.text
    node.children.each { |child| collect_texts(child, acc) }
    acc
  end

  def find_all(node, class_name, acc = [])
    acc << node if node.props[:css_class].to_s.split(" ").include?(class_name)
    node.children.each { |child| find_all(child, class_name, acc) }
    acc
  end

  def find_first(node, class_name)
    find_all(node, class_name).first
  end

  # 组件边界节点（虚拟节点）：type == :component
  def boundaries(node, acc = [])
    acc << node if node.type == :component
    node.children.each { |child| boundaries(child, acc) }
    acc
  end
end
