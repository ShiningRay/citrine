# frozen_string_literal: true

# StringRenderer 单测（纯 CRuby）
require "minitest/autorun"
require "citrine"
require "citrine/string_renderer"

class RenderWidget < Citrine::Component
  prop    :name, type: String, default: "world"
  state   :n, default: 3
  computed(:sq) { n * n }

  def view
    box(direction: :column, gap: 8) do
      label { "hello <#{name}>" }
      label { "n=#{n} sq=#{sq}" }
      button(on_click: :noop) { "go" }
      check_box(checked: false)
    end
  end

  def noop; end
end

class CheckedWidget < Citrine::Component
  state :draft, default: "预填文字"

  def view
    box do
      text_input(value: signal(:draft), placeholder: "ph")
      check_box(checked: true)
    end
  end
end

# S3 回归：computed 的 Effect 若不在卸载时释放，组件卸载后仍会被上游信号打回来重算
class ComputedLeakWidget < Citrine::Component
  class << self
    attr_accessor :runs
  end
  self.runs = 0

  state :n, default: 2
  computed(:sq) { self.class.runs += 1; n * n }

  def view
    box { label { "sq=#{sq}" } }
  end
end

# ── 内存渲染器：验证 Renderer 基类的块级更新语义（回归防护）──────────
# 背景：曾因 mount 丢失 per-node Effect 包装，导致任何状态变化整树重建、
# 输入框等节点身份丢失。此测试锁定"更新只影响订阅了该信号的 block"。
class FakeDom
  attr_reader :children
  attr_accessor :parent, :class_name
  attr_reader :style

  def initialize
    @children = []
    @style = {}
  end
end

class MemoryRenderer < Citrine::Renderer
  private

  def setup_root(root, element)
    root.dom = element
  end

  def create_dom(_node)
    FakeDom.new
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

  # 与 DomRenderer#apply_props 同构：属性幂等重设 + 清掉消失的样式键
  # （供响应式属性测试观察"只重设属性、不重建子树"）
  def apply_props(node)
    node.dom.class_name = prop_value(node, node.props[:css_class]) if node.props.key?(:css_class)
    style = resolve_style(node)
    track_style_keys(node, style.keys).each { |key| node.dom.style.delete(key) }
    node.dom.style.merge!(style)
  end

  def set_text(node, text)
    node.text = text
  end
end

class TwoStateWidget < Citrine::Component
  state :alpha, default: 1
  state :b, default: 1

  def view
    box do
      label { "a=#{alpha}" }
      label { "b=#{b}" }
    end
  end
end

