# backtick_javascript: true
# frozen_string_literal: true

# 示例：组件嵌套 + keyed 复用（P0-1）
#
# 场景就是 FRICTION F6 的原始症状：**每行带一个输入框**，行的增删与重排不能把输入框
# 换掉——否则输入值、光标位置、输入法状态会一起丢。keyed 复用让"重排 = 移动 DOM 节点"，
# 而不是"重建整行"。
#
# 三件事在同一个例子里：
#   · 组件嵌套：列表组件渲染 N 个行组件（每个行组件有自己的 state）
#   · keyed 复用：key 相同的行跨重排保留实例与 DOM
#   · 子改父：行通过回调 prop 把"删除我"传回父组件
require "citrine/browser"

class EditRow < Citrine::Component
  prop :code, type: String
  prop :on_remove
  state :draft, default: ""

  def view
    row(gap: 6, css_class: "row") do
      label(css_class: "code") { code }
      text_input(value: signal(:draft), css_class: "qty", placeholder: "数量")
      button(on_click: :remove, css_class: "del") { "✕" }
    end
  end

  def remove
    handle_event(on_remove, code)
  end
end

class KeyedList < Citrine::Component
  components EditRow
  state :codes, default: %w[A B C]

  NEXT_CODES = %w[D E F G H].freeze

  def view
    stack(css_class: "list", gap: 6) do
      label(css_class: "count") { "行数：#{codes.size} · 顺序：#{codes.join(' ')}" }
      codes.each do |code|
        edit_row(code: code, key: code, on_remove: ->(target) { self.codes = codes - [target] })
      end
      row(gap: 6, css_class: "actions") do
        button(on_click: :add) { "加一行" }
        button(on_click: :shuffle) { "重排" }
        button(on_click: :drop_first) { "删第一行" }
      end
      label(css_class: "hint") { "在任意输入框里打字后点重排：值、光标、行节点都应保持不变" }
    end
  end

  def add
    extra = NEXT_CODES.find { |code| !codes.include?(code) } || "X#{codes.size}"
    self.codes = codes + [extra]
  end

  def shuffle
    self.codes = codes.reverse
  end

  def drop_first
    self.codes = codes[1..-1] || []
  end
end

Citrine::DomRenderer.mount_at("app", KeyedList.new)
