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
      @reuse_pools = []
    end

    def mount_component(component, element)
      # DSL（Component#emit）经全局 Citrine.renderer 分发到当前渲染器；
      # 响应式 Effect 重跑发生在 mount 之后，也依赖此设置，
      # 因此不恢复旧值——"活动渲染器 = 最近挂载的那个"。
      Citrine.renderer = self
      @undirected_boxes = 0
      root = Node.new(:root, {}, nil, owner: component)
      attach_root_ref(component, root)
      setup_root(root, element)
      run_view(root, component)
      finalize(root)
      warn_undirected_boxes
      register_window_keys(component)
      component.run_mount_hooks if component.respond_to?(:run_mount_hooks)
      root
    end

    # 卸载：销毁整棵子树（含每个节点的 Effect 订阅）、解绑全局键盘、跑 on_unmount。
    # root 自身留着（root.dom 就是页面上那个挂载容器，不属于组件），只清空内容。
    def unmount_component(root)
      root.children.dup.each { |child| dispose(child) }
      root.children.clear
      root.owned_effects.each(&:dispose)
      root.owned_effects.clear

      component = root.owner
      if component.respond_to?(:run_unmount_hooks)
        unregister_window_keys(component)
        component.run_unmount_hooks
      end
      root
    end

    # DSL 挂载入口（Component#emit 调用）：把 node 挂到当前父节点下
    def mount(node)
      parent = @parents.last
      unless parent
        raise "Citrine: 元素挂载时没有父节点。组件 view 只能在渲染器挂载过程中执行；" \
              "一页多根请分别用各渲染器实例（DomRenderer.new + mount_component），不要多次 mount_at"
      end

      node.reuse_key = node.props[:key]
      node.identity ||= [:element, node.type]

      unless node.virtual?
        node.dom = create_dom(node)
        warn_unreactive_proc(node)
        register_ref(node)
      end
      parent.children << node
      unless node.virtual?
        attach(node, attach_target)
        bind_events(node)
        setup_widget(node)
      end

      # G-2：响应式属性必须在**本节点自己的 Effect** 内求值——挂载路径上直接求值会让
      # 订阅落进外层块（正是要消除的隐性外扩）。重跑只重设属性，不重建子树。
      if reactive? && !node.virtual? && reactive_props?(node)
        node.props_effect = Effect.create { apply_props(node) }
        node.owned_effects << node.props_effect
      elsif !node.virtual?
        apply_props(node)
      end

      if node.block
        if reactive?
          node.block_effect = Effect.create do
            run_block(node) { node.owner.instance_exec(&node.block) }
          end
          node.owned_effects << node.block_effect
        else
          run_block(node) { node.owner.instance_exec(&node.block) }
        end
      end
      # 子节点此时才建好：多子容器才会真的"塌"，所以放在 block 之后统计（G-8）
      note_undirected_box(node)
      finalize(node)
      node
    end

    # 嵌套组件入口（Component#render 调用）：
    # 建一个**虚拟边界节点**承载子组件的 view 输出，并以它作为复用/销毁的单位。
    # 返回该边界节点（它不对应任何平台元素）。
    def render_component(owner, component, props)
      raise "Citrine.render：没有父节点（只能在组件的 view 里渲染子组件）" unless @parents.last

      klass = component.is_a?(Class) ? component : component.class
      key = props[:key]
      child_props = props.reject { |name, _| name == :key }
      identity = [:component, klass]

      if (existing = reusable_node(key, identity, child_props))
        # 复用：同一个子组件实例 + 同一棵子树（DOM、state、Effect 全保留）。
        # props 就地更新；结构是否变化交给子组件自己的 view Effect 重跑去调和。
        child = existing.rendered_component
        child.update_props(child_props) if component.is_a?(Class) && child.respond_to?(:update_props)
        existing.block_effect&.run
        return existing
      end

      child = component.is_a?(Class) ? klass.new(child_props) : component
      boundary = Node.new(:component, { key: key }.compact, nil, owner: child, virtual: true)
      boundary.reuse_key = key
      boundary.identity = identity
      boundary.rendered_component = child
      boundary.props = child_props
      child.root = boundary if child.respond_to?(:root=)
      child.renderer = self if child.respond_to?(:renderer=)

      @parents.last.children << boundary
      @parents.push(boundary)
      begin
        run_view(boundary, child)
      ensure
        @parents.pop
      end

      finalize(boundary)

      register_window_keys(child)
      child.run_mount_hooks if child.respond_to?(:run_mount_hooks)
      boundary
    end

    # 复用匹配：key 优先，没有 key 时按"本次第几个子节点"对位（React 的隐含位置 key）。
    # 命中后节点按新顺序重新排位。返回 nil 表示"不匹配，应新建"。
    def reusable_node(key, identity, props)
      pool = @reuse_pools.last
      return nil unless pool

      node = pool.take(key, identity, props)
      return nil unless node

      # 复用的节点要重新计入当前父的子节点表（本轮开始时已清空），顺序由追加次序决定
      @parents.last.children << node
      attach(node, attach_target) unless node.virtual?
      node
    end

    # 复用既有节点：就地换上新 props/block，重应用属性，并重跑两个 Effect。
    # 事件监听不需要重绑：DOM 监听器在事件发生时从 node.props 现取处理器（见 DomRenderer#bind_events）。
    def refresh_node(node, props, block)
      node.props = props
      node.block = block
      apply_props(node) unless node.virtual?
      node.props_effect&.run
      node.block_effect&.run
      node
    end

    private

    def run_view(root, component)
      if reactive?
        root.block_effect = Effect.create do
          run_block(root) { component.instance_exec { view } }
        end
        root.owned_effects << root.block_effect
      else
        run_block(root) { component.instance_exec { view } }
      end
    end

    # 重建 node 的子树：带 key 的子节点**复用**（同一批 DOM/Effect/组件实例），
    # 其余按今天的语义整体重建；本轮未被复用的旧节点在此完整卸载。
    def run_block(node)
      previous = node.children.dup
      node.children.clear
      @parents.push(node)
      pool = ReusePool.new(previous)
      @reuse_pools.push(pool)

      result = yield
      if !result.nil? && node.children.empty?
        if node.virtual?
          raise "Citrine.render：子组件的 view 必须渲染元素节点（返回了 #{result.class}）；" \
                "纯文本请包进 label { … } 之类"
        end
        warn_nonstring(node, result) unless result.is_a?(String)
        set_text(node, result)
      end
      result
    ensure
      @parents.pop
      @reuse_pools.pop
      pool.unused_nodes.each { |old| dispose(old) }
    end

    # keyed 复用的匹配池：一次块执行内，按 key + 身份标签取用旧节点。
    class ReusePool
      def initialize(nodes)
        @all = nodes.dup
        @keyed = {}
        nodes.each { |node| @keyed[node.reuse_key] = node if node.reuse_key }
        @taken = {}
        @seen = {}
        @cursor = 0
      end

      # key 优先；没有 key 时按"本次第几个子节点"对位匹配（React 的隐含位置 key）。
      def take(key, identity, props)
        @cursor += 1
        if key
          register!(key)
          candidate = @keyed[key]
        else
          candidate = @all[@cursor - 1]
        end
        return nil unless candidate && candidate.identity == identity
        return nil if @taken.key?(candidate.object_id)
        return nil unless same_props?(candidate.props, props)

        @taken[candidate.object_id] = candidate
        candidate
      end

      # 登记本层出现过的 key（新建路径也要走，用于重复检测）
      def register!(key)
        raise "Citrine: 同一层出现重复 key #{key.inspect}（key 只需在兄弟间唯一）" if @seen.key?(key)

        @seen[key] = true
      end

      # 复用之外的旧节点（含所有没 key 的）＝本轮被替换掉的，交给渲染器卸载
      def unused_nodes
        @all - @taken.values
      end

      private

      # 比较 props 时忽略 key 与 Proc：Proc（响应式属性 / 回调）每次都是新对象，
      # 不能作为"变了"的依据（S2 会让它们真正参与更新）
      def same_props?(old_props, new_props)
        comparable(old_props) == comparable(new_props)
      end

      def comparable(props)
        props.reject { |name, value| name == :key || value.is_a?(Proc) }
      end
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

      # 组件边界：子组件随之卸载（解绑全局键盘 + 跑 on_unmount），顺序是"先子后父"
      if (child = node.rendered_component)
        node.rendered_component = nil
        unregister_window_keys(child)
        child.run_unmount_hooks if child.respond_to?(:run_unmount_hooks)
      end

      detach(node) unless node.virtual?
    end

    # 虚拟节点（组件边界）不产生平台元素：它的后代挂到最近的"真实"祖先上
    def attach_target
      @parents.reverse_each { |node| return node unless node.virtual? }
      nil
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

    # ── 生命周期与全局键盘（G-9 / G-10）────────────────────

    # 组件与它的根节点/渲染器互相记住：卸载时才知道该拆哪棵树
    def attach_root_ref(component, root)
      return unless component.respond_to?(:root=)

      component.root = root
      component.renderer = self if component.respond_to?(:renderer=)
    end

    # ref: :name → component.refs[:name] = 平台句柄（DOM 下是元素本身）
    def register_ref(node)
      name = node.props[:ref]
      return unless name && node.owner.respond_to?(:refs)

      node.owner.refs[name] = node.dom
    end

    def register_window_keys(component)
      return unless component.respond_to?(:run_unmount_hooks)

      component.class.window_key_handlers.each { |handler| register_window_key(component, handler) }
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

    # 全局键盘（window 级）：DOM 渲染器实现；其它平台默认无操作
    def register_window_key(_component, _handler)
      nil
    end

    def unregister_window_keys(_component)
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
