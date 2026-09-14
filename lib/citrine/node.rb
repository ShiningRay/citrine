# frozen_string_literal: true

module Citrine
  # 元素树节点：类型 + 属性 + 内容 block + 子节点。
  # 平台无关（M3 抽象渲染器接口的输入）；由渲染器解释挂载。
  class Node
    attr_reader :type, :owner, :children, :owned_effects
    attr_accessor :props, :block
    attr_accessor :dom, :text
    # 上一次应用过的内联样式键：响应式 style 变化时用来清掉已消失的键
    attr_accessor :applied_style_keys
    # 上一次应用过的透传属性键（S2-2）：值翻 false/nil 时用来清掉旧属性
    attr_accessor :applied_attrs
    # keyed 复用的身份：显式 key + 身份标签（元素类型）+ 组件根身份（若它是某子组件的根）
    attr_accessor :reuse_key, :identity, :component_identity, :component_props
    # 组件边界节点：由 `render(Child)` 产生，承载子组件 view 的输出。
    # 它自己不对应任何 DOM/画布元素（虚拟节点），只提供"一块可整体复用、整体销毁的区域"。
    attr_accessor :rendered_component
    # 该节点的两个 Effect（响应式属性 / 内容 block）：复用时用来就地重跑
    attr_accessor :props_effect, :block_effect
    # 已按需绑定的事件监听标签（DOM 渲染器用）：事件发生时从 props 现取处理器，
    # 因此复用时只补挂新出现的处理器，不做"解绑再重绑"
    attr_accessor :bound_listeners

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
