# RubyReact — 愿景、路线图与待决策问题

> 记录日期：2026-09-14
> 状态：立项探索期，尚未写代码

## 一、愿景

用 Ruby 写 React 风格的组件，一套组件代码编译后渲染到多个平台：

- **Web**：浏览器里的响应式 UI（React 本体对标）
- **桌面**：打包成桌面应用（对标 Electron / React Native for Desktop）
- **移动端**：原生或接近原生的 App（对标 React Native）

开发体验对齐 React 的核心抽象：**组件、props、状态、组合**；架构上对齐
React 最关键的分层的经验——**Reconciler（树协调）与 Renderer（平台渲染）分离**，
"Learn once, write anywhere"。

执行底层：**Opal**（Ruby → JavaScript 编译器），组件代码最终以 JS 形态运行在
浏览器 / JS 引擎（如 RN 的 Hermes）中。

## 二、非目标（初期明确不做）

- 不兼容 React 的 npm 组件生态（远期再评估互操作）
- 不做服务端框架（路由、ORM、数据层）——专注 UI 层
- 不做 SSR / 同构（M3 之后视渲染器抽象的成熟度再议）

## 三、两条候选架构（最重要的决策）

### 路线 A：客户端 Ruby（真 · React 类比）★ 当前倾向

组件 + reconciler 全部经 Opal 编译，跑在浏览器/JS 引擎里。

- 优点：与 React 架构同构；客户端状态、离线能力；通往 React Native 式
  原生渲染的路径最顺
- 缺点：调试、包体积、性能受 Opal 约束；热更新工具链需要自建
- 前提验证：Opal 产物在目标 JS 引擎（含 Hermes）的兼容性 → M0 必做

### 路线 B：宿主端 Ruby + 瘦显示端（Scarpe / LiveView 类比）

组件跑在 CRuby 上（本地进程或服务端），渲染成 HTML/补丁，经 IPC 或
WebSocket 推给 webview 显示。

- 优点：整个 Ruby 生态（gem）可用；调试容易；Scarpe 已验证可行
- 缺点：状态在宿主侧，不是"React 模式"；离线、延迟、移动端打包都更绕；
  与原生渲染目标距离远

**当前结论：主线走 A；DSL 设计保持平台无关，使 B 可作为后备渲染通道。**

## 四、分阶段路线图

### M0 — 地基验证（spike，1~2 个实验）

- [x] Opal 工具链跑通：Ruby 文件编译为 JS，在现代浏览器执行并操作 DOM
- [x] **风险前置验证：Opal 输出能否运行在 Hermes（React Native 引擎）上**
- 验收：浏览器控制台里执行 Ruby 操作 DOM 成功

**M0 结果（2026-09-14，全部通过）**：
- Spike A：Opal 1.8.3 编译产物在真实浏览器运行；Ruby 经 Native interop 操作
  DOM；Signal/Effect 原型实现细粒度更新（单次点击精确 +1，计数与按钮文案
  同步更新，只重跑受影响的 block）。
- Spike B：同一产物在 Hermes 0.12.0 与 Node 输出逐字节一致，corelib 冒烟
  （类/块/集合/字符串/Hash/异常/信号机制）全部通过。
  **移动端路线（RN/Hermes）地基成立。**
- 遗留观察：产物 ~2MB（含完整 corelib，待按需裁剪）；裸 Hermes 无 console
  （RN 中为 polyfill，框架需输出抽象）；`Native`/`to_n` 需 `require "native"`；
  backtick 需 magic comment。

### M1 — Mini-React 核心（Web Demo）

- [x] 元素 DSL：box / label / button / text_input / check_box + block，
      生成元素树（等价 `React.createElement`）
- [x] 类组件 + props 传递（决策 #4：类组件 + `view` 方法 + block）
- [x] 渲染管线：**块级重建**（block 级细粒度更新，取代原计划的
  "全量重渲染 → diff/patch"——决策 #3 信号模型的直接实现）
- [x] `state` / `computed` 三宏触发定向更新（Signal/Effect）
- [x] DOM 事件绑定（Symbol 方法名 / Proc 两种处理器）

**M1 结果（2026-09-14，全部通过）**：
- 核心库 `lib/rv`（signal / node / component）平台无关，**CRuby 单测
  9 项全绿**（依赖追踪、陈旧依赖释放、dispose、同值跳过、级联失效、
  三宏语义、prop 校验）
- DOM 渲染器 `lib/rv/dom`：挂载 / 块级重建 / 销毁（含 Effect 退订）/
  事件 / 双向输入
- 三层验收：CRuby 单测 → Node 桩（Counter 4 项、Todo 6 项）→ 真实
  浏览器（单次点击精确 +1、computed 联动、Todo 增/勾选 line-through/
  删、回车与按钮双通道添加、输入清空）
