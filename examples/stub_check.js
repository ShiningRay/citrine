// stub_check.js — Node DOM 桩验收 M1 示例（不起浏览器）
// 用法: node stub_check.js counter | node stub_check.js todo
const which = process.argv[2];
if (!["counter", "todo"].includes(which)) {
  console.error("用法: node stub_check.js counter|todo");
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
    appendChild(c) { c.parentElement = this; this.children.push(c); return c; },
    removeChild(c) { c.parentElement = null; this.children = this.children.filter((x) => x !== c); },
    addEventListener(ev, fn) { (this._listeners[ev] = this._listeners[ev] || []).push(fn); },
    fire(ev, event) { (this._listeners[ev] || []).forEach((fn) => fn(event || {})); },
  };
}

const app = makeEl("div");
global.window = global;
global.document = { getElementById: () => app, createElement: (t) => makeEl(t) };

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
} else {
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
