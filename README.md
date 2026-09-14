# Citrine（黄水晶）

[![CI](https://github.com/ShiningRay/citrine/actions/workflows/ci.yml/badge.svg)](https://github.com/ShiningRay/citrine/actions/workflows/ci.yml)

用 Ruby 写信号式响应 UI，经 Opal 编译后渲染到 Web、桌面与移动端。
愿景、架构决策与路线图见 [GOALS.md](GOALS.md)。
（历史记录中的工作代号 RV 指同一项目。）

## 安装

```bash
# 从源码（本仓库）
bundle install
bin/citrine dev examples

# 从 gem（发布到 rubygems.org 后）
gem install citrine
citrine dev <你的应用目录>
```

说明：Citrine 只通过 RubyGems 分发（源语言是 Ruby，npm 不在分发路径上；
运行时拆分方案见 GOALS 决策 #7 的例外条件）。

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
│   ├── reactive_props.rb|html # 响应式属性：props 传 Proc，订阅收敛到节点（G-2）
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

### ⚠️ 跨平台语义陷阱（CRuby 单测全绿 ≠ 浏览器正确，务必先读）

1. **整数除法返回浮点**：`7 / 2` 在 CRuby 是 `3`，Opal 下是 `3.5`。金额/数量计算请显式
   取整（`(a / b).to_i`）或自建 `idiv` 工具方法——否则格式化输出会出现 `1,234,567,.89` 乱码。
2. **负数取整方向不同**：`(-1.5).round` CRuby 为 `-2`，Opal 为 `-1`（JS `Math.round` 朝 +∞）。
   需要对称取整时先取绝对值、取整后再贴符号。
3. **`Signal` 名字遮蔽**：Ruby/Opal 标准库里另有 `::Signal`（进程信号类）。在组件里写裸
   `Signal.new(...)` 会拿到那个空类并报 `undefined method 'get'`——请始终写全限定名
   `Citrine::Signal`，或使用 `state` 宏。

### 框架备忘

- **布局方向必须显式**：`box` 的默认方向是 CSS 的 row（横排），而面板/网格这类容器绝大多数要竖排——
  忘了写方向时，真机上会"塌成一条"（行情终端面板塌成 2px、电子表格网格 553×35），
  而**桩里没有布局引擎，测不出来**。因此提供语法糖：`stack { }` = 竖排，`row { }` = 横排
  （等价于 `box(direction: :column|:row)`；再传 direction 会直接报错）。
  开发模式（`bin/citrine dev` 打开的页面会注入 `window.CITRINE_DEV`）下，一次挂载里
  "未声明方向且**有多子节点**"的 `box` 会在控制台汇总提醒一次（空容器/单子容器不提醒）；
  生产构建不提示。CRuby 侧要打开可写 `Citrine.dev_mode = true`。
- **props 的求值位置决定订阅范围（最容易踩的语义）**：`box(css_class: cell_class(row, col))` 的实参在
  **外层块**执行期间求值，外层块因此订阅了这一格的信号——改一格就整块重建（完全看不出差别，
  只在渲染量上体现）。把值改成 Proc 就能把订阅收敛到该节点：
  `box(css_class: -> { cell_class(row, col) })`——它在**该节点自己的 Effect** 内求值，
  重跑只重设属性、不重建子树。支持 Proc 的 prop：`css_class` / `placeholder` / `style` /
  `direction` / `gap`；事件 `on_*` 收到的 Proc 是**回调**，不在此列（示例
  `examples/reactive_props.rb`，桩验收 `node stub_check.js reactive_props`）。
- Opal 1.8.3：backtick 内嵌 JS 需要 `# backtick_javascript: true` magic comment
- `Native` / `to_n` 需要 `require "native"`（Opal stdlib）；Ruby String 可直接传给 JS 函数
- 带参数的方法调用接 `{}` block 必须写括号：`computed(:x) { ... }`（否则被解析为 Hash）
- 裸 Hermes VM 没有 `console`（React Native 中由 RN 注入），输出用 `print`
- 编译命令：`opal -c -I<lib路径> -o out.js in.rb`；产物 ~2MB（含完整 corelib，待按需裁剪）
