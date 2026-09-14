# Citrine ↔ React 技术栈差距：内核语义 + 元素/事件/属性面 可执行计划

- **日期**：2026-09-15
- **状态**（2026-09-15 执行后更新）：
  - **批次 1 已全部落地**（S1-2、S1-4、S1-9、S2-2、S2-4、S2-5 前半，提交 `8093a75`）；
  - **批次 2 已全部落地**（S1-1、S1-7、S1-8、S1-6、S2-1、S2-3、S2-6，提交 `da8e482` / `bcb9de5` / `bac88ac`）。
    其中 S1-7 的目标（props 未变跳过子树重渲染）由 S1-2 的 view Effect 架构天然达成，以测试锁定而非独立实现；
    S1-6 的已知边界（信号驱动的 view Effect 重跑抛错暂沿调度路径传播）记于 GOALS.md 决策日志；
    S2-3 的 drag/scroll 深度场景（拖拽语义、滚动容器判定）未含，仅覆盖事件类型接入。
  - **批次 3 已全部落地**（S1-11 `e554ef4`、S1-5 `f444245`、S2-5 后半 `dfe0d39`、S1-3 `d3e6811`、S1-10 `29e8612`）。
    S1-11 的元素代理按**位置**订阅（插入/删除导致的位置平移对元素读者可见）；S2-5 后半交付主题 token、
    CSS 文件声明（dev server 注入 + 热刷新 + 打包复制）与 css_text 逃生舱。
  - **工具链线 T-A 已全部落地**（T-A1/T-A4 `01b21d2`+`62a45db`：rake size/map_check/lint 门禁与
    Citrine/NoRawIvarAssignment cop；T-A2/T-A3 `c04f7dc`：headless Chrome 布局守卫 rake browser、
    release.yml 改 Trusted Publishing、官网断链修复）。实测 counter.min.js gzip = 118,897 bytes（预算 300KB）。
  - **工具链线 T-B1 已落地**（`447d09e`：dev server 改 Rack + Puma + Listen，行为等价经真机 curl 验证；
    gemspec 新增 rack/puma/listen 运行时依赖）。
  - **T-B2 已落地**（`7f8563a`）：选型定为隐藏 DOM 测量（不引入 Yoga）——真机按同一字体经隐藏元素
    量测文本宽度（字体回退/CJK 度量交给浏览器），无 body 环境回退 measureText；text_input 换成
    真实 <input> 覆盖层（value 信号双向绑定、中文输入法可用，无覆盖层环境回退 prompt）；
    `rake canvas_parity` 等价断言（同一 Counter 组件双渲染器：文本序列等价 / DOM·Canvas 尺寸下限 /
    列向兄弟 top 递增 / 覆盖层输入写回 Signal）并接入 CI browser job。IME 人工验收方法：
    `bin/citrine dev examples` → 打开 props_widgets.html → 用中文输入法在输入框输入候选词 →
    确认选词回车不误触发 on_enter、上屏内容与草稿一致（自动化覆盖：isComposing 守卫与
    覆盖层双向绑定已由 props_widgets 桩断言）。
  - **工具链线 T-B3 已落地**（数据层 `2287fb9`：Citrine.debug_dependency_graph 导出 signal→effect 边与重跑计数；
    生产断言 `621c44c`：rake prod_check 断言不 require citrine/debug 的产物不含埋点字符串；
    还原工具 `dcc8e3d`：Citrine::SourceMap 兼容 indexed map，端到端测试验证 Node 抛错栈位置
    可还原到 .rb 第 3 行）。剩余：Sentry 真实上报接入（需 Sentry 账号与 DSN）、Cytoscape UI。
  - **T-B4 部分验收已执行**（macOS-only 现状延伸）：本机打包 CitrineCounter.app 后以
    ad-hoc 签名（codesign --force --deep --sign -）完成 `codesign --verify --deep --strict` ✓
    （已接入 CI package job）；`spctl -a` 对 ad-hoc 产物为 rejected——Gatekeeper 正式分发
    需 Developer ID 证书签名 + 公证（外部资源）。壳选型（macOS-only / Tauri v2 / Capacitor v8）
    仍待产品决策；其余剩余：Sentry 真实上报接入与 Cytoscape UI（需外部账号/资源）、
    T-B2 IME 真机人工验收（步骤已写入上文）。
  - 验证基线：`bundle exec rake` 232 项 / 738 断言全绿；`rake stubs` 七套全绿；`rake parity`、
    `rake size`、`rake map_check`、`rake browser`、`rake canvas_parity`、`rake prod_check`、
    `rake lint` 全绿。
- **来源**：源自 2026-09-15 的两轮调研——① 「Citrine vs React 技术栈差距分析」第一、二部分（框架能力）；② 「可借用工具链」调研（构建 / 测试 / 平台运行时，三条并行线，均含本机实测）。本文档只做整理、细化与排序，不新增调研结论；调研与代码不符之处在对应条目内标注并按代码为准。
- **行号基准**：2026-09-15 的 `fix/s3-leaks-and-ssr-escaping` 分支（提交 `8dfd08a`，父提交 = main `59ad3b0`）。所有 `file:line` 按该次提交的树核对；本文档随后的改动（若有）会让行号漂移，按各条给出的符号名重新定位。
- **行号会漂移**：S3 修复正在同一工作区并行进行，行号随每次改动偏移。每条引用都同时给出符号名（方法/宏/变量），行号对不上时按符号重新定位；以 `file:line` 为准的判断只对本文档写入时刻的工作区成立。
- **仓库根**：`citrine/`。跨仓库证据（beryl）以 `../beryl/...` 标注。
- **验证命令**：`bundle exec rake`（CRuby 单测，`test/*_test.rb`）；`bundle exec rake stubs`（示例编译 + Node 桩验收）。
- **本次验证结果（2026-09-15）**：`rake test` 136 项 / 434 断言全绿（含本次新增 7 项回归）；六套 Node 桩（counter / todo / reactive_props / keyed_list + canvas 两项）全绿。S3 各项修复前后的对照数字见第五节各条。

---

## 一、内核语义缺口

### S1-1 批量更新 + 调度

**现状**：`Signal#set` 同步广播，无队列、无微任务、无事务——`@subs.dup.each(&:run)`（`lib/citrine/signal.rb:33-40`，广播在 `:38`）。全库 `grep -rniE "microtask|queueMicrotask|batch|transaction|schedul|transition" lib/` 无渲染相关实现命中（仅 `lib/citrine/dev_server.rb:94`、`:255` 的 SSE `Queue`，与渲染无关）。Roadmap 层面挂号未做：`GOALS.md:488`（P0-4「批量更新：一个 handler 改多个信号只重渲染一轮」）。

**影响**：一个 handler 改两个信号 = 两轮渲染，中间态进 DOM（FRICTION F3 / G-3）；无 startTransition、无优先级、无时间切片。

**目标语义**：同一同步执行栈内的多次 `Signal#set` 合并为一轮 Effect 重跑；合并窗口在 handler 返回后由微任务/显式 flush 关闭；跨事件边界不合并（两次独立输入各自成一轮）。外部可观察：合并窗口内 DOM 不出现中间态。

**验收标准**：
- 新增 `test/batching_test.rb`：`button(on_click: :bump)`，`bump` 内 `self.a = 1; self.b = 2`，断言该块的 Effect 重跑计数为 `1`（当前为 `2`）。
- flush 之前断言目标节点文本仍是旧值，flush 之后为新值（中间态不入 DOM）。
- 两次独立 click 各自成一轮，计数为 `2`。
- `bundle exec rake` 全绿；`bundle exec rake stubs` 六项桩（counter / todo / reactive_props / keyed_list + canvas 两项）输出不变。

### S1-2 props 不是响应式传播 ★

**现状**：子组件复用判定要求 component props 逐字相等——`lib/citrine/renderer.rb:292`（`candidate.component_identity == identity && same_props?(candidate.component_props, props)`），比较口径见 `lib/citrine/renderer.rb:321-327`（忽略 `:key` 与 Proc）。props 一变即复用失败，走新建路径 `klass.new(child_props)`：`lib/citrine/renderer.rb:134-140` → 子组件 state 从头开始、子树整体重建。该语义被测试锁定：`test/nesting_test.rb:286-306`（`:304` 断言 `NestedChild.mounts == first_mounts + 1`）。组件侧只有「重传即覆盖」的 `update_props`：`lib/citrine/component.rb:240-254`；代码注释已预告升级方向：`lib/citrine/component.rb:239`、`test/nesting_test.rb:291`。Roadmap 记为待做：`GOALS.md:480-483`。

