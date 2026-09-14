# frozen_string_literal: true

module Citrine
  # 细粒度响应信号（决策 #3 核心）：
  # 读取时向当前 Effect 登记依赖；写入时同步通知订阅者重跑。
  # 唯一读写通道是 #get / #set——绕过它们（如直接改内部数组）不会触发更新，
  # v1 集合为整体替换语义。
  class Signal
    def initialize(value = nil)
      @value = value
      @subs = []
    end

    def get
      effect = Effect.current
      effect&.depend(self)
      @value
    end

    def set(new_value)
      return self if new_value == @value

      @value = new_value
      @subs.dup.each(&:run)
      self
    end

    # 以下两个方法供 Effect 内部使用

    def subscribe(effect)
      @subs << effect unless @subs.include?(effect)
    end

    def unsubscribe(effect)
      @subs.delete(effect)
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
