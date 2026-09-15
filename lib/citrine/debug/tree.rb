# frozen_string_literal: true

module Citrine
  module Debug
    # 组件树快照遍历（DESIGN-devtools P4）：只读消费 node.rb 的自省字段与
    # Component 的公开诊断方法，不新建任何 Signal/Effect——SSR 与埋点关闭
    # 环境下照样输出结构信息（声明过的 state/computed 全部列出，未求值的项为 nil）。
    module ComponentTree
      module_function

      # root_node 通常是渲染器的 :root 节点（owner = 顶层组件）；
      # 传组件边界节点（rendered_component）则快照该组件子树。nil 进 nil 出。
      def snapshot(root_node)
        return nil if root_node.nil?
        unless root_node.is_a?(Citrine::Node)
          raise ArgumentError,
                "debug_component_tree 需要渲染器根节点（Node），实际收到 #{root_node.class}"
        end

        component = root_node.rendered_component || root_node.owner
        unless component.is_a?(Citrine::Component)
          raise ArgumentError,
                "debug_component_tree 需要渲染器根节点（Node），实际收到 #{root_node.class}"
        end

        build(component, root_node)
      end

      # 快照条目：一个组件一条，children 为按渲染位置嵌套的组件条目。
      # node_id 取组件边界节点（顶层组件取 :root 节点）的 object_id——
      # 协议 highlight_node 指令的 DOM 锚点。
      def build(component, node)
        {
          node_id: node.object_id,
          component: component.class.name || component.class.to_s,
          props: sanitize(node.component_props || component.props),
          state: declared_values(component.class.state_defs.keys, component.signals),
          computed: declared_values(component.class.compute_defs.keys, component.computations),
          watch_effect_count: component.watch_effect_count,
          effect_count: component.effect_count,
          computation_effect_count: component.computation_effect_count,
          reuse_key: node.reuse_key,
          children: node.children.flat_map { |child| entries(child) }
        }
      end

      # 位置序遍历：组件边界节点（rendered_component）收成一条快照并负责
      # 自己子树内的嵌套；普通元素透传下钻。插槽块（owner 是父组件）按
      # 渲染位置归属宿主组件的子树。
      def entries(node)
        child = node.rendered_component
        return [build(child, node)] if child

        node.children.flat_map { |grandchild| entries(grandchild) }
      end

      # 声明过的名字全部列出，读现成信号表（不取值创建）：未初始化 → nil。
      def declared_values(names, table)
        names.to_h { |name| [name, table[name]&.peek] }
      end

      # 快照要可 JSON 序列化（SSE 下行载荷）：Signal 解包当前值（peek 不订阅），
      # Proc（事件回调）记占位串，Hash/Array 递归，其余对象退化为 to_s。
      def sanitize(value)
        case value
        when Signal then sanitize(value.peek)
        when Proc then "(proc)"
        when Hash then value.transform_values { |v| sanitize(v) }
        when Array then value.map { |v| sanitize(v) }
        when String, Symbol, Numeric, true, false, nil then value
        else value.to_s
        end
      end
    end
  end

  class << self
    # 组件树快照（DESIGN-devtools P4）：从渲染器根节点遍历 VDOM，输出
    # {node_id:, component:, props:, state:, computed:, 三个 effect 计数, reuse_key:}
    # 树（children 为嵌套组件）。纯数据、可 to_json；不依赖 debug_tracking 开关。
    def debug_component_tree(root_node)
      Debug::ComponentTree.snapshot(root_node)
    end
  end
end