- v1 已知限制（与第七节代价清单一致）：列表为块级整体重建，无 keyed
  复用；节点销毁时正确退订 Effect

### M1 已识别的两个技术难点（提前挂号）→ 处理情况

1. **控制流**：✅ v1 以"块级重建"语义覆盖——分支/列表所在 block 重跑
   即重建子树，无需 Solid 式控制流组件；性能优化（keyed 复用）留给 M2+。
2. **响应式集合**：✅ v1 按计划采用整体替换语义（`self.items = ...`）；
   响应式集合包装留给后续里程碑。

### M2 — 开发体验

- [x] CLI：`bin/rv dev [目录] [-p 端口]` 起本地服务（含目录索引页）
- [x] 热替换：整页自动刷新——0.3s 轮询监听 lib/ 与目标目录的 .rb，
      变更经 SSE 推送浏览器
- [x] 友好的错误展示：编译失败时页面顶部红色浮层（含文件/行号/错误
      详情），修正保存后自动恢复，不再白屏
- [ ] Fast Refresh（保状态热替换）——进阶项，M5+ 再议

**M2 结果（2026-09-14，验收通过）**：
- 零新依赖：纯 CRuby 标准库（socket / open3 / json / tmpdir），
  `lib/rv/dev_server.rb` + `bin/rv` 约 220 行
- *.js 请求按对应 *.rb 现场编译 + mtime 缓存（首次 ~2s，命中 ~13ms）
- 浏览器实测三段闭环：改标题 → 自动刷新显示新标题；注入语法错误 →
  浮层显示 `./counter.rb:9:1: error: unexpected token kEND`；修复保存 →
  页面自动恢复正常渲染

### M3 — 渲染器抽象验证

- [x] 把 DOM 渲染从核心剥离：`Citrine::Renderer` 基类承载节点树管理 / Effect
  装配 / 块级重建 / 销毁（平台无关），DomRenderer 降级为平台钩子实现
- [x] 第二个渲染器：`Citrine::StringRenderer`（render-to-string，纯 CRuby 可用）
- [x] 第三个渲染器（计划外收获）：`MemoryRenderer`（测试用，仅 30 行）
      ——三渲染器并存即抽象成立的实证
- [x] 组件代码三端复用：examples/components.rb 同时服务浏览器（Opal +
  DomRenderer）与 CRuby SSR（examples/ssr_demo.rb）

**M3 第一阶段结果（2026-09-14）**：
- 测试矩阵全绿：signal_test 9 项 + render_test 6 项（含块级更新保留兄弟
  节点身份的回归测试）+ Node 桩双示例
- 过程中发现并修复两个真问题：① 重构曾丢失 per-node Effect 包装导致
  整树重建、节点身份丢失（已加回归测试锁定）；② StringRenderer 的内联
  样式必须转 kebab-case（camelCase 在 style 属性中是非法 CSS）
- SSR 语义限制：一次性渲染（不建 Effect 订阅）、事件处理器不序列化

**M3 第二阶段（CanvasRenderer，2026-09-14 完成）**：
- 第四个渲染器 `Citrine::CanvasRenderer`（Opal）：自管布局（direction/gap 的
  stack/flow 语义 + style padding 解析）、Canvas 2D 绘制原语、包围盒命中
  检测、任意变更后全量重绘（游戏式）；**组件代码零改动复用**
  （examples/components.rb 同时服务 DOM / SSR / Canvas 三后端）
- 验收：Node 桩（counter 3 项 + todo 7 项，含 prompt 添加/勾选/删除）
  全绿；真实浏览器验证 Counter 点击 + **像素级回归**（点击后变化、
  重置后与初始画布逐位一致）、Todo 勾选切换（✓ 字形消失 36→17 像素）
  与删除（条目 2→1、剩余行上移）
- 过程中修复：paint_check_box 漏登记命中区域（点击 ✓ 无响应）
- 已知限制：文本输入为 window.prompt（演示级，避开 canvas 输入 IME/
  光标深水区）；布局为线性 stack/flow，无文本换行与交叉轴对齐；
  IAB 自动化上下文会自动关闭原生 prompt（该路径由 Node 桩覆盖验证）

### M4a — 桌面 webview 壳（2026-09-14 完成）

- [x] `bin/rv package <示例名>` → `build/<Name>.app`（macOS，双击即用）
- [x] 壳实现：**零依赖 Swift + WKWebView**（desktop/main.swift，约 55 行）；
      未采用 Tauri / Electron——本机工具链即可构建，更符合 Shoes 精神，
      Tauri 留作 Windows / Linux 跨平台阶段的选项
- [x] 双模式：打包模式（Resources 内静态文件）+ 开发模式
      （`--dev URL` 连接 rv dev 服务器，桌面应用内同样享受热刷新与错误浮层）
