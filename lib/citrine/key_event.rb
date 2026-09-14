# frozen_string_literal: true

module Citrine
  # 键盘事件（平台无关视图）：DOM / Canvas 捕获原生事件后归一成它。
  #
  # 为什么要包装：键盘优先的应用（电子表格、编辑器）要判断"按了哪个键 + 有无修饰键 +
  # 是否阻止默认行为"，直接读 JS 事件会把平台细节漏进组件代码，也没法在 CRuby 里单测。
  # 需要原生事件时用 #raw（DOM 下是 Native 包装）。
  class KeyEvent
    attr_reader :key, :raw

    def initialize(key, shift: false, meta: false, ctrl: false, alt: false,
                   raw: nil, prevent_default: nil)
      @key = key.to_s
      @shift = shift
      @meta = meta
      @ctrl = ctrl
      @alt = alt
      @raw = raw
      @prevent_default = prevent_default
    end

    def shift? = @shift
    def meta?  = @meta
    def ctrl?  = @ctrl
    def alt?   = @alt
    # ⌘ / Ctrl 等价判断：应用里"保存/撤销"这类快捷键两边都要认
    def command? = @meta || @ctrl

    # 阻止默认行为（DOM：preventDefault；无平台回调时静默忽略）
    def prevent_default
      @prevent_default&.call
      self
    end

    def to_s = @key
    def inspect = "#<Citrine::KeyEvent #{@key}#{@meta ? ' meta' : ''}#{@ctrl ? ' ctrl' : ''}#{@shift ? ' shift' : ''}>"
  end
end
