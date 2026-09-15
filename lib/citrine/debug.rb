# frozen_string_literal: true

# DevTools 构建（T-B3）：显式 `require "citrine/debug"` 才会加载本文件——
# 生产构建不 require 它，产物中不含任何埋点字符串与依赖图导出代码。
#
# 能力：
#   1. 依赖图数据层：Citrine.debug_dependency_graph 导出 signal→effect 边
#      与重跑计数快照（可 to_json，供 Cytoscape 依赖图 UI 与信号泳道时序消费）。
#   2. 诊断接口：Effect#disposed? / debug_info、Signal#debug_info。
#
# 实现方式：以 prepend 模块包住 Signal/Effect 的 initialize/run——
# 内核方法保持原样，不因埋点改变行为。
#
# 时序探针（M1，DESIGN-devtools P1–P4）拆在 debug/ 子目录：
# 每个探针一个文件，全部显式 require 才加载，生产构建不含。
require_relative "debug/ring"
require_relative "debug/write_log"
require_relative "debug/flush_trace"
require_relative "debug/event_stream"
require_relative "debug/tree"

module Citrine
  # DevTools 埋点（仅 citrine/debug 加载时生效）
  module Debug
    module SignalClassTracking
      attr_accessor :debug_tracking

      def all
        @all ||= []
      end

      def track(signal)
        all << signal if debug_tracking
      end
    end

    module EffectClassTracking
      attr_accessor :debug_tracking

      def all
        @all ||= []
      end

      def track(effect)
        all << effect if debug_tracking
      end
    end

    module SignalInstanceTracking
      def initialize(*args, &block)
        super
        Signal.track(self)
      end

      def debug_info
        { id: object_id, subscribers: @subs.size }
      end
    end

    module EffectInstanceTracking
      def initialize(*args, &block)
        super
        Effect.track(self)
      end

      def run(*args, &block)
        super.tap { @runs = (@runs || 0) + 1 }
      end

      def disposed?
        @deps.nil?
      end

      def debug_info
        { id: object_id, deps: (@deps || []).map(&:object_id), runs: @runs, disposed: disposed? }
      end
    end

    class << Signal
      prepend SignalClassTracking
    end

    class << Effect
      prepend EffectClassTracking
    end
  end

  class Signal
    prepend Debug::SignalInstanceTracking
  end

  class Effect
    prepend Debug::EffectInstanceTracking
  end

  class << self
    def debug_tracking?
      @debug_tracking == true
    end

    def debug_tracking=(value)
      @debug_tracking = value == true
      Signal.debug_tracking = self.debug_tracking?
      Effect.debug_tracking = self.debug_tracking?
      self
    end

    # DevTools 依赖图数据：开启埋点 → 返回当前 signal→effect 边与
    # 各 Effect 的重跑计数快照（可 to_json）。UI 晚一步、数据先行。
    def debug_dependency_graph
      self.debug_tracking = true
      {
        signals: Signal.all.map(&:debug_info),
        effects: Effect.all.reject(&:disposed?).map(&:debug_info)
      }
    end
  end
end
