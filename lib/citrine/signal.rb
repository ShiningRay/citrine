# frozen_string_literal: true

module Citrine
  # 细粒度响应信号（决策 #3 核心）：
  # 读取时向当前 Effect 登记依赖；写入时同步通知订阅者重跑。
  # 唯一读写通道是 #get / #set——绕过它们（如直接改内部数组）不会触发更新，
  # v1 集合为整体替换语义。
  class Signal
    # 可以给块：块即**惰性初值**，第一次 get 时才求值（只求一次）。
    # 与 state 宏里 `init:` 的区别：这里块在**定义处**的词法作用域执行（普通 Proc 语义），
    # 组件的 `state ... do ... end` 则在组件实例上求值。
    def initialize(value = nil, &init)
      @value = value
      @init = init
      @subs = []
    end

    def get
      effect = Effect.current
      effect&.depend(self)
      run_init if @init
      @value
    end

    # 读值但**不订阅**：只想拿一份快照、不想让当前 Effect 依赖它时用（MobX 的 untracked）。
    # get 一旦落在块/Effect 里就会建立依赖——"订阅"与"取值"耦合在一起，
    # 想两者分开时就需要这个显式出口。
    def peek
      run_init if @init
      @value
    end

    def set(new_value)
      @init = nil # 显式写入过就不再是"未初始化"
      return self if new_value == @value

      @value = new_value
      @subs.dup.each(&:run)
      self
    end

    # 惰性初值是否还没求过（诊断用）
    def lazy? = !@init.nil?

    # 以下两个方法供 Effect 内部使用

    def subscribe(effect)
      @subs << effect unless @subs.include?(effect)
    end

    def unsubscribe(effect)
      @subs.delete(effect)
    end

    private

    def run_init
      init = @init
      @init = nil
      @value = init.call
    end
  end

  # Effect：block 内读取的信号自动成为依赖，任一依赖变化时重跑整个 block。
  # 每次重跑前先解除全部旧依赖、按新一次读取重建（MobX 式追踪），
  # 因此条件分支切换后，未再读取的信号不再触发本 Effect。
  class Effect
    class << self
      def stack
        @stack ||= []
      end

      def current
        stack.last
      end

      def create(&block)
        effect = new(block)
        effect.run
        effect
      end
    end

    def initialize(block)
      @block = block
      @deps = []
    end

    def run
      return self if @deps.nil? # 已 dispose 的 effect 保持惰性（广播快照中可能仍被迭代到）

      release_deps
      self.class.stack.push(self)
      begin
        @block.call
      ensure
        self.class.stack.pop
      end
      self
    end

    # 永久停用：从所有依赖中移除，block 不再执行（节点销毁时由渲染器调用）。
    # 幂等：同一 effect 可能被销毁两次（自身重跑中 dispose 兄弟节点后又被快照迭代）。
    def dispose
      return if @deps.nil?

      release_deps
      @block = nil
      @deps = nil
    end

    def depend(signal)
      @deps << signal
      signal.subscribe(self)
    end

    private

    def release_deps
      @deps.each { |s| s.unsubscribe(self) }
      @deps.clear
    end
  end
end