- 验收：bundle 结构完整（MacOS/Resources/Info.plist）；进程常驻；
  HTTP 服务日志证实 WKWebView 取回 html+js 并执行（`--dev` 模式下
  GET /counter.html、/counter.js 均 200）
- 限制：v1 仅 macOS；未做签名（本地构建无 Gatekeeper 拦截）；
  截屏验收因系统权限不可用，以网络日志 + 进程存活作为程序化证据

### M4b — 原生渲染（远期）

- [ ] React Native 桥接 / react-reconciler 渲染器（需切换内核，
      见决策 #2 的后备路线）
- [ ] 移动端（Hermes 地基已于 M0 验证通过）
- [ ] Windows / Linux 桌面（Tauri 壳或同等 webview 绑定）

## 五、待决策问题（按优先级）

| # | 问题 | 选项与当前倾向 |
|---|------|----------------|
| 1 | 架构路线 A vs B | 倾向 A（见第三节） |
| 2 | 内核自研 vs 包 Preact | 包 Preact：Isomorfeus 已证明可行且可参考其源码，能最快出 demo；自研 diff/调度是深坑。**倾向：M1 用 Preact 内核 + 自有 Ruby DSL，DSL 是我们的 API 资产，内核日后可换自研**。信号路线补充：Preact 官方的 @preact/signals 已生产验证"细粒度信号 + React 式组件"共存；同时信号模型（view 只跑一次、block 为响应单元）大幅降低自研迷你运行时的复杂度——**→ 已收敛（2026-09-14）：自研迷你内核**。理由：决策 #3 的 view-once/block 模型与 Preact 的组件重渲染模型根本不匹配，包裹它反而是负资产；自研核心仅约 300 行且 M0/M1 双重验证可行；@preact/signals 留作未来生态兼容的后备路线 |
| 3 | 状态模型：React 式 hooks vs Signal 细粒度响应式 | hooks 有调用顺序约束，在 Ruby block 里比较别扭；Solid/Vue 式 signal 更贴合 Ruby 的自然赋值。二次调研论据：服务端响应式已多人尝试但均不活跃；**客户端细粒度信号式在 Ruby 生态是空白**——选 signal 即做"Solid/Vue 的 Ruby 版"，差异化明显、避免与 React API 逐版本赛跑，代价是 Ruby 先例少（需直接学 Solid/Vue 源码）。**→ 已定案（2026-09-14）：Signal 三宏 API，详见第七节；待 M1 原型验证** |
| 4 | 组件形态 | 函数组件 + block（贴近现代 React）vs class 组件（Ruby 更自然但偏旧式 React） |
| 5 | JS 生态互操作姿势 | 直接调用 npm 包？统一包装层？互操作体验决定生态能否借力 |
| 6 | Opal 具体约束 | 输出体积、method_missing 式 DSL 的运行时开销、String 可变性、Hermes 兼容性（M0 验证）。信号方案的联动影响：访问器拦截不依赖 JS Proxy → Hermes 缺 Proxy 的风险从"致命"降为"仅深层集合响应式需要"，M0 验证仍做，但性质变为非致命。**M0 验证结论（2026-09-14）：Hermes 0.12.0 完全兼容，corelib 冒烟全过**；新观察：产物 ~2MB 待裁剪、裸 VM 无 console |
| 7 | 包结构与命名 | 单 gem vs monorepo（core / dom / native 分包，对齐 react / react-dom / react-native） |
| 8 | 测试策略 | 依赖 M3 的 string renderer；CRuby 侧跑 rspec/minitest |
| 9 | Rails 集成 | 非必须，后议 |
| 10 | 样式系统 | **已定案（2026-09-14）**：受限样式对象为 IR；**键统一 snake_case**（与 on_click 等事件命名同风格，Ruby 惯例优先），兼容 camelCase 输入（`Citrine::Style.normalize` 归一化）；值中 Symbol 自动转 CSS 连字符（`:line_through` → `"line-through"`）；各渲染器边界编译：DOM→camelCase 属性、CSS 字符串→kebab-case、Canvas 直接以 snake_case 消费。禁用 CSS 字符串 / 选择器 / 级联 |

## 六、先行者（参考与可挖掘的代码）

| 项目 | 状态 | 对我们的价值 |
|------|------|--------------|
| Hyperstack | 停止维护 | 曾是"React in Ruby"最完整实现，API 设计教材 |
| Isomorfeus-preact | 休眠 | **Opal 包 Preact 的完整先例，M1 最重要参考** |
| hyalite | 停止维护 | 路线 A 又一先行者：Opal 端 Ruby VDOM（youchan） |
| Mayu | 实验性 | 服务端 VDOM diff + WebSocket 推补丁，路线 B 中最接近目标的架构 |
| Scarpe | 活跃 | 路线 B 的现代实现，架构与打包思路可借鉴 |
| Preact / Inferno | 活跃 | 轻量 reconciler 源码，理解 diff 分层 |
| Solid.js | 活跃 | signal 状态模型的参照（问题 #3） |
| React 官方 | 活跃 | reconciler/renderer 分层与 Fiber 演进思路 |

