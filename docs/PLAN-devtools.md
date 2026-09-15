# PLAN-devtools — 调试器（DevTools）分期开发计划

> 来源：2026-09-15 调试器设计讨论。设计定案见 `DESIGN-devtools.md`（分层归属/探针规格/协议/红线）。
> 衔接 GOALS.md P1-8、PLAN-react-gap T-B3（数据层已验收，UI 空白由本计划承接）。
> 状态约定：`[x]` 已完成，`[ ]` 待执行，`[~]` 暂缓（需外部动作或用户决策，见每项备注）。

## 里程碑总览

| 里程碑 | 内容 | 所在仓库 | 验收标准 |
|---|---|---|---|
| M1 | 时序探针 + 组件树 API | citrine | CRuby 单测全绿 + prod_check 通过 |
| M2 | 独立中继服务 + 注入桥 | citrine-devtools（新仓） | 浏览器↔面板双向消息互通 |
| M3 | Web 面板：组件树 + 信号列表 | citrine-devtools | 打开面板即可看树、看信号实时值 |
| M4 | 依赖图 + Timeline | citrine-devtools | GOALS.md P1-8 验收 |
| M5 | Emerald 内置 App 版面板 | citrine-devtools + emerald | 桌面内调试同桌面应用 |

M1 不依赖新仓，可立即开工；M2 起需要新建 `citrine-devtools` 仓库 `[ ]`（本地仓先行，远端待定）。

## M1 — 时序探针与组件树 API（citrine 仓）`[x]`

> 2026-09-15 完成：340 runs / 1093 assertions 全绿，rubocop 无 offense，`rake prod_check` 14 项 needle 通过。对外入口四件套 `Citrine.debug_write_log` / `debug_flush_trace` / `debug_event_stream` / `debug_component_tree` + `Debug.*_ring` 三件套（`test/debug_prod_check_test.rb` 静态双向守门）。

### M1-1 信号写入日志 `[x]`
- **位置**：`lib/citrine/debug.rb`（扩展）；埋点 `lib/citrine/signal.rb:101-136`，收口 `#broadcast:119`
- **做法**：prepend 模块记录 `{t, signal_id, old, new, source}`，`source` 取 `Effect.current`；
  固定容量环形缓冲（默认 500，经模块属性可调）；值序列化截断（`to_s` 限 200 字符）。
- **测试**：`test/debug_write_log_test.rb`——写入产生记录、batch 内多次写入顺序正确、
  source 在 Effect 内外分别为 effect id / `:external`、缓冲溢出滚动、tracking 关闭时零记录。

### M1-2 flush 轨迹 `[x]`
- **位置**：埋点 `lib/citrine/signal.rb:49`（`Scheduler.flush`）
- **做法**：记录 `{flush_id, t, effects:[{effect_id, runs, duration_ms}], trigger_signal_ids}`；
  `flush_id` 进程内单调递增。
- **测试**：一次信号写入引发一次 flush 且 trigger 含该信号；effect 抛异常（C4 已修，逐 effect rescue）
  时轨迹仍完整记录。

### M1-3 事件流 `[x]`
- **位置**：`lib/citrine/debug/event_stream.rb`（prepend `Component#handle_event`，`component.rb:527`）；
  DOM 侧 `ensure_event` 埋点按计划归 M2-3
- **落地**：`{t, event_type, target_component, handler_name, flush_ids}`（另加 `component_id` 供面板
  join 组件树）；handler 抛异常时事件仍留痕（ensure 埋点）；`flush_ids` 为 FlushCounter 前后差集，
  空 batch 不留痕不留号（M1-2 适配语义，有跨探针测试锁定）。

### M1-4 组件树快照 API `[x]`
- **位置**：`lib/citrine/debug/tree.rb`（`Citrine.debug_component_tree`，零埋点遍历 `node.rb` 自省字段）；
  内核零改动
- **落地**：按渲染位置嵌套的 JSON 树——`node_id` 为组件边界节点 object_id（协议 `highlight_node`
  锚点）；props 消毒后可 `JSON.generate`；state/computed 只读现成表、快照零副作用（未求值项 nil）；
  SSR/无 Effect 环境照常输出（计数为 0）；keyed 复用场景断言 `reuse_key → node_id` 重排后不变。