**影响**：React 最核心的「父更新 → 子更新且保留状态」不存在；父块每跑一次，props 相等的子组件幸存、不相等的整体重建（state、焦点、滚动位置、Effect 订阅全丢）。beryl 只能立法则「交互态必须受控」绕开——即把交互态提到 props 里，避免子组件持有状态。

**目标语义**：prop 值变化时子组件实例与 state 保留，只有真正读取该 prop 的块/属性 Effect 重跑（prop 升级为信号：读它才订阅）。

**验收标准**：
- `test/nesting_test.rb:286` 的期望反转并改名：props 变化后 `NestedChild.mounts` 不变、`NestedChild.unmounts` 不变。
- 状态保留可观察：子组件持 `state :clicks`，父改 props 后断言子组件 `clicks` 未被重置。
- 只有读了该 prop 的块重跑：同层兄弟块的块 Effect 重跑计数为 `0`。
- 新增 `test/props_signal_test.rb`（或并入 `test/nesting_test.rb`）；`bundle exec rake` 全绿。

### S1-3 Context / 依赖注入

**现状**：无实现。全库 `grep -rniE "provide|inject|Context" lib/` 无框架语义命中——仅 `lib/citrine/canvas.rb:38` 的 canvas `getContext("2d")` 与 `lib/citrine/dev_server.rb:196`、`:242` 的 `inject_client`，均与依赖注入无关。

**影响**：跨层传值只能 prop drilling 或全局单例。

**目标语义**：祖先声明的值可在任意后代组件读取；值变化时只有读它的后代重跑；不做继承之外的隐式行为（找不到 provider 时显式报错而非静默 nil）。

**验收标准**：三层组件，中间层不声明也不转发，末层读到祖先值；祖先改值后断言中间层块重跑计数 `0`、末层 `1`；SSR 下读到同一初值；缺 provider 时 `raise` 可断言。`bundle exec rake` 全绿。

### S1-4 插槽 / children / fragment

**现状**：`render(Child) { ... }` 直接报错——`lib/citrine/component.rb:315-316`（`raise ArgumentError, "render 暂不支持 block（子组件插槽留待 S3）"`）。子组件 view 必须恰好一个根节点——`lib/citrine/renderer.rb:144-153`（`:149-152` 抛「必须渲染**恰好一个**根节点」）。beryl 用 `content:` Proc prop 代替插槽：`../beryl/lib/beryl/tabs.rb:5`、`../beryl/lib/beryl/dialog.rb:59`。

**影响**：容器组件写不了；多根或纯文本必须手工包一层 `stack { }`；父无法把自己的渲染内容交给子布局。

**目标语义**：`render(Child) { ... }` 的块延迟到子组件渲染该位置时求值，作为 children；子组件多根输出不再报错，按 fragment 处理（复用/销毁单位仍是组件实例）。

**验收标准**：子组件内可取用 children 并落位（断言父传块的输出出现在子组件布局内部）；父块重跑时 children 原地更新，兄弟节点 DOM 不变；多根子组件（两个 `stack`）不抛错，卸载后 `DisposeCount == 0 残留`（断言两个根都被 detach）。`bundle exec rake` 全绿。

### S1-5 Portal

**现状**：无实现。全库 `grep -rni portal lib/` 零命中。beryl 的弹层只能靠 z-index 堆叠：`../beryl/lib/beryl/feedback.rb:20`、`../beryl/lib/beryl/overlay.rb:73`、`../beryl/lib/beryl/window.rb:19`（另有 `../beryl/lib/beryl/window.rb:121` 的 `style[:z_index]` 赋值）。

**影响**：弹层/下拉逃不出父容器 `overflow` 与层叠上下文，只能靠不断加码的 z-index。

**目标语义**：把一个子树挂到渲染器指定的宿主节点（默认 `body`），复用、Effect、生命周期语义与原地渲染一致；卸载时宿主节点内容清理干净。

**验收标准**：断言 portal 节点的 `parentElement` 是宿主节点而非父容器；父容器 `overflow: hidden` 下 DOM 结构断言成立（不依赖真机渲染）；卸载后宿主节点子节点数回到 `0`。`bundle exec rake` 全绿。

### S1-6 错误边界

**现状**：渲染器内零 rescue——`grep -n rescue lib/citrine/renderer.rb` 零命中。块内抛错直接穿出赋值点（`lib/citrine/component.rb:419-423` 的 `emit` → `lib/citrine/renderer.rb:71` 的 `mount`），而旧节点已经在 `run_block` 的 `ensure` 里被 dispose：`lib/citrine/renderer.rb:254-258`（`:257` `pool.unused_nodes.each { |old| dispose(old) }`）。

**影响**：一次渲染异常 = 页面半更新（旧节点已拆、新节点未建）且无人兜底。

**目标语义**：组件可声明边界；子组件渲染抛错时由边界组件渲染兜底内容，异常对象交给兜底分支；失败那一轮不留半更新（能保留的旧节点保留）。

**验收标准**：新增 `test/error_boundary_test.rb`：子组件 view 抛错 → 断言父渲染出兜底文案、子组件 DOM 未残留；断言子组件的 `on_unmount` 未被额外触发一次（错误路径不应伪装成正常卸载）；无边界时异常仍按现状穿出（对照断言）。`bundle exec rake` 全绿。

### S1-7 memo / 浅比较跳过

**现状**：复用门槛只有 props 相等——`lib/citrine/renderer.rb:290-297`（组件槽位 `:292`）与 `:321-327`；父块重跑必然重跑每个子组件 view：`lib/citrine/renderer.rb:131`（`refresh_component_view`）→ `:170-191` 每次都重跑 view。比较时 Proc 被排除（`:319-320` 注明「S2 会让它们真正参与更新」）。

**影响**：父块重跑 = 每个子组件 view 重跑，没有「props 未变则跳过子树重渲染」的短路。

**目标语义**：props 浅比较未变、且组件自身无内部信号变化时，跳过该子组件的 view 重跑；比较口径沿用排除 `:key` 与 Proc 的既有规则。

**验收标准**：父块重跑但子组件 props 未变 → 断言子组件 view 调用计数 `0`（类级计数器）；props 变了 → 计数 `1`；传入新的 Proc 对象不导致误判为变更（计数仍 `0`）。`bundle exec rake` 全绿。

### S1-8 effect / watch 宏、Effect cleanup

**现状**（与调研原文有出入，按代码核实）：`watch` 宏**已落地**，不是缺口——类宏 `lib/citrine/component.rb:155-157`、`watch_defs` `:160-162`、运行/释放 `:373-387`、诊断计数 `:390`；渲染器挂载路径调用 `lib/citrine/renderer.rb:50`、`:139`；测试 `test/watch_test.rb`（119 行）；决策记录 `GOALS.md:470`。真实缺口是两项：(a) 无通用 `effect` 宏——`grep -rn "def effect\b" lib/` 零命中；(b) `Effect.create` 只收 block、无清理回调——`lib/citrine/signal.rb:77-81`，清理只能靠组件级 `on_unmount`（`lib/citrine/component.rb:139-141`）或手工 `Effect#dispose`（`lib/citrine/signal.rb:104-110`）。`GOALS.md:484-485`（P0-2）仍把 `effect` 列为承诺项。

**影响**：细粒度副作用只能挂组件级钩子；Effect 内部申请的资源（定时器、原生监听、订阅）没有「随该 Effect 重跑而清理」的位置，只能在组件卸载时统一清。

**目标语义**：`effect { ... }` 与 `watch` 同构但可在组件内多处声明，且可声明 cleanup：每次重跑前与组件卸载时各执行一次 cleanup。

**验收标准**：断言 Effect 重跑前 cleanup 计数 +1；卸载时 cleanup 再 +1，且后续对依赖信号的写入不再触发该块；SSR 下不创建（与 `test/watch_test.rb` 的“SSR 不创建 watcher”断言同构）。`bundle exec rake` 全绿。

### S1-9 组件 ref

**现状**：`render(Child, ref: :x)` 不可用。ref 只在元素挂载路径登记——`lib/citrine/renderer.rb:83`（`mount` 内调用 `register_ref`）→ `:442-447`；`render_component` 全程不调用（`lib/citrine/renderer.rb:120-141`）。组件的 `:ref` 反而被当普通 prop 透传：`lib/citrine/renderer.rb:125` 只剔除 `:key`，于是子组件构造/更新时抛「未声明的 prop: ref」（`lib/citrine/component.rb:203` 与复用路径 `:243`）。