class MemoryRenderTest < Minitest::Test
  def test_block_level_update_preserves_sibling_identity
    w = TwoStateWidget.new
    root = MemoryRenderer.new.mount_component(w, FakeDom.new)
    labels = root.children.first.children
    doms_before = labels.map(&:dom)

    w.b = 2

    assert_equal "b=2", labels[1].text
    assert_equal "a=1", labels[0].text
    assert_same doms_before[1], labels[1].dom
    assert_same doms_before[0], labels[0].dom
  end

  # ── G-2：响应式属性（props 传 Proc 时在该节点自己的 Effect 内求值）──────

  def test_reactive_prop_prop_updates_without_rebuilding_subtree
    w = ReactivePropsWidget.new
    root = MemoryRenderer.new.mount_component(w, FakeDom.new)
    box_node = root.children.first
    cell, other = box_node.children
    dom_before = cell.dom

    assert_equal "cold", cell.dom.class_name

    w.hot = true

    assert_equal "hot", cell.dom.class_name
    assert_same dom_before, cell.dom, "响应式属性重跑不应重建节点"
    assert_equal 2, box_node.children.size, "兄弟节点不应受影响"
    assert_equal "tone-plain", other.dom.class_name
  end

  def test_reactive_prop_does_not_widen_outer_block_subscription
    w = ReactivePropsWidget.new
    root = MemoryRenderer.new.mount_component(w, FakeDom.new)
    assert_equal 1, w.view_runs

    w.hot = true
    w.tone = "loud"

    # 订阅落在属性 Effect 上：外层 view/块不因这一格的信号重跑
    assert_equal 1, w.view_runs
    assert_equal "tone-loud", root.children.first.children[1].dom.class_name
  end

  def test_proc_event_handler_is_not_treated_as_reactive_prop
    w = HandlerProcWidget.new
    root = MemoryRenderer.new.mount_component(w, FakeDom.new)
    button = root.children.first.children.first

    # on_click 的 Proc 是回调而不是待求值的值：不应额外产生属性 Effect
    assert_equal 1, button.owned_effects.size
  end

  def test_reactive_style_prop_clears_keys_that_disappear
    w = StyleProcWidget.new
    root = MemoryRenderer.new.mount_component(w, FakeDom.new)
    box_dom = root.children.first.dom

    assert_equal "#ffeeee", box_dom.style[:background]
    assert_equal "4px", box_dom.style[:padding]

    w.alert = false

    refute box_dom.style.key?(:background), "不再出现的样式键必须清掉，否则高亮会残留"
    assert_equal "4px", box_dom.style[:padding]
  end

  def test_value_prop_with_proc_warns_instead_of_silently_ignoring
    w = ValueProcWidget.new
    _out, err = capture_io { MemoryRenderer.new.mount_component(w, FakeDom.new) }

    assert_match(/不是响应式属性/, err)
    assert_match(/value: signal\(:draft\)/, err)
  end

  # ── G-8：布局语法糖 + 未声明方向的开发期提醒 ──────────────────

  def test_undirected_box_warns_in_dev_mode_with_count
    Citrine.dev_mode = true
    _out, err = capture_io { MemoryRenderer.new.mount_component(UndirectedBoxWidget.new, FakeDom.new) }

    assert_match(/1 处 box 未声明方向/, err)
    assert_match(/stack \{ \}/, err)
  ensure
    Citrine.dev_mode = false
  end

  def test_undirected_box_is_silent_outside_dev_mode
    _out, err = capture_io { MemoryRenderer.new.mount_component(UndirectedBoxWidget.new, FakeDom.new) }

    assert_empty err
  end

  def test_stack_and_row_sugar_is_not_reported
    Citrine.dev_mode = true
    _out, err = capture_io { MemoryRenderer.new.mount_component(LayoutSugarWidget.new, FakeDom.new) }

    assert_empty err
  ensure
    Citrine.dev_mode = false
  end
end

# 响应式属性测试用组件：两个 label 各带一个 Proc 属性，view_runs 用来证明
# 外层块没有因这些信号重跑（G-2 的核心收益）
class ReactivePropsWidget < Citrine::Component
  state :hot, default: false
  state :tone, default: "plain"

  attr_reader :view_runs

  def view
    @view_runs = (@view_runs || 0) + 1
    box do
      label(css_class: -> { hot ? "hot" : "cold" }) { "cell" }
      label(css_class: -> { "tone-#{tone}" }) { "tone" }
    end
  end
end

class HandlerProcWidget < Citrine::Component
  state :n, default: 0

  def view
    box do
      button(on_click: -> { self.n += 1 }) { "go" }
    end
  end
end

class StyleProcWidget < Citrine::Component
  state :alert, default: true

  def view
    box(style: -> { { background: alert ? "#ffeeee" : nil, padding: 4 } }) { label { "x" } }
  end
end

class ValueProcWidget < Citrine::Component
  def view
    box { text_input(value: -> { "nope" }) }
  end
end

# G-8：外层 box 有两个子节点且未声明方向（应被计为 1 处）；内层是单子容器，不算
class UndirectedBoxWidget < Citrine::Component
  def view
    box do
      label { "a" }
      label { "b" }
    end
  end
end

# G-8：语法糖——方向显式，不应触发提醒
class LayoutSugarWidget < Citrine::Component
  def view
    stack(gap: 4) { row(gap: 2) { label { "x" } } }
  end
end

class CamelCompatWidget < Citrine::Component
  def view
    box(style: { padding: "4px" }) do
      label(style: { fontSize: "18px", fontWeight: "600", textDecoration: :line_through }) { "hi" }
    end
  end
end

