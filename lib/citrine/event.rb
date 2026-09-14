# frozen_string_literal: true

module Citrine
  # 指针/表单等事件（平台无关视图，S2-3）：DOM / Canvas 捕获原生事件后归一成它。
  # 与 KeyEvent 同理——组件代码不混入平台原生对象，CRuby 也能单测；
  # 需要原生细节时走 #raw（DOM 下是 Native 包装）。
  class Event
    attr_reader :type, :raw

    def initialize(type, raw: nil, prevent_default: nil, stop_propagation: nil)
      @type = type.to_s
      @raw = raw
      @prevent_default = prevent_default
      @stop_propagation = stop_propagation
    end

    # 阻止默认行为（DOM：preventDefault；无平台回调时静默忽略）
    def prevent_default
      @prevent_default&.call
      self
    end

    # 阻止事件继续传播：外层元素 / 祖先容器上的处理器不再收到这次事件
    def stop_propagation
      @stop_propagation&.call
      self
    end

    def inspect = "#<Citrine::Event #{@type}>"
  end
end