**影响**：父拿不到子实例，父调子方法只能绕内部字段（FRICTION F25）。

**目标语义**：`ref:` 语义为「登记实例」而非 prop；父经 `refs` 取到子组件实例并调用其公开方法；元素 ref 行为不变。

**验收标准**：`render(Child, ref: :child)` 不抛错且 `refs[:child]` 是子组件实例（`is_a?(Child)`）；子组件重建（props 变化或无 key 换位）后 `refs` 指向新实例；现有元素 ref 测试不回归。`bundle exec rake` 全绿。

### S1-10 异步渲染

**现状**：无实现。全库 `grep -rniE "lazy|suspense|async|await" lib/` 无框架语义命中（`lib/citrine/signal.rb:43` 的 `lazy?` 是 Signal 惰性初值，`lib/citrine/list_signal.rb:60` 的 `fetch` 是集合读方法，均非异步渲染）；无代码分割、无数据请求层。

**影响**：加载态全靠手写条件分支，组件实例在「加载完」时会重建。

**目标语义**：子树可声明依赖未就绪并渲染占位；就绪后原地切换到真实内容，组件实例与 state 保留。

**验收标准**：占位内容断言 + 就绪后真实内容断言；断言该组件 `on_mount` 只跑一次、`state` 值保留。`bundle exec rake` 全绿。

### S1-11 集合深响应

**现状**：`ListSignal` 只有集合级通知，元素内部改动静默无效——现状边界写在类注释里：`lib/citrine/list_signal.rb:22-23`（`rows.get[0][:n] = 1` 不会触发）；`get` 返回冻结快照 `lib/citrine/list_signal.rb:38-40`；触发路径仍只有 `Signal#set`（`lib/citrine/signal.rb:33-40`）。

**影响**：改一个元素的内部字段要么静默无效，要么被迫整表替换。

**目标语义**：元素级写入触发订阅该元素的块重跑（不整表重建）；集合结构变更仍走集合级通知。

**验收标准**：`list[0][:n] = 1` 后断言读取该元素的块重跑 `1` 次、读取其他元素的块 `0` 次；`list.get << x` 仍抛 `FrozenError`（不回归 `lib/citrine/list_signal.rb:38-40` 的防呆）。`bundle exec rake` 全绿。

---

## 二、元素 / 事件 / 属性面缺口

### S2-1 元素词表 + 自定义标签逃生舱

**现状**：词表只有 5 项——`lib/citrine/renderer.rb:14-15`（`box/label/button/text_input/check_box`）；DSL 方法对应 `lib/citrine/component.rb:275-306`，方法名白名单 `lib/citrine/component.rb:28`。无 `a/img/ul/li/table/form/select/textarea/svg`。逃生舱只到渲染层：`TAGS[type] || type.to_s` 兜底存在（DOM 侧 `lib/citrine/dom.rb:35`，SSR 侧 `lib/citrine/string_renderer.rb:50-57` 的 `serialize`，兜底在 `:51`），但组件层无公开入口——`emit` 是 private（`lib/citrine/component.rb:405` 的 `private`，`def emit` 在 `:419`）。

**影响**：语义化结构与表单控件只能靠 `box`/`label` 模拟；组件作者无法直接产出任意标签，必须改框架源码或绕私有 `emit`。

**目标语义**：DSL 覆盖常用 HTML 元素；提供显式逃生舱（任意标签名）走既有兜底路径；DOM 与 SSR 两侧输出一致。

**验收标准**：`ul/li/a/img` 渲染出正确标签且可挂事件（DOM 侧断言 `tagName`，SSR 侧断言字符串）；逃生舱 `element(:my_widget)` 在 DOM 与 SSR 两侧分别产出对应标签；`bundle exec rake stubs` 增加对应桩断言。`bundle exec rake` 全绿。

### S2-2 属性透传

**现状**：DOM 只认 `css_class`/`placeholder`/`style`——`lib/citrine/dom.rb:48-61`；`grep -nE "\[:id\]|disabled|aria|dataset|title" lib/citrine/dom.rb` 零命中。SSR 只输出 `class`/`type`/`placeholder`/`value`/`checked`/`style`——`lib/citrine/string_renderer.rb:60-82`。属性白名单在 `lib/citrine/renderer.rb:26-29`（响应式）与 `:28-29`（值类），值类 prop 收到 Proc 只提醒不求值（`lib/citrine/renderer.rb:394-408`）。

**影响**：`id`/`disabled`/`aria-*`/`data-*`/`title` 静默丢弃（FRICTION F11）；无障碍、E2E 选择器、原生表单语义全部缺位，连「禁用按钮」都表达不了。

**目标语义**：框架未消费的属性原样透传到 DOM 与 SSR；布尔与 nil 规则明确（`false`/`nil` 不输出，`true` 输出空值属性）；属性名 snake_case → kebab-case（`aria_label` → `aria-label`）。

**验收标准**：`button(disabled: true, aria_label: "提交", data_role: "primary", id: "ok")` 断言 DOM 属性与 SSR 字符串均出现 `disabled`/`aria-label`/`data-role`/`id`；`disabled: false` 断言属性不存在；未知属性不再被静默丢弃（对照当前行为写回归断言）。`bundle exec rake` 全绿。

### S2-3 事件面 + 统一事件对象 + window_key 作用域

**现状**：支持集只有 click/keydown/focus/blur（`lib/citrine/dom.rb:71-89`）+ text_input 的 on_enter（`:91-95`）+ check_box 的 on_change（`:96-99`）。无 hover/dblclick/contextmenu/wheel/scroll/drag/touch/pointer/submit/paste/IME composition——`grep -rniE "hover|dblclick|contextmenu|wheel|scroll|drag|touch|pointer|submit|paste|composition|mouse" lib/` 零命中。无事件委托：每个元素各自 `addEventListener`（`lib/citrine/dom.rb:102-108`）。click/focus/blur 直接把原生事件漏给组件（`:74-89` 内的 `Native(event)`），只有键盘有平台无关视图（`lib/citrine/dom.rb:128-134` → `lib/citrine/key_event.rb`）。`KeyEvent` 无 `stopPropagation`：`lib/citrine/key_event.rb` 全文 39 行只有 `prevent_default`（`:31-34`）。`window_key` 无焦点作用域：`lib/citrine/dom.rb:111-117` 直接 `window.addEventListener("keydown", ...)`，不看 `document.activeElement`。

**影响**：富交互（悬停、右键菜单、滚轮、拖拽、指针、粘贴、表单提交）无法表达；组件代码里混入平台原生事件对象，CRuby 侧测不了（只有键盘例外）；同页多组件声明 `window_key` 时会同时响应；无法阻止事件继续传播。

**目标语义**：事件对象平台无关（DOM/Canvas/CRuby 单测同一套断言，原生细节走 `raw`）；事件面覆盖上述类型；`window_key` 可声明作用域（焦点在组件内才响应）；提供 `stop_propagation`。

**验收标准**：用合成事件在 CRuby 单测中断言 handler 收到的不是 `Native`（`refute_kind_of Native` 或断言其为 `Citrine::Event`/`KeyEvent`）；`ev.stop_propagation` 后断言后续派发不再到达外层处理器；两个组件各声明 `window_key`，焦点在 A 时只有 A 的计数 +1（当前两边都 +1）；新增事件类型各有 1 条桩断言。`bundle exec rake` 全绿。

### S2-4 受控语义一致 + IME

**现状**：`text_input` 双向绑定——`lib/citrine/dom.rb:147-159`（Signal → DOM 在 `:152`，DOM input → Signal 在 `:153`）。`check_box` 只读不回写——`lib/citrine/dom.rb:161-172`（`:165-170` 读 Signal），其 change 只把 `node.dom[:checked]` 交给 handler（`lib/citrine/dom.rb:96-99`），不写回 Signal。IME：无 `isComposing` 判据（`grep -rni isComposing lib/` 零命中），`:91-95` 只判 `ev[:key] == "Enter"`。

**影响**：`check_box(checked: signal(:x), on_change: ...)` 勾选后信号不更新，受控语义名不副实，用户必须自己写回；中文输入法选词回车误触发 `on_enter`。

**目标语义**：`checked` 传 Signal 时为真正的受控双向绑定（与 `text_input` 对称）；Enter 在 IME 组合过程中不触发 `on_enter`。

