# frozen_string_literal: true

module Citrine
  module Debug
    class << self
      # 写入日志环形缓冲（默认 500 条）
      def write_log_ring
        @write_log_ring ||= Ring.new
      end

      attr_writer :write_log_ring
    end

    # 信号写入日志（DESIGN-devtools P1）：Signal#set / #set! / #replace 时记录
    # {t:, signal_id:, name:, old:, new:, source:}；source 为 Effect.current 的
    # object_id，Effect 上下文之外记 :external。仅在 debug_tracking 开启时记录。
    #
    # 埋点口径：set / set! 先把旧值存进探针 ivar，统一收口到私有 #broadcast
    # 落记录（相等短路时内核不调 broadcast，天然不记脏数据）；replace 是静默
    # 换值、不经过 broadcast，单独记录。batch 窗口内的写入同时记入待触发信号表，
    # 供 FlushTrace 归因为本轮 flush 的 trigger_signal_ids（M1-2）。
    module SignalWriteLog
      VALUE_LIMIT = 200

      def set(new_value)
        @debug_write_old = @value
        super
      end

      def set!(new_value)
        @debug_write_old = @value
        super
      end

      def replace(new_value)
        return super unless Citrine.debug_tracking?

        old = @value
        super.tap { append_write_log(old, @value) }
      end

      private

      # 记录先于 super（效果执行）落缓冲：写入时序即"哪个信号先被改"的原始顺序。
      # 埋点自身故障（宿主对象 to_s 抛错之类）只告警，信号写入与广播不受影响。
      def broadcast
        append_write_log(@debug_write_old, @value) if Citrine.debug_tracking?
        super
      end

      def append_write_log(old, new)
        Debug.write_log_ring.append(
          t: write_log_timestamp,
          signal_id: object_id,
          name: nil, # 信号本体不携带名字；面板侧经 signal_id 与依赖图连接
          old: write_log_value(old),
          new: write_log_value(new),
          source: Effect.current&.object_id || :external
        )
        Debug.track_flush_trigger(object_id) if Scheduler.batching?
      rescue StandardError => e
        warn "[citrine] 写入日志埋点失败（#{e.class}: #{e.message}），信号写入不受影响"
      end

      def write_log_timestamp
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      rescue NameError, NoMethodError
        Time.now.to_f
      end

      # old/new 序列化：标量原样保留（JSON 直出）；字符串与其余对象截断到
      # 200 字符——大对象进固定缓冲会撑爆内存（DESIGN-devtools P1），且截断
      # 即快照，应用侧之后再改原对象不影响已记录值。String#[](range) 恒返新串。
      def write_log_value(value)
        case value
        when String then value[0, VALUE_LIMIT]
        when Symbol, Numeric, true, false, nil then value
        else
          text = value.to_s
          text.length > VALUE_LIMIT ? text[0, VALUE_LIMIT] : text
        end
      rescue StandardError
        "(#{value.class} 无法序列化)"
      end
    end
  end

  class Signal
    prepend Debug::SignalWriteLog
  end

  class << self
    # 写入日志环形缓冲（默认 500 条）
    def debug_write_log
      Debug.write_log_ring
    end
  end
end
