# backtick_javascript: true
# frozen_string_literal: true

# Citrine 浏览器入口：require 本文件即完成 DOM 渲染器装配。

require "native"
require "citrine"
require "citrine/dom"

# 开发模式（布局/诊断提醒只在开发期输出）：由 dev_server 注入的 window.CITRINE_DEV 决定
Citrine.dev_mode = `typeof window !== "undefined" && window.CITRINE_DEV === true`