### Hyperstack 详情（~2020 停摆）

- 演化：`reactrb` → `hyper-react` → Hyperloop → 2019 更名 Hyperstack（避免与马斯克
  Hyperloop 混淆）；核心作者 Mitch Van Duyn（catmando），单人项目
- 定位：Rails 的 drop-in gem；家族成员 hyper-component / hyper-model /
  hyper-router / hyper-operation / hyper-spec
- API：类组件 + `mutate` / `state_accessor` / `mutator`（详见其 Component State
  文档）；**刻意不支持函数组件**
- 亮点：**HyperModel 响应式 ActiveRecord**——客户端模型经 ActionCable 同步，
  数据库一变、引用该模型的组件自动重渲染（LiveView / Meteor 式响应数据的先声）
- 死因：单人维护；React 转向 hooks 使类组件 API 过时；Opal/Rails 工具链 churn；
  2020 底 Hotwire 发布转移社区注意力；1.0 始终未发

### Isomorfeus 详情（~2023 休眠）

- 作者 Jan Biedermann；独立全栈同构框架（组件 / 数据 / 传输 / 权限 / SSR 全自研）
- 组件层：`isomorfeus-react`（包 React，止于 16.13.12，2022-04）→
  `isomorfeus-preact`（包 Preact 10.x）；因 React 商标，组件类改名
  `LucidApp` / `LucidComponent` / `LucidFunc`
- 工程化程度高：hooks、memo、Context、Refs、SSR（speednode）、HMR、wouter 路由
- 发布极勤（长期每日 patch），最后版本 23.9.0.rc12（2023-09）后沉寂
- 死因：单人维护全栈框架、表面积过大；文档分散；社区未起量

### 五条教训（映射到待决策问题）

1. **"包 Preact"是已验证的路**（决策 #2）：Isomorfeus 从 React 迁到 Preact 不是
   偶然——Preact 小、内部接口稳定、好包。M1 直接从 Preact 起步。
2. **API 必须跟现代 React，或换赛道做 signals**（决策 #3）：Hyperstack 一半死在
   "类组件 API 变成上一代"。
3. **范围纪律**：Hyperstack 只做 Rails 插件仍死；Isomorfeus 做全家桶死得更彻底。
   Demo 阶段只做"组件 + 状态 + 一个渲染器"，数据层 / 路由 / 传输全不碰。
4. **HyperModel 的思路值得偷**：响应式数据同步是两个项目里最有生命力的想法，
   可作为 M4 之后的特性方向。
5. **命名避开商标**：`Lucid` 前缀就是 React 商标逼出来的；DSL 关键词要预留
   "不叫 React"的余地（决策 #7）。

### 响应式生态扫描（2026-09-14 二次调研，Vue 类比）

- **服务端响应式**（路线 B 变体）：Matestack（最像 Vue，底层就是 Vue 3，
  事件触发局部 rerender）、StimulusReflex + CableReady（维护最活跃，reflex
  后自动 morph DOM）、motion（LiveView 式，已沉寂）、Mayu（服务端 VDOM
  diff + WebSocket 补丁，实验性）——**人多但均不活跃/不成熟**，共同困境：
  与 Hotwire 抢 Rails 生态的注意力。
- **客户端细粒度响应式**（Vue Proxy / Solid signal 式）：**Ruby 生态空白**，
  无人实现过；技术前提（Opal + JS Proxy 互操作）可行性未验证。
- 结论：若决策 #3 选 signal，等于开辟而非追赶——既是差异化机会，也意味着
  缺少可直接照抄的 Ruby 先例。API 示意：`count = signal(0)`，读取处自动
  建立依赖，写入只更新受影响的节点。

## 七、核心 API 设计（决策 #3 定案：Signal 三宏）

> 定案日期：2026-09-14；状态：倾向方案，待 M1 原型验证。

### 立论

Hooks 是"函数组件每次重跑、局部状态无处安放"的补丁。Ruby 组件若为持久
对象，状态天然活在实例里（`@count` 跨渲染持久），问题只剩"写入如何通知
框架"——而这正是 Ruby 元编程（访问器拦截）最擅长的事。
**Ruby 的 OOP 不是实现 hooks 的障碍，而是绕过 hooks 的理由。**

### 三宏 API

```ruby
class Counter < Citrine::Component
  prop  :title, type: String           # 只读，来自父组件
  state :count, default: 0             # 可变，读写均受追踪
  computed(:double) { count * 2 }      # 派生值，依赖变化自动失效（注意带括号）

  def view
    box(direction: :column) do
      label { "#{title}: #{count} (x2 = #{double})" }
      button(on_click: :bump) { "加一" }
    end
  end

  def bump
    self.count += 1                    # 赋值即更新，没有 setCount
  end
end
```

