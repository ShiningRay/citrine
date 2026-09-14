# frozen_string_literal: true

# Citrine — 信号式 Ruby UI 框架（黄水晶：水晶振荡器是信号源，命名致敬 Opal）
# 设计定案见 GOALS.md 第七节：Signal 三宏 + block 级细粒度更新。
# 本文件只加载平台无关核心；浏览器入口见 citrine/browser.rb。

module Citrine
  class << self
    # 当前渲染器（由具体平台入口设置，如 citrine/dom.rb 的 DomRenderer）
    attr_accessor :renderer

    # 开发模式：只影响提示/诊断输出，不改变渲染语义。
    # `bin/citrine dev` 打开的页面由 dev_server 注入 window.CITRINE_DEV 自动置位；
    # CRuby 侧（SSR / 单测）可用 `Citrine.dev_mode = true` 手动打开。
    attr_writer :dev_mode

    def dev_mode?
      !!@dev_mode
    end

    def mount(component, element)
      raise "Citrine.renderer 未设置（浏览器入口应 require \"citrine/browser\"）" unless renderer

      renderer.mount_component(component, element)
    end

    # 卸载一个已挂载的组件（会跑 on_unmount、解绑全局键盘、销毁所有 Effect）
    def unmount(component)
      root = component.respond_to?(:root) ? component.root : component
      raise ArgumentError, "Citrine.unmount：组件尚未挂载（root 为空）" unless root

      renderer = component.respond_to?(:renderer) && component.renderer ? component.renderer : self.renderer
      raise "Citrine.unmount：找不到挂载这个组件的渲染器" unless renderer

      renderer.unmount_component(root)
    end

    # render-to-string（纯 CRuby 可用）
    def render(component)
      require_relative "citrine/string_renderer"
      StringRenderer.render(component)
    end

    # 造一个新信号。模块级工厂，哪儿都能用（领域模型 / 测试 / 组件外）：
    #
    #   tick = Citrine.signal(0)
    #   rows = Citrine.signal { load_rows }   # 块 = 惰性初值，第一次读取时求值一次
    #
    # 存在的理由是"不让人写出裸的 `Signal`"——stdlib 与 Opal corelib 都有
    # `::Signal`（进程信号），裸写会拿到那个类，报错完全不指向真因（FRICTION F14）。
    # 普通类里想少打字可以 `include Citrine::Reactive`，得到同名实例方法。
    def signal(value = nil, &init)
      Signal.new(value, &init)
    end
  end
end

require_relative "citrine/version"
require_relative "citrine/signal"
require_relative "citrine/reactive"
require_relative "citrine/key_event"
require_relative "citrine/num"
require_relative "citrine/node"
require_relative "citrine/component"
require_relative "citrine/renderer"
