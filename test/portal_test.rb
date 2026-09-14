# frozen_string_literal: true

# S1-5：Portal——子树挂到渲染器指定的宿主节点（逃出父容器 overflow / 层叠上下文）。
# 树上仍是逻辑父的孩子（复用、Effect、卸载级联与原地渲染一致）。
require "minitest/autorun"
require "citrine"
require "citrine/string_renderer"

class PortalEl
  attr_reader :children
  attr_accessor :parent, :class_name, :text

  def initialize(tag = "el")
    @tag = tag
    @children = []
  end
end

class PortalRenderer < Citrine::Renderer
  attr_accessor :default_host, :hosts

  def initialize
    super
    @default_host = PortalEl.new("body")
    @hosts = {}
  end

  private

  def setup_root(root, element)
    root.dom = element
  end

  def create_dom(_node)
    PortalEl.new
  end

  def attach(node, parent)
    node.dom.parent = parent.dom
    parent.dom.children << node.dom
  end

  def detach(node)
    return unless node.dom.parent

    node.dom.parent.children.delete(node.dom)
    node.dom.parent = nil
  end

  def apply_props(node)
    node.dom.class_name = prop_value(node, node.props[:css_class]) if node.props.key?(:css_class)
  end

  def set_text(node, text)
    node.text = text
  end

  def resolve_portal_host(target)
    raise "找不到宿主 #{target.inspect}" if target && !@hosts.key?(target)

    @hosts[target] || default_host
  end
end

class PortalDialog < Citrine::Component
  state :open, default: true

  class << self
    attr_accessor :unmounts
  end
  self.unmounts = 0
  on_unmount { self.class.unmounts += 1 }

  def view
    stack(css_class: "dialog") { label { open ? "弹层内容" : "弹层内容已关闭" } }
  end
end

class PortalParent < Citrine::Component
  components PortalDialog
  state :show, default: true

  def view
    stack(css_class: "page") do
      label { "页面主体" }
      portal(target: "overlay") { portal_dialog if show }
    end
  end
end

class PortalTest < Minitest::Test
  def setup
    PortalDialog.unmounts = 0
  end

  def new_renderer
    renderer = PortalRenderer.new
    renderer.hosts["overlay"] = PortalEl.new("overlay")
    renderer
  end

  def test_portal_children_live_under_host_not_logical_parent
    renderer = new_renderer
    root = renderer.mount_component(PortalParent.new, PortalEl.new("root"))
    host = renderer.hosts["overlay"]

    portal_node = root.children.first.children.last
    assert_equal :portal, portal_node.type
    assert_equal host, portal_node.children.first.dom.parent,
                 "portal 子树的 parentElement 应是宿主节点而非父容器"
    assert_empty root.children.first.children.reject { |n| n.type == :portal }.select { |n| n.dom.parent == host },
                 "宿主里不该出现逻辑父容器的其他内容"
  end

  def test_portal_content_renders_and_is_reactive
    renderer = new_renderer
    root = renderer.mount_component(PortalParent.new, PortalEl.new("root"))

    assert_includes texts(root), "弹层内容", "portal 内容照常渲染"

    dialog = portal_dialog(root)
    dialog.open = false

    assert_includes texts(root), "弹层内容已关闭", "portal 内的块 Effect 照常驱动原地更新"
  end

  def test_unmount_clears_host_and_cascades
    renderer = new_renderer
    widget = PortalParent.new
    root = renderer.mount_component(widget, PortalEl.new("root"))
    host = renderer.hosts["overlay"]
    assert_equal 1, host.children.size

    Citrine.unmount(widget)

    assert_empty host.children, "卸载后宿主节点内容清理干净"
    assert_empty root.children, "树上的 portal 分支一并清理"
    assert_equal 1, PortalDialog.unmounts, "portal 内的子组件走正常卸载"
  end

  def test_ssr_inlines_portal_content
    html = Citrine.render(PortalParent.new)

    assert_includes html, "弹层内容", "SSR 侧 portal 内容按逻辑位置内联输出"
  end

  private

  def texts(node, acc = [])
    acc << node.text if node.text
    node.children.each { |child| texts(child, acc) }
    acc
  end

  def portal_dialog(root)
    dialog_node = nil
    hunt = lambda do |node|
      dialog_node = node if node.rendered_component&.class&.equal?(PortalDialog)
      node.children.each(&hunt)
    end
    hunt.call(root)
    dialog_node.rendered_component
  end
end