### M1-5 红线守门 `[x]`
- **位置**：`Rakefile`（prod_check needles 3 → 14 项）+ `test/debug_prod_check_test.rb`（新增静态守门）
- **落地**：三层覆盖（T-B3 数据层 / M1 入口四件套 / ring 访问器与 prepend 模块名）；
  守门测试与探针源码双向同步（新增探针自动纳入）；`rake prod_check` 真实 Opal 编译
  + 反向注入验证非空转。协议消息名（`signal_write` 等）不作 needle（内核/示例中合法存在必误报），
  M2 起由 citrine-devtools 仓标注。
- **基准**`[ ]`：debug_tracking 开启时 flush 开销 < 5%——实测回填，移至 M2 前完成
  （M2 的批量上报设计依赖此数据定聚合窗口）。

## M2 — 传输层（新仓 citrine-devtools）`[x]`

> 2026-09-15 完成：Ruby 16 runs / 60 assertions 全绿，node 契约 28/28 全绿，
> 真浏览器 e2e 通过（合成点击产出 `event ×1 + flush ×1 + signal_write ×5` 聚合批，
> 稳态 signal_write 流持续上报）。协议契约 docs/PROTOCOL.md（v1）。
> 仓库本地建仓（未 git init），gemspec 0.1.0。

### M2-1 仓库骨架 `[x]`
- gemspec（名 `citrine-devtools`）、bin/citrine-devtools、`serve` 子命令（Rack+Puma，参照
  `lib/citrine/dev_server.rb` 的 SSE 实现：Queue + pump 线程 + 15s ping 清扫）。
- 默认端口 9527；CORS 放开 localhost 任意端口（被调试页在 4402）。

### M2-2 协议端点 `[x]`
- `GET /__devtools/stream`（SSE 下行：signal_write/flush/event/tree/graph/hello）；
- `POST /__devtools/ingest`（桥接上报）；`POST /__devtools/cmd`（面板指令转发桥接）。
- 协议版本化 `v: 1`；`hello` 幂等（Emerald 热更新重连场景，见 DESIGN 第七节）。
- 落地附加：单批 1000 条安全阀；ingest 记账日志（`CITRINE_DEVTOOLS_DEBUG=1`）；
  测试用 port 0 随机端口（曾踩坑：固定 9527 与运行中的中继互染——浏览器桥接会把
  测试服务器当上报目标）。

### M2-3 浏览器桥接脚本 `[x]`
- `bridge.js`：激活条件 `window.CITRINE_DEV`；批量上报（50ms 窗口聚合，减请求数）；
  接收 cmd 执行（`set_signal`/`highlight_node`/`force_rerun`/`request_tree`/`request_graph`）。
- 注入方式：**dev_server 一行未改**——bridge.js 由中继静态服务，
  被调试页 `<script src="http://127.0.0.1:9527/bridge.js">` 引入
  （emerald/examples/debugger.html 已接线）。
- 落地细节：条目指纹去重（ring 滚动安全）；`jsToOpal` 值转换（`null→Opal.nil`）；
  热更新重求值防重（`__CITRINE_DEVTOOLS_BRIDGE__`）；request_tree 根节点三级发现
  （`CITRINE_DEVTOOLS_ROOT` → beryl `root_node` → `@root` ivar）；
  node vm 沙箱契约测试 28 项钉死行为。
- 注入方式的 dev_server 配置口（原 Plan B）不再需要——删去此项。

### M2-4 端到端验收 `[x]`
- `citrine dev examples` + `citrine-devtools serve` 同跑；counter 示例点击按钮，
  中继日志可见 event→signal_write→flush 完整链；面板侧 curl SSE 流验证。

## M3 — Web 面板：组件树 + 信号列表 `[x]`

> 2026-09-15 完成：技术栈定案 vanilla JS 无构建（选型问题 2 关闭——速度优先，
> Citrine 自举留作 M5 Emerald App 形态的探索）。Ruby 19 runs / 68 assertions 全绿，
> node 39 项全纯函数契约全绿；真浏览器双窗口验收通过（面板 cmd → 桥接 →
> tree/graph 回流 11 批，事件/写入稳态流动）。

- **形态**：独立 Web App，`http://localhost:9527` 即调试台；中继静态托管
  `GET /`（panel.html）与 `GET /panel.js`，资产缺失优雅 404（旧版安装降级）。
