# frozen_string_literal: true

require_relative "signal"
require_relative "node"
require_relative "style"

module Citrine
  # 渲染器基类：节点树管理 + Effect 装配 + 块级重建/销毁（平台无关）。
  #
  # 平台子类实现钩子：setup_root / create_dom / attach / detach /
  # apply_props / bind_events / set_text / setup_widget / finalize，
  # 并以 reactive? 声明是否建立更新订阅（一次性渲染如 StringRenderer 返回 false）。
  class Renderer
    TAGS = { box: "div", label: "p", button: "button",
             text_input: "input", check_box: "input" }.freeze
    VOID = %i[text_input check_box].freeze

    # 响应式属性白名单：这些 prop 的值可以是 Proc，在**该节点自己的 Effect** 内求值。
    #
    # G-2：props 的求值位置决定订阅范围——写成 `box(css_class: cell_class(row, col))`
    # 时实参在**外层块**执行期间求值，于是外层块订阅了这一格的信号（改一格 → 整块重建）。
    # 写成 `box(css_class: -> { cell_class(row, col) })` 则订阅落在本节点的属性 Effect 上，
    # 且重跑只重设属性、不重建子树。
    #
    # 事件处理器（on_*）不在此列：它们的 Proc 是回调，不是待求值的值。
    REACTIVE_PROPS = %i[css_class placeholder style direction gap].freeze

    # 由渲染器直接当作**值**消费的 prop：收到 Proc 时明确提醒，避免"写了但不生效"。
    VALUE_PROPS = %i[value checked].freeze

    def initialize
      @parents = []
    end

    def mount_component(component, element)
      # DSL（Component#emit）经全局 Citrine.renderer 分发到当前渲染器；
      # 响应式 Effect 重跑发生在 mount 之后，也依赖此设置，
      # 因此不恢复旧值——"活动渲染器 = 最近挂载的那个"。
      Citrine.renderer = self
      @undirected_boxes = 0
      root = Node.new(:root, {}, nil, owner: component)
      setup_root(root, element)
      run_view(root, component)
      finalize(root)
      warn_undirected_boxes
      root
    end

    # DSL 挂载入口（Component#emit 调用）：把 node 挂到当前父节点下
    def mount(node)
      parent = @parents.last
      unless parent
        raise "Citrine: 元素挂载时没有父节点。组件 view 只能在渲染器挂载过程中执行；" \
              "一页多根请分别用各渲染器实例（DomRenderer.new + mount_component），不要多次 mount_at"
      end

      node.dom = create_dom(node)
      warn_unreactive_proc(node)
      parent.children << node
      attach(node, parent)
      bind_events(node)
      setup_widget(node)

      # G-2：响应式属性必须在**本节点自己的 Effect** 内求值——挂载路径上直接求值会让
      # 订阅落进外层块（正是要消除的隐性外扩）。重跑只重设属性，不重建子树。
      if reactive? && reactive_props?(node)
        node.owned_effects << Effect.create { apply_props(node) }
      else
        apply_props(node)
      end

      if node.block
        if reactive?
          node.owned_effects << Effect.create do
            run_block(node) { node.owner.instance_exec(&node.block) }
          end
        else
          run_block(node) { node.owner.instance_exec(&node.block) }
        end
      end
      # 子节点此时才建好：多子容器才会真的"塌"，所以放在 block 之后统计（G-8）
      note_undirected_box(node)
      finalize(node)
      node
    end

    private

    def run_view(root, component)
      if reactive?
        root.owned_effects << Effect.create do
          run_block(root) { component.instance_exec { view } }
        end
      else
        run_block(root) { component.instance_exec { view } }
      end
    end

    # 重建 node 的子树：先销毁旧子节点（连同其 Effect 订阅），再执行 block
    def run_block(node)
      node.children.dup.each { |child| dispose(child) }
      node.children.clear
      @parents.push(node)
      result = yield
      if !result.nil? && node.children.empty?
        warn_nonstring(node, result) unless result.is_a?(String)
        set_text(node, result)
      end
      result
    ensure
      @parents.pop
    end

    # F16：block 返回非字符串时按 to_s 渲染而非静默置空；每类只提醒一次
    def warn_nonstring(node, result)
      @warned_types ||= {}
      type = result.class
      return if @warned_types[type]
      return unless respond_to?(:warn, true)

      @warned_types[type] = true
      warn "[citrine] #{node.type} 的内容 block 返回了 #{type}（#{result.inspect}），" \
           "已按 to_s 渲染。建议写成插值：label { \"#{'{...}'}\" }"
    end

    def dispose(node)
      node.owned_effects.each(&:dispose)
      node.owned_effects.clear
      node.children.dup.each { |child| dispose(child) }
      node.children.clear
      detach(node)
    end

    # box 支持布局快捷参数：direction（stack/flow 的抽象）、gap
    # 样式键在此后均为 snake_case（决策 #10，经 Style.normalize 归一）
    # 值可以是 Proc（响应式属性，见 REACTIVE_PROPS）——由本节点的属性 Effect 负责重求值
    def resolve_style(node)
      style = (prop_value(node, node.props[:style]) || {}).dup
      if node.type == :box
        style[:display] ||= "flex"
        if (direction = prop_value(node, node.props[:direction]))
          style[:flex_direction] = direction == :column ? "column" : "row"
        end
        gap = prop_value(node, node.props[:gap])
        style[:gap] = gap.is_a?(Numeric) ? "#{gap}px" : gap.to_s if gap
      end
      # Proc 求值出来的样式没经过 Component#emit，这里统一归一（幂等，静态样式重复归一无副作用）
      Style.normalize(style)
    end

    # ── 响应式属性（G-2）──────────────────────────────────

    # 求值一个 prop 值：Proc → 在该节点 owner 的上下文里求值（可调用组件方法、读信号）
    def prop_value(node, value)
      value.is_a?(Proc) ? node.owner.instance_exec(&value) : value
    end

    def reactive_props?(node)
      node.props.any? { |key, value| value.is_a?(Proc) && REACTIVE_PROPS.include?(key) }
    end

    # 响应式 style 会换掉整份内联样式：记录本次的键，返回需要显式清空的旧键
    # （否则 `style: -> { { background: ok ? "green" : nil } }` 里的绿色会残留）
    def track_style_keys(node, keys)
      stale = (node.applied_style_keys || []) - keys
      node.applied_style_keys = keys
      stale
    end

    # 值类 prop 收到 Proc 时提醒一次：它既不会被求值、也不会订阅
    def warn_unreactive_proc(node)
      bad = node.props.select { |key, value| value.is_a?(Proc) && VALUE_PROPS.include?(key) }
      return if bad.empty? || !respond_to?(:warn, true)

      @warned_value_procs ||= {}
      bad.each_key do |key|
        next if @warned_value_procs[key]

        @warned_value_procs[key] = true
        hint = key == :value ? "受控输入请传 Signal：value: signal(:draft)" : "请直接传值或 Signal"
        warn "[citrine] #{node.type} 的 prop :#{key} 收到 Proc，但它不是响应式属性：" \
             "Proc 不会被求值。支持 Proc 的只有 #{REACTIVE_PROPS.map { |k| ":#{k}" }.join(' / ')}；#{hint}"
      end
    end

    # ── 布局提醒（G-8）────────────────────────────────────

    # 未显式声明方向、且**有多个子节点**的 box 计数：默认 row 是"面板塌成一条"那类
    # 真机事故的根源（桩里没有布局引擎，测不出来），开发模式下按页汇报一次。
    # 空容器/单子容器不会塌，不提醒——避免用噪音换信任。
    def note_undirected_box(node)
      return unless node.type == :box && !node.props.key?(:direction) && node.children.size > 1

      @undirected_boxes = (@undirected_boxes || 0) + 1
    end

    def warn_undirected_boxes
      count = @undirected_boxes.to_i
      @undirected_boxes = 0
      return if count.zero? || !Citrine.dev_mode? || !respond_to?(:warn, true)

      warn "[citrine] 本次挂载有 #{count} 处 box 未声明方向（默认横排 row；内容一多，真机上会塌成一条）：" \
           "竖排请写 stack { }，横排请写 row { }（等价于 box(direction: :column|:row)）。" \
           "本提示只在开发模式出现。"
    end

    # ── 平台钩子 ───────────────────────────────────────────

    def reactive?
      true
    end

    def setup_root(_root, _element)
      raise NotImplementedError
    end

    def create_dom(_node)
      raise NotImplementedError
    end

    def attach(_node, _parent)
      raise NotImplementedError
    end

    def detach(_node)
      raise NotImplementedError
    end

    # 应用属性。必须是**幂等**的：响应式属性重跑时会再次调用，
    # 但只重设属性、不重建子树。事件监听请放 bind_events。
    def apply_props(_node)
      raise NotImplementedError
    end

    # 绑定事件监听（只在挂载时调用一次，不参与响应式重跑）
    def bind_events(_node)
      nil
    end

    def set_text(_node, _text)
      raise NotImplementedError
    end

    def setup_widget(_node)
      nil
    end

    def finalize(_node)
      nil
    end
  end
end
