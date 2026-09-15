# PLAN-code-review — 全项目评估后的修订计划

> 来源：2026-09-15 全项目评估（框架源码 21 文件通读 + 测试/CI/文档/Roadmap 核对）。
> 与 `PLAN-react-gap.md` 的关系：那份是"补齐 React 差距"的功能计划，本文件是"质量与工程化"修订计划。
> 状态约定：`[x]` 已执行，`[ ]` 待执行，`[~]` 暂缓（需外部动作或用户决策，见每项备注）。

## 一、高危 bug（优先）

### C1. 错误边界在响应式重跑路径失效 `[x]`
- **位置**：`lib/citrine/renderer.rb:273`（`rerun_component_view`）、`:308`（`rerun_fragment_view`）、`:252`（`first_component_render`）
- **问题**：`run_block` 的 rescue→fallback 只包住挂在块里的渲染；子组件 view 重跑走 `child.instance_exec { view }`，异常直接穿出 `Effect#run` → `Scheduler.flush` → 事件处理器，UI 停在半更新状态。子组件自己声明的 `error_fallback` 接不住自己的 view 错误。
- **修法**：把 view 执行统一包进带 fallback 的 `run_block`（抽 `run_view_with_fallback(child, node)`），并补回归测试：信号驱动重跑时子组件 view 抛错 → fallback 渲染、兄弟节点不受影响。

### C2. 复用路径 stale props `[x]`
- **位置**：`lib/citrine/component.rb:357-377`（`update_props`）
- **问题**：只迭代 `new_props`；父组件这轮少传 prop 时旧值残留，不回落 default。
- **修法**：复用时对 `defs.keys - new_props.keys` 补发 `signal.set(default)`；补测试覆盖"少传回落 default"。

### C3. 文本→子节点切换时旧 textContent 残留 `[x]`
- **位置**：`lib/citrine/renderer.rb:430-433`
- **问题**：`label { cond ? "text" : nil }`，上一轮写过 text、这轮 children 空时不清旧文本。
- **修法**：与 `track_text` 同思路，只要上一轮写过 text 本轮就显式 `set_text`；补测试。

### C4. `Scheduler.flush` 一个 effect 抛异常丢弃同批其余项并掩盖原始错误 `[x]`
- **位置**：`lib/citrine/signal.rb:35-44`
- **修法**：逐 effect rescue，跑完队列后统一报告（`warn` + 重新 raise 第一个）；确保 `batch` ensure 里不替换用户原始异常。补测试。

### C5. `Effect#depend` 运行中自 dispose 后 `nil.any?` `[x]`
- **位置**：`lib/citrine/signal.rb:191-196`
- **修法**：`depend` 开头加 `return if @deps.nil?`；补测试。

### C6. `Scheduler.schedule` 以 object_id 去重 `[x]`
- **位置**：`lib/citrine/signal.rb:26-31`
- **修法**：改用 effect 对象本身作 Hash 键（identity）。

## 二、API 一致性

### A1. `state`/`computed` 宏缺 DSL 方法名冲突检查 `[x]`
- **位置**：`lib/citrine/component.rb:70-80`（对照 `:58-67` prop 检查、`:204-212` context 检查）
- **修法**：提取共用校验，三宏同口径 raise。

### A2. `prop type:` 不允许 nil，无可空 prop `[x]`
- **位置**：`lib/citrine/component.rb:292-295`、`:364-366`
- **修法**：语义改为"nil 或 type 实例"（default 为 nil 时放宽）；补测试。

### A3. `ElementProxy` 白名单太脆，就地改写静默不通知 `[x]`
- **位置**：`lib/citrine/list_signal.rb:265-281`
- **修法**：在 `method_missing` 里对返回 self 的链式调用前后做元素快照对比（`dup ==`），变化即 `element_changed!`；无法判定的可变方法在开发模式 warn 提示手动 `element_changed!`。补测试覆盖 `push`/`store` 触发通知。

### A4. dev_server 目录逃逸守卫是前缀匹配 `[x]`
- **位置**：`lib/citrine/dev_server.rb:158-161`
- **修法**：`full == @dir || full.start_with?(@dir + File::SEPARATOR)`，先判 `File.file?`。

### A5. 裸调 `"opal"` 违反自己记录在案的坑 `[x]`
- **位置**：`lib/citrine/dev_server.rb:184-188`、`lib/citrine/packager.rb:64-69`
- **修法**：经 `Gem.bin_path("opal", "opal")` 解析；`opal`/`swiftc` 缺失时 rescue `ENOENT` → `abort` 带可执行提示。

