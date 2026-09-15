# frozen_string_literal: true

require_relative "signal"
require_relative "node"
require_relative "style"

module Citrine
  # 可调用体（Symbol / Proc）分发的统一入口：Symbol 在 receiver 上按 arity
  # 决定是否接收实参；Proc 默认保持闭包 self（事件回调的语义——嵌套组件的
  # 父级回调不能被重绑），bind: true 时重绑到 receiver（生命周期钩子 /
  # error_fallback 需要在 owner 上下文里调 DSL）。
  # 事件处理器（Component#handle_event）与错误兜底（Renderer#render_error_fallback）
  # 同此一份 arity 约定，不再各处手写分支。
  def self.dispatch_callable(handler, receiver, arg = nil, bind: false)
    case handler
    when Symbol
      receiver.method(handler).arity.zero? ? receiver.send(handler) : receiver.send(handler, arg)
    when Proc
      if handler.arity.zero?
        bind ? receiver.instance_exec(&handler) : handler.call
      else
        bind ? receiver.instance_exec(arg, &handler) : handler.call(arg)
      end
    else
      raise ArgumentError, "无法分发的处理器: #{handler.inspect}"
    end
  end

  # 渲染器基类：节点树管理 + Effect 装配 + 块级重建/销毁（平台无关）。
  #
  # 平台子类实现钩子：setup_root / create_dom / attach / detach /
  # apply_props / bind_events / set_text / setup_widget / finalize，
  # 并以 reactive? 声明是否建立更新订阅（一次性渲染如 StringRenderer 返回 false）。
  class Renderer
    TAGS = { box: "div", label: "p", button: "button",
             text_input: "input", check_box: "input" }.freeze
    VOID = %i[text_input check_box img].freeze

    # 响应式属性白名单：这些 prop 的值可以是 Proc，在**该节点自己的 Effect** 内求值。
    #
    # G-2：props 的求值位置决定订阅范围——写成 `box(css_class: cell_class(row, col))`
    # 时实参在**外层块**执行期间求值，于是外层块订阅了这一格的信号（改一格 → 整块重建）。
    # 写成 `box(css_class: -> { cell_class(row, col) })` 则订阅落在本节点的属性 Effect 上，
    # 且重跑只重设属性、不重建子树。
    #
    # 事件处理器（on_*）不在此列：它们的 Proc 是回调，不是待求值的值。
    REACTIVE_PROPS = %i[css_class placeholder style direction gap].freeze

    # 透明容器类型（S1-4 fragment / S1-5 portal / S1-10 suspense）：无自身 DOM 语义，
    # dispose 时不对它们做 detach（子根挂在真实容器上，逐个摘除）
    TRANSPARENT_TYPES = %i[fragment portal suspense].freeze

    # S2-2：框架未消费的属性原样透传到 DOM / SSR（id / disabled / aria_* / data_* / title …）。
    # 命名规则：snake_case → kebab-case（aria_label → aria-label）；
    # 布尔规则：true → 空值属性（<button disabled>）、false / nil → 不输出。
    # 消费面（不透传）：布局快捷键、样式、复用/引用标记、事件回调（on_*），
    # 以及值类 prop（见 WIDGET_VALUE_PROPS，节点感知）。
    ALWAYS_CONSUMED = %i[key ref style css_class direction gap portal_target
                         suspense_ready suspense_loading].freeze

    # 值类 prop 只在对应控件上被框架消费；其他元素（textarea / select / 自定义标签）
    # 照常透传——否则 value 又会被静默吞掉（F11 的老路）
    WIDGET_VALUE_PROPS = {
      placeholder: [:text_input], type: %i[text_input check_box],
      value: [:text_input], checked: [:check_box]
    }.freeze

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
      component.run_watch_effects if reactive? && component.respond_to?(:run_watch_effects)
      component.run_effects if reactive? && component.respond_to?(:run_effects)
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

      return mount_portal(node, parent) if node.type == :portal
      return mount_suspense(node, parent) if node.type == :suspense
      return mount_fragment(node, parent) if node.type == :fragment

      node.dom = create_dom(node)
      warn_unreactive_proc(node)
      register_ref(node)
      parent.children << node
      attach(node, parent)
      bind_events(node)
      setup_widget(node)

      # G-2：响应式属性必须在**本节点自己的 Effect** 内求值——挂载路径上直接求值会让
      # 订阅落进外层块（正是要消除的隐性外扩）。重跑只重设属性，不重建子树。
      if reactive? && reactive_props?(node)
        node.props_effect = Effect.create { apply_props(node) }
        node.owned_effects << node.props_effect
      else
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

    # 透明容器（S1-4）：children 插槽的落位节点。无自身 DOM——借父容器的，
    # 子孙 attach 经它落到真实父容器；不参与属性/事件（也没有 props 可言）。
    def mount_fragment(node, parent)
      mount_transparent(node, parent, parent.dom)
    end

    # Portal（S1-5）：子树挂到渲染器指定的宿主节点（DOM 下默认 body）——
    # 逃出父容器的 overflow / 层叠上下文。树上仍是逻辑父的孩子（复用、Effect、
    # 卸载级联与原地渲染一致），DOM 上子孙落到宿主；卸载时随 dispose 逐个摘除，
    # 宿主里 portal 之外的内容不受影响。
    def mount_portal(node, parent)
      mount_transparent(node, parent, resolve_portal_host(node.props[:portal_target]))
    end

    def mount_transparent(node, parent, host_dom)
      node.dom = host_dom
      parent.children << node
      if reactive?
        node.block_effect = Effect.create do
          run_block(node) { node.owner.instance_exec(&node.block) }
        end
        node.owned_effects << node.block_effect
      else
        run_block(node) { node.owner.instance_exec(&node.block) }
      end
      finalize(node)
      node
    end

    # Suspense（S1-10）：依赖未就绪时渲染占位，就绪后原地切换到真实内容。
    # ready Proc 的信号读取订阅在本节点的 Effect 上——就绪状态翻转驱动切换；
    # 占位/真实内容走通用块调和（旧分支节点被替换，其余组件实例与 state 不动）。
    # 只做"渲染期等待"，不含数据请求实现。
    def mount_suspense(node, parent)
      node.dom = parent.dom
      parent.children << node
      if reactive?
        node.block_effect = Effect.create { run_suspense(node) }
        node.owned_effects << node.block_effect
      else
        run_suspense(node) # SSR / 一次性渲染：只输出当前分支
      end
      finalize(node)
      node
    end

    def run_suspense(node)
      owner = node.owner
      ready = node.props[:suspense_ready]
      loading = node.props[:suspense_loading]
      # ready 的读取（Proc 在 owner 上下文求值）订阅本节点的 Effect——
      # 就绪状态翻转是切换的触发源
      ready_value = ready.nil? ? true : prop_value(node, ready)
      is_ready = !ready_value.nil? && ready_value != false

      previous = node.children.dup
      node.children.clear
      @parents.push(node)
      pool = ReusePool.new(previous)
      @reuse_pools.push(pool)

      if is_ready
        owner.instance_exec(&node.block) if node.block
      elsif loading
        owner.instance_exec(&loading)
      end
    ensure
      @parents.pop
      @reuse_pools&.pop
      pool&.unused_nodes&.each { |old| dispose(old) }
    end

    # 嵌套组件入口（Component#render 调用）。
    #
    # 复用单位 = 子组件实例（+它的根节点）。同类组件落到同一槽位即复用（S1-2）：
    # props 差异经 prop 信号原地传播，实例与 state 保留；子组件 view 在**自己的
    # Effect** 里执行（首次挂载创建），prop/state 的 view 体读取都订阅它——
    # 父块不再因子组件重渲染而重跑，prop 写入也不会再入正在运行的父块。
    # 带 block 调用即插槽（S1-4）：块由子组件经 children 落位，块内 self 是父组件。
    def render_component(owner, component, props, &children_block)
      raise "Citrine.render：没有父节点（只能在组件的 view 里渲染子组件）" unless @parents.last

      klass = component.is_a?(Class) ? component : component.class
      key = props[:key]
      ref_name = props[:ref]
      child_props = props.reject { |name, _| name == :key || name == :ref }

      if (existing = reusable_node(key, [:component, klass], child_props, owner))
        child = existing.rendered_component
        existing.component_props = child_props
        child.update_props(child_props) if component.is_a?(Class) && child.respond_to?(:update_props)
        child.set_children_block(children_block, owner) if child.respond_to?(:set_children_block)
        register_component_ref(owner, ref_name, child)
        return child.respond_to?(:root) && child.root ? child.root : existing
      end

      child = component.is_a?(Class) ? klass.new(child_props) : component
      child.set_children_block(children_block, owner) if child.respond_to?(:set_children_block)
      parent = @parents.last
      if reactive? && child.respond_to?(:view_effect=)
        child.view_effect = Effect.create do
          child.root ? rerun_component_view(child, parent) : first_component_render(child, parent, klass, key, child_props)
        end
        node = child.root
      else
        node = first_component_render(child, parent, klass, key, child_props)
      end
      register_component_ref(owner, ref_name, child)
      register_window_keys(child)
      child.run_mount_hooks if child.respond_to?(:run_mount_hooks)
      child.run_watch_effects if reactive? && child.respond_to?(:run_watch_effects)
      child.run_effects if reactive? && child.respond_to?(:run_effects)
      node
    end

    # 首次渲染子组件 view，收编输出为组件根：恰好一个真实节点 → 该节点就是根；
    # 多个 → 包进透明 fragment（复用/销毁单位仍是组件实例）。
    def first_component_render(child, parent, klass, key, child_props)
      before = parent.children.size
      run_view_with_fallback(child, parent)
      added = parent.children[before..] || []
      if added.empty?
        raise "Citrine.render：子组件的 view 必须渲染**至少一个**根节点，实际 0 个；" \
              "纯文本请包一层 label { }，多根会按 fragment 处理"
      end

      node = if added.size == 1
               added.first
             else
               wrap_fragment(added, parent, before, child)
             end
      adopt_root(node, child, [:component, klass], key, child_props)
      node
    end

    # 子组件 view 的后续重跑（prop/state 信号触发）：原地调和回既有根。
    # mount/reusable 的 attach 一律追加到末尾，信号驱动的重跑发生在父块渲染之外，
    # 因此 reconcile 后要把根挪回原渲染位（attach_before），保持兄弟次序。
    def rerun_component_view(child, parent)
      node = child.root
      return rerun_fragment_view(child, node, parent) if node.type == :fragment

      index = parent.children.index(node)
      raise "Citrine.render：子组件 #{child.class} 的根不在宿主容器里（正常流程不可达）" unless index

      anchor = parent.children[index + 1]
      parent.children.delete(node)
      size_before = parent.children.size
      pool = ReusePool.new([node])
      @parents.push(parent)
      @reuse_pools.push(pool)
      run_view_with_fallback(child, parent)
      if parent.children.size != size_before + 1
        raise "Citrine.render：子组件的 view 必须渲染**恰好一个**根节点，" \
              "实际 #{parent.children.size - size_before} 个；多根或纯文本请自行包一层 stack { }"
      end

      new_root = parent.children.pop
      parent.children.insert(index, new_root)
      unless new_root.equal?(node)
        # 根元素换了类型：旧根整棵卸载，但**组件实例仍然活着**（S3-2 的边界摘除舞步）：
        # 先摘组件边界再 dispose，dispose 就不会误跑 on_unmount / 解绑全局键盘。
        node.rendered_component = nil
        adopt_root(new_root, child, node.component_identity, node.reuse_key, node.component_props)
      end
      reposition(new_root, parent, anchor)
    ensure
      @parents.pop
      @reuse_pools&.pop
      pool&.unused_nodes&.each { |old| dispose(old) }
    end

    # 多根子组件的重跑：把 fragment 当块容器重跑（子根经 fragment.dom 落到真实父容器）
    def rerun_fragment_view(child, frag, parent)
      index = parent.children.index(frag)
      return unless index

      anchor = parent.children[index + 1]
      parent.children.delete(frag)
      pool = ReusePool.new(frag.children.dup)
      frag.children.clear
      @parents.push(frag)
      @reuse_pools.push(pool)
      run_view_with_fallback(child, frag)
    ensure
      @parents.pop
      @reuse_pools&.pop
      pool&.unused_nodes&.each { |old| dispose(old) }
      if index && !parent.children[index].equal?(frag)
        parent.children.insert(index, frag)
      end
      frag.children.each { |n| reposition(n, parent, anchor) if index }
    end

    # 多根输出 → 透明 fragment：子根已在 parent.dom 里（view 挂载时 attach 的），
    # 树上收拢到 fragment 名下、fragment 占据首个子根的原渲染位。
    # dom 借父容器的（与 mount_fragment 同一口径）：子根 attach 经它落到真实父容器。
    def wrap_fragment(added, parent, index, child)
      fragment = Node.new(:fragment, {}, nil, owner: child)
      fragment.identity = [:element, :fragment]
      fragment.dom = parent.dom
      added.each { |n| parent.children.delete(n) }
      fragment.children.concat(added)
      parent.children.insert(index, fragment)
      finalize(fragment)
      fragment
    end

    # 把一个真实节点标记为"某子组件的根"（复用 / 卸载 / 生命周期都以它为单位）
    def adopt_root(node, child, identity, key, child_props)
      node.rendered_component = child
      node.component_identity = identity # 注意：不覆盖 identity（它仍是该元素的元素身份）
      node.reuse_key = key
      node.component_props = child_props
      child.root = node if child.respond_to?(:root=)
      child.renderer = self if child.respond_to?(:renderer=)
      node
    end

    # S1-9：ref: :name 登记的是**子组件实例**（元素 ref 登记平台句柄），
    # 父经 refs 取到实例即可调用其公开方法。复用/重建两条路径都重新登记，
    # 保证指向当前活着的实例。
    def register_component_ref(owner, name, child)
      return unless name && owner.respond_to?(:refs)

      owner.refs[name] = child
    end

    # 复用匹配：key 优先，没有 key 时按"本次第几个子节点"对位（React 的隐含位置 key）。
    # 命中后节点按新顺序重新排位。返回 nil 表示"不匹配，应新建"。
    def reusable_node(key, identity, props, requester)
      pool = @reuse_pools.last
      return nil unless pool

      node = pool.take(key, identity, props, requester)
      return nil unless node

      # 复用的节点要重新计入当前父的子节点表（本轮开始时已清空），顺序由追加次序决定
      @parents.last.children << node
      # 透明容器（fragment / portal）无自身 DOM（借宿主容器的），没有可挂的东西
      attach(node, @parents.last) unless TRANSPARENT_TYPES.include?(node.type)
      node
    end

    # 复用既有节点：就地换上新 props/block，重应用属性，并重跑两个 Effect。
    # 事件监听不需要重绑：DOM 监听器在事件发生时从 node.props 现取处理器（见 DomRenderer#ensure_events）。
    def refresh_node(node, props, block)
      node.props = props
      node.block = block
      # 有属性 Effect 时由它求值（Effect 体内就是 apply_props）；再直接调一次会让每次复用
      # 都写两遍属性与样式（幂等但白做），因此这里二选一。
      if node.props_effect
        node.props_effect.run
      else
        apply_props(node)
      end
      node.block_effect&.run
      node
    end

    # Context 解析（S1-3）：沿当前渲染遍历栈向上找提供 name 的**最近**祖先组件
    # （跳过读者自己——组件读自己的 context 时应取到祖先的）。
    # 只在渲染遍历内可用；消费端首次绑定发生在挂载路径上，之后走缓存绑定。
    # 供 Component#use_context 跨对象调用，保持 public。
    def find_context_provider(name, consumer)
      @parents.reverse_each do |node|
        owner = node.owner
        next if owner.nil? || owner.equal?(consumer)

        return owner if owner.provides_context?(name)
      end
      nil
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

      result = begin
        yield
      rescue StandardError => e
        raise unless (fallback_owner = fallback_owner_for(node))

        # S1-6：失败那一轮不留半更新——块内本轮产出的节点全部拆掉
        # （抛错的子组件从未被收编，不会伪装成卸载、不跑 on_unmount），
        # 然后以异常对象渲染兜底内容
        node.children.dup.each { |child| dispose(child) }
        node.children.clear
        render_error_fallback(fallback_owner, fallback_owner.class.error_fallback_def, e)
        nil
      end
      if !result.nil? && node.children.empty?
        warn_nonstring(node, result) unless result.is_a?(String)
        set_text(node, result)
      elsif node.text && !node.text.to_s.empty?
        # C3：上一轮写过文本、本轮没有（内容切成子节点或 nil）——显式清空，
        # 否则旧 textContent 与新内容叠加（label { cond ? "text" : nil } 的残留）
        set_text(node, "")
      end
      result
    ensure
      @parents.pop
      @reuse_pools.pop
      pool.unused_nodes.each { |old| dispose(old) }
    end

    # S1-6：本块的 owner 声明了 error_fallback 时，它就是边界组件
    def fallback_owner_for(node)
      owner = node.owner
      owner && owner.class.error_fallback_def ? owner : nil
    end

    # C1：子组件 view 的统一执行入口（首次挂载与信号驱动重跑同口径）。
    # 与 run_block 的错误边界同思路，但兜底归**子组件自己**声明的 error_fallback——
    # 重跑路径上不存在外层块，异常原来直接穿出 Effect → Scheduler → 事件处理器，
    # 子组件自己的 fallback 永远接不住。未声明兜底的组件照常上抛
    # （由外层块的边界或调用方处理，与挂载路径一致）。
    def run_view_with_fallback(child, parent)
      before = parent.children.size
      child.instance_exec { view }
    rescue StandardError => e
      raise unless (fallback = child.class.error_fallback_def)

      # 失败那一轮不留半更新：本轮已产出（未收编）的节点全部拆掉，
      # 然后以异常对象渲染兜底内容（其输出占据组件根的位置）
      added = parent.children[before..] || []
      added.each { |n| dispose(n) }
      parent.children.pop(added.size)
      render_error_fallback(child, fallback, e)
      fallback_added = parent.children.size - before
      if fallback_added != 1
        raise "Citrine.render：error_fallback 的输出必须是**恰好一个**根节点，" \
              "实际 #{fallback_added} 个；多根请自行包一层 stack { }"
      end
      nil
    end

    # 异常对象交给兜底分支（经 Citrine.dispatch_callable，与事件处理器同口径；
    # Proc 需要 owner 上下文里的 DSL，故 bind: true 重绑 self）
    def render_error_fallback(owner, fallback, error)
      Citrine.dispatch_callable(fallback, owner, error, bind: true)
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
      # 同一个节点有两种身份：元素身份（自身）与组件根身份（它是某子组件的根）——
      # 父组件按组件身份匹配、子组件 view 重跑时按元素身份匹配，两者指向同一节点。
      #
      # requester = 本次正在渲染的组件（emit 的 owner）。**元素槽位只认这个组件自己的节点**：
      # 跨组件复用会让 refresh_node 沿用旧节点的 Effect，而 Effect 里是
      # `node.owner.instance_exec(&node.block)`——owner 不跟着换，新块就在老 self 上跑。
      # （同一位置换组件类型、或新组件的根按位置抢到旧组件的根，都会踩到。）
      def take(key, identity, props, requester)
        @cursor += 1
        candidate = if key
                      register!(key)
                      @keyed[key]
                    else
                      @all[@cursor - 1]
                    end
        return nil unless candidate
        return nil if @taken.key?(candidate.object_id)

        if identity.first == :component
          # 组件槽位（S1-2）：同类组件落到同一槽位即复用——props 差异经 prop 信号
          # 原地传播（读它的块才重跑），不再作为"变了就重建"的依据；
          # 按 props 比较会让父每次重传都重建子组件、丢光子组件 state。
          return nil unless candidate.component_identity == identity
        else
          # 元素槽位：keyed 与位置匹配都要求"由同一个组件渲染出来的节点"
          return nil unless candidate.owner.equal?(requester)
          return nil unless candidate.identity == identity && same_props?(candidate.props, props)
        end

        @taken[candidate.object_id] = candidate
        candidate
      end

      # 登记本层出现过的 key（新建路径也要走，用于重复检测）
      def register!(key)
        raise "Citrine: 同一层出现重复 key #{key.inspect}（key 只需在兄弟间唯一）" if @seen.key?(key)

        @seen[key] = true
      end

      # 复用之外的旧节点（含所有没 key 的）＝本轮被替换掉的，交给渲染器卸载。
      # 以 @taken（object_id 为键）判定"是否被取走"：不构造临时数组/哈希——每轮块重跑
      # 都会走这里，而 `Array#-` 会为右侧集合建一份临时哈希（Opal 侧同样如此）。
      def unused_nodes
        @all.reject { |node| @taken.key?(node.object_id) }
      end

      private

      # 比较 props 时忽略 key 与 Proc：Proc（响应式属性 / 回调）每次都是新对象，
      # 不能作为"变了"的依据（仅元素槽位还在用它；组件槽位走信号传播，S1-2）
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

      # 透明容器（fragment / portal）无自身 DOM：子根挂在真实父容器上，不能对它做 detach
      detach(node) unless TRANSPARENT_TYPES.include?(node.type)
    end

    # box 支持布局快捷参数：direction（stack/flow 的抽象）、gap
    # 样式键在此后均为 snake_case（决策 #10，经 Style.normalize 归一）
    # 值可以是 Proc（响应式属性，见 REACTIVE_PROPS）——由本节点的属性 Effect 负责重求值
    def resolve_style(node)
      style = (prop_value(node, node.props[:style]) || {}).dup
      if node.type == :box
        style[:display] ||= "flex"
        # A7：显式 display 不是 flex（如 grid）时 direction 与它无关——flex_direction
        # 写给 grid 容器是无效声明，还会让阅读者误以为方向控制生效了
        if style[:display].to_s == "flex" && (direction = prop_value(node, node.props[:direction]))
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

    # ── S2-2：属性透传 ─────────────────────────────────────

    def passthrough_prop?(name, node)
      return false if ALWAYS_CONSUMED.include?(name)
      return false if name.to_s.start_with?("on_")

      consumed_on = WIDGET_VALUE_PROPS[name]
      consumed_on ? !consumed_on.include?(node&.type) : true
    end

    # 未消费属性 → [[kebab-case 名, 字符串值]]。true → ""（空值属性）；false / nil 不输出。
    # DOM 与 SSR 两侧共用同一口径，保证输出一致。
    def passthrough_props(node)
      node.props.map do |name, value|
        next unless passthrough_prop?(name, node)
        next if value.nil? || value == false

        [Style.kebab(name), value == true ? "" : value.to_s]
      end.compact
    end

    # 响应式 style 会换掉整份内联样式：记录本次的键，返回需要显式清空的旧键
    # （否则 `style: -> { { background: ok ? "green" : nil } }` 里的绿色会残留）
    def track_style_keys(node, keys)
      stale = (node.applied_style_keys || []) - keys
      node.applied_style_keys = keys
      stale
    end

    # 值类 prop / 透传属性收到 Proc 或 Signal 时提醒一次：它们不会被求值、
    # 也不会订阅（on_* 的 Proc 是回调，不在此列；value:/checked: 传 Signal 是
    # 受控值语义，也不在 warn 之列）。Signal 落进透传属性会被 to_s 成
    # "#<Citrine::Signal…>" 输出——静默坏页面，必须提醒。
    def warn_unreactive_proc(node)
      bad = node.props.select do |key, value|
        (value.is_a?(Proc) && !REACTIVE_PROPS.include?(key) &&
          (WIDGET_VALUE_PROPS.key?(key) || passthrough_prop?(key, node))) ||
          (value.is_a?(Signal) && passthrough_prop?(key, node))
      end
      return if bad.empty? || !respond_to?(:warn, true)

      @warned_bad_props ||= {}
      bad.each do |key, value|
        next if @warned_bad_props[key]

        @warned_bad_props[key] = true
        message = if value.is_a?(Signal)
                    "[citrine] #{node.type} 的 prop :#{key} 收到 Signal，但它是透传属性：" \
                    "Signal 不会被解包，会渲染成 #<Citrine::Signal…>。请传 .get 后的值；" \
                    "要双向绑定请用受控值属性（value: / checked:）"
                  else
                    hint = key == :value ? "受控输入请传 Signal：value: signal(:draft)" : "请直接传值或 Signal"
                    "[citrine] #{node.type} 的 prop :#{key} 收到 Proc，但它不是响应式属性：" \
                    "Proc 不会被求值。支持 Proc 的只有 #{REACTIVE_PROPS.map { |k| ":#{k}" }.join(' / ')}；#{hint}"
                  end
        warn message
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

    # ── 信号驱动重跑的落位（S1-2）────────────────────────────
    # mount / reusable 的 attach 一律追加到父容器末尾；子组件 view 的信号重跑发生在
    # 父块渲染之外，reconcile 完必须把根挪回原渲染位，否则它会排到后续兄弟后面。

    # anchor = 原位后面的兄弟 Node；nil 表示本来就该排最后（attach 已就位，无需动）
    def reposition(node, parent, anchor)
      attach_before(node, parent, anchor) if anchor
    end

    # 平台钩子：把 node 挪到 parent 内 anchor 之前。默认无操作——
    # 线性追加式渲染器按渲染序落位（如 Canvas 全量重绘按树遍历），无需移动。
    def attach_before(_node, _parent, _anchor)
      nil
    end

    # Portal 宿主解析（S1-5）：target 为 nil → 平台默认宿主（DOM 下是 body）。
    # 显式给了 target 却解析不到时由平台实现处理（DOM 侧抛错，不静默回退）。
    def resolve_portal_host(_target)
      raise NotImplementedError, "#{self.class} 不支持 portal"
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

    # 绑定事件监听（挂载时调用一次）。DOM 渲染器按需绑定，并在响应式属性重跑时
    # 补齐新出现的处理器（见 DomRenderer#ensure_events）
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
