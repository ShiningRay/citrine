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
    class << self
      def prop_defs
        @prop_defs ||= {}
      end

      def state_defs
        @state_defs ||= {}
      end

      def compute_defs
        @compute_defs ||= {}
      end

      # 只读输入，来自父组件；未声明的 prop 视为错误
      def prop(name, type: nil, default: nil)
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
    end

    attr_reader :props

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

    # ── 内部 ────────────────────────────────────────────────

    def handle_event(handler, event = nil)
      case handler
      when Symbol then send(handler)
      when Proc
        handler.arity.zero? ? instance_exec(&handler) : instance_exec(event, &handler)
      else
        raise ArgumentError, "无法处理的事件处理器: #{handler.inspect}"
      end
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
  end
end
