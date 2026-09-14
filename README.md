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

v1 已知限制：组件 props 为创建时快照；SSR 为一次性渲染且不序列化事件；
Canvas 输入用 window.prompt（演示级）、布局为线性 stack/flow。
列表已有 keyed 复用（`key:` 命中即复用节点与实例）；集合用 `Citrine.signal_list([...])`
（集合自身的每次变更都是一次通知，`get` 返回冻结快照）。

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

v1 已知限制：组件 props 为创建时快照（S2 会信号化）。列表 keyed 复用与
`Citrine.signal_list` 集合 API 均已落地。

## 目录

```
├── GOALS.md              # 愿景 / 决策 / 路线图 / 参考资料（项目主文档）
├── lib/
│   ├── citrine.rb        # 入口：装配 + Citrine.mount / Citrine.unmount / Citrine.render
│   ├── citrine/signal.rb # Signal / Effect（平台无关，CRuby 可测）
│   ├── citrine/reactive.rb # 给普通类的小混入：include 后可用 signal(...)
│   ├── citrine/num.rb    # 跨平台数值工具（idiv / round_to / integral? / finite? …）
│   ├── citrine/key_event.rb # 键盘事件（平台无关视图；G-9）
│   ├── citrine/node.rb   # 元素树节点（平台无关）
│   ├── citrine/component.rb # 组件基类：三宏 + 元素 DSL + 生命周期/键盘声明
│   ├── citrine/renderer.rb # 渲染器基类：树管理 / Effect 装配 / 块级重建（平台无关）
│   ├── citrine/dom.rb    # Web DOM 渲染器（Opal 专用）
│   ├── citrine/canvas.rb # Canvas 2D 渲染器（Opal 专用，自管布局 + 命中检测）
│   ├── citrine/string_renderer.rb # render-to-string（纯 CRuby）
│   ├── citrine/dev_server.rb # 开发服务器：热刷新 + 错误浮层（纯 CRuby）
│   ├── citrine/packager.rb # macOS .app 打包器（纯 CRuby）
│   └── citrine/browser.rb # 浏览器入口
├── bin/citrine                # CLI（citrine dev / citrine package）
├── desktop/main.swift    # macOS WKWebView 桌面壳（零依赖，约 55 行）
├── build/                # 打包产物（.app）
├── examples/
│   ├── components.rb     # 共享组件（四个后端复用同一份代码）
│   ├── counter.rb|html   # M1 示例：state / computed / 事件（DOM）
│   ├── todo.rb|html      # M1 示例：列表 / 受控输入 / 勾选 / 删除（DOM）
│   ├── reactive_props.rb|html # 响应式属性 + 全局键盘 + 卸载（G-2 / G-9 / G-10）
│   ├── num_parity.rb     # 数值工具的跨平台一致性样本（rake parity 用）
│   ├── canvas_counter.rb|html / canvas_todo.rb|html # M3 Canvas 示例
│   ├── ssr_demo.rb       # M3 示例：CRuby 下 render-to-string
│   ├── stub_check.js     # Node DOM 桩验收脚本
│   └── canvas_stub_check.js # Node Canvas 桩验收脚本
├── test/
│   ├── signal_test.rb    # 核心机制单测（CRuby / minitest）
│   ├── component_test.rb # 生命周期 / 键盘分发 / KeyEvent 单测
│   ├── num_test.rb       # 数值工具单测
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

> 前两条的通用答案是 **`Citrine::Num`**（`idiv` / `round_to` / `round` / `integral?` /
> `finite?` / `percent`）——别在应用里再各写一份。`rake parity` 会把这套工具在 CRuby 与
> Opal 下各跑一遍并逐字节比对（CI 已接入）。

1. **整数除法返回浮点**：`7 / 2` 在 CRuby 是 `3`，Opal 下是 `3.5`。凡需整数商请用
   `Citrine::Num.idiv(a, b)`——注意 `(a / b).to_i` **不是**等价替代：它向零截断，
   `-7 / 2` 会得到 `-3` 而 Ruby 的语义是 `-4`。金额/数量算错时格式化输出会出现
   `1,234,567,.89` 这类乱码。
2. **负数取整方向不同**：`(-1.5).round` CRuby 为 `-2`（远离零），Opal 为 `-1`
   （JS `Math.round` 朝 +∞；上游修复见 opal/opal#2808）。要跨平台一致请用
   `Citrine::Num.round_to(value, digits)`——它先取绝对值再贴符号。
3. **`Signal` 名字遮蔽**：Ruby/Opal 标准库里另有 `::Signal`（进程信号类）。在组件里写裸
   `Signal.new(...)` 会拿到那个空类并报 `undefined method 'get'`——**不要写出裸名字**：
   组件内用 `state` 宏、组件外（领域模型/测试）用 `Citrine.signal(...)`，或给普通类
   `include Citrine::Reactive` 后直接写 `signal(...)`；组件内要"按 key 记忆的信号表"用
   `keyed_signal(:name, key) { 初值 }`。确实要拿类本身时写全限定名 `Citrine::Signal`。
4. **可变字符串方法不存在**：`String#<<` / `#gsub!` / `#[]=` 在 Opal 下抛
   `NotImplementedError`（上游明文记录的设计选择：字符串不可变）。累积字符串用
   `buffer = buffer + ch` 或数组 `join`。
