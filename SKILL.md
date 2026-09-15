---
name: citrine
description: 用 Citrine（黄水晶）信号式 Ruby UI 框架开发应用——纯 Ruby 组件经 Opal 编译渲染到 Web/桌面/Canvas。当项目 Gemfile 引用 citrine、使用 Citrine::Component 三宏 DSL、运行 bin/citrine dev/package，或用户提到 Citrine 框架时使用。
---

# Citrine 应用开发速查

> 目标读者是"要在项目里**用** Citrine"的 AI，不是框架贡献者。
> 改动框架本身前的红线见仓库 `AGENTS.md`；设计决策史见 `GOALS.md`。
> 本文与 gem 仓库根的 `SKILL.md` 同源，改一处记得同步另一处。

## 快速开始

```bash
gem install citrine          # 已发布（0.2.0+，https://rubygems.org/gems/citrine）
citrine dev <应用目录>        # 热刷新开发服务器，默认 4402 端口，-p 换端口
citrine package <入口名>      # 打包 macOS .app（零依赖 Swift + WKWebView 壳）
```

开发循环：改应用目录或框架 `lib/**/*.rb` 下任意 `.rb` → 浏览器自动整页刷新；
编译错误以红色浮层显示在页面顶部，修复保存即恢复。应用入口是目录下的 `*.html` + 同名 `.rb`。

## 心智模型（30 秒版）

1. **view 只执行一次**。组件的 `view` 不是"每次渲染重跑"，它只负责**描述结构**；
   每个带 block 的元素包在独立 Effect 里，block 内读到的信号变化 → 只重跑那个块。
2. **赋值即更新**。`self.count += 1` 自动触发依赖这个信号的块重跑，无 setState/dispatch。
3. **粒度是块不是组件**。响应式更新精确到"读了该信号的最小块"，没有虚拟 DOM diff。

## 组件 DSL 速查

```ruby
class Counter < Citrine::Component
  prop    :title, type: String, default: "Counter"  # type 校验"nil 或该类型实例"（可空）
  state   :count, default: 0                        # 三宏：prop / state / computed
  computed(:double) { count * 2 }                   # 必须带括号（Ruby 语法坑，见下）

  on_mount :focus_input                            # DOM 就位后执行（Symbol 或块）
  on_unmount { stop_timer }

  def view
    stack(gap: 10) do                               # stack=竖排 row=横排（box 必须显式给方向）
      label { "count = #{count} ×2 = #{double}" }   # block 内插值即建立订阅
      text_input(ref: :input, on_key: { "Enter" => :submit })
      button(on_click: :increment) { "＋1" }
    end
  end

  def increment
    self.count += 1
  end
end
```

事件 handler 三形态：Symbol（`on_click: :increment`）/ 零参 Proc / 收 `Citrine::Event` 的 Proc。
事件默认包在 `Citrine.batch` 里：一个 handler 改多个信号只重渲染一轮。

## 常用 API 表

| 场景 | 写法 |
|------|------|
| 组件外建信号 | `Citrine.signal(0)` / `Citrine.signal { 惰性初值 }`——**不要写裸 `Signal.new`**（撞 stdlib `::Signal`） |
| 普通类响应式 | `include Citrine::Reactive` 后 `signal(0)`（组件别 include，语义冲突） |
| 按 key 记忆的信号表 | `keyed_signal(:cell, [row, col]) { 初值 }` |
| 响应式集合 | `Citrine.signal_list([...])`：`<<`/`push`/`delete_at`/`replace`/`sort!` 每次变更一次通知；`get` 返回**冻结**快照（`rows.get << x` 当场 FrozenError）；`push_bounded(x, limit)` 有上限追加一次通知 |
| 只读快照不订阅 | `signal.peek`（`get` 会把取值与订阅绑定） |
| 副作用订阅 | `watch :sync_title` / `watch { ... }`——挂载后跑一次，读到的信号一变就重跑，卸载自动 dispose（替代手写 mount/unmount 样板） |
| effect + cleanup | `effect { ...; -> { cleanup } }`（块返回 Proc 即清理函数） |
| 全局快捷键 | 类宏 `window_key :handler`（window 级 keydown，随组件卸载自动解绑） |
| 元素句柄 | `ref: :input` → `refs[:input].focus` |
| 布局 | `stack { }` / `row { }` 是 `box(direction:)` 语法糖；`box` 默认横排，面板忘写方向会"塌成一条"且测试桩测不出来 |
| 收敛订阅粒度 | `box(css_class: -> { cell_class(row, col) })`——Proc 在该节点自己的 Effect 里求值；直接写实参会让**外层块**订阅，改一格重建整块 |
| SSR | `Citrine.render(component)`（纯 CRuby，StringRenderer） |
| 批量更新 | 显式 `Citrine.batch { ... }`（事件分发已自动包裹） |
| 依赖注入 | `provide_context(:key, value)` / `use_context(:key)`（绑定随组件实例缓存，provider 变化需换 key 重建） |
| 错误边界 | 类宏 `error_fallback { |error| ... }`（信号驱动重跑路径也覆盖） |

