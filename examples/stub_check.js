// stub_check.js — Node DOM 桩验收 M1 示例（不起浏览器）
// 用法: node stub_check.js counter | todo | reactive_props | keyed_list
const which = process.argv[2];
if (!["counter", "todo", "reactive_props", "keyed_list"].includes(which)) {
  console.error("用法: node stub_check.js counter|todo|reactive_props|keyed_list");
  process.exit(2);
}

function makeEl(tag) {
  return {
    tagName: tag,
    textContent: "",
    style: {},
    children: [],
    parentElement: null,
    _listeners: {},
appendChild(c) {
  // 真实 DOM 的 appendChild 是"移动"：已在别处的节点先摘下来，已在同一父下的也移到末尾
  if (c.parentElement && c.parentElement !== this) c.parentElement.removeChild(c);
  this.children = this.children.filter((x) => x !== c);
  c.parentElement = this;
  this.children.push(c);
  return c;
},
    removeChild(c) { c.parentElement = null; this.children = this.children.filter((x) => x !== c); },
    addEventListener(ev, fn) { (this._listeners[ev] = this._listeners[ev] || []).push(fn); },
    fire(ev, event) { (this._listeners[ev] || []).forEach((fn) => fn(event || {})); },
  };
}

const app = makeEl("div");
global.window = global;
global.document = { getElementById: () => app, createElement: (t) => makeEl(t) };

// window 级监听（G-9 的 window_key）：Node 的 global 本身没有 addEventListener，补最小实现
const windowListeners = {};
global.addEventListener = (ev, fn) => { (windowListeners[ev] = windowListeners[ev] || []).push(fn); };
global.removeEventListener = (ev, fn) => { windowListeners[ev] = (windowListeners[ev] || []).filter((f) => f !== fn); };
function fireWindow(ev, event) { (windowListeners[ev] || []).forEach((fn) => fn(event || {})); }

require(`./${which}.js`);

// ── 断言工具 ─────────────────────────────────────────────
let failures = 0;
function assert(name, actual, expected) {
  const ok = actual === expected;
  console.log(`${ok ? "✓" : "✗"} ${name}${ok ? "" : `  期望 ${JSON.stringify(expected)} 实际 ${JSON.stringify(actual)}`}`);
  if (!ok) failures += 1;
}
function texts(el) { // 深度收集文本
  return [el.textContent, ...el.children.flatMap(texts)].filter((t) => t && t.trim() !== "");
}
function findButton(el, text) {
  return el.children.flatMap(function walk(n) {
    return [n, ...n.children.flatMap(walk)];
  }).find((n) => n.tagName === "button" && n.textContent === text);
}
function findAll(el, tag) {
  return el.children.flatMap(function walk(n) {
    return [n, ...n.children.flatMap(walk)];
  }).filter((n) => n.tagName === tag);
}

