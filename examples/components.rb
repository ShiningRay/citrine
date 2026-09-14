# frozen_string_literal: true

# 共享组件定义：浏览器（Opal + DomRenderer）与 SSR（CRuby + StringRenderer）
# 复用同一份代码——这正是 M3 渲染器抽象要证明的事。
require "citrine"

class Counter < Citrine::Component
  prop    :title, type: String, default: "Counter"
  state   :count, default: 0
  computed(:double) { count * 2 }

  def view
    box(direction: :column, gap: 10, style: { padding: "20px", font_family: "sans-serif", width: "340px" }) do
      label(style: { font_size: "22px", font_weight: "600" }) { title }
      label(style: { font_size: "18px" }) { "count = #{count}　×2 = #{double}" }
      box(direction: :row, gap: 8) do
        button(on_click: :increment) { "＋1" }
        button(on_click: :decrement) { "－1" }
        button(on_click: :reset) { "重置" }
      end
    end
  end

  def increment
    self.count += 1
  end

  def decrement
    self.count -= 1
  end

  def reset
    self.count = 0
  end
end

class TodoApp < Citrine::Component
  state   :items, default: [] # v1：集合为整体替换语义
  state   :draft, default: ""
  computed(:remaining) { items.count { |t| !t[:done] } }

  CARD = {
    background: "#ffffff", border_radius: 20, padding: "28px",
    width: "480px", box_shadow: "0 24px 64px rgba(31,38,135,0.28)"
  }.freeze

  ITEM_LABEL_BASE = { flex: 1, font_size: "15px", transition: "color .25s" }.freeze
  ITEM_DONE = ITEM_LABEL_BASE.merge(color: "#9ca3af", text_decoration: "line-through").freeze
  ITEM_TODO = ITEM_LABEL_BASE.merge(color: "#1f2937").freeze

  ADD_BTN = {
    background: "linear-gradient(135deg,#667eea,#764ba2)", color: "#fff",
    border: "none", border_radius: 12, padding: "12px 22px",
    font_size: "15px", font_weight: "600", cursor: "pointer",
    transition: "transform .15s ease, box-shadow .25s ease"
  }.freeze

  DEL_BTN = {
    background: "transparent", border: "none", color: "#cbd5e1",
    border_radius: 8, font_size: "14px", cursor: "pointer",
    padding: "4px 8px", transition: "all .2s ease"
  }.freeze

  INPUT = {
    flex: 1, border: "2px solid #e5e7eb", border_radius: 12,
    padding: "12px 14px", font_size: "15px", background: "#f9fafb",
    outline: "none",
    transition: "border-color .2s, box-shadow .2s, background .2s"
  }.freeze

  def view
    box(direction: :column, gap: 18, style: CARD) do
      box(direction: :row, gap: 10, style: { align_items: "center" }) do
        label(style: { font_size: "26px", font_weight: "700" }) { "✨ 今日清单" }
        box(style: { flex: 1 }) {}
        box(style: {
          background: "linear-gradient(135deg,#667eea,#764ba2)",
          border_radius: 999, padding: "5px 14px"
        }) do
          label(style: { color: "#fff", font_size: "13px", font_weight: "600" }) { "剩余 #{remaining}" }
        end
      end
      label(style: { color: "#6b7280", font_size: "13px" }) { "待办 · 剩余 #{remaining} / #{items.size}" }

      box(direction: :row, gap: 10) do
        text_input(value: signal(:draft), placeholder: "写点什么，回车或点添加…",
                   on_enter: :add, css_class: "rv-input", style: INPUT)
        button(on_click: :add, css_class: "rv-add", style: ADD_BTN) { "添加 ↵" }
      end

      box(direction: :column, gap: 8) do
        items.each_with_index do |item, idx|
          box(direction: :row, gap: 10, css_class: "rv-item",
             style: { align_items: "center", padding: "10px 12px",
                      background: "#f8fafc", border_radius: 12,
                      transition: "background .2s ease, transform .2s ease" }) do
            check_box(checked: item[:done], on_change: ->(val) { toggle(idx, val) },
                      css_class: "rv-check",
                      style: { width: 18, height: 18, cursor: "pointer" })
            label(style: item[:done] ? ITEM_DONE : ITEM_TODO) { item[:text] }
            button(on_click: -> { remove_at(idx) }, css_class: "rv-del",
                   style: DEL_BTN) { "✕" }
          end
        end
        if items.empty?
          box(css_class: "rv-empty", direction: :column, gap: 6,
              style: { align_items: "center", padding: "26px 0" }) do
            label(style: { font_size: "34px" }) { "🗒️" }
            label(style: { color: "#9ca3af", font_size: "14px" }) { "暂无待办，加一条试试 ✍️" }
          end
        end
      end

      label(style: { color: "#94a3b8", font_size: "12px", text_align: "center" }) do
        "Citrine · 信号式 Ruby UI · 块级更新，改代码即热刷新"
      end
    end
  end

  def add
    text = draft.to_s.strip
    return if text.empty?

    self.items = items + [{ text: text, done: false }]
    self.draft = ""
  end

  def toggle(idx, val)
    self.items = items.each_with_index.map { |t, i| i == idx ? { text: t[:text], done: val } : t }
  end

  def remove_at(idx)
    self.items = items.reject.with_index { |_t, i| i == idx }
  end
end
