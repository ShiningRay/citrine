# frozen_string_literal: true

# Renderer 基类回归测试：
#   C1 错误边界在信号驱动重跑路径失效（子组件自己的 error_fallback 接不住）
#   C3 文本→子节点/ nil 切换时旧 textContent 残留
#   A7 css_class 数组、box display:grid、kebab 样式键、透传 Signal 提醒、dispatch_callable
#   P2 Style 转换 per-key memo
require "minitest/autorun"
require "citrine"
require "citrine/string_renderer"

class RendererCheckEl
  attr_reader :children
  attr_accessor :parent, :class_name, :text, :style

  def initialize
    @children = []
    @style = {}
  end
end

# 与 test/render_test.rb 的 MemoryRenderer 同构的本地装置（文件各自独立，避免跨文件类名冲突）
class RendererCheckRenderer < Citrine::Renderer
  private

  def setup_root(root, element)
    root.dom = element
  end

  def create_dom(_node)
    RendererCheckEl.new
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
    node.dom.class_name = prop_value(node, node.props[:css_class]).to_s if node.props.key?(:css_class)
  end

  # 与 DomRenderer 同口径：写 DOM 文本位的同时镜像进 node.text（文本槽）
  def set_text(node, text)
    node.dom.text = text
    node.text = text
  end
end

# ── C1：错误边界在响应式重跑路径失效 ─────────────────────────────

class RerunBombChild < Citrine::Component
  state :armed, default: false

  error_fallback :rescue_view

  def rescue_view(err)
    label(css_class: "child-rescue") { "子兜底：#{err.message}" }
  end

  def view
    raise "重跑爆炸" if armed

    box(css_class: "bomb-box") { label { "安静" } }
  end
end

# 无 error_fallback 的对照组：重跑抛错应照常穿出
class RerunBareBombChild < Citrine::Component
  state :armed, default: false

  def view
    raise "无兜底爆炸" if armed

    box(css_class: "bare-box") { label { "安静" } }
  end
end

# 多根输出的子组件：重跑走 rerun_fragment_view 分支
class RerunFragBombChild < Citrine::Component
  state :armed, default: false

  error_fallback ->(_err) { label(css_class: "frag-rescue") { "多根兜底" } }

  def view
    raise "多根爆炸" if armed

    label { "甲" }
    label { "乙" }
  end
end

# 首渲染即抛错的子组件（prop 驱动；父组件无 error_fallback）
class FirstRenderBombChild < Citrine::Component
  prop :mode, type: Symbol, default: :calm

  error_fallback :rescue_view

  def rescue_view(err)
    label(css_class: "first-rescue") { "首渲染兜底：#{err.message}" }
  end

  def view
    raise "首渲染爆炸" if mode == :boom

    box(css_class: "calm-box") { label { "安静" } }
  end
end

class RerunBombParent < Citrine::Component
  components RerunBombChild, RerunBareBombChild, RerunFragBombChild

  def view
    stack do
      label(css_class: "sibling") { "兄弟" }
      rerun_bomb_child(key: :bomb)
    end
  end
end

# ── C3：文本切换残留 ────────────────────────────────────────────

class TextFlipWidget < Citrine::Component
  state :show, default: true

  def view
    box { label(css_class: "flip") { show ? "有字" : nil } }
  end
end

class TextToChildrenWidget < Citrine::Component
  state :mode, default: :text

  def view
    box do
      label(css_class: "flip") do
        if mode == :text
          "字面量"
        else
          button(on_click: :noop) { "按钮" }
        end
      end
    end
  end

  def noop; end
end

# ── A7：透传属性收到 Signal ─────────────────────────────────────

class SignalPassthroughWidget < Citrine::Component
  state :title, default: "hi"

  def view
    box { label(title: signal(:title)) { "x" } }
  end
end

class ControlledSignalWidget < Citrine::Component
  state :draft, default: "d"

  def view
    box { text_input(value: signal(:draft)) }
  end
end

