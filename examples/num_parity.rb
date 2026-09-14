# frozen_string_literal: true

# 数值工具的一致性样本（G-11）：同一份脚本在 CRuby 与 Opal 下运行，输出必须逐字节一致
# （见 Rakefile 的 `rake parity` 与 CI）。因此这里只打印确定性的内容——
# 不要引入时间、随机数、哈希顺序或平台特有的 inspect 格式。
require "citrine"

NUM = Citrine::Num

def show(label, value)
  text = case value
         when true  then "true"
         when false then "false"
         when Numeric then format("%.6f", value)
         else value.to_s
         end
  puts "#{label}\t#{text}"
end

# 整数除法（Ruby 的 floor 语义）
show "idiv(7,2)", NUM.idiv(7, 2)
show "idiv(-7,2)", NUM.idiv(-7, 2)
show "idiv(7,-2)", NUM.idiv(7, -2)
show "idiv(7.0,1.5)", NUM.idiv(7.0, 1.5)

# 取整：半值远离零（Opal 1.8.3 的 Float#round 在负数半值上会朝 +∞）
[-1.5, 1.5, -2.5, 2.5, -0.5, 0.5, -1.4, -2.8, 0.49999999999999994].each do |v|
  show "round_to(#{v},0)", NUM.round_to(v, 0)
end
[-1.25, -1.35, 1.25, 2.675, -2.675].each do |v|
  show "round_to(#{v},1or2)", NUM.round_to(v, v.to_s.split(".").last.length)
end
show "round_to(123456.78,-2)", NUM.round_to(123_456.78, -2)
show "round_to(-123456.78,-2)", NUM.round_to(-123_456.78, -2)

# 判定与格式化
show "round(-2.5)", NUM.round(-2.5)
show "integral?(2.0)", NUM.integral?(2.0)
show "integral?(2.5)", NUM.integral?(2.5)
show "finite?(1)", NUM.finite?(1)
show "finite?(1/0.0)", NUM.finite?(1 / 0.0)
show "finite?(0/0.0)", NUM.finite?(0 / 0.0)
show "finite?('12')", NUM.finite?("12")
show "percent(-0.1234,1)", NUM.percent(-0.1234, 1)
show "percent(0.1234,3)", NUM.percent(0.1234, 3)

# 返回类型（Integer / Float）也要跨平台一致：显示层靠它决定 "2" 还是 "2.0"
# 注意：只比对**非整数值**的 to_s——Opal 下整数值的浮点会丢 ".0"（2.0.to_s == "2"），
# 那是平台固有差异（见 README 跨平台语义陷阱第 8 条），不是本工具要负责的事。
show "round(2.0).to_s", NUM.round(2.0).to_s
show "round(-2.5).to_s", NUM.round(-2.5).to_s
show "round_to(1.25,1).to_s", NUM.round_to(1.25, 1).to_s
show "round_to(123456.78,-2).to_s", NUM.round_to(123_456.78, -2).to_s
show "format-decimal", format("%.2f", NUM.round_to(2.0, 1))