## 跨平台陷阱（CRuby 单测全绿 ≠ 浏览器正确）

写应用代码时按条自查；完整版见 gem 内 README"技术备忘"：

1. **整数除法**：Opal 下 `7 / 2` 是 `3.5`（CRuby 是 `3`）。用 `Citrine::Num.idiv(a, b)`——`(a/b).to_i` 不等价（负数向零截断）。
2. **负数取整**：`(-1.5).round` 两侧不同。用 `Citrine::Num.round_to(v, digits)`。
3. **可变字符串方法不存在**：`String#<<`/`gsub!`/`[]=` 在 Opal 抛 NotImplementedError。用 `buffer + ch` 或数组 join。
4. **浮点打印**：Opal 下 `2.0.to_s` 是 `"2"`。定长小数用 `format("%.2f", v)`。
5. **反引号互操作**：不要插值 `Native` 包装对象（静默不生效）；Ruby 局部变量会遮蔽 JS 全局——别用 `window`/`document`/`event`/`name` 当变量名；JS 反调 Ruby 方法名改名规则 `!`→`$excl` 等，优先 `Opal.send(obj, "name!")`。
6. **实参静默丢弃**：给固定 arity 方法多传实参，Opal 不报错、只跑前面的——别依赖"多传会报错"兜底。
7. **`整数 ** 0` 返回 Rational**（Opal）：`10 ** 0` 是 `1/1`。
8. 数值工具统一用 **`Citrine::Num`**（`idiv`/`round_to`/`percent`/`integral?`…），别自己再写一份。

## v1 已知语义（不是 bug，别"修"）

- 列表渲染给 `key:` 命中即复用节点与组件实例（未命中仍块级重建）；不给 key 就是整体重建。
- `signal_list` 每次变更**一次通知**；`get` 冻结快照；`rows.get << x` 会 FrozenError 而非静默失败。
- `computed(:x) { }` **必须带括号**——`computed :x { }` 被 Ruby 解析成传 Hash。
- SSR 不建 Effect、不序列化事件；Canvas 后端布局是线性 stack/flow。
- 样式键全域 snake_case；camelCase/kebab-case 输入在渲染边界自动归一。
- `prop` 带 `type:` 时校验语义是"nil 或该类型实例"（可空 prop 直接写，无需 `default: nil`）。

## 测试与调试

- **CRuby 侧可单测**：组件逻辑、信号、SSR 输出都不需要浏览器；`Citrine.render` 做 SSR 快照断言。
- **布局类 bug 桩测不出来**（Node 桩无布局引擎）——视觉问题用 `citrine dev` 真机看，或 headless Chrome。
- 开发模式页面注入 `window.CITRINE_DEV`；控制台会汇总"未声明方向的 box"等开发期提醒。
- 自动化测试输入回车：某些驱动（如 ZCode 内置浏览器）的 `press("Enter")` 不派发 keydown，
  用合成事件 `dispatchEvent(new KeyboardEvent("keydown", {key: "Enter"}))`。

## 深入参考（按需读，别一次全读）

- gem 内 `README.md`——完整技术备忘与 API 细节（第一权威）
- `examples/components.rb`——四后端共享的实战组件代码（第二权威）
- `GOALS.md`——架构决策与路线图；`docs/PLAN-*.md`——批次计划
- 改框架本身前必读仓库 `AGENTS.md`（架构红线）与 `GOALS.md` 第七节（状态模型定案）