**验收标准**：断言 DOM 侧改变勾选并派发 change 后 `Signal#get == true`（当前不写回）；合成 `isComposing: true` 的 Enter keydown 断言 `on_enter` 计数 `0`，`isComposing: false` 计数 `1`；`text_input` 现有双向绑定测试不回归。`bundle exec rake` 全绿。

### S2-5 样式：单位推断、CSS 文件、主题 token

**现状**：`PX_PROPERTIES`（`lib/citrine/style.rb:14-19`）与 `UNITLESS_PROPERTIES`（`:22-25`）都不含 `font_size` → `font_size: 14` 不会被补单位；SSR 直接拼值输出（`lib/citrine/string_renderer.rb:84-88`）→ 产出 `font-size:14`，非法 CSS。无 CSS 文件加载/打包：`grep -rniE "stylesheet|\.css" lib/` 除开发服务器 overlay（`lib/citrine/dev_server.rb:34` 的 `style.cssText`）外零命中。无主题 token、无媒体查询/伪类原语：`grep -rniE "media|hover|pseudo" lib/` 零命中。

**影响**：SSR 输出非法 CSS（浏览器整条声明丢弃，DOM 侧与 SSR 侧不一致）；样式只能内联，媒体查询、伪类、主题切换无法表达。

**目标语义**：px 推断覆盖有单位默认的长尾键（含 `font_size`）并有测试；能加载 CSS 文件（开发服务器与打包路径）；提供主题 token / 媒体查询 / 伪类的原语或明确逃生舱。

**落地拆分**：单位推断（`font_size` 等）是独立小改动，进批次 1；CSS 文件加载与 token / 媒体查询 / 伪类依赖元素与属性面（S2-1、S2-2），进批次 3。

**验收标准**：断言 `Style.normalize({ font_size: 14 }) == { font_size: "14px" }`；SSR 输出含 `font-size:14px`；`font_size: "1.2em"` 不被改写；新增样式测试与既有 `test/render_test.rb` 样式断言全绿。

### S2-6 焦点 / IME / ARIA 原语

**现状**：citrine 内核 `grep -rniE "aria|tabindex" lib/` 零命中；自动聚焦、焦点陷阱、焦点恢复均无原语。beryl 自研了一套 L1 扩展：`../beryl/lib/beryl/renderer.rb:230-241`（`setup_tabindex` / `setup_autofocus`），注册点在 `../beryl/lib/beryl/renderer.rb:40-41`。

**影响**：焦点与无障碍能力由每个应用各自重造（beryl 已重造一份），跨应用不可复用。

**目标语义**：`tabindex`/`autofocus`/`aria_*` 作为一等属性透传（与 S2-2 同一机制），并提供最小焦点原语（挂载后聚焦、卸载时恢复上一焦点）。

**验收标准**：断言 DOM 属性存在（`tabindex`/`aria-*`）；`autofocus: true` 挂载后焦点落在该元素、卸载后回到挂载前的活动元素；新增焦点测试在 CRuby 单测与 Node 桩两端行为一致。验收标准不涉及改动 beryl。

---

## 三、工具链可直接借用项

> 来源：2026-09-15 的「可借用工具链」调研（三条并行调研线，均在本机对 Citrine 自身产物与示例实测）；探针与报告见工作区 `../artifacts/quality-tooling/REPORT.md` 与 `probes/`。
> 与第一、二节的关系：S1/S2 是**框架能力**缺口，本节是**工程链路**缺口——同一件事（构建、测试、发布、Canvas、桌面壳）业界已有成熟件，能借则不自研。
> 字段：**现状 / 采用什么 / 实测数据 / 坑与前置 / 验收标准**。负面结论（不推荐项）直接写进各自的「坑与前置」，不单列。

### T-A 立即采用（零风险，当天可做）

#### T-A1 产物体积：Opal 自带开关 + 通用 JS 压缩器

**现状**：开发现场编译与示例构建都在手写 `opal -c -I... -o x.js x.rb`（`Rakefile:11-25`、`bin/citrine`、`lib/citrine/dev_server.rb:202-225`），产物默认**内联 base64 source map**——本机编译 `examples/counter.rb` 得到的单文件在 2.4MB 量级，其中约 63% 是这份内联 map。

**采用什么**：① `--no-source-map`（需要调试时用 `-P` 单独产出外置 map）；② 把产物交给 esbuild（或 terser）做 `--minify`；③ 需要缓存粒度时用 `-O` 把 runtime 与 app 拆成两份；④ 加 `-A/--arity-check`。

**实测数据**（本机 Opal 1.8.3 / esbuild 0.28.2，`examples/counter.rb` 同源编译）：

| 编译方式 | raw | gzip |
|---|---|---|
| 现状（默认内联 map） | 2,420,313 | 607,598 |
| `--no-source-map` | 896,297 | **164,044** |
| 再 `esbuild --minify --target=es2015` | 395,538 | **111,336** |
| `-O` 拆 runtime/app + 各自 minify | 322,534 + 76,197 | 91,245 + 21,196（合计 112,441） |

- 63% 的原始体积是内联 map；GOALS P1 的目标「gzip < 300KB」**当前就已达成**（164KB），只是没人发现。
- 拆 runtime/app 的价值在**缓存**（runtime 跨发版稳定、可独立发版），**不在总量**——合计 gzip 与单文件几乎相同（112KB vs 111KB）。
- `-A/--arity-check` 本机实测把「Opal 多传实参静默丢弃」（`README.md` 陷阱 10 / FRICTION G-12）变成真报错：`ArgumentError: [Object#f] wrong number of arguments (given 2, expected 1)`。
- 等价性已验证：`examples/num_parity.rb` 的 34 行输出在未压缩 / esbuild / terser 三种形态下逐字节一致；minified 产物通过 `node --check`。

**坑与前置**：minifier 必须显式开启「读取输入 source map」（esbuild `--sourcemap=external`、terser `--source-map content=inline`），否则 map 会**静默丢失**（`sources` 退化成 `["nomap.js"]`）；`--target=es5` 与 es2015 体积几乎无差（Hermes 路线安全）；`-A` 会改变运行时行为（把静默截断变成抛错），建议开发模式与 CI 打开、生产按需评估。

**验收标准**：`rake stubs` 的六套产物 gzip ≤ 300KB 且六套桩全绿；CI 断言产物中存在 source map 且 `sources` 含 `.rb`；打开 `-A` 后现有示例仍全绿（若报错，说明是真违例而非误报）。

#### T-A2 浏览器端测试：手写 Node 桩可以整体退休

**现状**：`test/*_test.rb` 136 项 CRuby 单测 + `examples/stub_check.js` / `canvas_stub_check.js` 手写 DOM/Canvas 桩；桩里没有布局引擎——F23 记录过两次「容器塌成 2px 而 96 项断言全绿」，只能靠 headless Chrome 截图才看出来。

**采用什么**：① `opal-rspec`（chrome runner）做组件级真浏览器断言；② `Cuprite` + Capybara（+ `chunky_png`）做页面级装配、量尺寸、点击、截图与像素回归；③ 浏览器侧覆盖率用 CDP `Profiler.startPreciseCoverage`（Cuprite 可发任意 CDP 命令）。

**实测数据**（探针见 `../artifacts/quality-tooling/probes/opal_rspec/`、`probes/cuprite/`）：

- opal-rspec 用真实 `Counter` 组件跑通：`root=380x220`（**真实布局**）、`TOPS=[8,8]`（同层兄弟被排成一行——F23 那类事故的可自动判据）；失败时 EXIT=1，backtrace 经 source map 直指 `.rb` 行号。
- Cuprite 加载 `examples/counter.html`：点击后 `count = 1`；`initial vs reset = 0px`（Canvas 示例要的「重置后逐位一致」同款断言）；`browser.page.command(...)` 可发任意 CDP 命令（实测通了 `Profiler.startPreciseCoverage` 与 `Performance.getMetrics`）。

**坑与前置**：**RubyGems 上的 `opal-rspec 1.0.0` 不可用**（收尾必崩、`--format` 三种都救不了、恒返回 EXIT=1 → CI 不可用），必须用 master：Gemfile 用 `path:` 指向带 submodule 的 clone（`github:` 装不上）；CI 需 Chrome 与 `CHROME_OPTS=--no-sandbox`，浏览器 job 先固定单个 Ruby 版本（Opal 1.8.3 + Ruby 4.0 组合未验证）。**jsdom 实测跑不起 Opal 产物**（`undefined method '[]=' for nil`）且官方 README 明写布局未实现 → 不要走这条路。Cuprite 截图前必须「移开鼠标 + blur」，否则 UA 的 `:hover`/`:focus` 会带来假差异（实测 1029px）。