5. **反引号里不要插值 `Native` 包装对象**：`` `#{el}.focus()` `` 里的 `el` 是 Opal 的
   `Native::Object` 包装器，生成的 JS 里 `el.focus` 是 `undefined` → **静默不生效**。
   原生互操作优先用 Ruby 侧方法调用（`el.focus`），反引号只留给无法用方法调用表达的场景。
6. **从 JS 反调 Ruby 方法要知道改名规则**：`!` → `$excl`、`?` → `$question`、`=` → `$eq`
   （手写 `$focus_editor!()` 会生成非法 JS，整个 bundle 加载失败）。更稳的写法是
   `Opal.send(obj, "focus_editor!")`，或在插值里用 `#{obj.focus_editor!}` 让编译器替你改名。
7. **Ruby 局部变量会遮蔽反引号里的 JS 全局**：`def initialize(app, window = nil)` 之后，
   反引号里的 `window` 指的是那个参数而不是全局对象，症状是"没反应"。
   别用 `window` / `document` / `event` / `name` 当变量名或参数名。
8. **整数值的浮点会丢掉 `.0`**：Opal 下 `2.0.to_s` 是 `"2"`（`inspect` 同），CRuby 是 `"2.0"`
   ——显示层若依赖 `to_s` 输出小数位，两侧会不一样（上游 ruby/spec 的该用例至今在
   filter 列表里）。要定长小数请用 `Kernel#format`：`format("%.2f", 2.0)` → `"2.00"`（两侧一致）。
9. **`整数 ** 0` 会返回 Rational**：`10 ** 0` 在 Opal 下是 `1/1`（`Rational`），CRuby 是 `1`。
   成因是 `opal/corelib/number.rb` 的 `Integer#**` 把 `other > 0` 当成了"整数快路径"的条件
   ——指数为 0 也被归进负指数（Rational）分支。`Citrine::Num` 内部已绕开；
   上游修复已另提（同 `Float#round` 的处置路径）。
10. **给固定 arity 的方法多传实参，Opal 不报错只是静默丢弃**：`on_mount :a, :b` 在 CRuby 抛
    `ArgumentError`，在 Opal 下不报错、**只跑第一个**——表现为"某个副作用凭空消失"
    （dogfooding 实测：网格 ticker 没了，症状是闪烁永不清零，排查成本极高）。框架的
    生命周期宏已改成可变参数；写自己的宏/方法时也要注意：**别依赖"多传会报错"来兜底**，
    Opal 下这类错误不会浮出来。根治办法是让签名接收可变参数并自己校验实参。

### 框架备忘

- **创建信号（A/B/C/D 四个入口）**：组件内首选 `state` / `computed`；组件外与"按 key 记忆"场景：
  - `Citrine.signal(0)` / `Citrine.signal { 惰性初值 }` —— 到处可用（领域模型、测试），
    且**不必写出裸的 `Signal`**（会撞 stdlib 的 `::Signal`，见陷阱 3）
  - `include Citrine::Reactive` → 普通类里直接 `signal(0)`（组件不要 include：组件已有
    同名的 `signal(name)`，语义是"取已声明 state 的底层信号"）
  - `keyed_signal(:view, [row, col]) { { selected: false } }` —— 组件内按 (name, key) 记忆的
    信号表，替代到处手写 `@xxx[key] ||= Citrine::Signal.new(...)`；初值块在本组件实例上求值
  - `Citrine.signal_list([...])`（混入后 `signal_list([...])`）—— **响应式集合**：`<<` / `push` /
    `delete_at` / `replace` / `sort!` … 每次变更即一次通知（内部换新数组，触发路径仍只有
    `Signal#set` 一条）；`get` 返回**冻结**快照，`rows.get << x` 会当场 `FrozenError`
    而不是静默不更新；读操作（`size` / `each` / `map` / `include?` …）在块内读会建立依赖
- **键盘：元素级 + 全局（G-9）**：元素上写 `on_key:`——Symbol/Proc 直接收事件，哈希形式按 key 查表
  （`on_key: { "Escape" => :clear_draft, else: :fallback }`）；焦点相关用 `on_focus:` / `on_blur:`。
  键盘优先应用要的全局快捷键用类宏 `window_key :handler` 声明（window 级 keydown，
  **随组件卸载自动解绑**）。处理器拿到的是平台无关的 `Citrine::KeyEvent`：
  `key` / `shift?` / `meta?` / `ctrl?` / `command?` / `prevent_default` / `raw`。
- **生命周期（G-10）**：类宏 `on_mount :focus_editor`（DOM 就位后执行）与 `on_unmount { stop_timer }`，
  子类继承父类声明、按声明顺序执行；`ref: :editor` 把元素句柄登记到 `component.refs[:editor]`
  （DOM 下即元素本身，可直接 `.focus`）；`Citrine.unmount(component)` 卸载整棵组件树——
  销毁所有 Effect、跑 `on_unmount`、清空 refs、解绑全局键盘。
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
