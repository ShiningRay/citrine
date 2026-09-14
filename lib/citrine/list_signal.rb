# frozen_string_literal: true

require_relative "signal"

module Citrine
  # 响应式集合（D）：把"集合为整体替换语义"包成一套集合 API。
  #
  # 框架的触发路径只有一条——`Signal#set`。于是列表代码只能写成
  # `self.rows = rows + [row]`，或者更糟：维护一份普通数组、在改动末尾补一句
  # `@rows_signal.set(@rows.dup)`（两个真相源，漏一处就静默不更新）。
  # ListSignal 让"改集合"本身成为触发点：每次变更内部换一份**新数组**再通知，
  # 仍然只有一条触发路径，但调用方写的是自然写法：
  #
  #   rows = Citrine.signal_list([])
  #   rows << row              # 通知一次
  #   rows.delete_at(0)
  #   rows.replace(list)       # 整体替换（等价 rows.set(list)）
  #
  # **`get` 返回冻结的快照**：就地改它（`rows.get << x`）会当场 `FrozenError`，
  # 而不是像普通数组那样静默不触发。这是本类存在的主要理由——把最阴的坑变成显式错误。
  #
  # 语义边界：只追踪**集合自身**的变化；元素内部的改动不算变更
  # （`rows.get[0][:n] = 1` 不会触发），要更新请替换那个元素——
  # 或者用 S1-11 的元素代理：`rows[0][:n] = 1`（见 {[]}）。
  class ListSignal < Signal
    include Enumerable # each 已在下面接了订阅语义 → find/select/count/min/max/sum/sort_by… 都能用

    def initialize(value = [], &init)
      super(list_value(value), &init)
    end

    # 写入一律冻结副本：调用方的原数组不受影响，内部值也不会被就地改到。
    # 相等短路 + 元素信号刷新 + 集合级广播的顺序见 {set}。
    def set(list)
      new_list = list_value(list)
      return self if new_list == @value

      @init = nil
      @value = new_list
      refresh_element_signals # 元素级读者先拿到新元素（等值检查，未变的不通知）
      broadcast               # 再广播集合级
      self
    end

    # ── 读：都经 get，因此在 Effect / 块内读会建立依赖 ──────────────

    def get
      super.freeze
    end

    # 不订阅的读（"只想拿一份快照看"）：get 一旦落在 Effect 里就建立依赖，
    # peek 明确表达"这次读不参与响应"
    def peek
      @value
    end

    # 复制一份集合（而不是像 Object#dup 那样克隆信号对象）——
    # 从数组迁过来的人会习惯性地写 `list.dup`
    def dup = ListSignal.new(get)
    def clone = ListSignal.new(get)

    def to_a = get
    def size = get.size
    alias length size
    def empty? = get.empty?
    def first(*args) = args.empty? ? get.first : get.first(*args)
    def last(*args) = args.empty? ? get.last : get.last(*args)
    def fetch(*args, &block) = get.fetch(*args, &block)
    def each(&block) = get.each(&block)
    def map(&block) = get.map(&block)
    def include?(value) = get.include?(value)
    alias member? include?
    def index(value) = get.index(value)
    def join(sep = nil) = get.join(sep)
    def inspect = "#<Citrine::ListSignal #{get.inspect}>"

    # ── S1-11：集合深响应 ─────────────────────────────────────
    #
    # 位置读取返回**元素代理**：在 Effect / 块内 `list[i]` 即订阅该位置的元素，
    # 经代理就地改写（`list[i][:n] = 1`）只通知订阅这个位置的块——其他位置的
    # 读者与集合级读者都不重跑。代理的读取与行为全部转发给底层元素，
    # 与裸元素的 `==` 比较保持一致。
    #
    # 集合结构变更（push / delete_at / 整表 set…）会按位置刷新已存在的元素信号：
    # 位置上的元素内容变了才通知（插入/删除导致的位置平移因此对元素读者可见）。
    def [](index)
      element = element_signal(index).get
      ElementProxy.new(self, index, element)
    end

    # 元素代理就地改写后回调：强制广播该位置的元素信号
    # （值按引用共享、内容已变，相等检查会误判为没变，所以走 set!）
    def element_changed!(index)
      element_signal(index).set!(@value[index])
      self
    end

    # 元素信号按位置懒创建；值与底层元素按引用共享（代理改写的是活元素）
    def element_signal(index)
      (@element_signals ||= {})[index] ||= Signal.new(@value[index])
    end

    # ── 写：每次都是一份新数组 + 一次通知（值相等则不通知）──────────

    def <<(item)
      set(get + [item])
      self
    end

    def push(*items)
      set(get + items)
      self
    end
    alias append push

    def concat(items)
      set(get + items.to_a)
      self
    end

    def unshift(*items)
      set(items + get)
      self
    end
    alias prepend unshift

    # 追加 / 前插并保留最多 limit 个（超出的丢弃另一端的旧元素）：**一次通知**。
    # 直接写 `list << x` 再 `list.shift` 会通知两次 —— 每次通知都是一轮块重跑 / 渲染，
    # 所以"有上限的列表"需要这个防呆写法。
    def push_bounded(item, limit)
      set((get + [item]).last(limit))
      self
    end

    def unshift_bounded(item, limit)
      set(([item] + get).first(limit))
      self
    end

    def insert(index, *items)
      list = get.dup
      list.insert(index, *items)
      set(list)
      self
    end

    # 以下两个沿用 Array 的返回值（被移除的元素 / 元素数组 / nil）
    def pop(count = nil)
      list = get
      return nil if list.empty?

      if count.nil?
        set(list.take(list.size - 1))
        list.last
      else
        n = [count, list.size].min
        set(list.take(list.size - n))
        list.last(n)
      end
    end

    def shift(count = nil)
      list = get
      return nil if list.empty?

      if count.nil?
        set(list.drop(1))
        list.first
      else
        n = [count, list.size].min
        set(list.drop(n))
        list.take(n)
      end
    end

    def delete(item)
      list = get
      return nil unless list.include?(item)

      set(list.reject { |value| value == item })
      item
    end

    def delete_at(index)
      list = get
      at = index.negative? ? list.size + index : index
      return nil if at.negative? || at >= list.size

      set(list[0...at] + list.drop(at + 1))
      list[at]
    end

    def clear
      set([])
      self
    end

    def replace(items)
      set(items.to_a)
      self
    end

    def []=(index, value)
      list = get.dup
      result = list.[]=(index, value)
      set(list)
      result
    end

    # 就地改写类：统一返回信号本身以便链式写（与 Array 返回 self/nil 的约定略有出入；
    # 真正"没变化"时 set 不会通知）
    def sort!(&block) = transform_values { |list| list.sort(&block) }
    def reverse! = transform_values(&:reverse)
    def uniq! = transform_values(&:uniq)
    def map!(&block) = transform_values { |list| list.map(&block) }
    def compact! = transform_values(&:compact)
    def select!(&block) = transform_values { |list| list.select(&block) }
    def reject!(&block) = transform_values { |list| list.reject(&block) }

    private

    # 归一 + 类型守卫：Hash 会被 to_a 悄悄拆成键值对，这类错误必须在构造/写入期就报
    def list_value(value)
      case value
      when nil then [].freeze
      when Array then value.dup.freeze
      when Hash
        raise ArgumentError, "signal_list 需要数组，收到 Hash；要放 Hash 请用 Citrine.signal(...)"
      else
        raise ArgumentError, "signal_list 需要数组，收到 #{value.class}" unless value.respond_to?(:to_a)

        value.to_a.dup.freeze
      end
    end

    def transform_values
      set(yield(get))
      self
    end

    # 集合结构变更后，把已存在的元素信号按位置刷新到新数组的元素上
    # （等值检查：位置上的元素没变就不通知，push 不会误伤位置读者）。
    # 迭代快照：订阅者的重跑可能经 [] 新建元素信号，不能边遍历边改表。
    def refresh_element_signals
      return unless @element_signals

      @element_signals.values.dup.each do |signal|
        index = @element_signals.key(signal)
        signal.set(index < @value.size ? @value[index] : nil)
      end
    end

    # 元素代理（S1-11）：list[i] 的返回值。读取与行为全部转发给底层元素；
    # 就地改写（proxy[:n] = 1、proxy.sort! …）改的是活元素并强制通知订阅
    # 这个位置的块——其他位置的读者与集合级读者都不重跑。
    class ElementProxy
      NAME_SUFFIX_BANG = /\A\w+!\z/.freeze

      def initialize(list, index, element)
        @list = list
        @index = index
        @element = element
      end

      def []=(key, value)
        @element[key] = value
        @list.element_changed!(@index)
        value
      end

      def method_missing(name, *args, &block)
        unless @element.respond_to?(name)
          raise NoMethodError, "元素代理（#{safe_class}）没有 #{name} 方法"
        end

        result = @element.public_send(name, *args, &block)
        # 转发的就地改写方法（sort! / compact! …）同样触发该位置的通知；
        # != 这类操作符不匹配 NAME_SUFFIX_BANG，不会误报
        @list.element_changed!(@index) if NAME_SUFFIX_BANG.match?(name)
        result
      end

      def respond_to_missing?(name, include_private = false)
        @element.respond_to?(name, include_private) || super
      end

      # 与裸元素比较保持一致：keyed 复用、相等断言、Hash 键都靠它
      def ==(other)
        @element == other
      end
      alias eql? ==

      def hash
        @element.hash
      end

      def inspect
        "#<Citrine::ElementProxy(#{@index}) #{@element.inspect}>"
      end

      private

      def safe_class
        @element.class
      rescue StandardError
        Object
      end
    end
  end
end