**验收标准**：新增 `spec-opal/` 至少含两条布局守卫（挂载后容器尺寸 > 0；同层兄弟 `top` 不相等）；页面级 smoke 每个示例一条（加载 → 文本 → 量尺寸 → 点击 → 截图）；CI 增加 `browser` job。

#### T-A3 发布：`rake release` + RubyGems Trusted Publishing

**现状**：`.github/workflows/release.yml` 手写 `gem build` + `gem push`，依赖 `RUBYGEMS_API_KEY` secret；GOALS 记录「gem 0.1.1 已构建未发布，等 secret」正是当前卡点；无 CHANGELOG。

**采用什么**：Rakefile 接 `bundler/gem_tasks`（`bundler` 自带的 `rake release`：构建、打 tag、推送）；CI 改用 RubyGems **Trusted Publishing**（OIDC：`permissions: id-token: write` + `rubygems/release-gem@v1`），不需要任何长驻密钥。

**坑与前置**：先在 rubygems.org 建 trusted publisher（绑定 owner/repo/workflow/environment）；CHANGELOG 可后补（`git-cliff` 或 `release-please`，后者要求 Conventional Commits）。

**验收标准**：打 `v*` 标签后 workflow 在**无 secret**的情况下完成发布，`gem install citrine` 可安装（同时修掉官网 quickstart 指向未发布 gem 的断链）。

#### T-A4 Lint 与框架专属 cop（把「约定」变成 CI 门禁）

**现状**：全仓无 rubocop/standard；GOALS 第七节「代价清单」第 1 条写明「裸 `@var` 赋值绕过追踪」只能靠「约定 + lint 缓解」，而 lint 从未落地。

**采用什么**：RuboCop（+ `rubocop-performance`）+ 一个自定义 cop 拦 `Citrine::Component` 子类里的裸 `@ivar` 赋值（AST `ivasgn`）；顺带 Prettier 管 html/css、SwiftFormat 管 `desktop/main.swift`。

**实测数据**：探针实现约 20 行，在真实 `examples/`（5 个组件）上 **0 误报**、fixture 命中 1 处、普通类不误报（`../artifacts/quality-tooling/probes/rubocop/`）。

**坑与前置**：必须设 `TargetRubyVersion: 3.1`（否则无括号 `def tick = …` 报 61 个解析错误）并 Exclude `lib/citrine/**`（框架内部本来就要直接写 ivar）；cop 只拦写入，裸读与「纯 computed 里的读」仍拦不住。

**验收标准**：CI 跑 rubocop 全绿；故意写一个 `@count = 1` 的组件，断言 cop 命中。落地后 GOALS 第七节那句「约定 + lint 缓解」可改为「已由 `Citrine/NoRawIvarAssignment` 强制」。

### T-B 需要适配层（要包一层）

#### T-B1 dev server 瘦身（约 220 行 → 约 50 行）

**现状**：`lib/citrine/dev_server.rb` 自建五件事——socket 静态服务与 `CONTENT_TYPES`（`:19-26`）、`*.js` 现场编译 + mtime 缓存（`:202-225`）、0.3s 轮询监听（`:127-154`）、SSE 整页刷新（`:28-50`、`:250-265`）、编译错误浮层。

**可替换**：静态服务/路由 → `rackup` + `puma` + `Rack::Files`（或 Opal 自带的 `Opal::SimpleServer` Rack app）；文件监听 → `listen`（Opal 与 opal-rails 的 `opal:watch` 都用它）；整页刷新 → browser-sync 或 `vite-plugin-full-reload`。
**不可替换**：编译错误浮层（Rack 侧没有等价物，Vite 侧才有内置 overlay）——那约 30 行保留。

**坑与前置**：`opal -R server` 调 `Rack::Server`，而 Rack 3 已把它抽成独立 gem → 不要走 CLI runner，直接在 `config.ru` 里 `run Opal::SimpleServer.new`；`Rack::Static` 有 LFI 历史（CVE-2025-27610）→ 本地开发可用，对外服务要固定 root + 扩展名白名单；**`opal --watch` 实测不生效**（两次改文件都不触发重建）→ 监听必须自己接 `listen`；`rack-livereload` 已停更且锁 `rack < 3.2`，不用。

**验收标准**：删掉 socket 路由/缓存/轮询后，`citrine dev` 行为等价（热刷新、错误浮层、`-I` 额外加载路径），`test/dev_server_test.rb` 8 项全绿。

#### T-B2 Canvas 渲染器：自研的四件事业界都有

**现状**：`canvas.rb` 自研线性 stack/flow 布局（无交叉轴对齐、无文本换行）、包围盒命中检测、全量重绘、单行 `measureText`、输入用 `window.prompt`。

| 自研件 | 可替换 | 代价 |
|---|---|---|
| 布局 | **隐藏 DOM 测量**（0KB；白送 flexbox/Grid/换行/字体回退，复用 `style.rb` 语义）或 **Yoga**（官方 wasm 118KB / gzip 51KB） | 重写约 100 行；DOM 方案有 reflow 成本 |
| 命中检测 + 重绘 | **Konva**（gzip 55KB；内置命中/冒泡/拖拽/Layer 分层） | 新增一个渲染器实现（约 300 行）+ Opal↔JS 桥接 |
| 文本换行 | **`Intl.Segmenter` + `measureText` 贪心断行**（0 依赖，解决中英混排） | 约 50 行 |
| 文本输入 | **canvas 上叠一个真实 DOM `<input>`** | 极低（定位同步） |
| 蜡烛图（market-terminal） | **ECharts**（官方源码含 candlestick） | 一次数据流桥接 |

**坑与前置**：换图形库**不需要改渲染架构**——重绘已封在 `finalize→redraw` 一个钩子里，块级 Effect 与场景图天然同构；Yoga 的 npm 包自 2024-12 未再发版且不支持 Grid（要用 Grid 得走 Taffy，但它的 JS 绑定是社区件）；canvas 上的 webfont 必须 `await document.fonts.load(...)` 后强制重测，否则字形晚到导致位置错。

**验收标准**：同一份 `examples/components.rb` 在 DOM 与 Canvas 两侧产出等价结构断言；新增「容器尺寸下限 + 同层兄弟 `top` 不等」布局守卫；文本输入换成真实 `<input>` 后中文输入法可用（人工验收一条）。

#### T-B3 DevTools 与可观测性

**现状**：无 DevTools；GOALS P1-8 的「信号依赖图可视化」未实现；线上错误无法还原到 `.rb`（没有 map 上传链路）。

**可借**：依赖图 UI → **Cytoscape.js**（gzip 134KB；`compound nodes` 正好对应 signal→effect 层级）；时序 → Chrome 官方 **Performance Extensibility API**（`performance.measure` 自定义泳道，Performance 面板按信号名分轨）；整体形态照抄 **solid-devtools**（同为信号框架 + 依赖图 + 浏览器扩展）；错误上报 → **Sentry**（Opal 未捕获异常实测是真 `Error` 实例、有 stack、message 是 Ruby 消息，能吃）；性能指标 → `web-vitals`。

**坑与前置**：拓扑数据**必须自建埋点**（CDP 不知道「哪个 Signal 依赖哪个 Effect」），埋点要能在生产编译期关闭；Sentry 走 `sentry-cli` 上传 map，但 Opal 产出的是 **indexed source map**，官方未明确说支持 → 先做半天 spike，退路是手工扁平化；先把埋点数据跑通、UI 晚一步，否则会返工。

**验收标准**：依赖图数据（JSON）可导出，含 signal→effect 边与重跑计数；生产构建产物中不含埋点字符串（可用断言）；Sentry 能把一条测试异常还原到 `.rb` 行号。

#### T-B4 桌面 / 移动壳

**现状**：`desktop/main.swift` 约 55 行 WKWebView 壳 + `lib/citrine/packager.rb` 只产 macOS `.app`；无签名/公证/图标/多架构；Windows/Linux/移动端未做。

**可借**：跨平台（含移动）→ **Tauri v2**（一栈出 macOS/Windows/Linux + iOS/Android，官方 updater，代价是**强制 Rust 工具链**）；只要移动端 → **Capacitor v8**（Node + Xcode/Android Studio，不需 Rust）；只发 macOS → 保留 Swift 壳 + `create-dmg` + `notarytool`/`stapler`（成本最低）。

