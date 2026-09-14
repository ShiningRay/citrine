# frozen_string_literal: true

module Citrine
  # 跨平台数值工具（G-11）。
  #
  # Opal 的数值模型是 JS number：整数与浮点同为 Number，`7 / 2` 是 3.5 而非 3；
  # `Float#round` 在负数半值上也曾与 MRI 不一致（见 opal/opal#2808）。
  # 这些都是 Opal 明文记录的设计选择，不会改——但**每个真实应用都要重写一遍同样的工具**，
  # 两个 dogfooding demo 各写了一份 `Num`，所以框架提供一次。
  #
  # 用法约定：需要整数商、需要与 MRI 一致的取整、需要跨平台一致的判定时走这里，
  # 不要自己写 `(a / b).to_i`（负数会错）或直接 `.round`（负数半值会错）。
  module Num
    module_function

    # 整数除法，语义同 Ruby 的 Integer#/（向 -∞ 取整）：
    #   Num.idiv(7, 2)   # => 3
    #   Num.idiv(-7, 2)  # => -4（注意不是 -3：Ruby 是 floor 语义）
    def idiv(value, divisor)
      value.div(divisor)
    end

    # 取整到 digits 位小数，**半值远离零**（与 MRI 的 Float#round 一致）：
    #   Num.round_to(-1.5, 0)   # => -2（Opal 1.8.3 的 -1.5.round 得 -1）
    #   Num.round_to(-1.25, 1)  # => -1.3
    # 先取绝对值再贴符号，绕开平台上"半值朝 +∞"的实现。
    # 返回类型与 MRI 对齐：digits <= 0 → Integer，digits > 0 → Float。
    #
    # 注意：这里不写 `10 ** -digits` 统一处理——Opal 的 Integer#** 在指数为 0 时
    # 会返回 Rational（`10 ** 0` → 1/1，上游 opal/corelib/number.rb:281 的条件
    # `other > 0` 把 0 也归进了负指数分支），直接用它会让结果变成 -3/1 这种形态。
    def round_to(value, digits)
      digits = digits.to_i
      sign = value.negative? ? -1 : 1
      abs = value.abs

      if digits.zero?
        return value.to_i if integral?(value)

        # 取绝对值后交给平台的 round：正数上两个平台的半值方向一致，
        # 且 CRuby 的 Float#round 处理 0.49999999999999994 这类边界比 "+0.5 再 floor" 正确
        abs.round * sign
      elsif digits.positive?
        factor = 10.0**digits
        (abs * factor).round / factor * sign
      else
        # 负精度：按 10 的幂取整，用整数乘法避免浮点误差（1235 * 100 而不是 1235 / 0.01）
        factor = 10**-digits
        (abs / factor.to_f).round * factor * sign
      end
    end

    # 取整到整数（半值远离零）：Num.round(-2.5) # => -3
    def round(value)
      round_to(value, 0)
    end

    # 整数值判定（显示层常用：2.0 显示成 "2" 而不是 "2.00"）
    def integral?(value)
      value.to_f == value.to_f.round
    end

    # 有限数判定（NaN / ±Infinity → false）；非 Numeric 一律 false
    def finite?(value)
      return false unless value.is_a?(Numeric)

      value.to_f.finite?
    end

    # 百分比格式化（显示层常用）：Num.percent(0.1234, 1) # => "12.3%"
    def percent(ratio, digits = 1)
      "#{round_to(ratio.to_f * 100, digits)}%"
    end
  end
end