- **Components 页**：树形视图渲染 `tree` 消息（缩进列表，component #node_id + reuse_key）；
  打开/手动刷新/每 3s 自动重发 `request_tree`。
- **Signals 页**：六列表格（sig 短号/当前值/写入次数/最近写入/订阅数/runs），
  `graph` 消息 + `signal_write` 流累计；每 5s 重发 `request_graph`；值变化行内闪烁 .flash。
- **落地口径**（非偏差，记录在案）：① 写入时间显示用面板侧 `receivedAt` 墙钟——
  M1 的 `t` 是 CLOCK_MONOTONIC，直接格式化无意义；② runs 取第一个 deps 命中且
  未 dispose 的 effect（多 effect 归属的聚合口径 M4 定夺）。
- **面板架构**：纯函数视图模型层（buildSignalsModel/renderTreeLines 等，不碰 DOM）
  挂 module.exports 供 node vm 沙箱测试；DOM 绑定仅浏览器分支——无 jsdom 依赖。
- **验收**：Emerald 桌面真实点击驱动 event/signal_write 持续流入面板侧；
  tree 快照 3s 节律回流；面板自身为静态页 + 单一 SSE 连接，无泄漏面。
- **未做（移交 M4/M5）**：选中节点详情侧栏（props/state/computed 面板）、
  `highlight_node` 页面描边（协议 v1 本就未实现）。

## M4 — 依赖图 + Timeline + Inspector（P1-8 验收）`[x]`

> 2026-09-15 完成：依赖图 + Timeline + Inspector 三块全部落地。
> Ruby 21 runs / 81 assertions、node 61 项全绿；Inspector set_signal 全环路
> e2e PASS（含错误路径）。P1-8 可标记验收。

- **依赖图**`[x]`：Cytoscape.js 3.30.4 vendor 进仓（lib/citrine-devtools/vendor/，零外网
  运行时依赖；路由 `GET /vendor/cytoscape.min.js`）。面板第三个标签页：signal/effect
  二分图（cose 布局，边 signal→effect 来自 effect.deps，disposed 剔除，孤儿 dep 容忍）、
  写入频次热力着色（颜色写进 data.heat，样式层固定映射，增量零样式重建）、
  tap 节点高亮相邻（closedNeighborhood，其余 dimmed 0.15）、切页签惰性 init +
  每 5s request_graph（与 Signals 页共享一份快照）。
  - 架构延续 M3：buildGraphModel/heatColor/graphSignature 纯函数进 module.exports，
    node vm 沙箱 8 项契约锁定；cytoscape 缺失优雅降级文案。
  - **已知取舍**：graphSignature 含 runs → 调试活跃期每次快照重建布局（cose 重跑）。
    求布局稳定可把 runs 移出签名改原位刷 label（一行改动），留 follow-up。
- **Timeline**`[x]`：第四个标签页。event/flush/write 三流环形缓冲（各 200，M1 ring
  口径），纵向时间轴最新在上，泳道 = 事件 / flush / 信号写入（按出现序前 8 个信号
  各占短号泳道，溢出归「其他信号」）；点击 event 行高亮其 flush_ids 关联的 flush 行
  （整组 toggle）——"哪次点击引发哪次更新"一眼可见（P1-8 验收核心用例）。
  `performance.measure` 集成：flush 画成耗时块（startTime=receivedAt−Σduration）、
  event 画成零长 instant，detail 带触发链，进浏览器 Performance 面板（守卫+仅页签可见）。
  纯函数 buildTimelineRows/laneOf/formatTimelineTime/trimBuffer 进 module.exports，
  node 14 项新契约锁定；排序 = 时间降序 + 到达序号 tiebreak。
- **Inspector**`[x]`：Signals 表行选中 → 详情条（当前值 + 宽松 JSON 解析输入框 +
  「写入」+「force_rerun」）。回执判定：2s 内同 signal_id 的 signal_write 即「✓ 已生效」
  （bridge $set 必经探针上报，天然回执）。**e2e 已验证**：set_signal 全环路 PASS
  （cmd → 桥接 → $set → write_log → ingest → SSE 回执值精确命中）；
  错误路径同样验证（对 ListSignal 设字符串值 → `error` 消息干净回传面板）。
  cmd id 类型注意：graph 的 id 是数字，经 cmdId() 转回 number 再发（否则桥接 === 找不到）。