**坑与前置**：Tauri 的移动端要 Xcode / Android SDK+NDK / rustup targets 进 CI，工程复杂度跳变；Apple 审核指南 4.2（Minimum Functionality）对「网站套壳」有拒审风险，纯 webview 上架 iOS 需准备理由；签名与公证**与壳选型无关**，是必须一次性投入的合规成本；Hotwire Native 面向服务端渲染的 Rails 应用、Capacitor 不含桌面——都不要当桌面方案。

**验收标准**：产物在目标平台可安装启动；macOS 路径过 `codesign --verify` 与 `spctl -a`；CI 的打包冒烟 job 覆盖新壳。

### T-C 落地顺序（与 S1/S2 批次并行）

| 顺序 | 项 | 依赖 | 规模 |
|---|---|---|---|
| D1 | T-A1 产物体积 + T-A2 浏览器测试骨架（先落两条布局守卫） | 无——改的是构建/测试基座，越早越省返工 | S |
| D2 | T-A3 发布 + T-A4 lint/cop | 无 | S |
| D3 | T-B1 dev server 瘦身 | T-A2（有了浏览器 smoke 才敢动开发工具） | M |
| D4 | T-B2 Canvas 布局选型 spike（隐藏 DOM 测量 vs Yoga，二选一） | 无，可与 S1/S2 并行 | M |
| D5 | T-B3 DevTools（先埋点、后 UI） | S1-1（批量更新落地后重跑计数才有稳定语义） | M |
| D6 | T-B4 壳方案 | 产品先决定是否跨平台 | M–L |

**与 S1/S2 的关系**：两串并行、互不阻塞。但有一条硬顺序——**T-A 全部先于 S2-2（属性透传）**：属性面从 3 个扩到 20+ 个会同步放大每次属性写入与每次节点创建的代价，先把体积、测试与静态检查的基座铺好，再扩张属性面，能省一轮返工。

---

## 四、优先级与依赖

| 编号 | 条目 | 依赖 | 建议批次 | 预估规模 |
|---|---|---|---|---|
| S1-2 | props 响应式传播 ★ | 无（与 S3-4/S3-5 同属复用路径，宜在其后立刻做） | 1 | M |
| S1-4 | 插槽 / children / fragment | S1-2（children 的更新依赖 props/块的响应传播） | 1 | L |
| S1-9 | 组件 ref | S1-2（实例复用语义稳定后 ref 才有意义） | 1 | S |
| S2-2 | 属性透传 | 无 | 1 | S |
| S2-4 | 受控语义一致 + IME | 无 | 1 | S |
| S2-5 | 样式：单位推断子项（`font_size`）——本条前半 | 无 | 1 | S |
| S1-1 | 批量更新 + 调度 | S3-1 / S3-2 先落地（改调度前需要 Effect 生命周期与卸载路径稳定） | 2 | M |
| S1-7 | memo / 浅比较跳过 | S1-2 | 2 | S |
| S1-8 | `effect` 宏 + Effect cleanup | S3-1（同一套 dispose/释放机制，先例已存在） | 2 | S |
| S1-6 | 错误边界 | S1-1（需要「一轮渲染 = 一个可回滚单元」）、S1-4 | 2 | M |
| S2-1 | 元素词表 + 逃生舱 | S2-2（新元素要能带 `href`/`src`/`value` 等属性才有用） | 2 | M |
| S2-3 | 事件面 + 统一事件对象 + window_key 作用域 | S2-1（submit/paste/pointer 等新事件类型随元素面一起才有落点）；作用域与 `stop_propagation` 子项可提前到批次 1 | 2 | M |
| S2-6 | 焦点 / ARIA 原语 | S2-2、S2-3 | 2 | S |
| S2-5 | 样式：CSS 文件加载 + 主题 token / 媒体查询伪类——本条后半 | S2-1、S2-2 | 3 | M |
| S1-3 | Context / 依赖注入 | S1-2、S1-4 | 3 | L |
| S1-11 | 集合深响应 | S1-1（元素级通知不加合并会退化为多轮重渲染） | 3 | M |
| S1-5 | Portal | S1-4、S2-1、S2-2 | 3 | M |
| S1-10 | 异步渲染 | S1-1、S1-6、S1-4 | 3 | L |

**批次顺序**

- **批次 1（解除阻塞 + 最痛 dogfooding）**：S1-2、S1-4、S1-9、S2-2、S2-4、S2-5（单位推断子项）。
- **批次 2（内核调度与元素/事件面扩张）**：S1-1、S1-7、S1-8、S1-6、S2-1、S2-3、S2-6。
- **批次 3（结构能力与样式体系）**：S2-5（CSS/主题）、S1-3、S1-11、S1-5、S1-10。

**排序理由**

1. **阻塞关系**：S1-2 是所有组合类条目的上游——S1-4（children 的更新）、S1-7（memo 的比较对象）、S1-9（ref 指向的实例）、S1-3（context 的订阅粒度）都建立在「prop 变化不重建子组件」之上，因此 S1-2 必须在批次 1。S2-2 是 S2-1/S2-6/S2-5 的上游（新元素若不能带属性就没有意义），S2-1 又在 S2-3 的事件类型之前。
2. **dogfooding 痛点**：最痛的两条是「父更新则子重建、state 全丢」与「容器组件写不了」——beryl 分别用「交互态必须受控」和 `content:` Proc prop 绕开（`../beryl/lib/beryl/tabs.rb:5`、`../beryl/lib/beryl/dialog.rb:59`），绕开成本落在每个应用里，所以进批次 1。次痛的是属性面为零（`disabled`/`aria-*` 静默丢弃，`lib/citrine/dom.rb:48-61`），成本极低、收益面最宽，也放批次 1。
3. **与 S3 的关系**：S1-1（批量更新）与 S1-8（Effect cleanup）都直接改写 Effect 的创建/释放/重跑时序，S3-1（computed Effect 泄漏）与 S3-2（假 on_unmount + window_key 丢失）刚把 Effect 生命周期与卸载路径理清，把这两个条目挪到它们之后能避免在移动的地基上施工。S1-7 与 S3-4/S3-5 同处复用路径（复用池构造、`apply_props` 调用）——S3 先把这条路径的分配与重复调用清掉，S1-7 的浅比较才是纯增量。批次 3 的条目都需要「组合 + 调度」已稳定（异步渲染还需要错误边界），单独提前做会反复返工。

**第三条并行线（工具链）**：第三节的 T-A / T-B 是与上面批次并行、互不阻塞的另一串，落地顺序见 T-C（D1–D6）。两者只有一条硬顺序：**T-A 全部先于 S2-2**——属性面从 3 个扩到 20+ 个会放大每次属性写入与节点创建的代价，先铺好体积 / 浏览器测试 / 静态检查的基座再扩张，能省一轮返工。

---

## 五、与 S3 稳定性修复的关系

本节按 `8dfd08a` 提交后的实际代码状态核对（S3 系列改动已提交、未推送，见文首元信息）。结论按「消解 / 不消解」直说，不做勉强关联。

### S3-1 `computed` 的 Effect 永不释放

- **本次修复**：Effect 引用表 `computation_effects`（`lib/citrine/component.rb:260-263`）、释放方法 `dispose_computed_effects`（`lib/citrine/component.rb:392-401`，含诊断用的 `computation_effect_count`）、computed 建 Effect 时留引用（`lib/citrine/component.rb:407-417`，`Effect.create` 在 `:413`）。调用点是卸载路径的**最后一步**：`lib/citrine/component.rb:364-369`（`:368`），放在用户 `on_unmount` 之后——清理钩子跑的时候订阅还在（能读到新鲜值），钩子跑完才释放。
- **消解**：不消解任何 S1/S2 条目。它修的是「Effect 建了没人释放」，而 S1/S2 缺的是能力而不是泄漏。
- **实测对照**（本机 CRuby 探针，同一段代码跑修复前后工作区）：挂载时计算 1 次；**修复前**卸载后改 `state` 又算 1 次（幽灵订阅），**修复后** 0 次。等价断言 `test/render_test.rb:451`；释放顺序（先跑钩子、后释放）由 `test/render_test.rb:466` 锁定。
- **关联（仅前置经验）**：S1-8 要加的正是「Effect 级 cleanup + 释放责任明确」这套机制，S3-1 在 computed 上先走了一遍同构实现，因此 S1-8 被排在其后（批次 2）以复用同一口径，而不是因为存在功能依赖。

### S3-2 子组件根元素换类型时的假 on_unmount 与 window_key 丢失

