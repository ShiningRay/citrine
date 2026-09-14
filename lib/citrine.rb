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

    # render-to-string（纯 CRuby 可用）
    def render(component)
      require_relative "citrine/string_renderer"
      StringRenderer.render(component)
    end
  end
end

require_relative "citrine/version"
require_relative "citrine/signal"
require_relative "citrine/node"
require_relative "citrine/component"
require_relative "citrine/renderer"
