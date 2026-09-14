# frozen_string_literal: true

require_relative "signal"

module Citrine
  # 给**普通 Ruby 类**（领域模型、服务对象、测试替身）用的信号小混入：
  #
  #   class Engine
  #     include Citrine::Reactive
  #
  #     def initialize
  #       @tick_signal = signal(0)
  #       @quote_signals = {}
  #     end
  #
  #     def quote_signal(code)
  #       @quote_signals[code] ||= signal { quote(code) }   # 块 = 惰性初值
  #     end
  #   end
  #
  # 为什么要有它：
  #   - 普通类拿不到组件的 `state` 宏，只能 `Citrine::Signal.new(...)`，冗长；
  #   - 更要紧的是**裸写 `Signal` 会撞上 stdlib / Opal corelib 的 `::Signal`（进程信号）**，
  #     拿到的是那个类，报错完全不指向真因（FRICTION F14 为此排查过十几分钟）。
  #     `signal(...)` / `Citrine.signal(...)` 让用户永远不必写出那个裸名字。
  #
  # 组件里不要 include 它：组件已有同名的 `signal(name)`（按名字取已声明 state 的
  # 底层信号），组件内要"按 key 取用的信号表"请用 `Component#keyed_signal`。
  module Reactive
    # 造一个新信号；给块则为惰性初值（第一次读取时求值一次）
    def signal(value = nil, &init)
      Signal.new(value, &init)
    end

    # 造一个响应式集合（ListSignal）：集合自身的每次变更都是一次通知
    def signal_list(items = [])
      ListSignal.new(items)
    end
  end
end