if (which === "counter") {
  const value = () => texts(app).find((t) => t.startsWith("count = "));
  assert("初始渲染", value(), "count = 0　×2 = 0");

  findButton(app, "＋1").fire("click");
  findButton(app, "＋1").fire("click");
  assert("点击 +1 两次", value(), "count = 2　×2 = 4");

  findButton(app, "－1").fire("click");
  assert("点击 －1 一次", value(), "count = 1　×2 = 2");

  findButton(app, "重置").fire("click");
  assert("重置", value(), "count = 0　×2 = 0");
} else if (which === "reactive_props") {
  // 响应式属性（G-2）：点格子只重设两格属性，DOM 节点零重建
  const cells = () => findAll(app, "div").filter((d) => (d.className || "").startsWith("cell"));
  const status = () => texts(app).find((t) => t.startsWith("选中"));

  assert("初始 5 格", cells().length, 5);
  assert("初始状态文本", status(), "选中：格 0");
  assert("初始选中格类名", cells()[0].className, "cell on");
  assert("初始选中格样式", cells()[0].style.background, "#fde68a");

  const before = cells();
  cells()[2].fire("click");
  const after = cells();

  assert("点击后状态文本更新", status(), "选中：格 2");
  assert("新选中格类名", after[2].className, "cell on");
  assert("原选中格类名复原", after[0].className, "cell");
  assert("新选中格样式更新", after[2].style.background, "#fde68a");
  assert("原选中格样式复原", after[0].style.background, "#f1f5f9");
  assert("兄弟格 DOM 未被重建", after[1] === before[1] && after[3] === before[3] && after[4] === before[4], true);
  assert("目标格 DOM 未被重建（只重设属性）", after[2] === before[2], true);
  assert("整棵子树节点数不变", after.length, before.length);
  assert("旧格消失的样式键被清空", after[0].style.boxShadow, "");
  assert("新选中格拿到描边", after[2].style.boxShadow, "0 0 0 2px #f59e0b");

  // G-9：window_key —— 全局 ← → 移动选中（处理器拿到归一化的 KeyEvent）
  fireWindow("keydown", { key: "ArrowRight" });
  assert("→ 前进一格", status(), "选中：格 3");
  fireWindow("keydown", { key: "ArrowLeft" });
  fireWindow("keydown", { key: "ArrowLeft" });
  assert("← 两次回退到格 1", status(), "选中：格 1");
  assert("键盘移动同样只重设属性", after[1] === cells()[1] && cells()[1].className, "cell on");

  // G-10：卸载 —— 跑 on_unmount、清理 DOM、解绑全局键盘
  findButton(app, "卸载").fire("click");
  assert("卸载后 DOM 清空", app.children.length, 0);
  assert("卸载后 window 监听解绑", (windowListeners.keydown || []).length, 0);
  fireWindow("keydown", { key: "ArrowRight" });
  assert("卸载后按键不再有反应", app.children.length, 0);
} else if (which === "keyed_list") {
  // 组件嵌套 + keyed 复用（P0-1）：重排/增删不能换掉行节点与输入框
  const rows = () => findAll(app, "div").filter((d) => (d.className || "").split(" ").includes("row"));
  const inputs = () => findAll(app, "input");
  const count = () => texts(app).find((t) => t.startsWith("行数"));
  const clickBtn = (text) => findButton(app, text).fire("click");
  const sameSet = (a, b) => a.length === b.length && a.every((x) => b.includes(x));

  assert("初始 3 行", rows().length, 3);
  assert("初始顺序", count(), "行数：3 · 顺序：A B C");

  // 在 B 行的输入框里打字
  const beforeRows = rows();
  const beforeInputs = inputs();
  const bInput = findAll(beforeRows[1], "input")[0];
  bInput.value = "12345";
  bInput.fire("input");
  assert("输入已记录", bInput.value, "12345");

  // 重排：行节点与输入框都应被复用（只是换位置）
  clickBtn("重排");
  const afterRows = rows();
  const afterInputs = inputs();
  assert("重排后顺序", count(), "行数：3 · 顺序：C B A");
  assert("重排复用同一批行节点", sameSet(afterRows, beforeRows), true);
  assert("重排复用同一批输入框", sameSet(afterInputs, beforeInputs), true);
  assert("输入框的值没丢", findAll(afterRows[1], "input")[0].value, "12345");
  assert("输入框还是同一个节点", findAll(afterRows[1], "input")[0], bInput);

  // 加一行：既有行不受影响，只多一个新行
  clickBtn("加一行");
  const afterAdd = rows();
  assert("加一行后 4 行", afterAdd.length, 4);
  assert("加行不换旧行", afterAdd.slice(0, 3).every((r, i) => r === afterRows[i]), true);
  assert("加行不动输入框", findAll(afterAdd[1], "input")[0], bInput);

  // 删第一行：只摘掉那一行
  const removed = afterAdd[0];
  clickBtn("删第一行");
  const afterDrop = rows();
  assert("删一行后 3 行", afterDrop.length, 3);
  assert("被删的行已摘除", afterDrop.indexOf(removed), -1);
  assert("其余行原样复用", afterDrop.every((r, i) => r === afterAdd[i + 1]), true);
  assert("输入框仍在且值还在", findAll(afterDrop[0], "input")[0] === bInput && bInput.value, "12345");
} else if (which === "todo") {
  const summary = () => texts(app).find((t) => t.startsWith("待办"));
  const input = findAll(app, "input").find((i) => i._listeners.input);
  const addButton = findButton(app, "添加 ↵");

  assert("初始为空", summary(), "待办 · 剩余 0 / 0");

  // 添加两条
  input.value = "买牛奶";
  input.fire("input");
  input.fire("keydown", { key: "Enter" });
  input.value = "写 GOALS";
  input.fire("input");
  addButton.fire("click");
  assert("添加两条后统计", summary(), "待办 · 剩余 2 / 2");
  assert("输入框已清空", input.value, "");

  // G-9：元素级键盘 on_key: { "Escape" => :clear_draft }
  input.value = "临时草稿";
  input.fire("input");
  input.fire("keydown", { key: "Escape" });
  assert("Esc 清空输入框", input.value, "");

  // 勾选第一条
  const box1 = findAll(app, "input").find((i) => i._listeners.change);
  box1.checked = true;
  box1.fire("change");
  assert("勾选后剩余减一", summary(), "待办 · 剩余 1 / 2");

  // 删除第二条（未勾选的那条）
  const deletes = findAll(app, "button").filter((b) => b.textContent === "✕");
  deletes[1].fire("click");
  assert("删除第二条后统计", summary(), "待办 · 剩余 0 / 1");

  // 空输入不添加
  input.value = "   ";
  input.fire("input");
  input.fire("keydown", { key: "Enter" });
  assert("空白输入不添加", summary(), "待办 · 剩余 0 / 1");
}

console.log(failures === 0 ? "\n全部通过 ✅" : `\n${failures} 项失败 ❌`);
process.exit(failures === 0 ? 0 : 1);