- `state`：define_method + 惰性初始化（ActiveRecord `attribute` 模式），
  生成的 writer 触发通知
- `computed`：声明式派生值，依赖自动收集、变化自动失效
- `effect` / `watch`：副作用块自动收集依赖，按依赖图拆解，多数 cleanup 免写
- 依赖收集机制：读取时向"当前求值上下文"栈登记（全局栈，约 50 行实现，
  Opal 兼容）

### Block 级细粒度更新（Solid 模型的 Ruby 形态）

`view` 只执行一次；`label { "#{count}" }` 的 block 即响应单元——读取时
订阅，写入时只重跑该 block、只更新对应节点。Ruby block 比 JSX 更适合
承载此模型。

### 命名约定（决策 #10，2026-09-14 补充）

DSL 全域 snake_case：事件 `on_click` / `on_change` / `on_enter`，样式键
`font_size` / `flex_direction`（camelCase 输入经 `Citrine::Style` 归一化等价）。
理由：一个 DSL 一种方言——JS 的 camelCase 只允许存在于渲染边界内部。

### React API 对照（Ruby 白送的红利）

| React | Ruby 形态 | 说明 |
|---|---|---|
| useState | `state` 宏 + 赋值 | 核心设计 |
| useEffect | `effect`/`watch` + `on_mount` 宏 | 副作用按依赖图拆解，多数 cleanup 免写 |
| useMemo | `computed` 宏 | 声明式派生值 |
| useRef | 普通实例变量 | 实例持久，ref 失去存在意义 |
| useCallback | 方法名引用（`on_click: :bump`） | 实例方法身份天然稳定 |
| custom hooks | `module` mixin | `include Fetchable` |

附带收益：无 hooks 调用顺序规则（状态身份由实例保证）；闭包捕获稳定的
`self`，stale closure 类 bug 概念上消失。

### 代价清单（诚实条款）

1. 必须走访问器：裸 `@count = 1` 绕过追踪（MRI/Opal 均无法廉价拦截 ivar
   写入语法）。约定 + lint 缓解，Vue 有同类约束。
2. `computed` 块必须是纯读取。
3. 集合深响应为二期：v1 整体替换语义，v2 响应式集合包装。
4. 与 React API 正式分道扬镳——本项目做"信号式 Ruby 原生 API"。

### 对其他决策的联动影响

- 决策 #2：@preact/signals 验证了内核可行性；自研迷你运行时复杂度也大幅
  下降。M1 首周双路 spike。
- 决策 #6：不再依赖 JS Proxy，Hermes 风险降级为非致命。

## 八、就绪度评估（2026-09-14）

**结论：M0 可以立即启动；M1 有两个已识别技术难点（已挂号），无阻塞性未决问题。**

| 决策 | 状态 |
|------|------|
| #1 架构 A/B | 已定倾向 A，M0 即验证 |
| #2 内核 | 缩小为 M1 首周双路 spike（自研迷你运行时 vs Preact + @preact/signals） |
| #3 状态模型 | ✅ 已定案（第七节），待原型验证 |
| #4 组件形态 | 随 #3 事实上已定：类组件 + `view` 方法 + block |
| #5 JS 互操作 | 明确延后，不阻塞 demo |
| #6 Opal 约束 | M0 验证；Proxy 风险已降级为非致命 |
| #7 命名/包结构 | **命名已定案（2026-09-14）：Citrine**（黄水晶）。寓意：水晶振荡器是"信号源"的硬件原型，与 signal 框架本质暗合；延续 Ruby 生态宝石命名传统（Opal 先例）。rubygems.org 未占用 ✅、避开 React 商标 ✅；npm 同名包为无关小项目，无碍。代码命名空间 `RV` → `Citrine` 已完成全库重命名（历史记录中的 RV 指同一项目）。**包结构定案（同日）：v1 单 gem**（`citrine`，含 CLI 与桌面壳模板，不分包），分包留 P2 视复杂度再拆；**npm 包不做**——源语言是 Ruby，分发主渠道是 RubyGems。唯一例外条件：P1 体积优化若做"运行时拆分"（编译产物不再内嵌 2MB corelib），预编译运行时 `citrine-runtime` 可能以静态资产或 npm 包形式分发 |
| #8 测试策略 | 依赖 M3 string renderer，节奏匹配 |
| #9 Rails 集成 | 非目标，不阻塞 |

### M1 已识别的两个技术难点（提前挂号）

（已随 M1 以 v1 语义落地，处理情况详见第四节 M1 结果：控制流以块级重建
覆盖；响应式集合采用整体替换语义。keyed 复用与集合包装为 M2+ 事项。）

### 启动检查单（M0）

