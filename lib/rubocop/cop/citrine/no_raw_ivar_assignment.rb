# frozen_string_literal: true

require "rubocop"

module RuboCop
  module Cop
    module Citrine
      # Citrine 组件里的裸 @ivar 赋值绕过信号追踪——写入不会触发任何更新，
      # 是"改了但界面不动"这类事故的根源（GOALS.md 第七节代价清单第 1 条）。
      #
      # 状态请用 `state` 宏（赋值即更新），跨渲染的派生值用 `computed`，
      # 单次渲染内的中间值用局部变量。
      #
      #   class Counter < Citrine::Component
      #     state :count, default: 0      # ✓
      #     @cache = {}                   # ✗ 裸 ivar 赋值
      #   end
      #
      # 只拦"写入"：裸读（@foo）在框架语义里无法区分，交由 code review。
      class NoRawIvarAssignment < RuboCop::Cop::Base
        MSG = "Citrine 组件内不要直接赋值 @ivar（绕过信号追踪）：状态用 state 宏，中间值用局部变量"

        # 类体上的 @ivar 赋值（如宏实现的内部状态）不属于组件实例，不拦；
        # 框架源码（lib/citrine/**）整体豁免，见 .rubocop.yml
        def on_ivasgn(node)
          return unless inside_component_scope?(node)

          add_offense(node.loc.name)
        end

        private

        # 词法上落在 Citrine::Component 子类（具名类或 Class.new(Citrine::Component)）
        # 的**方法体**里的赋值。类体上的直接赋值是"组件类"状态（宏实现的内部
        # 状态就是这种写法），不属于组件实例，不拦。
        def inside_component_scope?(node)
          node.each_ancestor(:class, :block).any? do |scope|
            case scope.type
            when :class
              component_superclass?(scope.children[1]) && defined_in_method?(node, scope)
            when :block
              # (block (send Class :new <Component>) ...) → children[0] 是调用节点
              class_new_component?(scope.children[0]) && defined_in_method?(node, scope)
            else false
            end
          end
        end

        def defined_in_method?(node, class_scope)
          method_scope = node.each_ancestor(:def, :defs).first
          return false unless method_scope

          # def 最近的词法作用域必须就是该组件作用域
          #（匿名类没有 :class 节点，最近作用域是 Class.new 的 :block）
          nearest = method_scope.each_ancestor(:class, :sclass, :module, :block).first
          nearest&.equal?(class_scope)
        end

        def component_superclass?(superclass_node)
          return false unless superclass_node&.const_type?

          %w[Citrine::Component Component].include?(superclass_node.const_name)
        end

        def class_new_component?(send_node)
          return false unless send_node&.method?(:new) && send_node.receiver&.const_type?
          return false unless send_node.receiver.const_name == "Class"

          base = send_node.arguments.first
          base&.const_type? && %w[Citrine::Component Component].include?(base.const_name)
        end
      end
    end
  end
end
