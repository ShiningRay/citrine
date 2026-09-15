# DESIGN-devtools — Emerald/Citrine 调试器（DevTools）设计

> 来源：2026-09-15 调试器设计讨论。衔接 GOALS.md P1-8（信号依赖图可视化）与
> `PLAN-react-gap.md` T-B3 决策（先埋点、后 UI；数据层已验收，UI 为空白）。
> 姊妹文档：`PLAN-devtools.md`（分期开发计划）。
> 状态约定：`[x]` 已定案，`[ ]` 待定，`[~]` 暂缓。

## 一、目标与定位

为 Emerald 应用开发提供类 Web Developer Tools 的调试器，核心卖点是**信号式调试**——
这是 signal 框架独有、CDP（Chrome DevTools Protocol）给不出的能力：

1. **哪个信号触发了哪次更新**（写入时序 + flush 轨迹，依赖边一目了然）；
2. **组件树自省**（props/state/computed 实时值、effect 计数、复用 key）；
3. **事件追踪**（DOM 事件 → batch → 引发的 signal 写入与 effect 重跑全链路）；
4. **在线干预**（面板改信号值、强制重跑 effect，观察连锁反应）。

非目标：替代浏览器自带 DevTools（DOM 检查/网络/控制台仍用浏览器的）；
生产环境诊断（生产产物零埋点是红线，见第六节）。

## 二、关键决策 `[x]`

### D1. 分层归属：探针留核心仓，传输与 UI 独立成 gem `[x]`

```
citrine/              ← 探针层：debug.rb 扩展（prepend 埋点，生产可关）
citrine-devtools/     ← 新独立仓库/gem：中继服务 + 注入桥 + 面板 UI
```

- **探针必须同仓**：埋点语义与内核强耦合（`Signal#set`、`Scheduler.flush` 行为演进），
  同仓单测同步防劣化；生产零开销靠仓内 `rake prod_check` 强制守门。
  技术上 prepend 模式允许独立 gem，但版本追逐与红线失守风险不值得。
- **传输/UI 独立**：面板只消费 JSON 协议，独立发布节奏，Cytoscape.js 等依赖不污染核心；
  协议稳定后 Web/桌面/Emerald App 三种面板形态可共存。
- 参照系：solid-devtools / Redux DevTools 同构——核心库只留极小 hook 点，调试器是独立产品。

### D2. 探针实现：prepend + 显式 require + 环形缓冲 `[x]`

沿用 `lib/citrine/debug.rb` 已验证的模式：prepend 模块包裹内核方法，内核零改动；
`require "citrine/debug"` 才加载；`Citrine.debug_tracking=` 总开关运行时可控。
时序数据用固定容量环形缓冲（默认 500 条），避免长会话内存膨胀。

### D3. 传输：SSE 下行 + POST 上行，独立中继服务 `[x]`

- 浏览器侧探针采集 → `POST /__devtools/ingest` 上报 → 中继经 SSE 广播给所有连上的面板；
- 面板指令 → `POST /__devtools/cmd`（`set_signal` / `highlight_node` / `force_rerun`）→ 桥接脚本执行。
- **不上 WebSocket**：SSE+POST 与 dev_server 现有架构（`dev_server.rb` `broadcast`/`pump_client`）一致，
  且中继可独立进程运行（`citrine-devtools serve`，默认端口 9527），dev_server 至多需提供
  "注入额外脚本"配置口，理想情况一行不改。
- 桥接脚本仅在 `window.CITRINE_DEV`（`browser.rb:11`，由 dev_server 注入）为真时激活。

### D4. 面板形态：先 Web 浮层，后 Emerald 内置 App `[x]`

- **第一阶段**：独立 Web App（`localhost:9527` 即调试台）+ 可选 Shadow DOM 浮层注入被调试页
  （Shadow DOM 隔离样式污染）。
- **第二阶段**：DevTools 作为 `Emerald::App` 走 AppRegistry/CommandRegistry 贡献点，
  在 Emerald 桌面内调试同桌面其他应用——Web DevTools 做不到的"系统内自省"，
  与 Emerald 的 Web 桌面 OS 定位契合，是差异化卖点。

### D5. 依赖图可视化选型：Cytoscape.js `[x]`

沿用 `PLAN-react-gap.md` 调研结论：Cytoscape.js compound nodes 对应 signal→effect 层级；
Timeline 泳道用 Chrome Performance Extensibility API（`performance.measure` 按信号名分泳道），
数据直接进浏览器 Performance 面板。错误上报（Sentry source map 还原 .rb 行号）暂缓 `[~]`。

## 三、探针层规格（citrine 仓，`lib/citrine/debug.rb` 扩展）

现有能力（T-B3 已验收）：`Signal.all`/`Effect.all` 注册表、`debug_info`（id/subscribers/deps/runs/disposed）、
`Citrine.debug_dependency_graph`（JSON 快照）。**快照已有，缺时序**。新增三类探针：

### P1. 信号写入日志

- **埋点**：`Signal#set`/`#set!`/`#replace`（`signal.rb:101-136`），统一收口在私有 `#broadcast`（`:119`）；
  `ListSignal`（`list_signal.rb:25`）继承同一通道，天然覆盖集合变更。
- **记录**：`{t, signal_id, name?, old, new, source}`。`source` 取 `Effect.current`（`signal.rb:166`）；
  无 Effect 上下文时记 `:external`（事件处理器/定时器等）。
- **注意**：`old`/`new` 值序列化需截断（大对象 `to_s` 限长，避免缓冲爆炸）。

### P2. 批量执行轨迹（flush trace）

