# CHANGELOG

本项目的所有重要变更记录于此。格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [Unreleased]

## [0.2.0] - 2026-09-15

主线批次（v0.1.1 修复之后的全部 S/T 特性）：

- 组件组合：组件嵌套 + keyed 复用（P0-1）；插槽 children 与组件 ref（S1-4/S1-9）
- props 响应式传播：prop 升级为 Signal，父重传只重跑读它的块，子组件实例与 state
  原地保留（S1-2）；配套子组件 view Effect
- 批量更新 `Citrine.batch`：事件分发自动包裹合并窗口，一个 handler 改多个信号
  只重渲染一轮（S1-1）
- `effect` 宏：块返回 Proc 即 cleanup，重跑前与卸载时各执行一次（S1-8）；
  声明式订阅 `watch`（卸载自动 dispose）
- Context 依赖注入（S1-3）；Portal 子树外挂（S1-5）；错误边界
  `error_fallback`（S1-6）；suspense 渲染期等待（S1-10）；集合深响应——
  元素代理与位置级订阅（S1-11）
- 元素词表扩充 18 个常用 HTML 标签 + `element(:标签)` 逃生舱（S2-1）；
  属性透传（id/disabled/aria_*/data_*…，S2-2）；受控 `check_box` 与 IME
  组合期守卫（S2-4）；统一事件对象 `Citrine::Event` 与事件面扩展（S2-3）；
  焦点原语 `autofocus:`（S2-6）；样式单位推断与主题 token / CSS 资产（S2-5）
- 信号创建三入口（`Citrine.signal` / `Citrine::Reactive` 混入 / `keyed_signal`）；
  `Signal#peek`；`ListSignal` 增补（Enumerable / 有上限追加 / dup / 类型守卫）；
  生命周期宏改可变参数（G-12）
- Canvas：隐藏 DOM 文本量测 + 真实 `<input>` 输入覆盖层 + 贪心文本换行（T-B2）；
  `rake canvas_parity` DOM/Canvas 等价断言
- 工具链：产物体积守卫 `rake size`、source map 指回 .rb 断言、框架专属 rubocop
  cop（T-A1/T-A4）；headless Chrome 布局守卫 `rake browser`（T-A2）；
  dev server 重构为 Rack + Puma + Listen（T-B1）；DevTools 依赖图数据层 +
  `rake prod_check` 生产断言 + source map 错误还原（T-B3）；
  macOS 打包 ad-hoc 签名接入 CI（T-B4 部分）
- Ruby 3.0–4.0 测试矩阵；Trusted Publishing 发布（T-A3）
- 代码评估修订批次（docs/PLAN-code-review.md）：错误边界覆盖信号驱动重跑、stale props
  回落 default、Scheduler flush 容错、ElementProxy 就地改写检测、可空 prop、三宏 DSL 冲突
  检查、dev server 路径守卫与 opal 解析、Canvas 尺寸缓存、事件分派统一、版本链收敛，
  以及文档/CI/测试工程化（simplecov 91.5%+ 行覆盖）

## [0.1.1] - 2026-09-14

> 注：该版本未单独发版打标——内容已随 v0.2.0 首次发布到 rubygems.org
> （见 docs/PLAN-code-review.md T7）。

摩擦记录（citrine-market-terminal dogfooding 的 FRICTION.md）驱动的修复：

- F1：Effect dispose 后仍被广播——快照迭代不再崩溃（含回归测试）
- F2：`DomRenderer.mount_at` 复用渲染器实例；mount 无父节点时抛可读异常
- F16：内容 block 非字符串按 `to_s` 渲染（每类型提醒一次），nil 仍为空
- F17：样式数值按属性推断 px 单位，nil 值剔除
- F19：`check_box` 支持 Signal 驱动（此前恒为 true）
- F20：`text_input` 字面量初值落到 DOM（与 SSR 一致）

## [0.1.0] - 2026-09-14

初始发布：信号式 Ruby UI 框架（经 Opal 编译渲染到 Web / 桌面）。

- Signal 三宏内核（`prop` / `state` / `computed` + 块级细粒度更新）
- 渲染器家族：DOM（Opal）/ String（CRuby SSR）/ Memory（测试）/ Canvas 2D
- `bin/citrine dev` 热刷新开发服务器（编译错误浮层）；`bin/citrine package`
  macOS .app 打包（零依赖 Swift + WKWebView 壳）
- 响应式属性（值传 Proc 订阅收敛到节点）；`stack`/`row` 布局语法糖与
  开发期方向提醒
- 生命周期与键盘（`on_mount` / `on_unmount` / `window_key` / 元素级
  `on_key`；平台无关 `Citrine::KeyEvent`）
- 响应式集合 `Citrine.signal_list`；跨平台数值工具 `Citrine::Num` +
  `rake parity`；信号创建工厂与 `Citrine::Reactive` 混入
- GitHub Actions CI（Ruby 矩阵 + 桩验收 + macOS 打包冒烟）、官网落地页

[Unreleased]: https://github.com/ShiningRay/citrine/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/ShiningRay/citrine/releases/tag/v0.2.0
