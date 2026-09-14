// stub_check.js — 用最小 DOM 桩在 Node 里冒烟测试 Opal 互操作(不起浏览器)
function makeEl(tag) {
  return {
    tagName: tag,
    textContent: "",
    style: {},
    children: [],
    _listeners: {},
    appendChild(c) { this.children.push(c); return c; },
    addEventListener(ev, fn) { (this._listeners[ev] = this._listeners[ev] || []).push(fn); },
  };
}
global.window = global;
global.document = { body: makeEl("body"), createElement: (t) => makeEl(t) };

require("./demo.js");

const b = document.body;
console.log("h1    :", b.children[0].textContent);
console.log("p1    :", b.children[1].textContent);
console.log("count :", b.children[2].textContent);
console.log("btn   :", b.children[3].textContent);

// 模拟点击按钮 ×2
b.children[3]._listeners.click[0]();
b.children[3]._listeners.click[0]();
console.log("--- 点击 x2 后 ---");
console.log("count :", b.children[2].textContent);
console.log("btn   :", b.children[3].textContent);
