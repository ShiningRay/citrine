# RubyReact（工作代号 Citrine）

用 Ruby 写信号式响应 UI，经 Opal 编译后渲染到 Web、桌面与移动端。
愿景、架构决策与路线图见 [GOALS.md](GOALS.md)。

## 当前状态：M0 / M1 / M2 / M3 / M4a 完成（2026-09-14）

| 里程碑 | 内容 | 结果 |
|---|---|---|
| M0 | Opal → 浏览器 / Hermes 地基验证 | ✅ 全部通过 |
| M1 | Mini-React 核心：三宏 API + DOM 渲染器 | ✅ 三层验收全过 |
| M2 | `bin/citrine dev` 开发服务器：热刷新 + 错误浮层 | ✅ 浏览器实测闭环 |
| M3 | Renderer 基类 + 四个渲染器（DOM / String / Memory / Canvas） | ✅ 可移植性实证 |
| M4a | `bin/citrine package` 桌面化（macOS .app，零依赖壳） | ✅ 立项原点达成 |

**日常开发流程**（M2 起）：

```bash
bin/citrine dev examples        # 打开 http://localhost:4402/
# 改 lib/ 或 examples/ 下任意 .rb → 浏览器自动刷新
# 编译错误直接显示在页面顶部红色浮层，修复保存即自动恢复
```

**打包桌面应用**（M4a 起）：

```bash
bin/citrine package counter     # → build/CitrineCounter.app（双击即用）
open build/CitrineCounter.app

# 桌面开发模式：应用内热刷新（需先 bin/citrine dev）
build/CitrineCounter.app/Contents/MacOS/CitrineCounter --dev http://localhost:4402/counter.html
```

**渲染器家族**（M3 抽象的实证——组件代码零改动跨后端）：

- `Citrine::DomRenderer` — 浏览器（Opal），响应式块级更新
- `Citrine::StringRenderer` — render-to-string，纯 CRuby（`Citrine.render(component)`）
- `Citrine::CanvasRenderer` — Canvas 2D 绘制：自管布局 + 命中检测 + 全量重绘
- `MemoryRenderer`（test 内）— 30 行的测试渲染器，验证渲染器接口的最小实现

同一份组件代码（`examples/components.rb`）跑在四个后端：浏览器 DOM
（`counter.html` / `todo.html`）、CRuby SSR（`ssr_demo.rb`）、浏览器 Canvas
（`canvas_counter.html` / `canvas_todo.html`）。

v1 已知限制：列表为块级整体重建（无 keyed 复用）；集合为整体替换语义
（`self.items = ...`）；组件 props 为创建时快照；SSR 为一次性渲染且不序列化
事件；Canvas 输入用 window.prompt（演示级）、布局为线性 stack/flow。

M1 落地的 API（决策 #3 定案形态）：

```ruby
class Counter < Citrine::Component
  prop    :title, type: String, default: "Counter"
  state   :count, default: 0
  computed(:double) { count * 2 }

  def view
    box(direction: :column, gap: 10) do
      label { "count = #{count}　×2 = #{double}" }
      button(on_click: :increment) { "＋1" }
    end
  end

  def increment
    self.count += 1   # 赋值即更新
  end
end
```

v1 已知限制：列表为块级整体重建（无 keyed 复用）；集合为整体替换语义
（`self.items = ...`）；组件 props 为创建时快照。

## 目录

```
├── GOALS.md              # 愿景 / 决策 / 路线图 / 参考资料（项目主文档）
├── lib/
│   ├── rv.rb             # 入口：装配 + Citrine.mount / Citrine.render
│   ├── rv/signal.rb      # Signal / Effect（平台无关，CRuby 可测）
│   ├── rv/node.rb        # 元素树节点（平台无关）
│   ├── rv/component.rb   # 组件基类：prop / state / computed 三宏 + 元素 DSL
│   ├── rv/renderer.rb    # 渲染器基类：树管理 / Effect 装配 / 块级重建（平台无关）
│   ├── rv/dom.rb         # Web DOM 渲染器（Opal 专用）
│   ├── rv/canvas.rb      # Canvas 2D 渲染器（Opal 专用，自管布局 + 命中检测）
│   ├── rv/string_renderer.rb # render-to-string（纯 CRuby）
│   ├── rv/dev_server.rb  # 开发服务器：热刷新 + 错误浮层（纯 CRuby）
│   ├── rv/packager.rb    # macOS .app 打包器（纯 CRuby）
│   └── rv/browser.rb     # 浏览器入口
├── bin/citrine                # CLI（citrine dev / citrine package）
├── desktop/main.swift    # macOS WKWebView 桌面壳（零依赖，约 55 行）
├── build/                # 打包产物（.app）
├── examples/
│   ├── components.rb     # 共享组件（四个后端复用同一份代码）
│   ├── counter.rb|html   # M1 示例：state / computed / 事件（DOM）
│   ├── todo.rb|html      # M1 示例：列表 / 受控输入 / 勾选 / 删除（DOM）
│   ├── canvas_counter.rb|html / canvas_todo.rb|html # M3 Canvas 示例
│   ├── ssr_demo.rb       # M3 示例：CRuby 下 render-to-string
│   ├── stub_check.js     # Node DOM 桩验收脚本
│   └── canvas_stub_check.js # Node Canvas 桩验收脚本
├── test/
│   ├── signal_test.rb    # 核心机制单测（CRuby / minitest）
│   └── render_test.rb    # StringRenderer + MemoryRenderer 单测
└── spike/                # M0 验证存档（browser + hermes）
```

## 运行

```bash
gem install opal

# 核心机制单测（CRuby，不需要 Opal）
ruby -Ilib test/signal_test.rb
ruby -Ilib test/render_test.rb

# SSR demo（CRuby render-to-string）
ruby -Ilib examples/ssr_demo.rb

# ── 推荐的开发方式（M2 起）──────────────────────────────
bin/citrine dev examples            # http://localhost:4402/ 热刷新开发

# ── 手动编译（不使用 dev server 时） ─────────────────────
cd examples
opal -c -I../lib -I. -o counter.js counter.rb
opal -c -I../lib -I. -o todo.js todo.rb
opal -c -I../lib -I. -o canvas_counter.js canvas_counter.rb
opal -c -I../lib -I. -o canvas_todo.js canvas_todo.rb

# Canvas 桩验收
node canvas_stub_check.js counter
node canvas_stub_check.js todo

# Node 桩验收（自动断言，不起浏览器）
node stub_check.js counter
node stub_check.js todo

# 浏览器运行
ruby -run -e httpd . -p 4401
# 打开 http://localhost:4401/counter.html 与 todo.html
```

## 技术备忘

- Opal 1.8.3：backtick 内嵌 JS 需要 `# backtick_javascript: true` magic comment
- `Native` / `to_n` 需要 `require "native"`（Opal stdlib）；Ruby String 可直接传给 JS 函数
- 带参数的方法调用接 `{}` block 必须写括号：`computed(:x) { ... }`（否则被解析为 Hash）
- 裸 Hermes VM 没有 `console`（React Native 中由 RN 注入），输出用 `print`
- 编译命令：`opal -c -I<lib路径> -o out.js in.rb`；产物 ~2MB（含完整 corelib，待按需裁剪）
