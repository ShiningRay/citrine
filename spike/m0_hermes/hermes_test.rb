# backtick_javascript: true
# M0 Spike B：Opal corelib 在 Hermes 上的冒烟测试（无 DOM）
# 覆盖：类/继承/块/proc、数值与集合、字符串、Hash、异常、符号
# 注：Hermes 裸 VM 无 console（React Native 中由 RN 注入），用 print 输出

results = []

class Greeter
  def initialize(name) = @name = name

  def greet = "你好, #{@name}!"
end

results << Greeter.new("Hermes").greet
results << (1..10).select(&:even?).map { |i| i * i }.sum
results << "abcdef".upcase.reverse

h = { a: 1, b: 2 }
h[:c] = h.sum { |_k, v| v }
results << h.inspect

begin
  raise "异常机制正常"
rescue => e
  results << e.message
end

results << [3, 1, 2].sort.inspect
results << "块调用: " + [1, 2, 3].map { |x| x * 10 }.join(",")

# 信号机制顺带验证（纯 Ruby，无 DOM）
class MiniSignal
  def initialize(value) = (@value = value; @subs = [])

  def get = @value

  def set(value)
    @value = value
    @subs.each(&:call)
  end

  def subscribe(&blk) = @subs << blk
end

s = MiniSignal.new(0)
log = []
s.subscribe { log << "值变为 #{s.get}" }
3.times { s.set(s.get + 1) }
results << log.join("/")

output = results.join(" | ")
if `typeof print === 'function'`
  `print(#{output})`
else
  puts output
end
