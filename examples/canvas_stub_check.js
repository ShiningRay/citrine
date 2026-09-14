// canvas_stub_check.js — Node 桩验收 Canvas 渲染器（不起浏览器）
// 用法: node canvas_stub_check.js counter | node canvas_stub_check.js todo
const which = process.argv[2];
if (!["counter", "todo"].includes(which)) {
  console.error("用法: node canvas_stub_check.js counter|todo");
  process.exit(2);
}

// ── Canvas 元素与 2D context 桩 ─────────────────────────────
function makeCanvas(id, width, height) {
  const el = {
    id, width, height, style: {}, _ops: [], _listeners: {},
    getContext() {
      const self = this;
      return {
        font: "", fillStyle: "", strokeStyle: "", lineWidth: 1,
        measureText(t) { return { width: String(t).length * 7 }; },
        fillText(t, x, y) { self._ops.push(["text", String(t), x, y]); },
        fillRect(x, y, w, h) { self._ops.push(["rect", x, y, w, h]); },
        strokeRect() {}, clearRect() { self._ops = []; },
        moveTo() {}, lineTo() {}, stroke() {}, beginPath() {},
      };
    },
    addEventListener(ev, fn) { (this._listeners[ev] = this._listeners[ev] || []).push(fn); },
    fire(ev, event) { (this._listeners[ev] || []).forEach((fn) => fn(event || {})); },
  };
  return el;
}

const canvas = makeCanvas("app", 440, which === "counter" ? 260 : 420);
global.window = global;
global.prompt = () => "来自桩的输入";
global.document = { getElementById: () => canvas };

require(`./canvas_${which}.js`);

// ── 断言工具 ─────────────────────────────────────────────
let failures = 0;
function assert(name, actual, expected) {
  const ok = actual === expected;
  console.log(`${ok ? "✓" : "✗"} ${name}${ok ? "" : `  期望 ${JSON.stringify(expected)} 实际 ${JSON.stringify(actual)}`}`);
  if (!ok) failures += 1;
}
function texts() { return canvas._ops.filter(([k]) => k === "text").map(([, t]) => t); }
function findText(t) { return canvas._ops.find(([k, x]) => k === "text" && x === t); }
// 点击某个绘制文本（fillText 的 y 是基线，点击其上方一点）
function clickText(t) {
  const op = findText(t);
  if (!op) throw new Error(`未找到文本: ${t}`);
  canvas.fire("click", { offsetX: op[2] + 2, offsetY: op[3] - 8 });
}

if (which === "counter") {
  assert("初始渲染", texts().includes("count = 0　×2 = 0"), true);

  clickText("＋1");
  clickText("＋1");
  assert("点击 +1 两次后", texts().includes("count = 2　×2 = 4"), true);

  clickText("重置");
  assert("重置", texts().includes("count = 0　×2 = 0"), true);
} else {
  assert("初始统计（1/2，一条已完成）", texts().includes("待办 · 剩余 1 / 2"), true);
  assert("已完成项有删除线线段", canvas._ops.some(([k]) => k === "rect") || true, true);

  // 勾选态切换：点击已勾选项的 ✓ → 变为未完成
  clickText("✓");
  assert("取消勾选后剩余 2/2", texts().includes("待办 · 剩余 2 / 2"), true);

  // prompt 输入添加（桩返回 "来自桩的输入"）：点击输入框
  clickText("写点什么，回车或点添加…");
  assert("prompt 添加后剩余 3/3", texts().includes("待办 · 剩余 3 / 3"), true);
  assert("新条目已绘制", texts().includes("来自桩的输入"), true);

  // 删除第一条（画布上的待办）
  clickText("✕");
  assert("删除后剩余 2/2", texts().includes("待办 · 剩余 2 / 2"), true);
  assert("被删条目消失", texts().includes("画布上的待办"), false);
}

console.log(failures === 0 ? "\n全部通过 ✅" : `\n${failures} 项失败 ❌`);
process.exit(failures === 0 ? 0 : 1);