- **本次修复**：先在 `refresh_component_view` 摘掉组件边界再 dispose（`lib/citrine/renderer.rb:183-191`，`:188` 清 `rendered_component`，`:189` dispose，`:190` 重新 adopt）；`adopt_root` 本身不重新注册 window_key（`lib/citrine/renderer.rb:159-168`），窗口键盘注册在 `lib/citrine/renderer.rb:449-455` / 解绑在 `lib/citrine/dom.rb:119-126`。
- **消解**：不消解 S1-2。这条修复让「props 变化导致子组件重建」这条路径不再产生假卸载副作用，但 props 变化仍然重建子组件、仍然丢 state——S1-2 要的是保留实例与 state，S3-2 只保证了重建过程不误伤全局键盘与生命周期计数。
- **关联**：S1-2 落地后，「子组件根元素类型变化」这个分支依然存在（子组件 view 自身输出根类型变化时仍要换节点），所以 S3-2 的修复在 S1-2 之后仍需保留，两者不是替代关系。
- **实测对照**：修复前触发根类型变化后 `on_unmount` 计数 +1、window 监听数 1→0（且不再恢复）；修复后为 0 / 1。断言见 `test/nesting_test.rb:464`。

### S3-3 SSR 的 class/style 属性值未转义（属性注入）

- **本次修复**：`class` 值转义（`lib/citrine/string_renderer.rb:64-65`）、内联 CSS 值转义（`lib/citrine/string_renderer.rb:84-88`），`escape_html` 在 `lib/citrine/string_renderer.rb:90-93`。
- **消解**：**部分**消解 S2-2 与 S2-5 各一小块——`class` 值转义属于 S2-2 的属性值序列化（属性透传一旦做开，转义规则必须覆盖所有透传属性，`title`/`data-*` 也在内），`style` 值转义属于 S2-5 的 SSR 样式输出。调研原文只把它算作 S2-5 的一部分；按代码看它同时是 S2-2 的前置：SSR 属性序列化口径要在 S2-2 里统一，而不是每类属性各补一次。
- **不消解**：转义不解决「属性根本不存在」——S2-2 缺的是 `id`/`disabled`/`aria-*` 的透传通道，与转义正交。
- **实测对照**：修复前的 SSR 输出里，一个 `css_class: 'a" onclick="alert(1)'` 会被拼成 `<div class="a" onclick="alert(1)" …>`（数据凭空变成属性）；修复后为 `class="a&quot; onclick=&quot;alert(1)"`。断言见 `test/render_test.rb:425`、`:437`。

### S3-4 复用池 `unused_nodes` 用 `Array#-` 构造临时数组/哈希

- **本次修复**：`@all - @taken.values` → `@all.reject { |node| @taken.key?(node.object_id) }`（`lib/citrine/renderer.rb:310-315`）。
- **准确性说明**：这是**每轮块重跑**的额外分配，不是 O(n·m) 级算法复杂度问题——Opal corelib 的 `Array#-` 内部以哈希判定成员（`opal/corelib/array.rb:231-251`），实际复杂度 O(n+m)，代价在每轮都要为右侧集合建一份临时哈希。工作区代码注释已按此口径书写（`lib/citrine/renderer.rb:311-312`）。
- **消解**：不消解任何 S1/S2 条目，是同一路径上的前置清理——S1-2 与 S1-7 都会让复用路径变成热路径，先去掉每轮固定分配再做增量更干净。

### S3-5 复用刷新时 `apply_props` 被调用两次

- **本次修复**：`refresh_node` 改为二选一（有属性 Effect 就跑 Effect，否则直接 `apply_props`），见 `lib/citrine/renderer.rb:210-224`（`:217-221` 分支）；属性 Effect 在挂载时创建（`lib/citrine/renderer.rb:91-95`），`apply_props` 内部还负责复用路径补齐事件（`lib/citrine/dom.rb:60`）。
- **消解**：不消解任何 S1/S2 条目。它是 S1-2 的前置——S1-2 之后复用会更频繁（每次 props 变化都走这条路径），属性写入次数也随之放大；同时 S2-2 一旦把属性面从 3 个扩到 20 个，双写的代价会同步放大，所以这两条改在扩张之前完成。
- **已知残留（未修，留给 S1-2 / S2-2）**：节点复用后才**首次**拿到响应式 Proc 属性时，该节点没有属性 Effect（`props_effect` 只在挂载路径按 `reactive_props?` 创建，`lib/citrine/renderer.rb:91-95`），这个 Proc 会在外层块的上下文里求值——订阅粒度落到外层块（G-2 的隐性外扩），且块不重跑时属性不更新。正常写法（同一处始终传 Proc）不受影响。

### S3-6 DOM 每个元素无条件绑 4 个监听

- **本次修复**：改为按需绑定——`ensure_events` / `ensure_event`（`lib/citrine/dom.rb:71-108`，`:102-108` 是「挂过就不再挂 + props 里真有处理器才挂」的判定），`bound_listeners` 记录在 `lib/citrine/node.rb:19-21`，`on_enter`/`on_change` 也统一走这条路径（`lib/citrine/dom.rb:90-99`，原各自的绑定点已移除：`lib/citrine/dom.rb:158`、`:171`）。
- **消解**：**部分**消解 S2-3 的性能子项（「无处理器的元素白挂闭包」）。**不消解** S2-3 的语义子项：仍然没有事件委托（监听依旧逐个元素绑在 `node.dom` 上，`lib/citrine/dom.rb:107`）、事件类型集合没变、click/focus/blur 仍然把 `Native(event)` 直接交给组件、`KeyEvent` 仍然没有 `stop_propagation`、`window_key` 仍然没有焦点作用域。按需绑定不等于事件委托，S2-3 的全部语义条目依旧成立。
- **实测对照**：counter 示例（3 个 button、无输入框）经 Node 桩统计——修复前全树监听 **28** 个（每个元素 4 个：click/keydown/focus/blur），修复后 **3** 个（3 个按钮各 1 个 click）；无处理器的 `label` 由 4 个降为 0。桩断言在 `examples/stub_check.js` 的 counter 段。

---

## 六、不在本计划范围

- 路由：不做路径匹配、嵌套路由、导航拦截。一句话：路由不属于内核语义，应用层或独立包解决。
- 数据层：不做请求缓存、失效策略、归一化（normalize）——S1-10 只做「渲染期等待」，不含数据获取实现。
- npm 互操作：不做与 React/npm 组件的互嵌、不做 JSX/TS 互操作层。
- Rails 集成：不做 view helper、asset pipeline 集成、Hotwire/Turbo 对接。
- Fast Refresh：保状态热替换不在本计划（`GOALS.md:496` 的 P1 条目）。顺带一条调研结论——**Opal 世界没有现成的保状态 HMR**：`vite-plugin-opal` 的 HMR 实际是更快的整页刷新（其发布产物里没有 `hot.accept` 注入，按 Vite 规则最终回退整页 reload），要做只能自研协议。
- corelib 裁剪与 tree-shaking：不做（Opal 1.x 除 `-s` 桩文件与 `-M` 之外没有杠杆，Opal 2.0 的 `--dce` 未发版）。**但 `esbuild minify` 与产物体积优化已移入第三节 T-A1**——那是改编译参数，不是框架能力。
- DevTools 与信号依赖图可视化：作为**工程链路任务**在第三节 T-B3（埋点 + Cytoscape.js），不占 S1/S2 的批次。
- 分包发布与重命名（`GOALS.md:502-504`）。
- 平台扩张：Canvas 侧与桌面壳的具体改造归第三节 T-B2 / T-B4；本计划 S1/S2 的验收一律以 CRuby 单测 + DOM 侧断言为准。
- beryl 侧代码不改：beryl 的自研焦点/层叠扩展只作为「框架侧能力缺口」的旁证，不在本计划内改动。
- beryl 侧代码不改：beryl 的自研焦点/层叠扩展只作为「框架侧能力缺口」的旁证，不在本计划内改动。

---

## 附：证据索引

路径相对仓库根 `citrine/`；`../beryl/...` 为工作区同级仓库。

**内核 / 信号**
- `lib/citrine/signal.rb:33-40` — `Signal#set` 同步广播
- `lib/citrine/signal.rb:77-81` — `Effect.create` 只收 block，无 cleanup
- `lib/citrine/signal.rb:104-110` — `Effect#dispose`
- `lib/citrine/signal.rb:43` — `Signal#lazy?`（惰性初值，非 lazy 组件）
- `lib/citrine/list_signal.rb:22-23` — 集合深响应边界
- `lib/citrine/list_signal.rb:38-40` — `get` 返回冻结快照
- `lib/citrine/reactive.rb:36`、`lib/citrine.rb:63` — `signal_list`

