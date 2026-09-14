# frozen_string_literal: true

# S1-10：异步渲染（渲染期等待）——suspense 在依赖未就绪时渲染占位，
# 就绪后原地切换到真实内容；组件实例与 state 全程保留；不含数据请求实现。
require "minitest/autorun"
require "citrine"
require "citrine/string_renderer"

class SuspenseEl
  attr_reader :children
  attr_accessor :parent, :class_name, :text

  def initialize
    @children = []
  end
end

class SuspenseRenderer < Citrine::Renderer
  private

  def setup_root(root, element)
    root.dom = element
  end

  def create_dom(_node)
    SuspenseEl.new
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
end

class AsyncProfile < Citrine::Component
  state :user, default: nil
  state :clicks, default: 0

  class << self
    attr_accessor :mounts
  end
  self.mounts = 0
  on_mount { self.class.mounts += 1 }

  def view
    box do
      button(on_click: :bump) { "点击 #{clicks}" }
      suspense(ready: -> { !user.nil? },
               loading: -> { label(css_class: "loading") { "加载中…" } }) do
        label(css_class: "ready") { "用户：#{user[:name]} · 点击 #{clicks}" }
      end
    end
  end

  def bump
    self.clicks += 1
  end
end

class SuspenseTest < Minitest::Test
  def setup
    AsyncProfile.mounts = 0
  end

  def mount(widget)
    SuspenseRenderer.new.mount_component(widget, SuspenseEl.new)
  end

  def texts(node, acc = [])
    acc << node.text if node.text
    node.children.each { |child| texts(child, acc) }
    acc
  end

  def test_placeholder_shown_while_not_ready
    root = mount(AsyncProfile.new)

    assert_includes texts(root), "加载中…", "依赖未就绪时渲染占位"
    assert_empty texts(root).grep(/\A用户：/), "真实内容不出现"
  end

  def test_ready_switches_content_in_place_and_keeps_state
    w = AsyncProfile.new
    root = mount(w)
    w.clicks = 3

    w.user = { name: "Ray" }

    assert_includes texts(root), "用户：Ray · 点击 3", "就绪后原地切换到真实内容"
    refute_includes texts(root), "加载中…", "占位被替换"
    assert_equal 1, AsyncProfile.mounts, "切换不重建组件（on_mount 只跑一次）"

    w.clicks = 4

    assert_includes texts(root), "点击 4", "就绪后 state 照常响应"
  end

  def test_becomes_unready_again_switches_back
    w = AsyncProfile.new
    root = mount(w)
    w.user = { name: "Ray" }
    assert texts(root).any? { |t| t.include?("用户：Ray") }

    w.user = nil

    assert_includes texts(root), "加载中…", "回到未就绪时重新渲染占位"
  end

  def test_ssr_renders_current_branch
    assert_includes Citrine.render(AsyncProfile.new), "加载中…"

    ready = AsyncProfile.new
    ready.user = { name: "Ray" }
    assert_includes Citrine.render(ready), "用户：Ray"
    refute_includes Citrine.render(ready), "加载中…"
  end
end