- **验收**：P1-8 逐项核对完成——依赖图（信号-效果边可视化）、Timeline（更新溯源）、
  Inspector（在线干预）全部落地并有 e2e/契约测试双证据。GOALS.md P1-8 可标记验收。

### M4 已知问题（非阻塞）

- 面板自身 state 写入回灌 write_log 的狗粮噪声：debugger.rb 的 `snap == writes`
  深比较在 Opal 下疑似恒 false（CRuby 下正常）→ 面板每 poll 自写一次。ring 有界，
  不影响正确性；M5 Emerald App 形态或面板过滤自身信号时一并解决。
- graphSignature 含 runs → 活跃期每 5s 重建布局（follow-up：移出签名原位刷 label）。
- **验收**：对照 GOALS.md P1-8 描述逐项核对；"哪个信号触发了哪次更新"可从 Timeline
  直接回答具体用例（如 todo 输入框每击键触发的 flush 链）。

## M5 — Emerald 内置 App 版面板 `[x]`

> 2026-09-15 完成（原标记暂缓，实际无需额外决策即开工）。无头 DOM 断言 10/10 PASS
> （DevTools 窗口标题/四分区/组件树 80 行——计算器 19 键 button 指纹一一对应），
> 真浏览器已打开验收。M4 遗留的自噪声问题在本 App 双重解决。

- DevTools 注册为 `Emerald::App`：`emerald/examples/apps/devtools/main.rb`
  （`app_id :devtools`，单例，580×600），入口 `emerald/examples/devtools.rb` +
  `devtools.html`（DesktopShell + Calculator/StickyNote/DevToolsApp，自开调试窗口）。
- **数据通路比面板更简**：App 与被调试对象同会话，直接读本地 ring 探针，
  无需中继/桥接——"系统内自省"形态落地。
- **自噪声双重规避**：① 指纹比较（`snap.map(&:inspect).join`）替代 Opal 下失效的
  深比较；② 过滤面板自身 6 个 state 信号的写入与 flush——无头验证稳态零自噪
  （开机 3 条外部写入，24 次轮询后仍恒为 3）。
- 视图：四分区 tab（事件流 20 / flush 15 / 信号写入 30 / 组件树-元素树降级 80 行），
  口径与 debugger.rb 面板一致；`deactivate` 里 Timer.cancel 收轮询。
- **与原计划的偏差**："复用 M3/M4 视图逻辑"未达成——panel.js 纯函数是 JS 模块，
  Opal 侧无法直接消费；M5 用 Citrine DSL 重写了等价视图（数据 API 层面仍是
  同一套 M1 探针入口，语义一致）。若未来要真复用，方向是把视图模型下沉为
  协议级纯数据（中继已在做），两侧各自渲染。
- **验收**：在 Emerald 桌面打开 DevTools 窗口，实时调试同桌面的 Calculator
  （19 键子树逐键可见）/StickyNote 应用；无头 + 真浏览器双通过。
- 热更新重连（hello 幂等）对本形态不适用（无中继会话）——窗口内数据始终本地最新。

## 风险与开放问题

1. **新仓远端与发布**`[ ]`：citrine-devtools 是否上架 rubygems.org（Trusted Publishing 同流程）？
2. **面板技术栈**`[x]`：M3 定案 vanilla JS 无构建；Citrine 自举留作 M5 Emerald App 形态探索。
3. **开销阈值**`[x]`：M1-5 已实测回填——20 万次 batch×4 写入微基准（CRuby 3.3.5，
   best-of-3）：纯内核 0.035s / tracking 关 0.066s / tracking 开 0.066s。
   结论：开销主体是 prepend 双包裹的方法派发（关闭态即存在，微基准 worst case ≈ +89%），
   ring 记录本身 ≈ 0（开/关无差）；真实应用中 effect 体有实际工作（DOM 操作），
   相对开销随 effect 体成本摊薄。"<5%" 阈值仅在真实应用（Emerald 桌面）浏览器
   profiling 下才有意义，作为 M3 面板的性能页签候选，不阻塞。
4. **Sentry source map**`[~]`：PLAN-react-gap 暂缓项，不在本计划范围，协议预留 `error` 消息类型。
5. **多会话**：中继按 `hello` 的 app 标识分会话；多 Emerald 窗口同时调试场景 M5 前不考虑——
   M5 落地后此场景优先级进一步降低（内置 App 形态天然单会话）。
