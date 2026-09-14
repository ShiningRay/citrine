# backtick_javascript: true
# frozen_string_literal: true

# T-B2：DOM / Canvas 等价断言页——同一份 components.rb 的 Counter 组件分别经
# DomRenderer 与 CanvasRenderer 渲染，页面内做结构等价断言与布局守卫，
# 结果写入 #parity-report（rake canvas_parity 用 headless Chrome 解析断言）。
#
# 断言：
#   1. 文本序列等价（DOM p/button 文本 == Canvas 叶子文本，按渲染序）
#   2. 容器尺寸下限：DOM 根、Canvas stack 的宽高均 > 0
#   3. 同层兄弟 top 不等（列向布局的子节点纵向排布）
#   4. text_input 真实 <input> 覆盖层存在，且输入事件写回 Signal
require "native"
require "citrine/browser"
require "citrine/canvas"
require_relative "components"

doc = Native(`window.document`)
raw_document = `window.document` # backtick 内需要裸对象（Native 包装会泄漏）；全局 document 保持原样

# ── DOM 侧 ────────────────────────────────────────────
dom_renderer = Citrine::DomRenderer.new
Citrine.renderer = dom_renderer
dom_renderer.mount_component(Counter.new(title: "Parity"), doc.getElementById("parity-dom"))

# ── Canvas 侧 ─────────────────────────────────────────
canvas_renderer = Citrine::CanvasRenderer.new
Citrine.renderer = canvas_renderer
canvas_widget = Counter.new(title: "Parity")
canvas_renderer.mount_component(canvas_widget, doc.getElementById("parity-canvas"))

# ── 1. 文本序列等价 ───────────────────────────────────
dom_texts = `Array.from(#{raw_document}.querySelectorAll("#parity-dom p, #parity-dom button"))
  .map(function (e) { return e.textContent.trim(); })
  .filter(function (t) { return t.length > 0; })`

canvas_texts = []
collect_leaf_texts = proc do |node|
  if %i[label button].include?(node.type) && node.text
    canvas_texts << canvas_renderer.instance_exec(node) { |n| display_text(n) }
  end
  node.children.each { |child| collect_leaf_texts.call(child) }
end
collect_leaf_texts.call(canvas_widget.root)

texts_equal = dom_texts == canvas_texts

# ── 2/3. 布局守卫：尺寸下限 + 列向兄弟 top 互异 ─────────
dom_root = doc.querySelector("#parity-dom > *")
dom_rect = dom_root.getBoundingClientRect()
dom_ok = dom_rect[:width] > 0 && dom_rect[:height] > 0
dom_top_distinct = `(function () {
  var root = document.querySelector("#parity-dom > *");
  var tops = Array.from(root.children).map(function (c) { return c.getBoundingClientRect().top; });
  return tops.length < 2 || tops[0] !== tops[1];
})()`

canvas_root = canvas_widget.root
stack = canvas_root.children.first
stack_w = stack.dom[:w]
stack_h = stack.dom[:h]
canvas_ok = stack_w > 0 && stack_h > 0
ys = stack.children.map { |c| c.dom[:y] }
column_y_increasing = ys.each_cons(2).all? { |a, b| b > a }

# ── 4. 真实 <input> 覆盖层（Signal 双向绑定）──────────
input_probe = Class.new(Citrine::Component) do
  state :draft, default: "初始"

  define_method(:view) do
    stack { text_input(value: signal(:draft), placeholder: "可输入") }
  end
end
probe = input_probe.new
probe_renderer = Citrine::CanvasRenderer.new
Citrine.renderer = probe_renderer
probe_renderer.mount_component(probe, doc.getElementById("parity-canvas2"))

overlays = probe_renderer.instance_variable_get(:@overlays) || {}
entry = overlays.values.first
input_synced = false
if entry
  raw = entry[:input].to_n
  `#{raw}.value = "真实输入"`
  `#{raw}.dispatchEvent(new Event("input"))`
  input_synced = probe.draft == "真实输入"
end

# ── 报告 ──────────────────────────────────────────────
report = {
  texts_equal: texts_equal,
  dom_texts: dom_texts,
  canvas_texts: canvas_texts,
  dom_ok: dom_ok,
  dom_top_distinct: dom_top_distinct,
  canvas_ok: canvas_ok,
  stack_w: stack_w,
  stack_h: stack_h,
  column_y_increasing: column_y_increasing,
  overlay_input_present: entry ? true : false,
  input_synced: input_synced
}

pre = doc.createElement("pre")
pre.setAttribute("id", "parity-report")
pre[:textContent] = `JSON.stringify(#{report.to_n})`
doc.body.appendChild(pre)