### A6. `parse_args` 对 `-p` 缺参/未知 flag 静默吞掉 `[x]`
- **位置**：`lib/citrine/dev_server.rb:68-88`
- **修法**：`-p` 缺参 raise（与 `-I` 同口径）；未知 flag 警告。

### A7. 其他低危一致性 `[x]`
- 两个 `mount_at` 多根策略不一致（`dom.rb:16-22` 复用 vs `canvas.rb:21-25` 每次 new）→ Canvas 侧对齐或注释说明暂不支持多根。
- SSR `css_class` 数组渲染成字面量（`string_renderer.rb:77`）→ `Array(css_class).join(" ")`；DOM 侧 `className=`（`dom.rb:59`）同处理。
- `box` 显式 `display: grid` 时仍写 `flex_direction`（`renderer.rb:563-567`）→ 仅 flex/缺省时应用。
- kebab-case 样式键未归一（`style.rb:56-58`）→ normalize 时 `-` 也转 `_`。
- 透传属性收到 Signal 时 `to_s` 成 `#<Citrine::Signal…>`（`renderer.rb:598-605`）→ 纳入 `warn_unreactive_proc` 同款提醒。
- `mount_at` 找不到元素时显式 raise（`dom.rb:24-32`）。
- `Renderer#find_context_provider` 用 `private` + 事后 `public` 翻转（`renderer.rb:701-717`）→ 直接声明位置调整。
- 事件分发三路重复（`component.rb:519-551`、`renderer.rb:448-455`）→ 抽 `Citrine.dispatch_callable`；`event_defs` 提为冻结常量。

## 三、性能（低危，演示后端为主）

### P1. Canvas redraw 尺寸计算 O(深度×n) `[x]`
- **位置**：`lib/citrine/canvas.rb:269-286`、`:346-362`
- **修法**：redraw 内一次后序遍历缓存尺寸进 `node.dom`，place/paint 只读；或给 `size_of` 加当轮 memo。
- 备注：演示后端，改动以不破坏 canvas_dom_parity 测试为准。

### P2. `apply_props` 重复分配 / `Style.camel` churn `[x]`
- **位置**：`lib/citrine/renderer.rb:598-605`、`lib/citrine/dom.rb:65-76`
- **修法**：`Style` 加 per-key memo（kebab/camel 结果缓存）。

### P3. `use_context` 绑定永不重解析 / 元素信号表只增不减 `[x]`
- **位置**：`lib/citrine/component.rb:321-324`、`lib/citrine/list_signal.rb:99-101,244-251`
- **修法**：前者加注释说明约束；后者 `refresh_element_signals` 时清理越界键（dup 上收集、循环后删）。
- 备注：均为低危，以注释/最小改动为主。

## 四、工具链与 CI

### T1. release job 的 `rake size` 守卫静默失效 `[x]`
- **位置**：`.github/workflows/release.yml:25-28`
- **修法**：job 加 setup-node + `npm i -D esbuild`（或 Rakefile 检测缺失时显式 notice）；本地与 CI 行为一致化——新增 `package.json` 把 esbuild 钉为 dev 依赖，`rake size` 走 `npx esbuild`。
- **执行（2026-09-15）**：`package.json` + `package-lock.json` 钉 esbuild 0.28.2（dev 依赖）；
  release.yml 加 setup-node + `npm ci`；Rakefile `size` 任务在 esbuild 缺失时输出显式 notice
  （CI 下同步发 GitHub Actions `::notice::` 注记），不再静默降级。

### T2. 发布门禁轻于 CI `[x]`
- **位置**：`.github/workflows/release.yml`
- **修法**：release job 前置 `rake stubs` + `rake lint`。
- **执行（2026-09-15）**：发布门禁步骤现跑 `rake` + `rake stubs` + `rake lint` + `rake size`，
  与 CI 对齐（setup-node + `npm ci` 先行，保证 size 守卫完整生效）。

### T3. Ruby 3.0 声明了但从未测 `[x]`
- **位置**：`.github/workflows/ci.yml:15`、gemspec:19
- **修法**：矩阵加 3.0（若挂则抬 gemspec 到 3.1 并记录决策）。
- **执行（2026-09-15）**：矩阵已加 `3.0`（3.0–4.0 共 6 腿，检查名 `Ruby 3.0` 为新增、既有名不动）。
  前置核对：lib/test/bin/Rakefile 无 3.1+ 专有语法；依赖均声明支持 3.0（bundler 会为 3.0 腿
  解析兼容的 minitest 5.x 旧版）——无需抬 gemspec，维持 `>= 3.0.0`。