- [x] Ruby + Opal 环境就绪，hello world 编译到浏览器并操作 DOM
- [x] Opal 产物在 Hermes 上的兼容性验证（决定移动端优先级）
- [x] 目录骨架 + gem 工作代号（#7 临时决议：工作代号 **RV**）

## 九、决策记录

| 日期 | 决策 | 理由 |
|------|------|------|
| 2026-09-14 | 立项，记录愿景与路线图 | 初次记录，尚无代码 |
| 2026-09-14 | 完成 Hyperstack / Isomorfeus 深入调研，补入先行者详情与参考资料 | 为决策 #2（包 Preact）、#3（状态模型）提供论据 |
| 2026-09-14 | 响应式生态调研（Vue 类比）：hyalite / Mayu 入先行者清单，新增参考分组，决策 #3 补充"客户端信号式为空白"论据 | 服务端响应式路线均不活跃；客户端细粒度响应式无先例，signal 路线 = 差异化机会 |
| 2026-09-14 | 决策 #3 定案：Signal 三宏 API（类组件 + block 级细粒度更新），详见第七节；完成就绪度评估（第八节） | Ruby OOP + 元编程使 hooks 的存在理由消失；@preact/signals 验证内核可行；评估结论：M0 可立即启动 |
| 2026-09-14 | **M0 完成并全部通过**：Spike A（浏览器 + DOM + Signal/Effect 原型，真实浏览器验收单次点击精确 +1）；Spike B（Hermes 0.12.0 与 Node 输出一致，corelib 冒烟全过）。工作代号定为 RV | 路线 A 地基成立，移动端路径打通；决策 #6 的 Hermes 未知项消除；遗留：产物体积 ~2MB 待裁剪、Hermes 需输出抽象 |
| 2026-09-14 | **M1 完成并全部通过**：三宏 API + DOM 渲染器落地（核心 lib/rv 约 300 行），Counter / Todo 双示例经 CRuby 单测、Node 桩、真实浏览器三层验收；决策 #2 收敛为自研迷你内核 | 信号模型与 Preact 重渲染模型不匹配；块级重建取代 diff/patch（比原计划更简单且更符合决策 #3）；v1 限制：列表块级整体重建、无 keyed 复用 |
| 2026-09-14 | **M3 第一阶段完成**：Renderer 基类 + StringRenderer（CRuby SSR）+ MemoryRenderer（测试），同一份组件代码三端渲染 | 渲染器抽象成立；CRuby 下可脱离浏览器测组件；修复"整树重建丢身份"与"style 需 kebab-case"两问题并加回归测试 |
| 2026-09-14 | **M3 全部完成**：第四个渲染器 CanvasRenderer 落地，组件代码零改动跑在 DOM / SSR / Canvas / Memory 四后端；可移植性从叙事变为实证 | 渲染器接口经四实现检验；浏览器像素级回归（重置后画布逐位一致）；限制：canvas 输入用 prompt、布局为线性 stack/flow |
| 2026-09-14 | **M2 完成**：`bin/rv dev` 开发服务器（热刷新 + 编译错误浮层），零新依赖 | 开发闭环 = 改代码 → 自动重编译 → 自动刷新；错误可见且可自动恢复；Fast Refresh 留待后续 |
| 2026-09-14 | **M4a 完成**：`bin/rv package` 产出 macOS .app（零依赖 Swift+WKWebView 壳，打包/开发双模式） | 立项原点"像 Shoes 一样跑成桌面应用"达成；零依赖优于引入 Rust/Tauri，跨平台壳留待 M4b |
| 2026-09-14 | **决策 #10 定案并落地**：DSL 命名统一 snake_case（样式键 + 事件），camelCase 兼容输入；全量回归通过（单测 16 项 + 四桩）+ 桌面应用重打包 | 消除"一个 DSL 两种方言"（事件 snake vs 样式 camel 的 JS 泄漏）；归一化在 Component#emit 单点完成，渲染器各自边界编译 |
| 2026-09-14 | **Todo 视觉升级**：DSL 新增 `css_class` 透传（DOM→className / SSR→class / Canvas 忽略）；动效分工定式：状态过渡用内联 `transition`，hover/focus/@keyframes 由页面级样式承载（决策 #10 的边界分工）；Canvas 增加纯色护栏（渐变值跳过绘制） | 内联样式无法表达伪类与关键帧，页面样式是正确出口；调查结论：IAB 自动化的 press 不派发键盘事件（探针证实 keydown 到达数为 0），框架无碍——真实键盘与合成事件均正常 |
| 2026-09-14 | **Roadmap v2 制定**（第十一节）：P0 组合 API（嵌套/keyed 复用/props 传播）+ 生命周期宏 + 响应式集合 → P1 体积/构建/Fast Refresh/DevTools → P2 命名/分包/CI/文档/基准 → P3 平台扩张；附风险对冲清单 | 组件组合是当前最大 API 缺口（无嵌套则不成立"React-like"）；单人维护是三家先行者共同死因，开源与 co-maintainer 为生存项 |
| 2026-09-14 | **正式命名定案：Citrine**（决策 #7）。完成全库重命名：`RV` → `Citrine`（模块 / lib/citrine/ / bin/citrine / 示例 / 测试 / 文档），全量回归通过（单测 + 四桩 + 重打包 CitrineCounter.app）。候选评估：常见单词名在 rubygems 全被占用，可用候选 Opaline / Rubine / Citrine / Signa 中选定 Citrine | 水晶振荡器 = 信号源的隐喻；宝石命名传统（Opal 先例）；避开 React 商标与主要冲突 |
| 2026-09-14 | **仓库化 + gem 0.1.0**：代码迁入独立 citrine/ 仓库（git init，首次提交 41 文件），gemspec + version + MIT LICENSE + .gitignore 就绪，`gem build` 通过（citrine-0.1.0.gem，21.5KB，未发布）；决策 #7 包结构定案：v1 单 gem，**npm 不做** | 源语言 Ruby → RubyGems 为唯一分发渠道；npm 的唯一例外是 P1 运行时拆分时的 citrine-runtime 预编译资产 |

