# frozen_string_literal: true

module Citrine
  # 元素树节点：类型 + 属性 + 内容 block + 子节点。
  # 平台无关（M3 抽象渲染器接口的输入）；由渲染器解释挂载。
  class Node
    attr_reader :type, :props, :block, :owner, :children, :owned_effects
    attr_accessor :dom, :text

    def initialize(type, props = {}, block = nil, owner: nil)
      @type = type
      @props = props
      @block = block
      @owner = owner
      @children = []
      @owned_effects = []
    end
  end
end