class RenderTest < Minitest::Test
  def test_camelcase_style_and_symbol_value_compat
    html = Citrine.render(CamelCompatWidget.new)
    assert_includes html, "font-size:18px"
    assert_includes html, "font-weight:600"
    assert_includes html, "text-decoration:line-through"
  end

  # G-2：SSR 侧同样支持 Proc 属性（只求值一次，输出与 DOM 一致）
  def test_reactive_props_render_in_ssr
    html = Citrine.render(ReactivePropsWidget.new)
    assert_includes html, 'class="cold"'
    assert_includes html, 'class="tone-plain"'

    styled = Citrine.render(StyleProcWidget.new)
    assert_includes styled, "background:#ffeeee"
    assert_includes styled, "padding:4px"
  end

  # G-8：布局语法糖（stack=竖排 / row=横排）在 SSR 侧同样生效
  def test_stack_and_row_sugar_render_flex_direction
    html = Citrine.render(LayoutSugarWidget.new)

    assert_includes html, "flex-direction:column"
    assert_includes html, "flex-direction:row"
    assert_includes html, "gap:4px"
  end

  def test_stack_rejects_explicit_direction
    widget = Class.new(Citrine::Component) do
      def view
        stack(direction: :row) { label { "x" } }
      end
    end

    error = assert_raises(ArgumentError) { Citrine.render(widget.new) }
    assert_match(/已隐含方向/, error.message)
  end

  def test_css_class_rendered
    widget = Class.new(Citrine::Component) do
      def view
        box(css_class: "card") { label(css_class: "t") { "x" } }
      end
    end
    html = Citrine.render(widget.new)
    assert_includes html, '<div class="card"'
    assert_includes html, '<p class="t">'
  end

  def test_numeric_block_result_rendered_via_to_s
    # F16：非字符串内容按 to_s 渲染，不再静默为空
    widget = Class.new(Citrine::Component) do
      def view
        box do
          label { 42 }
          label { items.size }
        end
      end

      def items = [1, 2, 3]
    end
    html = Citrine.render(widget.new)
    assert_includes html, "<p>42</p>"
    assert_includes html, "<p>3</p>"
  end

  def test_nil_block_result_renders_empty
    widget = Class.new(Citrine::Component) do
      def view
        box { label { nil } }
      end
    end
    assert_includes Citrine.render(widget.new), "<p></p>"
  end

  def test_style_numeric_px_inference_and_nil_stripping
    # F17：数值按属性推断单位；nil 值剔除而非输出非法 CSS
    widget = Class.new(Citrine::Component) do
      def view
        box(style: { width: 100, border_radius: 8, flex: 1, opacity: 0.5, color: nil }) do
          label { "x" }
        end
      end
    end
    html = Citrine.render(widget.new)
    assert_includes html, "width:100px"
    assert_includes html, "border-radius:8px"
    assert_includes html, "flex:1"
    assert_includes html, "opacity:0.5"
    refute_includes html, "color"
  end

  def test_mount_without_renderer_context_raises_readable_error
    # F2：无父节点时给出可读异常，而非 nil.children 的裸 NoMethodError
    err = assert_raises(RuntimeError) do
      Citrine::StringRenderer.new.mount(Citrine::Node.new(:box, {}, nil, owner: nil))
    end
    assert_includes err.message, "没有父节点"
  end

  def test_structure_and_style
    html = Citrine.render(RenderWidget.new)
    assert_includes html, '<div style="display:flex;flex-direction:column;gap:8px">'
    assert_includes html, "<p>hello &lt;world&gt;</p>"
    assert_includes html, "<p>n=3 sq=9</p>"
    assert_includes html, "<button>go</button>"
  end

  def test_void_elements_and_handler_omission
    html = Citrine.render(RenderWidget.new)
    assert_includes html, '<input type="checkbox">'
    refute_includes html, "on_click"
    refute_includes html, "</input>"
  end

  def test_state_and_computed_reflect_changes
    w = RenderWidget.new
    w.n = 5
    assert_includes Citrine.render(w), "n=5 sq=25"
  end

  def test_widget_attributes
    html = Citrine.render(CheckedWidget.new)
    assert_includes html, 'type="text"'
    assert_includes html, 'placeholder="ph"'
    assert_includes html, 'value="预填文字"'
    assert_includes html, "<input type=\"checkbox\" checked"
  end

  def test_html_escaping_in_attributes
    html = Citrine.render(CheckedWidget.new)
    # 预填文字不含特殊字符，用临时组件验证转义
    w = RenderWidget.new(name: 'a"b')
    assert_includes Citrine.render(w), "&lt;a&quot;b&gt;"
  end

  # ── S3：SSR 的 class / style 属性值必须转义（此前是裸插值，可属性注入）──────

  def test_ssr_escapes_css_class_value
    w = Class.new(Citrine::Component) do
      def view
        box(css_class: 'a" onclick="alert(1)') { label { "x" } }
      end
    end.new

    html = Citrine.render(w)
    assert_includes html, %(class="a&quot; onclick=&quot;alert(1)")
    refute_includes html, %(class="a" onclick="alert(1)"), "属性值里的引号必须转义，否则会凭空多出一个属性"
  end

  def test_ssr_escapes_inline_style_value
    w = Class.new(Citrine::Component) do
      def view
        box(style: { font_family: 'x" onload="y' }) { label { "x" } }
      end
    end.new

    html = Citrine.render(w)
    assert_includes html, %(font-family:x&quot; onload=&quot;y)
    refute_includes html, %(font-family:x" onload="y)
  end

  # ── S3：computed 的 Effect 随组件一起释放（此前卸载后仍跟着上游重算）────

  def test_unmount_releases_computed_effects
    ComputedLeakWidget.runs = 0
    w = ComputedLeakWidget.new
    MemoryRenderer.new.mount_component(w, FakeDom.new)

    assert_equal 1, ComputedLeakWidget.runs
    assert_equal 1, w.computation_effect_count

    Citrine.unmount(w)

    assert_equal 0, w.computation_effect_count, "卸载后不该留下存活的 computed Effect"
    w.n = 9
    assert_equal 1, ComputedLeakWidget.runs, "卸载后 computed 不该再被上游信号打回来重算"
  end

  def test_unmount_hook_can_still_read_computed
    seen = nil
    w = Class.new(Citrine::Component) do
      state :n, default: 4
      computed(:sq) { n * n }
      on_unmount -> { seen = sq } # 局部变量接住：验证清理钩子里读到的值

      def view = box { label { "sq=#{sq}" } }
    end.new

    MemoryRenderer.new.mount_component(w, FakeDom.new)
    w.n = 9
    Citrine.unmount(w)

    assert_equal 81, seen, "清理钩子里应能读到 computed 的新鲜值"
    assert_equal 0, w.computation_effect_count, "钩子跑完后 computed 的订阅同样要释放"
  end

  def test_remount_rebuilds_computed_lazily
    ComputedLeakWidget.runs = 0
    w = ComputedLeakWidget.new
    MemoryRenderer.new.mount_component(w, FakeDom.new)
    Citrine.unmount(w)

    root = MemoryRenderer.new.mount_component(w, FakeDom.new)

    assert_equal 1, w.computation_effect_count, "重新挂载后 computed 应重新建 Effect"
    assert_equal "sq=4", root.children.first.children.first.text
    assert_equal 2, ComputedLeakWidget.runs
  end

  # ── S3：复用刷新只应用一次属性（此前 refresh_node 直调 + 属性 Effect 各跑一次）──

  def test_reuse_applies_props_once_per_refresh
    calls = Hash.new(0)
    renderer = Class.new(MemoryRenderer) do
      define_method(:apply_props) do |node|
        calls[node.object_id] += 1
        super(node)
      end
    end.new

    w = Class.new(Citrine::Component) do
      state :tick, default: 0
      state :hue, default: "c0"

      def view
        stack do
          tick # 读在容器块里：容器块重跑 → 子节点走复用/刷新路径
          # 响应式属性读的是**另一个**信号：刷新路径与信号广播不会各跑一次属性 Effect
          box(key: "k", css_class: -> { hue }) { label { "x" } }
        end
      end
    end.new

    root = renderer.mount_component(w, FakeDom.new)
    box_node = root.children.first.children.first
    after_mount = calls[box_node.object_id]

    w.tick = 1

    assert_equal "c0", box_node.dom.class_name
    assert_equal after_mount + 1, calls[box_node.object_id],
                 "复用刷新只应应用一次属性（属性 Effect 内部已经就是 apply_props）"
  end
end
