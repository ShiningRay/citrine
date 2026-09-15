# backtick_javascript: true
# frozen_string_literal: true

# T-A2：真实浏览器布局守卫——挂载后在真机里量尺寸。
# Node 桩没有布局引擎，"容器塌成 2px 而 96 项断言全绿"（F23）这类事故
# 只有用真机布局才测得出来。rake browser 会用 headless Chrome 打开本页，
# 解析 #browser-report 的 JSON 并断言。
require "citrine/browser"
require "native"

class BrowserProbe < Citrine::Component
  def view
    stack(css_class: "stack") do
      label(css_class: "cell") { "A" }
      label(css_class: "cell") { "B" }
    end
  end
end

Citrine::DomRenderer.mount_at("app", BrowserProbe.new)

# ── 布局守卫：真实布局引擎量测 ──────────────────────────────
document = Native(`window.document`)
stack = document.querySelector(".stack")
cells = document.querySelectorAll(".cell")
rect = stack.getBoundingClientRect()

tops = `Array.from(#{cells.to_n}).map(function (c) { return c.getBoundingClientRect().top; })`

report = {
  stack_width: rect[:width],
  stack_height: rect[:height],
  cell_count: tops.length,
  top_distinct: tops[0] != tops[1] # 同层兄弟必须排在不同的纵向位置
}

pre = document.createElement("pre")
pre.setAttribute("id", "browser-report")
pre[:textContent] = `JSON.stringify(#{report.to_n})`
document.body.appendChild(pre)