- **埋点**：`Scheduler.flush`（`signal.rb:49`）。
- **记录**：`{flush_id, t, effects:[{effect_id, runs, duration_ms}], trigger_signal_ids}`。
  `flush_id` 单调递增，作为事件流与信号写入的关联键——这是"哪个信号触发了哪次更新"的原始数据。
- 逐 effect `performance.now` 计时（浏览器）/ `Process.clock_gettime`（CRuby）。

### P3. 事件流

- **埋点**：`DomRenderer#ensure_event`（`dom.rb:159`，23 种事件实际绑定处）
  + `Component#handle_event`（`component.rb:527`，正好是 batch 边界）。
- **记录**：`{t, event_type, target_component, handler_name, flush_ids}`。
  handle_event 前后对比 flush_id 计数即得该事件引发的 flush 链。

### P4. 组件树快照 API

**不新埋点**——`Node`（`node.rb:6`）已带 `owner`/`children`/`owned_effects`/`props_effect`/
`block_effect`/`rendered_component`/`component_identity`/`reuse_key` 全套自省字段；
beryl 侧 `Beryl::Renderer#root_node`（`beryl/lib/beryl/renderer.rb:17`）是已预留的 DevTools 入口。
新增 `Citrine.debug_component_tree(root_node)`：遍历 VDOM 输出
`{node_id, component, props, state:{name=>value}, computed:{name=>value},
watch_effect_count, effect_count, computation_effect_count, reuse_key}`（计数器现成，
`component.rb:594/615/628`）。纯数据、CRuby 可测，MemoryRenderer 作测试范式。

## 四、传输协议（JSON，版本化 `v: 1`）

### 下行（面板 ← 中继）

| 消息 | 载荷 | 触发 |
|---|---|---|
| `hello` | `{v, app_name, citrine_version}` | 桥接脚本连接 |
| `signal_write` | P1 记录（可批量） | 信号写入 |
| `flush` | P2 记录 | Scheduler.flush |
| `event` | P3 记录 | DOM 事件分发 |
| `tree` | P4 快照 | 面板请求 / 挂载卸载后 |
| `graph` | 依赖图快照 | 面板请求 |

### 上行（面板 → 中继 → 桥接脚本）

| 指令 | 参数 | 说明 |
|---|---|---|
| `set_signal` | `{signal_id, value}` | 在线改值，观察连锁重跑 |
| `highlight_node` | `{node_id}` | 页面高亮对应 DOM（overlay 描边） |
| `force_rerun` | `{effect_id}` | 手动触发 effect.run |
| `request_tree` / `request_graph` | `{}` | 拉取快照 |

环形缓冲容量、采样开关（按消息类型过滤）经 `config` 指令运行时可调。

## 五、面板 UI（四个标签页）

1. **Components**——组件树（P4），选中显示 props/state/computed 当前值与 effect 计数；
   值变化时行内闪烁提示。
2. **Signals**——信号列表（runs/订阅数排序）+ 依赖图视图（Cytoscape.js，
   compound nodes 表 signal→effect，点击节点高亮相邻边；写入频繁的信号热力着色）。
3. **Timeline**——事件流与 flush 轨迹时间轴，按信号名分泳道；
   同步写 `performance.measure` 进浏览器 Performance 面板。
4. **Inspector**——选中信号在线改值（上行 `set_signal`），实时看依赖 effect 连锁重跑。

技术栈：面板自身可用 Citrine 开发（自举，吃自己狗粮），或 vanilla JS 起步求快 `[ ]` 待实施时定。

## 六、红线与约束（不可妥协）

- **生产零埋点**：全部 prepend + 显式 `require "citrine/debug"`；`rake prod_check` 断言产物无
  `debug_dependency_graph`/`debug_tracking`/`citrine/debug` 字符串，新增探针消息名同步加入断言清单。
- **核心 CRuby 可测**：探针层禁 Opal/JS 依赖；浏览器专有逻辑（performance.now、上报 fetch）
  只在桥接脚本，不进 debug.rb。SSR 路径不建 Effect，P4 在无 Effect 环境下须可跑（降级输出）。
- **架构红线不变**：平台无关核心不引入 Opal；埋点不得改动内核方法签名；DSL 语义零影响。
- **性能**：debug_tracking 关闭时 prepend 路径开销须可忽略（空判断短路）；
  开启时单次 flush 埋点开销 < 5%（用 `rake size` 同款思路做基准守门）`[ ]` 阈值待定。

## 七、已知坑（实施时对照）

- Opal 反引号 JS 需文件级 `# backtick_javascript: true`；`Native`/`to_n` 需 `require "native"`。
- bundler 下用 `bundle exec opal`；编译 `-I.` 不能省。
- 自动化测试：ZCode 内置浏览器 `press("Enter")` 不派发 keydown，面板测试用合成
  `dispatchEvent(new KeyboardEvent("keydown", {key: "Enter"}))`。
- Emerald 应用级热更新（`apphost.rb` reopen 语义）会重求值 App 类——调试器面板自己作为
  Emerald App 时，重载后需重建桥接连接，协议 `hello` 须幂等。

## 八、与既有规划的对齐

- GOALS.md **P1-8**：本文档即其落地设计；M4 完成（依赖图可视化）后可标记验收。
- PLAN-react-gap **T-B3**：数据层已验收（debug.rb 快照），本文档补时序层；Sentry source map 暂缓项不变。
- PLAN-code-review **暂缓项**："T-B3 后半 DevTools 可视化 UI"由 PLAN-devtools.md 的 M3/M4 承接。
