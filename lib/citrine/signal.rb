# frozen_string_literal: true

module Citrine
  # 批量调度（S1-1）：同一同步窗口内的多次 Signal#set 合并为一轮 Effect 重跑——
  # 去重后每个受影响的 Effect 只重跑一次，中间态不入 DOM。
  # 窗口：事件处理器的分发过程自动包裹一次；应用代码也可用 Citrine.batch 显式开启。
  class Scheduler
    class << self
      # 开启合并窗口：块内所有 set 只入队不广播，块返回后 flush 一次跑完。
      # 可嵌套（内层不 flush）；块抛异常时同样 flush（与同步语义一样保留已写入的状态）。
      def batch
        @depth = (@depth || 0) + 1
        begin
          yield
        ensure
          @depth -= 1
          if @depth.zero?
            pending = $! # 用户块抛出的异常（若有）正在传播
            begin
              flush
            rescue StandardError
              raise if pending.nil? # 无用户异常时调度错误照常抛出
              # 用户原始异常优先：flush 的错误不替换它（warn 已由 flush 发出）
            end
          end
        end
      end

      def batching?
        !@depth.nil? && @depth > 0
      end

      # 去重入队：同一 Effect 被多个信号命中也只跑一次。
      # 以 effect 对象本身作 Hash 键（identity）：object_id 会被 GC 复用，
      # 复用期内同 id 的新 effect 会被误判为"已入队"而静默丢弃更新。
      def schedule(effect)
        return if @queued && @queued.key?(effect)

        (@queue ||= []) << effect
        (@queued ||= {})[effect] = true
      end

      # 排空队列。重跑期间产生的新写入（depth 已归零）走同步广播——
      # 与窗口外的既有语义一致，也避免循环依赖时无限排空。
      # 单个 effect 抛错不中断本轮其余项：逐项 rescue、记档第一个错误，
      # 队列排空后统一 warn 并重新抛出它——既避免同批更新半途丢弃，
      # 也不让调度错误从 ensure 路径穿出时替换用户块的原始异常
      # （batch 的 ensure 依 $! 判定：用户异常在传播时吞掉调度错误，只保留 warn）。
      def flush
        first_error = nil
        while @queue && !@queue.empty?
          current = @queue
          @queued = nil
          @queue = nil
          current.each do |effect|
            begin
              effect.run
            rescue StandardError => e
              first_error ||= e
              warn "[citrine] effect 重跑失败（#{e.class}: #{e.message}），已跳过；" \
                   "同批其余 effect 不受影响"
            end
          end
        end
        @queue = nil
        @queued = nil
        raise first_error if first_error
      end
    end
  end

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
      broadcast
      self
    end

    # 强制广播：跳过相等短路（S1-11）。用于"值按引用共享、内容被就地改写"的
    # 场景——对象还是同一个，相等检查会误判为没变。
    def set!(new_value)
      @init = nil
      @value = new_value
      broadcast
      self
    end

    def broadcast
      if Scheduler.batching?
        # 批量窗口（S1-1）：只入队不广播——去重后 flush 一次跑完
        @subs.dup.each { |effect| Scheduler.schedule(effect) }
      else
        @subs.dup.each(&:run)
      end
      self
    end

    private :broadcast # 只经 set / set! 触发，不允许外部绕过值更新手动广播

    # 惰性初值是否还没求过（诊断用）
    def lazy? = !@init.nil?

    # 静默换值：不广播、不触发任何订阅者。用于"每次重传都是新对象的回调类 prop"
    # （S1-2）：换引用不算变更，与 keyed 复用忽略 Proc 的口径一致。
    def replace(new_value)
      @init = nil
      @value = new_value
      self
    end

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

      # track_cleanup: 块返回 Proc 时把它当作 cleanup——每次重跑前与 dispose 时
      # 各执行一次（S1-8 的 effect 宏用；其余 Effect 不启用，避免把普通返回值误当清理）。
      def create(track_cleanup: false, &block)
        effect = new(block, track_cleanup)
        effect.run
        effect
      end
    end

    def initialize(block, track_cleanup = false)
      @block = block
      @track_cleanup = track_cleanup
      @deps = []
    end

    def run
      return self if @deps.nil? # 已 dispose 的 effect 保持惰性（广播快照中可能仍被迭代到）

      call_cleanup # 重跑前先清上一轮申请的资源（订阅还在，清理时读得到新鲜值）
      release_deps
      self.class.stack.push(self)
      begin
        result = @block.call
        @cleanup = result if @track_cleanup && result.is_a?(Proc)
      ensure
        self.class.stack.pop
      end
      self
    end

    # 永久停用：从所有依赖中移除，block 不再执行（节点销毁时由渲染器调用）。
    # 幂等：同一 effect 可能被销毁两次（自身重跑中 dispose 兄弟节点后又被快照迭代）。
    def dispose
      return if @deps.nil?

      call_cleanup # 卸载路径的清理：跑完才释放订阅（与 computed 释放顺序同口径）
      release_deps
      @block = nil
      @deps = nil
    end

    def depend(signal)
      return if @deps.nil? # 块运行中自 dispose：依赖表已清空，不再登记（原 nil.any? 崩溃点）
      return if @deps.any? { |d| d.equal?(signal) } # 同一信号读多次只记一条依赖边

      @deps << signal
      signal.subscribe(self)
    end

    private

    def release_deps
      @deps.each { |s| s.unsubscribe(self) }
      @deps.clear
    end

    def call_cleanup
      cleanup = @cleanup
      @cleanup = nil
      cleanup&.call
    end
  end
end
