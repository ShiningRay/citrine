# frozen_string_literal: true

require_relative "signal"
require_relative "node"

module Citrine
  # 渲染器基类：节点树管理 + Effect 装配 + 块级重建/销毁（平台无关）。
  #
  # 平台子类实现钩子：setup_root / create_dom / attach / detach /
  # apply_props / set_text / setup_widget / finalize，并以 reactive?
  # 声明是否建立更新订阅（一次性渲染如 StringRenderer 返回 false）。
  class Renderer
    TAGS = { box: "div", label: "p", button: "button",
             text_input: "input", check_box: "input" }.freeze
    VOID = %i[text_input check_box].freeze

    def initialize
      @parents = []
    end

    def mount_component(component, element)
      # DSL（Component#emit）经全局 Citrine.renderer 分发到当前渲染器；
      # 响应式 Effect 重跑发生在 mount 之后，也依赖此设置，
      # 因此不恢复旧值——"活动渲染器 = 最近挂载的那个"。
      Citrine.renderer = self
      root = Node.new(:root, {}, nil, owner: component)
      setup_root(root, element)
      run_view(root, component)
      finalize(root)
      root
    end

    # DSL 挂载入口（Component#emit 调用）：把 node 挂到当前父节点下
    def mount(node)
      node.dom = create_dom(node)
      apply_props(node)
      @parents.last.children << node
      attach(node, @parents.last)
      setup_widget(node)
      if node.block
        if reactive?
          node.owned_effects << Effect.create do
            run_block(node) { node.owner.instance_exec(&node.block) }
          end
        else
          run_block(node) { node.owner.instance_exec(&node.block) }
        end
      end
      finalize(node)
      node
    end

    private

    def run_view(root, component)
      if reactive?
        root.owned_effects << Effect.create do
          run_block(root) { component.instance_exec { view } }
        end
      else
        run_block(root) { component.instance_exec { view } }
      end
    end

    # 重建 node 的子树：先销毁旧子节点（连同其 Effect 订阅），再执行 block
    def run_block(node)
      node.children.dup.each { |child| dispose(child) }
      node.children.clear
      @parents.push(node)
      result = yield
      set_text(node, result) if result.is_a?(String) && node.children.empty?
      result
    ensure
      @parents.pop
    end

    def dispose(node)
      node.owned_effects.each(&:dispose)
      node.owned_effects.clear
      node.children.dup.each { |child| dispose(child) }
      node.children.clear
      detach(node)
    end

    # box 支持布局快捷参数：direction（stack/flow 的抽象）、gap
    # 样式键在此后均为 snake_case（决策 #10，经 Style.normalize 归一）
    def resolve_style(node)
      style = (node.props[:style] || {}).dup
      if node.type == :box
        style[:display] ||= "flex"
        if (direction = node.props[:direction])
          style[:flex_direction] = direction == :column ? "column" : "row"
        end
        gap = node.props[:gap]
        style[:gap] = gap.is_a?(Numeric) ? "#{gap}px" : gap.to_s if gap
      end
      style
    end

    # ── 平台钩子 ───────────────────────────────────────────

    def reactive?
      true
    end

    def setup_root(_root, _element)
      raise NotImplementedError
    end

    def create_dom(_node)
      raise NotImplementedError
    end

    def attach(_node, _parent)
      raise NotImplementedError
    end

    def detach(_node)
      raise NotImplementedError
    end

    def apply_props(_node)
      raise NotImplementedError
    end

    def set_text(_node, _text)
      raise NotImplementedError
    end

    def setup_widget(_node)
      nil
    end

    def finalize(_node)
      nil
    end
  end
end