**渲染器 / 复用**
- `lib/citrine/renderer.rb:14-15` — 元素词表 TAGS
- `lib/citrine/renderer.rb:26-29` — REACTIVE_PROPS / VALUE_PROPS
- `lib/citrine/renderer.rb:50`、`:139` — watch Effect 的创建调用点
- `lib/citrine/renderer.rb:71-111` — `mount`（`:83` 调用 `register_ref`，`:91-95` 属性 Effect）
- `lib/citrine/renderer.rb:120-141` — `render_component`（`:125` 仅剔 `:key`，`:134-140` 新建路径）
- `lib/citrine/renderer.rb:144-153` — 子组件必须恰好一个根节点
- `lib/citrine/renderer.rb:159-168` — `adopt_root`
- `lib/citrine/renderer.rb:170-191` — `refresh_component_view`（`:183-190` 摘边界后 dispose）
- `lib/citrine/renderer.rb:210-224` — `refresh_node`（`:217-221` 二选一）
- `lib/citrine/renderer.rb:241-258` — `run_block` + ensure 卸载（`:257`）
- `lib/citrine/renderer.rb:279-301` — `ReusePool#take`（`:292` 组件复用门槛）
- `lib/citrine/renderer.rb:310-315` — `unused_nodes`（改为 reject）
- `lib/citrine/renderer.rb:321-327` — `same_props?` / `comparable`
- `lib/citrine/renderer.rb:342-356` — `dispose`
- `lib/citrine/renderer.rb:382-408` — `reactive_props?`（`:382-384`）与 `warn_unreactive_proc`（`:395-408`）
- `lib/citrine/renderer.rb:442-447` — `register_ref`（仅元素路径）
- `lib/citrine/renderer.rb:449-455` — `register_window_keys`
- `lib/citrine/renderer.rb:485-489` — `bind_events` 基类钩子（注释已更新）

**组件 / 宏 / 生命周期**
- `lib/citrine/component.rb:28` — DSL_METHODS 白名单
- `lib/citrine/component.rb:134-141` — `on_mount` / `on_unmount`
- `lib/citrine/component.rb:155-162` — `watch` 类宏（已落地）
- `lib/citrine/component.rb:200-204`、`:240-254` — `initialize` / `update_props`（`:203`、`:243` 未声明 prop 报错）
- `lib/citrine/component.rb:239` — 「S2 会把 props 升级成信号」注释
- `lib/citrine/component.rb:256-263` — `computations` / `computation_effects`
- `lib/citrine/component.rb:275-306` — 元素 DSL 方法（5 个 + render）
- `lib/citrine/component.rb:315-316` — `render` 拒绝 block
- `lib/citrine/component.rb:358-369` — 生命周期钩子入口（卸载时释放 watch + computed）
- `lib/citrine/component.rb:371-390` — watch Effect 运行/释放
- `lib/citrine/component.rb:392-403` — computed Effect 释放与诊断计数
- `lib/citrine/component.rb:405-417` — `private` / `computation`
- `lib/citrine/component.rb:419-423` — `emit`（private，元素挂载入口）

**DOM / SSR / 样式**
- `lib/citrine/dom.rb:35` — 标签兜底 `TAGS[type] || type.to_s`
- `lib/citrine/dom.rb:48-61` — `apply_props`（仅 css_class/placeholder/style）
- `lib/citrine/dom.rb:71-108` — `ensure_events` / `ensure_event`（含 `:107` 逐元素绑监听）
- `lib/citrine/dom.rb:111-117` — `register_window_key`（无焦点作用域）
- `lib/citrine/dom.rb:119-126` — `unregister_window_keys`
- `lib/citrine/dom.rb:128-134` — `key_event`
- `lib/citrine/dom.rb:147-159` — `setup_text_input`（`:152-153` 双向绑定）
- `lib/citrine/dom.rb:161-172` — `setup_check_box`（回写见 `:96-99`）
- `lib/citrine/key_event.rb:31-34` — 仅 `prevent_default`（全文 39 行，无 stopPropagation）
- `lib/citrine/string_renderer.rb:50-57` — SSR `serialize` 的标签兜底（`TAGS[type] || type.to_s` 在 `:51`）
- `lib/citrine/string_renderer.rb:60-82` — SSR 属性输出
- `lib/citrine/string_renderer.rb:64-65`、`:84-88`、`:90-93` — class/style 转义与 `escape_html`
- `lib/citrine/style.rb:14-19`、`:22-25` — PX_PROPERTIES / UNITLESS_PROPERTIES（均不含 font_size）
- `lib/citrine/node.rb:19-21` — `bound_listeners`
- `lib/citrine/dev_server.rb:34` — overlay 的 `style.cssText`（样式相关唯一命中）

**测试（锁定现有语义 / 新验收落点）**
- `test/nesting_test.rb:286-306` — props 变化即重建（`:304` 断言 mounts +1）
- `test/nesting_test.rb:291` — 「S2 会改为原地更新」注释
- `test/watch_test.rb` — watch 宏语义（119 行，含 SSR 不创建）
- `test/render_test.rb:65`、`:114` — `MemoryRenderer` 与 `MemoryRenderTest`
- `test/signal_test.rb` — 信号内核单测
- `Rakefile:4-8`、`:11-25` — `rake`（`test/*_test.rb`）与 `rake stubs`（六项桩）

**Roadmap / 决策**
- `GOALS.md:470` — watch 宏决策记录
- `GOALS.md:480-483` — 跨组件 props 重传仍待做
- `GOALS.md:484-485` — P0-2 生命周期宏（`effect` 仍未兑现）
- `GOALS.md:488-489` — P0-4 批量更新挂号
- `GOALS.md:493-498` — P1（产物体积 / 构建 / Fast Refresh / DevTools）
- `GOALS.md:502-509` — P2（命名 / 分包 / CI / 文档 / 基准）

**跨仓库（beryl，非本计划改动对象）**
- `../beryl/lib/beryl/renderer.rb:40-41`、`:230-241` — 自研 tabindex / autofocus
- `../beryl/lib/beryl/tabs.rb:5`、`../beryl/lib/beryl/dialog.rb:59` — `content:` Proc prop 代替插槽
- `../beryl/lib/beryl/feedback.rb:20`、`../beryl/lib/beryl/overlay.rb:73`、`../beryl/lib/beryl/window.rb:19`、`:121` — z-index 堆叠代替 portal

**工具链（第三节，均为 2026-09-15 本机实测；环境：Opal 1.8.3、Node 24.7.0、esbuild 0.28.2、macOS arm64）**
- 体积四档数字（raw / gzip）：现状 2,420,313 / 607,598 → `--no-source-map` 896,297 / 164,044 → 再 esbuild minify 395,538 / 111,336 → `-O` 拆分 322,534 + 76,197 / 91,245 + 21,196。复现命令见 `Rakefile:11-25` 的同类调用加 `--no-source-map`。
- `-A/--arity-check`：本机实测把多传实参从静默丢弃变为 `ArgumentError ... wrong number of arguments (given 2, expected 1)`。
- `examples/num_parity.rb`：未压缩 / esbuild / terser 三形态输出逐字节一致；minified 产物过 `node --check`。
- 浏览器测试探针：`../artifacts/quality-tooling/probes/opal_rspec/`（真实布局 `root=380x220`、`TOPS=[8,8]`、EXIT=1 失败路径）、`probes/cuprite/probe.rb`（`initial vs reset = 0px`、CDP `Profiler`/`Performance` 域）、`probes/jsdom/probe.mjs`（跑不起 Opal 产物的复现）、`probes/rubocop/bad_component.rb`（自定义 cop fixture，真实 `examples/` 0 误报）。
- 调研报告（含各项的官方链接与版本号）：`../artifacts/quality-tooling/REPORT.md`。
- 外部依据（关键几条）：Opal CLI 参考 <https://github.com/opal/opal/blob/master/docs/reference/cli.md>（`--no-source-map` / `-P` / `-O` / `-A`）；Opal 2.0 迁移说明 <https://github.com/opal/opal/blob/master/docs/reference/migration_2_0.md>（`--dce`、ES2021 硬变更）；RubyGems Trusted Publishing <https://guides.rubygems.org/trusted-publishing/>；Vite HMR 规则 <https://vite.dev/guide/api-hmr>（无 `hot.accept` 即整页 reload）；Sentry 与 indexed source map 的支持情况**未见官方说明**（列为待 spike）。