class RendererTest < Minitest::Test
  def mount(widget)
    RendererCheckRenderer.new.mount_component(widget, RendererCheckEl.new)
  end

  def texts(node, acc = [])
    acc << node.text if node.text
    node.children.each { |child| texts(child, acc) }
    acc
  end

  def find_first(node, class_name)
    return node if node.props[:css_class].to_s.split(" ").include?(class_name)

    node.children.each do |child|
      found = find_first(child, class_name)
      return found if found
    end
    nil
  end

  # ── C1 ───────────────────────────────────────────────────────

  def test_rerun_error_is_caught_by_childs_own_fallback
    parent = RerunBombParent.new
    root = mount(parent)
    child = find_first(root, "bomb-box").rendered_component
    stack_dom = root.children.first.dom
    sibling_dom = stack_dom.children.first
    bomb_dom = find_first(root, "bomb-box").dom

    child.armed = true # 信号驱动 view_effect 重跑，view 抛错

    assert_includes texts(root), "子兜底：重跑爆炸", "子组件自己的 fallback 应接住重跑路径的异常"
    rescue_node = find_first(root, "child-rescue")
    assert rescue_node, "兜底节点应成为组件的新根"
    assert_same child, rescue_node.rendered_component, "组件实例保持存活（边界摘除舞步）"
    refute_includes stack_dom.children, bomb_dom, "旧根 DOM 应被摘除"
    assert_equal 2, stack_dom.children.size, "兄弟节点不受影响"
    assert_same sibling_dom, stack_dom.children.first, "兄弟节点身份不变"

    child.armed = false # 恢复：下一轮重跑 view 正常执行

    assert_includes texts(root), "安静"
    refute_includes texts(root), "子兜底"
  end

  def test_rerun_error_without_fallback_still_propagates
    parent = Class.new(Citrine::Component) do
      components RerunBareBombChild

      def view
        stack { rerun_bare_bomb_child(key: :b) }
      end
    end.new
    root = mount(parent)
    child = find_first(root, "bare-box").rendered_component

    error = assert_raises(RuntimeError) { child.armed = true }
    assert_match(/无兜底爆炸/, error.message)
  end

  def test_fragment_root_rerun_error_renders_fallback_in_place
    parent = Class.new(Citrine::Component) do
      components RerunFragBombChild

      def view
        stack { rerun_frag_bomb_child(key: :f) }
      end
    end.new
    root = mount(parent)
    child = root.children.first.children.first.rendered_component

    assert_equal %w[甲 乙], texts(root)

    child.armed = true

    assert_includes texts(root), "多根兜底"
    refute_includes texts(root), "甲"
    refute_includes texts(root), "乙"
  end

  def test_first_render_error_uses_childs_own_fallback_without_parent_boundary
    parent = Class.new(Citrine::Component) do
      components FirstRenderBombChild

      def view
        stack { first_render_bomb_child(key: :b, mode: :boom) }
      end
    end.new

    root = mount(parent) # 父组件未声明 error_fallback：不再穿出

    assert_includes texts(root), "首渲染兜底：首渲染爆炸"
  end

  # ── C3 ───────────────────────────────────────────────────────

  def test_text_to_nil_clears_previous_text
    w = TextFlipWidget.new
    root = mount(w)
    flip = find_first(root, "flip")
    label_dom = flip.dom

    assert_equal "有字", label_dom.text

    w.show = false

    assert_equal "", label_dom.text, "上一轮写过文本、本轮为 nil 时必须显式清空"
    assert_same label_dom, flip.dom, "块级更新不重建节点"
  end

  def test_text_to_children_switch_clears_previous_text
    w = TextToChildrenWidget.new
    root = mount(w)
    flip = find_first(root, "flip")
    label_dom = flip.dom

    assert_equal "字面量", label_dom.text

    w.mode = :button

    assert_equal "", label_dom.text, "文本切成子节点时旧文本不得残留"
    assert_equal 1, label_dom.children.size
    assert_equal "按钮", label_dom.children.first.text

    w.mode = :text # 切回文本：正常恢复

    assert_equal "字面量", label_dom.text
  end

  # ── A7 ───────────────────────────────────────────────────────

  def test_ssr_css_class_array_is_joined_with_space
    w = Class.new(Citrine::Component) do
      def view
        box(css_class: ["card", "active"]) { label { "x" } }
      end
    end.new

    assert_includes Citrine.render(w), 'class="card active"'
  end

  def test_box_with_explicit_grid_does_not_emit_flex_direction
    w = Class.new(Citrine::Component) do
      def view
        box(style: { display: "grid" }, direction: :column) { label { "x" } }
      end
    end.new
    html = Citrine.render(w)

    assert_includes html, "display:grid"
    refute_includes html, "flex-direction", "grid 容器不属于 direction 管辖"
  end

  def test_box_flex_and_default_still_apply_direction
    html = Citrine.render(Class.new(Citrine::Component) do
      def view
        box(style: { display: "flex" }, direction: :column) { label { "a" } }
      end
    end.new)
    assert_includes html, "flex-direction:column"

    default_html = Citrine.render(Class.new(Citrine::Component) do
      def view
        box(direction: :row) { label { "b" } }
      end
    end.new)
    assert_includes default_html, "flex-direction:row"
  end

  def test_kebab_case_style_keys_are_normalized
    w = Class.new(Citrine::Component) do
      def view
        label(style: { "font-size" => 14, "text-align" => :center }) { "x" }
      end
    end.new
    html = Citrine.render(w)

    assert_includes html, "font-size:14px"
    assert_includes html, "text-align:center"
  end

  def test_passthrough_prop_with_signal_warns
    _out, err = capture_io { mount(SignalPassthroughWidget.new) }

    assert_match(/收到 Signal/, err)
    assert_match(/title/, err)
  end

  def test_controlled_value_signal_does_not_warn
    _out, err = capture_io { mount(ControlledSignalWidget.new) }

    assert_empty err, "value: 传 Signal 是受控值语义，不在提醒之列"
  end

  def test_dispatch_callable_symbol_respects_arity
    receiver = Object.new
    def receiver.greet = "hi"
    def receiver.echo(x) = x

    assert_equal "hi", Citrine.dispatch_callable(:greet, receiver)
    assert_equal 42, Citrine.dispatch_callable(:echo, receiver, 42)
  end

  def test_dispatch_callable_proc_keeps_closure_self_unless_bind
    ctx = Object.new
    def ctx.num = 10

    assert_equal 10, Citrine.dispatch_callable(proc { num }, ctx, nil, true)
    assert_equal 5, Citrine.dispatch_callable(->(x) { x + 1 }, ctx, 4)
    assert_raises(NameError) { Citrine.dispatch_callable(proc { num }, ctx) }
  end

  # 事件 payload 是位置参数 Hash（拖拽 {x,y,w,h}、相机 {x,y,delta_y}）：
  # 必须原样抵达处理器。bind 一旦改回关键字参数，Opal 的 extract_kwargs 会
  # 把该 Hash 抽成 kwargs、arg 变 nil（浏览器 NoMethodError，CRuby 单测不可见）
  def test_dispatch_callable_hash_payload_arrives_as_positional_arg
    receiver = Object.new
    def receiver.take(e) = e

    payload = { x: 12, y: 34 }
    assert_same payload, Citrine.dispatch_callable(:take, receiver, payload)
    assert_equal payload, Citrine.dispatch_callable(->(e) { e }, receiver, payload)
  end

  def test_dispatch_callable_rejects_unknown_handler
    assert_raises(ArgumentError) { Citrine.dispatch_callable(42, Object.new) }
  end

  # ── P2 ───────────────────────────────────────────────────────

  def test_style_key_conversion_is_memoized
    assert_same Citrine::Style.camel(:font_size), Citrine::Style.camel(:font_size)
    assert_same Citrine::Style.kebab(:font_size), Citrine::Style.kebab(:font_size)
    assert_same Citrine::Style.underscore("fontSize"), Citrine::Style.underscore("fontSize")
  end
end
