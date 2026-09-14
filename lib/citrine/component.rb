# frozen_string_literal: true

require_relative "signal"
require_relative "node"
require_relative "style"

module Citrine
  # 组件基类：prop / state / computed 三宏（GOALS.md 第七节定案 API）。
  #
  #   class Counter < Citrine::Component
  #     prop    :title, type: String, default: "Counter"
  #     state   :count, default: 0
  #     computed :double { count * 2 }
  #
  #     def view
  #       box(direction: :column) do
  #         label { "count = #{count} (x2 = #{double})" }
  #         button(on_click: :increment) { "加一" }
  #       end
  #     end
  #
  #     def increment
  #       self.count += 1          # 赋值即更新
  #     end
  #   end
  class Component
    # 元素 DSL 方法名：prop 不能与它们重名（否则读 prop 会覆盖元素方法）
    DSL_METHODS = %i[box stack row label button text_input check_box render].freeze

    class << self
      def prop_defs
        @prop_defs ||= superclass.respond_to?(:prop_defs) ? superclass.prop_defs.dup : {}
      end

      def state_defs
        @state_defs ||= superclass.respond_to?(:state_defs) ? superclass.state_defs.dup : {}
      end

      def compute_defs
        @compute_defs ||= superclass.respond_to?(:compute_defs) ? superclass.compute_defs.dup : {}
      end

      # 只读输入，来自父组件；未声明的 prop 视为错误
      def prop(name, type: nil, default: nil)
        if DSL_METHODS.include?(name)
          raise ArgumentError,
                "prop :#{name} 与元素 DSL 方法同名：读它会把 #{name} { … } 覆盖掉。" \
                "请改名，或显式读 props[:#{name}]"
        end

        prop_defs[name] = { type: type, default: default }
        define_method(name) { @props[name] }
      end

      # 可变状态：读写受追踪，写入触发订阅该状态的 block 重跑
      def state(name, default: nil, &init)
        state_defs[name] = [default, init]
        define_method(name) { signal(name).get }
        define_method("#{name}=") { |value| signal(name).set(value) }
      end

      # 派生值：依赖自动收集，上游变化自动失效重算
      def computed(name, &block)
        compute_defs[name] = block
        define_method(name) { computation(name) }
      end

      # ── 子组件关键字（P0-1，写法 A：小写关键字）────────────────
      #
      #   class WatchlistPanel < Citrine::Component
      #     components WatchRow                 # → view 里可用 watch_row(…)
      #     components PositionRow => :pos_row  # → 显式改名（与本类已有方法重名时）
      #   end
      #
      # 关键字是与元素 DSL（box / label / stack / …）同构的小写方法，底层就是 render。
      def components(*specs)
        specs.each do |spec|
          klass, keyword = spec.is_a?(Hash) ? spec.first : [spec, nil]
          name = (keyword || default_keyword(klass)).to_sym
          if method_defined?(name) || private_method_defined?(name)
            raise ArgumentError,
                  "components #{klass}: 关键字 #{name} 与本类已有方法重名，请显式改名：" \
                  "components #{klass.name} => :其他名字"
          end

          component_keywords[name] = klass
          define_method(name) do |**props, &block|
            render(klass, **props, &block)
          end
        end
      end

      def component_keywords
        @component_keywords ||=
          superclass.respond_to?(:component_keywords) ? superclass.component_keywords.dup : {}
      end

      # PositionRow → position_row；Panels::WatchRow → watch_row
      def default_keyword(klass)
        name = klass.name.to_s
        if name.empty?
          raise ArgumentError,
                "components 需要具名组件类；匿名类请显式给关键字（components Foo => :foo_keyword）"
        end

        name.split("::").last
            .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
            .gsub(/([a-z\d])([A-Z])/, '\1_\2')
            .downcase
      end

      # ── 生命周期与全局键盘（G-9 / G-10）─────────────────────
      # 三者都是"挂载期间生效"的声明，随组件卸载一起失效；子类继承父类的声明。

      def mount_hooks
        @mount_hooks ||= superclass.respond_to?(:mount_hooks) ? superclass.mount_hooks.dup : []
      end

      def unmount_hooks
        @unmount_hooks ||= superclass.respond_to?(:unmount_hooks) ? superclass.unmount_hooks.dup : []
      end

      # window 级 keydown 处理器（键盘优先应用的导航/快捷键）：挂载时注册、卸载时移除
      def window_key_handlers
        @window_key_handlers ||= superclass.respond_to?(:window_key_handlers) ? superclass.window_key_handlers.dup : []
      end

      # 挂载完成后执行（DOM 已就位）：适合 focus、定时器、第三方库初始化
      def on_mount(handler = nil, &block)
        mount_hooks << (block || handler)
      end

      # 组件销毁时执行：清理定时器、监听器、未完成的请求
      def on_unmount(handler = nil, &block)
        unmount_hooks << (block || handler)
      end

      # 声明一个 window 级键盘处理器（Symbol 或 Proc）；卸载时自动解绑
      #
      #   class Editor < Citrine::Component
      #     window_key :global_key
      #     def global_key(ev) = move(1) if ev.key == "ArrowDown"
      #   end
      def window_key(handler)
        window_key_handlers << handler
      end
    end

    attr_reader :props

    # 组件挂载的根节点与所属渲染器（挂载时由渲染器写入；卸载时用）
    attr_accessor :root, :renderer

    # ref: :name 的元素句柄（DOM 下是元素本身）；挂载时登记，卸载时清空
    def refs
      @refs ||= {}
    end

    def initialize(props = {})
      defs = self.class.prop_defs
      unexpected = props.keys - defs.keys
      raise ArgumentError, "未声明的 prop: #{unexpected.join(', ')}" unless unexpected.empty?

      @props = {}
      defs.each do |name, definition|
        value = props.key?(name) ? props[name] : definition[:default]
        if definition[:type] && !value.is_a?(definition[:type])
          raise TypeError, "prop #{name} 应为 #{definition[:type]}，实际为 #{value.class}"
        end

        @props[name] = value
      end
    end

    def signals
      @signals ||= {}
    end

    # 父组件重传 props（嵌套复用时的就地更新，P0-1/S1）：
    # 校验口径与 initialize 完全一致（未声明 prop / 类型不符都当场报错）。
    # 子组件侧的读法不变（prop :x 仍是只读），S2 会把它们升级成信号以获得细粒度更新。
    def update_props(new_props)
      defs = self.class.prop_defs
      unexpected = new_props.keys - defs.keys
      raise ArgumentError, "未声明的 prop: #{unexpected.join(', ')}" unless unexpected.empty?

      new_props.each do |name, value|
        definition = defs[name]
        if definition[:type] && !value.is_a?(definition[:type])
          raise TypeError, "prop #{name} 应为 #{definition[:type]}，实际为 #{value.class}"
        end

        @props[name] = value
      end
      self
    end

    def computations
      @computations ||= {}
    end

    # 取底层 Signal（双向绑定等需要信号对象本身的场景）
    def signal(name)
      default, init = self.class.state_defs.fetch(name) do
        raise ArgumentError, "未声明的 state: #{name}"
      end
      signals[name] ||= Signal.new(init ? instance_eval(&init) : default)
    end

    # ── 元素 DSL：在 view / block 中调用，由当前渲染器挂载 ──────────

    def box(**props, &block)
      emit(:box, props, &block)
    end

    # 布局语法糖（G-8）：方向必须显式——避免"忘了写 direction 的 box"在真机上塌掉
    # （box 的默认方向仍是 CSS 的 row；未声明方向的 box 会在开发模式下被提醒）
    def stack(**props, &block)
      emit_directional(:column, props, &block)
    end

    def row(**props, &block)
      emit_directional(:row, props, &block)
    end

    def label(**props, &block)
      emit(:label, props, &block)
    end

    def button(on_click: nil, **props, &block)
      props = props.merge(on_click: on_click) if on_click
      emit(:button, props, &block)
    end

    # 受控文本输入：value 传 Signal（通常用 signal(:name) 获取）
    def text_input(value: nil, placeholder: nil, on_enter: nil, **props)
      emit(:text_input, props.merge(value: value, placeholder: placeholder, on_enter: on_enter).compact)
    end

    def check_box(checked: false, on_change: nil, **props)
      emit(:check_box, props.merge(checked: checked, on_change: on_change).compact)
    end

    def view
      raise NotImplementedError, "#{self.class} 必须实现 #view"
    end

    # 渲染子组件（P0-1 的底层原语，写法 C）：
    #   render(WatchRow, code: code, key: code)   # 传类 + props（推荐）
    #   render(row_instance, key: code)           # 传实例（props 由实例自己持有）
    # 需要复用实例/state 时给 key：同一层（同一父节点下）key 相同的子组件会被保留。
    def render(component, **props, &block)
      raise ArgumentError, "render 暂不支持 block（子组件插槽留待 S3）" if block

      unless component.is_a?(Class)
        extra = props.keys - [:key]
        raise ArgumentError, "render(实例) 不能再传 props（#{extra.join(', ')}）：props 由实例自己持有" unless extra.empty?
      end

      Citrine.renderer.render_component(self, component, props)
    end

    # ── 内部 ────────────────────────────────────────────────

    def handle_event(handler, event = nil)
      case handler
      when Symbol
        # 无参方法保持原语义；带参方法（如 on_key: :on_key_press）拿到事件对象
        method(handler).arity.zero? ? send(handler) : send(handler, event)
      when Proc
        # 事件 Proc 是回调（区别于 REACTIVE_PROPS 的求值 Proc）：保持闭包 self。
        # 嵌套组件传入的父级回调，其方法接收者由定义处（父）的词法作用域决定，
        # instance_exec 重绑到 emit 的 owner（子）会让父组件回调里的方法调用全部断裂。
        handler.arity.zero? ? handler.call : handler.call(event)
      else
        raise ArgumentError, "无法处理的事件处理器: #{handler.inspect}"
      end
    end

    # 键盘分发（G-9）：Symbol/Proc 直接调用；Hash 形式按 ev.key 查表
    #
    #   on_key: { "Enter" => :commit, "Escape" => :cancel, else: :fallback }
    def handle_key(handler, event)
      case handler
      when Hash
        target = handler[event.key] || handler[:else]
        return if target.nil?

        handle_event(target, event)
      else
        handle_event(handler, event)
      end
    end

    # ── 生命周期钩子（由渲染器调用，G-10）───────────────────

    def run_mount_hooks
      self.class.mount_hooks.each { |hook| run_hook(hook) }
    end

    def run_unmount_hooks
      refs.clear
      self.class.unmount_hooks.each { |hook| run_hook(hook) }
    end

    private

    def computation(name)
      block = self.class.compute_defs.fetch(name) do
        raise ArgumentError, "未声明的 computed: #{name}"
      end
      unless computations.key?(name)
        out = Signal.new(nil)
        Effect.create { out.set(instance_eval(&block)) }
        computations[name] = out
      end
      computations[name].get
    end

    def emit(type, props, &block)
      # keyed 复用：命中旧节点就沿用（DOM / 子树 / Effect 全保留）
      if (existing = Citrine.renderer.reusable_node(props[:key], [:element, type], props))
        return Citrine.renderer.refresh_node(existing, props, block)
      end

      # 样式在 API 边界归一（决策 #10）；Proc 样式是响应式属性，求值后归一（Renderer#resolve_style）
      if props[:style] && !props[:style].is_a?(Proc)
        props = props.merge(style: Style.normalize(props[:style]))
      end
      node = Node.new(type, props, block, owner: self)
      Citrine.renderer.mount(node)
      node
    end

    # stack / row：方向由语法糖给定，再传 direction 属于自相矛盾，直接报错（fail fast）
    def emit_directional(direction, props, &block)
      if props.key?(:direction)
        raise ArgumentError, "stack / row 已隐含方向（#{direction}），不要再传 direction；" \
                             "需要自定义方向请用 box(direction: ...)"
      end

      emit(:box, props.merge(direction: direction), &block)
    end

    # 生命周期声明（G-10）：块 或 方法名（Symbol），与事件处理器同一套约定
    def run_hook(hook)
      case hook
      when Symbol then send(hook)
      when Proc then instance_exec(&hook)
      else raise ArgumentError, "无法执行的生命周期钩子: #{hook.inspect}"
      end
    end
  end
end
