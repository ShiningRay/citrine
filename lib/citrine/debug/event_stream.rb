# frozen_string_literal: true

module Citrine
  module Debug
    class << self
      # 事件流环形缓冲（默认 500 条）
      def event_stream_ring
        @event_stream_ring ||= Ring.new
      end

      attr_writer :event_stream_ring
    end

    # 事件流（DESIGN-devtools P3）：Component#handle_event 前后对比 flush_id
    # 计数，记录 {t:, event_type:, target_component:, handler_name:, flush_ids:}——
    # 即该事件引发的整条 flush 链。DOM 侧 ensure_event 埋点在 dom.rb（Opal），
    # 本模块只覆盖核心可测的 handle_event 路径。
    #
    # flush_id 分配是 FlushTrace（M1-2）的职责，本模块只消费
    # Debug.flush_counter.current 的前后差集；计数器未接入时 flush_ids 恒为空
    # 数组，事件本身照常记录。
    module EventStream
      def handle_event(handler, event = nil)
        return super unless Citrine.debug_tracking?

        first_flush = Debug.flush_counter.current
        begin
          super
        ensure
          begin
            last_flush = Debug.flush_counter.current
            Debug.event_stream_ring.append(
              t: event_stream_timestamp,
              event_type: event_stream_type_of(event),
              target_component: self.class.name,
              component_id: object_id,
              handler_name: event_stream_handler_name(handler),
              flush_ids: ((first_flush + 1)..last_flush).to_a
            )
          rescue StandardError => e
            warn "[citrine] 事件流埋点失败（#{e.class}: #{e.message}），事件分发不受影响"
          end
        end
      end

      private

      def event_stream_timestamp
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      rescue NameError, NoMethodError
        Time.now.to_f
      end

      # 事件类型尽力推导：平台无关视图有明确 type；nil 是 Canvas 等无参触发；
      # 其余（check_box 的布尔写回、Opal 下透传的原生事件）退化为类名。
      def event_stream_type_of(event)
        case event
        when nil then :none
        when Citrine::Event then event.type
        when Citrine::KeyEvent then "key"
        else event.class.name || :unknown
        end
      end

      # handler_name：Symbol 原样记录；Proc 记 source_location（文件:行），
      # 拿不到（Opal 部分环境）记 (proc)。
      def event_stream_handler_name(handler)
        case handler
        when Symbol then handler
        when Proc
          location = begin
            handler.source_location
          rescue StandardError
            nil
          end
          location ? "#{File.basename(location[0])}:#{location[1]}" : "(proc)"
        else
          handler.class.name || handler.inspect
        end
      end
    end
  end

  class Component
    prepend Debug::EventStream
  end

  class << self
    # 事件流环形缓冲（默认 500 条）
    def debug_event_stream
      Debug.event_stream_ring
    end
  end
end
