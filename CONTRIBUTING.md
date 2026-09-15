# 贡献指南

感谢你对 Citrine 感兴趣。本项目目前由单人维护，欢迎 issue 与 PR——
以下流程与主仓库 `main` 受保护的分支策略一致。

## 分支与 PR 流程

- `main` 受分支保护，**直接推送会被拒**。流程：推 feature 分支 → 开 PR →
  CI 全绿 → squash 合并。
- 分支命名建议带前缀：`feat/`、`fix/`、`docs:`、`ci:`、`chore:`（与现有
  提交历史同风格）。
- PR 请写清动机与行为变化；框架行为的变更需要配套测试（见下）。
- 合并后删除远端分支；仓库定期清理已合并分支。

## 开发环境

```bash
git clone https://github.com/ShiningRay/citrine.git
cd citrine
bundle install   # Ruby ≥ 3.0；本地开发建议 rbenv 装 3.3.x
npm ci           # 可选：仅 rake size 体积守卫需要 esbuild
```

## 测试与验收命令

提交前请至少跑过前两条；CI 会全量跑：

```bash
bundle exec rake          # CRuby 单测（27 个文件 232 项，不需要 Opal）
bundle exec rake stubs    # 编译全部示例 + Node 桩验收（8 套）
bundle exec rake lint     # 框架专属 rubocop 门禁（Citrine/NoRawIvarAssignment）
bundle exec rake size     # 产物体积守卫（需要 esbuild）
```

涉及 Canvas / DOM 渲染的改动，如本机有 Chrome，请追加：

```bash
bundle exec rake browser         # headless Chrome 布局守卫
bundle exec rake canvas_parity   # DOM/Canvas 等价断言
```

## CI 必需检查（5 项，全绿才能合并）

`test`（Ruby 3.0–4.0 矩阵 + parity）/ `stubs` / `quality`（体积 + source map
+ 生产断言 + lint）/ `browser` / `package`（macOS 打包冒烟）。

## 红线（改动前必读）

- 平台无关核心（signal / node / component / renderer / style 及同类）禁止
  引入 Opal/JS 依赖——必须保持 CRuby 可直接单测；Opal 专有代码只出现在
  dom.rb / canvas.rb / browser.rb。
- DSL 全域 snake_case；camelCase 兼容输入的归一化只在 `Component#emit` 单点。
- v1 已知语义不是 bug，勿"修复"：列表 keyed 复用的边界、集合整体替换语义、
  `computed(:x) { }` 必须带括号、SSR 不建 Effect 不序列化事件。
- 详细背景见 GOALS.md（愿景、架构决策、Roadmap）与 docs/ 下的两份计划文档。

## 发布

推 `v*` 标签触发 Release 工作流（Trusted Publishing，无需 API key）：
构建 gem → 附到 GitHub Release → 发布到 RubyGems。版本号在
`lib/citrine/version.rb`；CHANGELOG 随 PR 同步更新。