## 十一、后续发展路线（Roadmap v2，2026-09-14 制定）

> 定位：从"完整 demo"走向"能用 → 好用 → 是个开源项目"。

### P0 — 成为"能用"的框架（核心 API 缺口）

1. **组件嵌套/组合**（最大的缺口）：当前组件无法在 view 中渲染另一个
   组件——而这正是 React 的核心价值。需要：
   - `render(ChildComponent.new(props))` 挂载子树；
   - **keyed 实例复用**：父块重建时按 key 复用子组件实例，否则状态全丢；
   - **props 响应式传播**：props 从"创建时快照"升级为可更新（父重传 →
     子组件读取 props 的块失效重跑）。这三个子问题本质上是同一件事。
2. **生命周期宏**：兑现第七节承诺的 `effect` / `watch` / `on_mount` /
   `on_unmount`（当前只实现了 state / computed 两宏）。
3. **响应式集合**：ReactiveArray / ReactiveHash（`items << x` 直接触发），
   替换 v1 的整体替换语义。
4. **批量更新**：一个 handler 改多个信号只重渲染一轮（事务/microtask 合并），
   消除级联重跑的中间闪烁。

### P1 — 成为"好用"的开发体验

5. **产物体积**：2.2MB 全量 corelib → 按需裁剪 / tree-shaking / esbuild
   minify，目标 gzipped < 300KB（决策 #6 遗留观察项）。
6. **`rv build`**：生产构建（minify + 哈希文件名 + source map）。
7. **Fast Refresh**：保状态热替换（需要组件模块热替换协议）。
8. **DevTools**：**信号依赖图可视化**——signal 框架独有的调试卖点
   （哪个信号触发了哪次更新、依赖边一目了然）。

### P2 — 成为"项目"而非代码（生态与可持续）

9. **正式命名**（决策 #7 悬而未决，RV 仅为工作代号）+ 仓库/域名。
10. **分包发布**：citrine-core / citrine-dom / citrine-canvas / citrine-cli（对齐 react /
    react-dom 的分包结构，决策 #7 的 monorepo 方案）。
11. **CI + 测试矩阵**：GitHub Actions 跑 CRuby 单测 + 多桩验收。
12. **文档**：API 参考 + 教程（当前只有 GOALS/README）；把 MemoryRenderer
    提升为官方组件测试助手。
13. **性能基准**：js-framework-benchmark 式的对比数据（vs React/Preact/
    Solid），没有数字就没有说服力。

### P3 — 平台扩张

14. Canvas 渲染器深化（文本换行、交叉轴对齐）。
15. M4b 原生渲染（react-reconciler 内核切换，决策 #2 后备路线）。
16. Windows / Linux 桌面壳（Tauri 或同等绑定）。

### 风险清单（前人的死因，逐条对冲）

- **单人维护**：Hyperstack / Isomorfeus / RubyMotion 三家皆亡于此 →
  P2 的开源 + 尽早寻找 co-maintainer 不是可选项而是生存项。
- **上游漂移**：Opal 版本跟进、浏览器 API 变化 → CI 化 + 锁版本策略。
- **范围蔓延**：不碰路由 / 数据层 / 状态管理库（教训 #3 继续有效）。
- **API 冻结过早**：P0 的组合 API 设计定稿前不承诺 semver。

## 十二、参考资料

> 整理自 2026-09-14 的调研（网络检索 + 文档抓取），链接有效性以当日为准，
> 后续请以各项目仓库为第一信源。

### 本方向先行者（Opal + React/Preact in Ruby）