### T4. CI 杂项 `[x]`
- ci.yml 加 `concurrency`（抄 pages.yml）。✅（`group: ci-${{ github.ref }}`，cancel-in-progress）
- dependabot.yml 加 `groups:` 合并 action 升级为一个周 PR。✅（`github-actions` 组，patterns `*`）
- `.gitignore` 的 examples 产物改 `examples/*.js` + 否定规则保留桩文件，替代逐个枚举。✅
  （桩文件已确认为 `stub_check.js` / `canvas_stub_check.js`；顺带修正 stubs 步骤名"七套"→"八套"）
- `bin/citrine:22` help 文案去掉"工作代号"措辞；`website/build.sh:3` 注释修正。⏳ 前者属
  bin/ 并行任务，后者已改（`bin/citrine build-site` 是不存在的命令，注释改为仅 `bash website/build.sh`）。

### T5. 版本链统一 `[x]`
- `packager.rb:97-100` Info.plist 改用 `Citrine::VERSION.to_s`。⏳ 属 lib/ 并行任务。
- `website/website.rb:9` 徽章版本改为构建时注入。✅（build.sh 从 `lib/citrine/version.rb` 读出版本，
  经临时副本替换 `state :version, default:` 后编译，不污染源文件）
- `website/dist/` 从 git 索引移除并加入 .gitignore（pages.yml 每次部署重建，提交的副本是腐化源）。✅
  （`git rm -r --cached` 已执行）

### T6. dev_server 杂项 `[x]`
- SSE 僵尸连接：写失败清理 + 定期 ping 清扫。
- 临时产物 `rand` 命名改 `Tempfile`/`Dir::mktmpdir`。

### T7. 打标与发布验证 `[~]`
- ~~v0.1.1 未打标~~ 已决策：0.1.1 不单独发版，整体以 **v0.2.0** 首发（version.rb 已升 0.2.0，CHANGELOG 重组）；`gem install citrine` 上架验证随 v0.2.0 标签执行。
- **需用户决策/外部动作**：确认 0.1.1 是否发布；推 `v0.1.1` 标签；README 安装节按实际状态标注"尚未发布"。

## 五、文档

### D1. README 修订 `[x]`
- 删除 `:89` 过时的"props 为创建时快照"块，消除与 `:63` 的矛盾。✅（`:63` 的 props 快照表述
  同步改为 S1-2 后的真实语义：props 已信号化，父重传只重跑读它的块）
- 更新产物体积数字（896KB / gzip 164KB / minify 111KB，指向 `rake size`）。✅
- 目录树精简（改为指针式或只列顶层）。✅（只列顶层结构）
- "当前状态"表补 09-15 批次特性；安装节标注发布状态。✅（补 S/T 两行批次特性 + 两份计划文档链接；
  安装节注明"尚未发布到 rubygems.org，请从源码安装"，T7）

### D2. 文档入口与指针化 `[x]`
- README + GOALS.md 第十一节加 `docs/PLAN-react-gap.md` 与本文件的链接。✅
- GOALS.md 文首"立项探索期"加注当前状态指针；M2"零新依赖"补 T-B1 变更记录；Roadmap 的
  `rv build` 改名 `citrine build`；"分包发布"条标注被决策 #7 覆盖。✅（分包发布标注为"显式推迟"）
- 根目录 `AGENTS.md`：单测 17→"见 Rakefile"、桩 4→8、检查 6→5、gem 发布状态更新、lib 清单补齐；
  数字类内容改指针式引用。✅（按批次负责人指示写实际值：单测 27 个文件 232 项、桩 8 套、检查 5 项；
  lib 清单补齐 browser/debug/event/key_event/list_signal/num/reactive/sourcemap/theme/version）

### D3. 开源就绪文件 `[x]`
- 补最低三件套：`CONTRIBUTING.md`、`CHANGELOG.md`、`.github/ISSUE_TEMPLATE/`（或 issue 表单）+ PR 模板。
- CHANGELOG 从 git 历史回填 0.1.0 / 0.1.1 条目。
- **执行（2026-09-15）**：`CONTRIBUTING.md`（分支+PR 流程、main 保护、5 项 CI 必需检查、测试命令、
  红线）、`CHANGELOG.md`（0.1.0 初始发布 / 0.1.1 摩擦修复回填；Unreleased 节汇集 09-15 全部批次
  并注明 **v0.1.1 未打标**）、`.github/pull_request_template.md`（简述 + 测试项勾选）已建。
  issue 表单未建——当前以 PR 模板为最低集，需要时再补 `.github/ISSUE_TEMPLATE/`。

