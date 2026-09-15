# frozen_string_literal: true

module Citrine
  module Debug
    # 固定容量环形缓冲：探针时序数据的统一存放处。
    # 容量溢出时丢弃最旧记录，避免长会话内存膨胀（DESIGN-devtools D2）。
    # 非线程安全——与内核 Scheduler 同口径，假设单线程事件循环。
    class Ring
      include Enumerable

      attr_reader :capacity

      def initialize(capacity = 500)
        @capacity = capacity
        @items = []
      end

      def capacity=(value)
        @capacity = value
        trim!
      end

      def append(item)
        @items << item
        trim!
        item
      end

      def to_a
        @items.dup
      end

      def each(&block)
        @items.each(&block)
      end

      def size
        @items.size
      end

      def clear
        @items.clear
        self
      end

      private

      def trim!
        overflow = @items.size - @capacity
        @items.shift(overflow) if overflow.positive?
      end
    end
  end
end
