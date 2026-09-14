# backtick_javascript: true
# frozen_string_literal: true

require "native"
require "citrine"
require "citrine/renderer"

module Citrine
  # Canvas 2D 渲染器（Opal 环境）——可移植性演示后端。
  #
  # 与 DOM 渲染器共用 Renderer 基类的全部树管理 / Effect / 块级重建机制，
  # 差异只在钩子实现：布局自管（direction/gap 的 stack/flow 语义）、
  # 绘制原语、包围盒命中检测；任何变更后全量重绘（游戏式）。
  # 文本输入用 window.prompt（演示级，避开 canvas 输入的 IME/光标深水区）。
  class CanvasRenderer < Renderer
    def initialize
      super()
      @hits = [] # [bbox, node]，绘制时登记，点击时反查
    end

    def self.mount_at(element_id, component)
      Citrine.renderer = new
      canvas = Citrine.renderer.document_element(element_id)
      Citrine.mount(component, canvas)
    end

    def document_element(element_id)
      Native(`window.document`).getElementById(element_id)
    end

    private

    # ── Renderer 钩子 ────────────────────────────────────────

    def setup_root(root, element)
      @root = root
      @canvas = element
      @ctx = element.getContext("2d")
      root.dom = { x: 0, y: 0, w: @canvas[:width], h: @canvas[:height] }
      element.addEventListener("click", ->(event) {
        ev = Native(event)
        handle_canvas_click(ev[:offsetX], ev[:offsetY])
      })
    end

    def create_dom(_node)
      {} # 布局盒，redraw 时填充
    end

    def attach(_node, _parent); end

    def detach(_node); end

    def apply_props(_node); end

    # 响应式属性（G-2）：Canvas 每次重绘都重新读 props，Proc 在绘制时求值
    def style_of(node)
      prop_value(node, node.props[:style]) || {}
    end

    def set_text(node, text)
      node.text = text
    end

    def setup_widget(_node); end

    # 嵌套挂载期间不重绘，等最外层 settle（@parents 为空）后整体画一次
    def finalize(_node)
      redraw if @parents.empty?
    end

    # 子组件 view 的信号重跑（S1-2）发生在父块渲染之外：重跑收尾时补一次整体重绘。
    # 若重跑本身嵌在别的渲染过程里（@parents 非空），仍由最外层 finalize 统一重绘。
    def rerun_component_view(child, parent)
      super
    ensure
      redraw if @parents.empty?
    end

    # ── 事件（命中检测 → 分发） ─────────────────────────────

    def handle_canvas_click(x, y)
      @hits.reverse_each do |box, node|
        next unless x >= box[:x] && x <= box[:x] + box[:w] &&
                    y >= box[:y] && y <= box[:y] + box[:h]

        dispatch(node)
        break
      end
      redraw
    end

    def dispatch(node)
      case node.type
      when :button
        handler = node.props[:on_click]
        node.owner.handle_event(handler) if handler
      when :check_box
        checked = node.props[:checked]
        checked = checked.get if checked.is_a?(Signal)
        handler = node.props[:on_change]
        return unless handler

        # 受控语义（S2-4）：先写回信号再调处理器，处理器读到的是新勾选态
        node.props[:checked].set(!checked) if node.props[:checked].is_a?(Signal)
        node.owner.handle_event(handler, !checked)
      when :text_input
        dispatch_text_input(node)
      end
    end

    def dispatch_text_input(node)
      text = prompt_value(prop_value(node, node.props[:placeholder]).to_s)
      return if text.nil?

      value = node.props[:value]
      value.set(text) if value.is_a?(Signal)
      handler = node.props[:on_enter]
      node.owner.handle_event(handler) if handler
    end

    def prompt_value(message)
      return nil unless `typeof window.prompt === 'function'`

      `window.prompt(#{message})`
    end

    # ── 布局：size（后序测尺寸）→ place（前序定位） ──────────

    def redraw
      return unless @root && @ctx

      @hits = []
      @ctx.clearRect(0, 0, @root.dom[:w], @root.dom[:h])
      place(@root, 0, 0)
      paint(@root)
    end

    def box?(node)
      # fragment（S1-4）：透明容器按容器参与布局，让多根子组件在画布上照常展开
      node.type == :root || node.type == :box || node.type == :fragment
    end

    def box_axes(node)
      style = style_of(node)
      pad = px_num(node.type == :root ? (style[:padding] || 12) : (style[:padding] || 0))
      gap = (gap_prop = prop_value(node, node.props[:gap])) ? gap_prop.to_i : 10
      direction = if node.type == :root || prop_value(node, node.props[:direction]) == :column
                    :column
                  else
                    :row
                  end
      [direction, pad, gap]
    end

    def size_of(node)
      return [@root.dom[:w], @root.dom[:h]] if node.type == :root

      if box?(node)
        direction, pad, gap = box_axes(node)
        sizes = node.children.map { |child| size_of(child) }
        n = node.children.size
        gaps = n > 1 ? gap * (n - 1) : 0
        main = direction == :column ? sizes.sum(&:last) + gaps : sizes.sum(&:first) + gaps
        cross = direction == :column ? (sizes.map(&:first).max || 0) : (sizes.map(&:last).max || 0)
        w = (direction == :column ? cross : main) + 2 * pad
        h = (direction == :column ? main : cross) + 2 * pad
      else
        w, h = leaf_size(node)
      end
      node.dom = node.dom.merge(w: w, h: h)
      [w, h]
    end

    def leaf_size(node)
      case node.type
      when :text_input then [240, 36]
      when :check_box  then [18, 18]
      else
        text = display_text(node).to_s
        @ctx.font = font_string(node)
        [@ctx.measureText(text)[:width] + (node.type == :button ? 24 : 4),
         font_size(node) * (node.type == :button ? 1.9 : 1.6)]
      end
    end

    def place(node, x, y)
      size_of(node)
      node.dom = node.dom.merge(x: x, y: y)
      return unless box?(node)

      direction, pad, gap = box_axes(node)
      cx = x + pad
      cy = y + pad
      node.children.each do |child|
        place(child, cx, cy)
        if direction == :column
          cy += child.dom[:h] + gap
        else
          cx += child.dom[:w] + gap
        end
      end
    end

    # ── 绘制 ───────────────────────────────────────────────

    def paint(node)
      case node.type
      when :root
        node.children.each { |child| paint(child) }
      when :box
        style = style_of(node)
        bg = style[:background] || style[:background_color]
        # 渐变等复杂值在 Canvas 上跳过（仅支持纯色），避免污染当前 fillStyle
        if bg.is_a?(String) && bg.start_with?("#", "rgb")
          @ctx.fillStyle = bg
          @ctx.fillRect(node.dom[:x], node.dom[:y], node.dom[:w], node.dom[:h])
        end
        node.children.each { |child| paint(child) }
      when :fragment
        # 透明容器：只递归子根，自身不占绘制
        node.children.each { |child| paint(child) }
      when :label
        paint_label(node)
      when :button
        paint_button(node)
      when :text_input
        paint_text_input(node)
      when :check_box
        paint_check_box(node)
      end
    end

    def paint_label(node)
      style = style_of(node)
      text = display_text(node)
      color = style[:color] || "#222"
      @ctx.font = font_string(node)
      @ctx.fillStyle = color
      @ctx.fillText(text, node.dom[:x] + 2, node.dom[:y] + font_size(node) * 1.15)
      return unless style[:text_decoration] == "line-through"

      y_mid = node.dom[:y] + font_size(node) * 0.75
      @ctx.strokeStyle = color
      @ctx.moveTo(node.dom[:x] + 2, y_mid)
      @ctx.lineTo(node.dom[:x] + 2 + @ctx.measureText(text)[:width], y_mid)
      @ctx.stroke
    end

    def paint_button(node)
      box = node.dom
      text = display_text(node)
      @ctx.fillStyle = "#f3f3f3"
      @ctx.fillRect(box[:x], box[:y], box[:w], box[:h])
      @ctx.strokeStyle = "#999"
      @ctx.strokeRect(box[:x], box[:y], box[:w], box[:h])
      @ctx.font = font_string(node)
      @ctx.fillStyle = "#222"
      @ctx.fillText(text, box[:x] + (box[:w] - @ctx.measureText(text)[:width]) / 2,
                    box[:y] + font_size(node) * 1.25)
      @hits << [box, node]
    end

    def paint_text_input(node)
      box = node.dom
      value = node.props[:value]
      value = value.get if value.is_a?(Signal)
      value = value.to_s
      @ctx.fillStyle = "#fff"
      @ctx.fillRect(box[:x], box[:y], box[:w], box[:h])
      @ctx.strokeStyle = "#aaa"
      @ctx.strokeRect(box[:x], box[:y], box[:w], box[:h])
      @ctx.font = "15px sans-serif"
      if value.empty?
        @ctx.fillStyle = "#999"
        @ctx.fillText(prop_value(node, node.props[:placeholder]).to_s, box[:x] + 8, box[:y] + 23)
      else
        @ctx.fillStyle = "#222"
        @ctx.fillText(value[0, 20], box[:x] + 8, box[:y] + 23)
      end
      @hits << [box, node]
    end

    def paint_check_box(node)
      box = node.dom
      @ctx.fillStyle = "#fff"
      @ctx.fillRect(box[:x], box[:y], box[:w], box[:h])
      @ctx.strokeStyle = "#666"
      @ctx.strokeRect(box[:x], box[:y], box[:w], box[:h])
      @hits << [box, node]
      checked = node.props[:checked]
      checked = checked.get if checked.is_a?(Signal)
      return unless checked

      @ctx.fillStyle = "#333"
      @ctx.font = "14px sans-serif"
      @ctx.fillText("✓", box[:x] + 3, box[:y] + 14)
    end

    # ── 工具 ───────────────────────────────────────────────

    def display_text(node)
      node.text.to_s
    end

    def font_size(node)
      px_num(style_of(node)[:font_size] || 16)
    end

    def font_string(node)
      weight = style_of(node)[:font_weight]
      size = font_size(node)
      if weight && weight.to_s != "400"
        "#{weight} #{size}px sans-serif"
      else
        "#{size}px sans-serif"
      end
    end

    def px_num(value)
      value.to_s.sub("px", "").to_f
    end
  end
end
