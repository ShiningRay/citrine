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
  # 语义边界（与 v1 一致）：只追踪**集合自身**的变化；元素内部的改动不算变更
  # （`rows.get[0][:n] = 1` 不会触发），要更新请替换那个元素。
  class ListSignal < Signal
    include Enumerable # each 已在下面接了订阅语义 → find/select/count/min/max/sum/sort_by… 都能用

    def initialize(value = [], &init)
      super(list_value(value), &init)
    end

    # 写入一律冻结副本：调用方的原数组不受影响，内部值也不会被就地改到
    def set(list)
      super(list_value(list))
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
    def [](*args) = get[*args]
    def fetch(*args, &block) = get.fetch(*args, &block)
    def each(&block) = get.each(&block)
    def map(&block) = get.map(&block)
    def include?(value) = get.include?(value)
    alias member? include?
    def index(value) = get.index(value)
    def join(sep = nil) = get.join(sep)
    def inspect = "#<Citrine::ListSignal #{get.inspect}>"

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
  end
end
