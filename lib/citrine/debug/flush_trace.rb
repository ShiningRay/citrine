# frozen_string_literal: true

module Citrine
  module Debug
    # flush 计数器（M1-2 生产、M1-3 消费，共享契约）：进程内单调递增。
    # FlushTrace 在 flush 开始时 next! 分配 flush_id；
    # EventStream 在 handle_event 前后读 current，差集即该事件引发的 flush 链。
    class FlushCounter
      def initialize
        @n = 0
      end

      def next!
        @n += 1
      end

      def current
        @n
      end
    end

    def self.flush_counter
      @flush_counter ||= FlushCounter.new
    end

    class << self
      # flush 轨迹环形缓冲（默认 500 条）
      def flush_trace_ring
        @flush_trace_ring ||= Ring.new
      end

      attr_writer :flush_trace_ring
    end

    # ── batch 窗口内的待触发信号：P1 写入探针生产，flush 开场一次性取走归因 ──

    def self.track_flush_trigger(signal_id)
      (@flush_triggers ||= []) << signal_id
    end

    def self.take_flush_triggers!
      triggers = @flush_triggers || []
      @flush_triggers = []
      triggers.uniq
    end

    # ── flush 窗口内的逐 effect 计时采集栈：返回新采集数组供 FlushTrace 持有；
    #    栈式保存以支持重入——effect 重跑里再开 batch 会触发嵌套 flush，
    #    各自的计时归各自的采集（current 恒取栈顶，即当前这轮 flush）──

    def self.begin_flush_capture
      capture = []
      (@flush_capture_stack ||= []) << capture
      capture
    end

    def self.current_flush_capture
      @flush_capture_stack&.last
    end

    def self.end_flush_capture
      @flush_capture_stack.pop
    end

    # ── 入队计数：flush 是否"有活可干"的判据。空 batch（事件处理器没写任何
    #    信号）不留痕也不消耗 flush_id——事件流按计数器差集归因的契约因此
    #    不会被幽灵 flush_id 污染。内核保证 batch ensure 必 flush，
    #    计数与队列同生命周期：schedule 只发生在 batch 窗口内，flush 全取走。──

    def self.track_flush_schedule
      @flush_scheduled = (@flush_scheduled || 0) + 1
    end

    def self.flush_scheduled?
      (@flush_scheduled || 0) > 0
    end

    def self.reset_flush_schedules!
      @flush_scheduled = 0
    end

    # flush 轨迹（DESIGN-devtools P2）：Scheduler.flush 时记录
    # {flush_id:, t:, effects: [{effect_id:, runs:, duration_ms:}], trigger_signal_ids:}。
    # flush_id 经 Debug.flush_counter 分配，进程内单调递增——"哪个信号触发了
    # 哪次更新"的关联键：事件流（M1-3）经计数器差集、信号写入（M1-1）经
    # trigger_signal_ids 挂到同一轮 flush 上。
    module FlushTrace
      def schedule(effect)
        Debug.track_flush_schedule
        super
      end

      def flush
        scheduled = Debug.flush_scheduled?
        Debug.reset_flush_schedules!
        trigger_signal_ids = Debug.take_flush_triggers!
        return super unless scheduled && Citrine.debug_tracking?

        flush_id = Debug.flush_counter.next!
        t = flush_trace_timestamp
        effects = Debug.begin_flush_capture
        begin
          super
        ensure
          Debug.end_flush_capture
          begin
            Debug.flush_trace_ring.append(
              { flush_id: flush_id, t: t, effects: effects, trigger_signal_ids: trigger_signal_ids }
            )
          rescue StandardError => e
            warn "[citrine] flush 轨迹埋点失败（#{e.class}: #{e.message}），调度不受影响"
          end
        end
      end

      private

      def flush_trace_timestamp
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      rescue NameError, NoMethodError
        Time.now.to_f
      end
    end

    # flush 窗口内的逐 effect 计时：采集激活时给 run 包一层计时。成功的 run
    # 计数 +1——EffectInstanceTracking 在更外层 +1，这里自算同一口径，成功/
    # 抛错两条路径都与事后 Effect#debug_info[:runs] 一致（内核 C4 逐 effect
    # rescue 后统一重抛：抛错的 run 不计数，但时长照记，轨迹仍完整落缓冲）。
    module FlushEffectTiming
      def run
        capture = Debug.current_flush_capture
        return super unless capture

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        completed = false
        begin
          super.tap { completed = true }
        ensure
          begin
            duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
            runs = @runs || 0
            runs += 1 if completed
            capture << { effect_id: object_id, runs: runs, duration_ms: duration_ms }
          rescue StandardError
            # 计时埋点故障不影响 effect 生命周期
          end
        end
      end
    end
  end

  class Scheduler
    class << self
      prepend Debug::FlushTrace
    end
  end

  class Effect
    prepend Debug::FlushEffectTiming
  end

  class << self
    # flush 轨迹环形缓冲（默认 500 条）
    def debug_flush_trace
      Debug.flush_trace_ring
    end
  end
end