- Hyperstack 主仓库：<https://github.com/hyperstack-org/hyperstack>
- Hyperstack 组件状态文档（`mutate` / `state_accessor` / `mutator` 语法）：
  <https://docs.hyperstack.org/client-dsl/state>
- 旧仓库迁移公告（Hyperloop → Hyperstack 的改名证据）：
  <https://github.com/ruby-hyperloop/hyper-react>
- Hyperstack 1.0 冲刺进度报告（Reddit，2019-04）：
  <https://www.reddit.com/r/ruby/comments/b91taq/hyperstack_progress_report/>
- 官方对"为何不支持函数组件"的回答（Stack Overflow）：
  <https://stackoverflow.com/questions/55690284/can-i-make-a-functional-component-in-hyperstack>
- Isomorfeus GitHub 组织：<https://github.com/isomorfeus>
- isomorfeus-preact（RubyGems，含版本史）：<https://rubygems.org/gems/isomorfeus-preact>
- isomorfeus-preact README（RubyDoc，组件类型清单）：<https://www.rubydoc.info/gems/isomorfeus-preact>
- isomorfeus-react 版本史（止于 16.13.12 / 2022-04）：<https://rubygems.org/gems/isomorfeus-react>
- isomorfeus-operation（`LucidQuickOp` 等，全家桶规模佐证）：
  <https://www.rubydoc.info/gems/isomorfeus-operation/2.0.20>
- hyalite（Opal 端 Ruby VDOM，路线 A 先行者）：
  <https://github.com/youchan/hyalite>

### 响应式 / 服务端驱动路线（Vue 类比，2026-09-14 二次调研）

- Matestack 主仓库（纯 Ruby 组件 + 事件触发局部 rerender）：
  <https://github.com/matestack/matestack-ui-core>
- matestack-ui-vuejs 文档（其 Vue 3 响应式层，3.0 起独立成 gem）：
  <https://docs.matestack.io/about/ecosystem/matestack-ui-vuejs>
- StimulusReflex（reflex 跑完自动 morph DOM，此领域维护最活跃）：
  <https://github.com/stimulusreflex/stimulus_reflex> ·
  <https://docs.stimulusreflex.com/hello-world/>
- CableReady（服务端命令 → 客户端 DOM 变更，可独立使用）：
  <https://github.com/stimulusreflex/cable_ready>
- Mayu（服务端组件 + 服务端 VDOM diff + WebSocket 推补丁，实验性）：
  <https://github.com/mayu-live/framework>
- motion（LiveView 式纯 Ruby 组件，ActionCable 传输，已沉寂）：
  <https://github.com/unabridged/motion>
- Reactive Rails 资源索引（Obie Fernandez 策展清单）：
  <https://github.com/obie/guide-to-reactive-rails>

### 同生态其他路线（对比参照）

- Phlex vs ViewComponent 讨论（GoRails 论坛）：
  <https://gorails.com/forum/2025-rails-frontend-solution-phlex-or-viewcomponents>
- Evil Martians：现代 Rails 前端工具链（Phlex/ViewComponent + Hotwire 的主流共识）：
  <https://evilmartians.com/chronicles/keeping-rails-cool-the-modern-frontend-toolkit>
- Rails 8 视图层综述（ERB / ViewComponent / Phlex，iRonin）：
  <https://www.ironin.it/blog/modern-ruby-on-rails-8-frontend-view-layer.html>
- Scarpe（路线 B 的活跃实现，Shoes API over Web）：<https://scarpe-team.github.io/scarpe/>
- Shoes3 维护仓库：<https://github.com/Shoes3/shoes3>
- Shoes 4 仓库（JRuby + SWT，止于 pre-release）：<https://github.com/shoes/shoes4>
- Shoes 下载页：<http://shoesrb.com/downloads/>
- Glimmer DSL for SWT（JRuby 桌面，活跃，"喜欢 Shoes 就会爱上 Glimmer"）：
  <https://github.com/andyobtiva/glimmer-dsl-swt>

### 内核与状态模型参考（M1 前精读）

- Preact（M1 拟包裹的内核）：<https://preactjs.com/>
- Preact 源码中的 diff/ reconciler 分层：<https://github.com/preactjs/preact>
- Inferno（另一个轻量 reconciler 参照）：<https://www.infernojs.org/>
- Solid.js（signal 细粒度响应式，决策 #3 的对照方案）：<https://www.solidjs.com/>
- React 官方（reconciler / renderer 分层思想的源头）：<https://react.dev/>
- React Reconciler 包（自制渲染器的官方接口范本）：
  <https://github.com/facebook/react/tree/main/packages/react-reconciler>

### 工具链

- Opal（Ruby → JS 编译器，路线 A 的地基）：<https://opalrb.com/>
- Opal GitHub（M0 需确认其输出对 Hermes 的兼容性）：<https://github.com/opal/opal>
- Inertia.js（若最终需与 React 共存的退路）：<https://inertiajs.com/>
