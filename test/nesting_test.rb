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

  # S1-2：信号驱动的 view 重跑把根挪回原渲染位（镜像真实 DOM 的 insertBefore 语义）
  def attach_before(node, parent, anchor)
    dom = parent.dom
    dom.children.delete(node.dom)
    idx = dom.children.index(anchor.dom)
    dom.children.insert(idx || dom.children.size, node.dom)
    node.dom.parent = dom
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

# S1-4：children 插槽的宿主——children 落位在 slot-body 容器内
class SlotChild < Citrine::Component
  def view
    box(css_class: "slot-body") { children }
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
    child = component_roots(root).last.rendered_component

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

  # S1-2：props 变化 → 子组件实例与 state 原地保留，只有读该 prop 的块重跑
  def test_props_change_keeps_keyed_child_instance
    parent = ListParent.new
    mount(parent)

    # 同一 key、props 变化 → S1-2 语义：原地更新（旧语义是重建、丢光子组件 state）
    klass = Class.new(Citrine::Component) do
      components NestedChild
      state :label_text, default: "a"

      def view = stack { nested_child(title: label_text, key: :one) }
    end
    widget = klass.new
    root = mount(widget)
    child = component_roots(root).first.rendered_component
    child.clicks = 2
    first_mounts = NestedChild.mounts

    widget.label_text = "b"

    assert_equal first_mounts, NestedChild.mounts, "props 变化不再重建 keyed 子组件"
    assert_equal 0, NestedChild.unmounts, "被保留的子组件不应走卸载"
    assert_includes collect_texts(root), "b:2", "读 title 的块应重跑出新文案，且子组件 clicks 未被重置"
  end

  def test_element_keys_are_reused_too
    parent = NestingParent.new
    root = mount(parent)
    plain_before = find_all(root, "plain-0").map(&:dom)

    parent.tick = 2

    # key: :plain 的元素被复用（其 block 重跑与否取决于它读了什么信号）
    assert_equal plain_before, find_all(root, "plain-2").map(&:dom)
  end

  # 回归（FRICTION F24）：同一父块里按条件换**子组件类型**时，新组件的根元素不能按位置
  # 抢到旧组件的根节点——抢到的话 refresh_node 会沿用旧节点的 Effect，而 Effect 里是
  # `node.owner.instance_exec(&node.block)`，owner 仍是旧实例 → 新块在老 self 上执行
  # （表现为 NameError；Opal/DOM 侧表现为页面卡死）。
  def test_swapping_component_type_in_same_block_does_not_steal_old_root
    trade_row = Class.new(Citrine::Component) do
      prop :trade

      def view = box(css_class: "log-row") { label { trade[:id] } }
    end
    order_row = Class.new(Citrine::Component) do
      prop :order

      def view = box(css_class: "log-row") { label { order[:id] } }
    end
    parent = Class.new(Citrine::Component) do
      state :tab, default: :trades

      define_method(:view) do
        box(css_class: "log-body") do
          if tab == :trades
            render(trade_row, trade: { id: "T1" }, key: "T1")
            render(trade_row, trade: { id: "T2" }, key: "T2")
          else
            render(order_row, order: { id: "O1" }, key: "O1")
          end
        end
      end
    end.new

    root = mount(parent)
    texts = collect_texts(root)
    assert_includes texts, "T1"
    assert_includes texts, "T2"

    parent.tab = :orders

    texts = collect_texts(root)
    assert_includes texts, "O1", "换组件类型后应渲染新组件的根内容"
    refute_includes texts, "T1", "旧组件的根内容应随卸载消失"
    refute_includes texts, "T2"
  end

  # 同一族：组件根被**普通元素**取代时也不能复用那个节点（否则旧组件实例既不卸载、
  # 其状态与 Effect 还会继续挂在被"改嫁"的节点上）
  def test_component_root_is_not_reused_as_a_plain_element
    unmounted = 0
    row = Class.new(Citrine::Component) do
      prop :id
      on_unmount -> { unmounted += 1 }

      def view = box(css_class: "row") { label { id } }
    end
    parent = Class.new(Citrine::Component) do
      state :show_row, default: true

      define_method(:view) do
        stack do
          if show_row
            render(row, id: "R1", key: "R1")
          else
            box(css_class: "row") { label { "plain" } }
          end
        end
      end
    end.new

    root = mount(parent)
    assert_includes collect_texts(root), "R1"

    parent.show_row = false

    texts = collect_texts(root)
    assert_includes texts, "plain"
    refute_includes texts, "R1"
    assert_equal 1, unmounted, "被取代的子组件应走卸载钩子"
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

  # S1-4：多根子组件按 fragment 处理——0 根仍然报错（纯文本请包 label）
  def test_nested_view_with_zero_roots_raises
    error = assert_raises(RuntimeError) { mount(StringViewParent.new) }
    assert_match(/至少一个/, error.message)
  end

  def test_render_outside_view_raises
    widget = Class.new(Citrine::Component) do
      def view = label { "x" }
    end.new

    error = assert_raises(RuntimeError) { widget.render(ListRow, code: "A") }
    assert_match(/没有父节点/, error.message)
  end

  # ── S1-4：插槽 children —— render(Child) { … } 的块在子组件里落位 ──

  def test_children_block_renders_inside_child_layout
    parent = Class.new(Citrine::Component) do
      components SlotChild

      def view = stack { slot_child { label(css_class: "from-parent") { "父传内容" } } }
    end.new
    root = mount(parent)

    assert_includes collect_texts(find_first(root, "slot-body")), "父传内容",
                    "父传块的输出应出现在子组件布局内部"
  end

  def test_children_update_in_place_when_signal_changes
    parent = Class.new(Citrine::Component) do
      components SlotChild
      state :word, default: "一"

      def view = stack { slot_child { label(css_class: "from-parent") { word } } }
    end.new
    root = mount(parent)
    before = find_all(root, "from-parent").map(&:dom)

    parent.word = "二"

    assert_equal before, find_all(root, "from-parent").map(&:dom),
                 "children 由自己的块 Effect 驱动，原地更新、DOM 不换新"
    assert_includes collect_texts(root), "二"
  end

  def test_children_block_disappears_when_no_longer_passed
    parent = Class.new(Citrine::Component) do
      components SlotChild
      state :show, default: true

      def view
        stack do
          if show
            slot_child { label(css_class: "from-parent") { "内容" } }
          else
            slot_child
          end
        end
      end
    end.new
    root = mount(parent)
    assert_includes collect_texts(root), "内容"

    parent.show = false

    refute_includes collect_texts(root), "内容", "children 块消失应随 presence 翻转被移除"

    parent.show = true

    assert_includes collect_texts(root), "内容", "children 块复现应重新落位"
  end

  def test_multi_root_child_is_supported_as_fragment
    unmounted = 0
    child = Class.new(Citrine::Component) do
      on_unmount -> { unmounted += 1 }

      define_method(:view) do
        stack(css_class: "root-a") { label { "A" } }
        stack(css_class: "root-b") { label { "B" } }
      end
    end
    parent = Class.new(Citrine::Component) do
      components child => :multi

      def view = stack { multi }
    end.new
    root = mount(parent)

    assert_includes collect_texts(root), "A"
    assert_includes collect_texts(root), "B", "多根子组件不再抛错，两根都应渲染"

    Citrine.unmount(parent)

    assert_equal 1, unmounted, "多根子组件卸载只跑一次 on_unmount"
    assert_empty root.children, "两个根都应被 detach，宿主无残留"
  end

  def test_multi_root_child_renders_in_ssr
    child = Class.new(Citrine::Component) do
      define_method(:view) do
        label { "A" }
        label { "B" }
      end
    end
    parent = Class.new(Citrine::Component) do
      components child => :multi

      def view = stack { multi }
    end

    assert_includes Citrine.render(parent.new), "<p>A</p><p>B</p>", "SSR 侧多根按 fragment 拼接"
  end

  def test_multi_root_child_view_reruns_and_disappears_roots
    child = Class.new(Citrine::Component) do
      state :n, default: 1

      define_method(:view) do
        stack(css_class: "root-a") { label { "A" } }
        stack(css_class: "root-b") { label { "B" } } if n == 1
      end
    end
    parent = Class.new(Citrine::Component) do
      components child => :multi

      def view = stack { multi }
    end.new
    root = mount(parent)
    multi_child = component_roots(root).first.rendered_component
    assert_includes collect_texts(root), "B"

    multi_child.n = 2 # view 体读取（条件根）→ 子组件自己的 view Effect 重跑

    assert_includes collect_texts(root), "A"
    refute_includes collect_texts(root), "B", "消失的根应随重跑被卸载"
    assert_equal 1, find_all(root, "root-a").size

    multi_child.n = 1

    assert_includes collect_texts(root), "B", "复出的根应重新渲染"
  end

  def test_child_view_body_read_reruns_view_effect_and_swaps_root
    child = Class.new(Citrine::Component) do
      state :expanded, default: false

      define_method(:view) do
        box(css_class: expanded ? "open" : "shut") { label { "x" } }
      end
    end
    parent = Class.new(Citrine::Component) do
      components child => :pane

      def view = stack { pane }
    end.new
    root = mount(parent)
    shut_box = find_first(root, "shut")
    assert shut_box

    component_roots(root).first.rendered_component.expanded = true

    open_box = find_first(root, "open")
    assert open_box, "view 体读取变化应经 view Effect 重跑出新根"
    refute_same shut_box.dom, open_box.dom, "css_class 值类 prop 变化走元素重建（新节点）"
    assert_nil find_all(root, "shut").first, "旧根应被卸载"
  end

  def test_view_rerun_keeps_sibling_order
    child = Class.new(Citrine::Component) do
      state :expanded, default: false

      define_method(:view) do
        box(css_class: expanded ? "open" : "shut") { label { "x" } }
      end
    end
    parent = Class.new(Citrine::Component) do
      components child => :pane

      def view = stack { pane; label(css_class: "tail") { "尾" } }
    end.new
    root = mount(parent)
    host = root.children.first.dom
    tail = find_first(root, "tail").dom

    component_roots(root).first.rendered_component.expanded = true

    new_root_dom = find_first(root, "open").dom
    assert_equal [new_root_dom, tail], host.children.last(2),
                 "view 重跑换根后，新根应回到原渲染位（在后续兄弟之前）"
  end

  # ── S1-9：组件 ref —— 登记实例而非 prop ─────────────────────

  def test_component_ref_registers_instance
    parent = Class.new(Citrine::Component) do
      components NestedChild

      def view = stack { nested_child(title: "a", ref: :kid, key: :one) }
    end.new
    mount(parent)

    kid = parent.refs[:kid]
    assert_kind_of NestedChild, kid, "组件 ref 应登记子组件实例（元素 ref 才登记 DOM）"
    assert_equal "a", kid.title
  end

  def test_component_ref_points_to_new_instance_after_swap
    row = Class.new(Citrine::Component) do
      prop :id

      def view = box { label { id } }
    end
    other = Class.new(Citrine::Component) do
      prop :id

      def view = label { id }
    end
    parent = Class.new(Citrine::Component) do
      state :tab, default: :row

      define_method(:view) do
        stack do
          if tab == :row
            render(row, id: "R", ref: :pane, key: "pane")
          else
            render(other, id: "O", ref: :pane, key: "pane")
          end
        end
      end
    end.new
    mount(parent)

    assert_instance_of row, parent.refs[:pane]

    parent.tab = :other

    assert_instance_of other, parent.refs[:pane], "子组件重建后 ref 应指向新实例"
  end

  def test_element_ref_still_registers_dom_handle
    parent = Class.new(Citrine::Component) do
      def view = stack { box(css_class: "target", ref: :el) }
    end.new
    root = mount(parent)

    assert_same find_first(root, "target").dom, parent.refs[:el], "元素 ref 行为不变（平台句柄）"
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

  # S3：子组件的根元素换类型 ≠ 组件卸载——既不能跑 on_unmount，也不能丢 window_key
  # （此前 dispose 把还活着的子组件当成卸载，解绑全局键盘后 adopt_root 又不重新注册）
  def test_child_root_type_change_keeps_component_alive
    unmounted = 0
    child_klass = Class.new(Citrine::Component) do
      state :expanded, default: false
      window_key :on_key_press
      on_unmount -> { unmounted += 1 }

      def on_key_press(_ev); end

      def view
        expanded ? label(css_class: "leaf") { "open" } : box(css_class: "panel") { label { "closed" } }
      end
    end
    parent = Class.new(Citrine::Component) do
      define_method(:view) do
        stack { render(child_klass, key: "c") }
      end
    end.new

    renderer = NestingRenderer.new
    root = renderer.mount_component(parent, FakeEl.new)

    assert_equal 1, renderer.window_keys.size
    assert_equal :box, component_roots(root).first.type

    component_roots(root).first.rendered_component.expanded = true

    assert_equal :label, component_roots(root).first.type, "根元素应换成 label"
    assert_equal 0, unmounted, "根元素换类型不是组件卸载，不该跑 on_unmount"
    assert_equal 1, renderer.window_keys.size, "根元素换类型后全局键盘仍应保持绑定"
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

  # 子组件的根节点：带 rendered_component 标记的真实节点
  def component_roots(node, acc = [])
    acc << node if node.rendered_component
    node.children.each { |child| component_roots(child, acc) }
    acc
  end
end
