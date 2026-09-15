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

    # Canvas 没有"页面宿主"概念：portal 内容按画布根级布局/绘制
    def resolve_portal_host(_target)
      @root.dom
    end

    def detach(_node); end

    def apply_props(_node); end

    # 响应式属性（G-2）：Canvas 每次重绘都重新读 props，Proc 在绘制时求值
    def style_of(node)
      prop_value(node, node.props[:style]) || {}
    end

    def set_text(node, text)
      node.text = text
    end

    def setup_widget(node)
      # T-B2：text_input 换成真实 <input> 覆盖层（中文输入法可用）；
      # 无 DOM 环境的宿主（Node 桩）回退 window.prompt 路径
      setup_text_input_overlay(node) if node.type == :text_input && overlay_available?
    end

    # ── T-B2 spike：隐藏 DOM 测量 + 真实输入覆盖层 ──────────────
    # 选型结论：隐藏 DOM 测量（0KB、白送字体回退与度量），不引入 Yoga。
    # 环境探测带缓存：Node 桩等无 body 环境自动走旧路径，行为不回归。

    def dom_measurement?
      return @dom_measurement unless @dom_measurement.nil?

      @dom_measurement = `typeof document !== 'undefined' && !!document.body`
    end

    def overlay_available?
      return @overlay_available unless @overlay_available.nil?

      @overlay_available = `typeof document !== 'undefined' && !!document.body && !!document.createElement`
    end

    def hidden_measurer
      @hidden_measurer ||= begin
        el = Native(`document.createElement("div")`)
        style = el[:style]
        style[:position] = "absolute"
        style[:left] = "-99999px"
        style[:top] = "0"
        style[:visibility] = "hidden"
        style[:whiteSpace] = "nowrap"
        `document.body.appendChild(#{el.to_n})`
        el
      end
    end

    # 按节点字体量测文本宽度（px）——度量与回退由浏览器负责
    def dom_text_width(text, node)
      el = hidden_measurer
      el[:textContent] = text.to_s
      el[:style][:font] = font_string(node)
      el.getBoundingClientRect()[:width]
    end

    # 真实 <input> 覆盖层：绝对定位到画布上方，value 信号双向绑定
    def setup_text_input_overlay(node)
      input = Native(`document.createElement("input")`)
      input[:type] = "text"
      value = node.props[:value]
      input[:value] = value.get.to_s if value.is_a?(Signal)
      input[:style][:position] = "absolute"
      input[:style][:boxSizing] = "border-box"
      input[:style][:border] = "1px solid #999"
      input[:style][:font] = "15px sans-serif"
      input[:style][:background] = "#fff"
      overlay_root.appendChild(input)
      if value.is_a?(Signal)
        input.addEventListener("input", ->(_e) { value.set(input[:value]) })
        node.owned_effects << Effect.create { input[:value] = value.get.to_s }
      end
      (@overlays ||= {})[node.object_id] = { node: node, input: input }
      node
    end

    # 覆盖层宿主：挂在 body 上的绝对定位层（节点坐标 = 画布视口偏移 + 布局盒）
    def overlay_root
      @overlay_root ||= begin
        wrap = Native(`document.createElement("div")`)
        wrap[:style][:cssText] = "position:absolute;left:0;top:0;width:0;height:0;overflow:visible"
        `document.body.appendChild(#{wrap.to_n})`
        wrap
      end
    end

    # 每次 redraw 后按布局盒重新定位覆盖层，并清掉已消失的输入框
    def sync_overlays
      return unless @overlays

      canvas_rect = @canvas.getBoundingClientRect()
      live = {}
      collect_text_inputs = proc do |node|
        live[node.object_id] = true if node.type == :text_input
        node.children.each { |child| collect_text_inputs.call(child) }
      end
      collect_text_inputs.call(@root)

      @overlays.each do |id, entry|
        unless live.key?(id)
          entry[:input].remove
          @overlays.delete(id)
          next
        end

        box = entry[:node].dom
        style = entry[:input][:style]
        style[:left] = "#{canvas_rect[:left] + box[:x]}px"
        style[:top] = "#{canvas_rect[:top] + box[:y]}px"
        style[:width] = "#{box[:w]}px"
        style[:height] = "#{box[:h]}px"
      end
    end

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
      # T-B2：有覆盖层时聚焦真实 <input>（IME 可用）；否则回退 prompt 演示路径
      overlay = @overlays && @overlays[node.object_id]
      if overlay
        overlay[:input].focus
        return
      end

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
      # P1：本轮重绘的尺寸缓存。size_of 原本随 place 的前序遍历被逐层重复递归
      # （复杂度 深度 × 节点数，叶子量测重复最狠）——每轮重绘只算一次、缓存命中即返回；
      # ensure 里清空：样式 / props 变化后的下一轮重绘必须重新量测
      @size_cache = {}
      @ctx.clearRect(0, 0, @root.dom[:w], @root.dom[:h])
      place(@root, 0, 0)
      paint(@root)
      sync_overlays
    ensure
      @size_cache = nil
    end

    def box?(node)
      # fragment / portal（S1-4 / S1-5）：透明容器按容器参与布局，让多根/弹层照常展开
      node.type == :root || node.type == :box || node.type == :fragment || node.type == :portal
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

      # P1：命中本轮缓存直接返回——首次计算时已把尺寸写进 node.dom，place/paint 只读
      return @size_cache[node.object_id] if @size_cache&.key?(node.object_id)

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
      @size_cache[node.object_id] = [w, h] if @size_cache
      [w, h]
    end

    def leaf_size(node)
      case node.type
      when :text_input then [240, 36]
      when :check_box  then [18, 18]
      else
        text = display_text(node).to_s
        # T-B2 spike（隐藏 DOM 测量）：真机里按同一字体用隐藏元素量测宽度——
        # 字体回退 / CJK 度量交给浏览器；Node 桩等无 body 环境回退 measureText。
        width = dom_measurement? ? dom_text_width(text, node) : ctx_text_width(text, node)
        width += node.type == :button ? 24 : 4
        height = font_size(node) * (node.type == :button ? 1.9 : 1.6)

        # T-B2：显式 style width 且文本超宽 → 贪心断行，多行堆叠
        max_w = wrap_max_width(node)
        if max_w && width > max_w
          lines = wrapped_lines(text, node, max_w)
          width = max_w
          height = lines.size * font_size(node) * 1.5
        end
        [width, height]
      end
    end

    # 断行宽度上限：label 的显式 style width
    def wrap_max_width(node)
      w = style_of(node)[:width]
      w ? px_num(w) : nil
    end

    # 贪心断行：CJK 逐字、拉丁/数字按词、空白串整体。
    # 返回各行文本；调用方需已设置 @ctx.font（量测用）。
    def wrapped_lines(text, node, max_width)
      @ctx.font = font_string(node)
      lines = []
      current = ""
      wrap_units(text).each do |unit|
        candidate = current + unit
        if current.empty? || @ctx.measureText(candidate)[:width] <= max_width
          current = candidate
        else
          lines << current
          current = unit
        end
      end
      lines << current unless current.empty?
      lines
    end

    # 分词：拉丁/数字词整体、空白串整体、其余逐字（CJK 逐字断行）
    def wrap_units(text)
      text.to_s.scan(/[A-Za-z0-9]+|\s+|[^A-Za-z0-9\s]/)
    end

    def ctx_text_width(text, node)
      @ctx.font = font_string(node)
      @ctx.measureText(text)[:width]
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
      when :fragment, :portal
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
      color = style[:color] || "#222"
      @ctx.font = font_string(node)
      @ctx.fillStyle = color

      # T-B2：多行文本逐行绘制（换行条件与 leaf_size 一致）
      max_w = wrap_max_width(node)
      lines = max_w ? wrapped_lines(display_text(node).to_s, node, max_w) : [display_text(node).to_s]
      line_h = font_size(node) * 1.5
      lines.each_with_index do |line, i|
        @ctx.fillText(line, node.dom[:x] + 2, node.dom[:y] + font_size(node) * 1.15 + i * line_h)
      end

      return unless lines.size == 1 && style[:text_decoration] == "line-through"

      y_mid = node.dom[:y] + font_size(node) * 0.75
      @ctx.strokeStyle = color
      @ctx.moveTo(node.dom[:x] + 2, y_mid)
      @ctx.lineTo(node.dom[:x] + 2 + @ctx.measureText(lines.first)[:width], y_mid)
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
      # 真实 <input> 覆盖层已就位：不再绘制占位框（避免视觉重复）
      return if @overlays && @overlays.key?(node.object_id)

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
