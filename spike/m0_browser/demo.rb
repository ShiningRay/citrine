# backtick_javascript: true
# M0 Spike A：Opal 编译 → 浏览器执行
# 验收点：Ruby 操作 DOM + 信号原型驱动界面更新（三宏机制的可行性验证）
require "native"

# ── 最小 Signal / Effect 原型（决策 #3 的核心机制）───────────────
class Signal
  def initialize(value)
    @value = value
    @subs = []
  end

  def get
    Effect.current&.depend(self)
    @value
  end

  def set(new_value)
    return if new_value == @value

    @value = new_value
    @subs.each(&:run)
  end

  def subscribe(effect)
    @subs << effect unless @subs.include?(effect)
  end
end

class Effect
  STACK = []

  def self.current = STACK.last

  def self.create(&block)
    effect = new(block)
    effect.run
    effect
  end

  def initialize(block)
    @block = block
    @deps = []
  end

  def run
    @deps.clear
    STACK.push(self)
    @block.call
  ensure
    STACK.pop
  end

  def depend(signal)
    return if @deps.include?(signal)

    @deps << signal
    signal.subscribe(self)
  end
end

# ── DOM 互操作（纯 Native interop，零额外依赖）─────────────────
document = Native(`window.document`)
body = document.body

title = document.createElement("h1")
title[:textContent] = "RubyReact M0 — Opal 在浏览器中运行"
body.appendChild(title)

status = document.createElement("p")
status[:textContent] = "信号原型：点击按钮，只有计数文本所在的 block 会重跑"
body.appendChild(status)

count_label = document.createElement("p")
count_label[:style][:fontSize] = "28px"
count_label[:style][:fontWeight] = "bold"
body.appendChild(count_label)

button = document.createElement("button")
button[:style][:fontSize] = "18px"
body.appendChild(button)

count = Signal.new(0)
clicks = Signal.new(0)

# Effect：block 内读取的信号自动成为依赖；信号变化只重跑这个 block
Effect.create do
  count_label[:textContent] = "count = #{count.get}"
end

Effect.create do
  button[:textContent] = "点我 +1（已点 #{clicks.get} 次）"
end

button.addEventListener("click", ->(_event) {
  count.set(count.get + 1)
  clicks.set(clicks.get + 1)
})