### D4. 测试与示例布局 `[x]`
- 测试 job 加 simplecov，控制台输出覆盖率摘要（不上传外部服务，保持零依赖门禁）。✅
  （`test/test_helper.rb` 启动 simplecov，`Rakefile` 以 `-rtest_helper` 先于全部测试加载；
  Gemfile test/development 组加 `simplecov`；require 有 `begin/rescue LoadError` 守卫，
  未 bundle install 时 warn 跳过、不阻断测试）
- `examples/` 中的测试装置（`browser_check.rb`、`canvas_dom_parity.rb`）迁往 `test/browser/`，examples/ 只留可运行 demo；Rakefile 相应改路径。✅
  （`.rb`/`.html` 四件迁移；`canvas_dom_parity.rb` 的 `require_relative "components"` 改为
  `require "components"` + `-Iexamples`；编译产物落在 `test/browser/` 并已 gitignore；
  examples/ 里残留的编译产物 `browser_check.js` / `canvas_dom_parity.js` 已删除）
- `packager.rb` 纯函数（plist 生成、app 名派生、缺文件 abort）补单测。⏳ 不属本次范围。
- 基于 T-A2 已验证的 Cuprite 探针，给 counter/todo 各加一条点击级冒烟（若环境缺 Chrome 则跳过不 fail）。⏳ 不属本次范围。

## 六、暂缓项（Roadmap 已挂号，不在本次执行）

- T-B3 后半：DevTools 可视化 UI（Cytoscape.js）、Sentry source map 上传。
- P1-6：`citrine build` 生产构建命令（minify + 哈希 + sourcemap 串联）。
- P2-12：MemoryRenderer 抽 `lib/citrine/testing.rb`；文档站/API 参考。
- P2-13：js-framework-benchmark 性能基准。
- M4b：移动端 spike 触发条件决策记录。
- Fast Refresh：M5+ 再议。
- `examples/stub_check.js` 桩的替换方案：T-A2 结论（opal-rspec 不可用、jsdom 跑不起 Opal）已在 PLAN 记录，本次只做"部分采用"显式决策注记。
- 仓库清理：删除 ~12 个已合并远端分支、释放旁挂 worktree（`../citrine-nesting` 等）——需用户确认。

## 验收

- `bundle exec rake` 全绿（新增回归测试随各修复项落地）。
- `bundle exec rake stubs` 全绿。
- `bundle exec rake lint` 全绿（新增/改动文件符合 rubocop 配置）。
- 本文件所有 `[ ]` 转为 `[x]` 或附注暂缓理由。

## 执行记录（2026-09-15）

本节由执行阶段回填，记录与计划有偏差或需要知悉的决策：

- **A1 引发测试改名**：state/computed 新增 DSL 冲突检查后，`test/batching_test.rb` 与
  `test/render_test.rb` 中的 `state :a`（`a` 是锚点标签）在类加载期报错，已改名 `state :alpha`。
  这是检查生效的预期结果，非回归。
- **C4 语义细节**：flush 逐 effect rescue 后重抛第一个错误；`batch` ensure 中若用户块异常
  正在传播则吞掉调度错误，不替换原始异常（`$!` 口径经 Opal 编译探针实测确认）。
- **A3 取舍**：ElementProxy 快照变更检测只对值语义 `==` 的类型（Array/Hash/String/Struct）做，
  identity == 的类型 dup 后必不相等，会误报造成重跑死循环；嵌套裸对象改写
  （`proxy[:nested][:x] = 1`）仍是文档化静默边界；"无法判定"分支（返回 self 的链式调用 +
  非值语义元素）在 dev mode 按 [类, 方法名] 每信号提醒一次。
- **A2 语义**：prop type 校验统一为"nil 或 type 实例"，`prop :foo, type: String` 不再需要显式
  `default: nil`。
- **A7 拆分**：`Citrine.dispatch_callable` 落地于 renderer.rb；component.rb 侧
  handle_event/handle_key/run_hook 的切换在执行批次内由同一批修订完成（行为等价）。
- **C3 依赖 DOM 侧镜像**：`dom.rb#set_text` 现在把文本镜像进 `node.text`，与 Canvas/SSR 同口径。
- **T1 补充**：quality job 也加了 `npm ci`（原计划只点名 release.yml），否则它仍以降级模式
  跑体积守卫。
- **验收基线**：`bundle exec rake` 280 项 / 909 断言全绿（simplecov 91.54%）、
  `rake stubs` 八套全过、`rake lint` 0 offenses、`rake size` minify 后 gzip 123KB（预算 300KB）。
- **遗留暂缓**：T7（v0.1.1 打标发布与 rubygems.org 上架验证）、第六节全部 Roadmap 项、
  stub_check.js 替换方案决策注记、远端分支/worktree 清理——均需用户决策或外部动作。
