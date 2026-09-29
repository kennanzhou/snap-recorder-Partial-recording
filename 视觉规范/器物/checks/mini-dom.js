'use strict';
/*
 * 最小 DOM 与虚拟时钟：只用于在 Node 里离线跑样片脚本的模拟交互检查。
 * 它不做布局、不跑 CSS、不渲染画面，所以通过这里的检查不等于真实浏览器里的视觉与交互验收。
 * 支持的选择器：标签、#id、.class、[attr]、[attr="v"]、[attr^="v"]、:not(...)，以及空格后代组合。
 */

const VOID = new Set(['area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'source', 'track', 'wbr']);

function createClock() {
  let now = 0;
  let seq = 0;
  const queue = [];
  return {
    now: () => now,
    setTimeout(fn, ms) { const id = ++seq; queue.push({ id, at: now + Math.max(0, ms | 0), fn, every: 0 }); return id; },
    setInterval(fn, ms) { const id = ++seq; const every = Math.max(1, ms | 0); queue.push({ id, at: now + every, fn, every }); return id; },
    clear(id) { const i = queue.findIndex((t) => t.id === id); if (i >= 0) queue.splice(i, 1); },
    advance(ms) {
      const end = now + ms;
      for (;;) {
        queue.sort((a, b) => a.at - b.at || a.id - b.id);
        const t = queue[0];
        if (!t || t.at > end) break;
        now = t.at;
        if (t.every) t.at += t.every; else queue.shift();
        t.fn();
      }
      now = end;
    },
    pendingIntervals: () => queue.filter((t) => t.every).length
  };
}

function evt(type, props) {
  return Object.assign({
    type, target: null, defaultPrevented: false,
    preventDefault() { this.defaultPrevented = true; },
    stopPropagation() {}
  }, props || {});
}

class Node0 { constructor(type) { this.nodeType = type; this.parentNode = null; this.childNodes = []; } }
function detach(n) {
  const p = n.parentNode;
  if (!p) return;
  const i = p.childNodes.indexOf(n);
  if (i >= 0) p.childNodes.splice(i, 1);
  n.parentNode = null;
}
function walk(n, fn) { for (const c of n.childNodes) if (c.nodeType === 1) { fn(c); walk(c, fn); } }

class TextNode extends Node0 {
  constructor(data) { super(3); this.data = data; }
  get textContent() { return this.data; }
  set textContent(v) { this.data = String(v); }
  remove() { detach(this); }
}

/* ---------- 选择器 ---------- */
function parseCompound(s) {
  const c = { tag: null, id: null, classes: [], attrs: [], nots: [] };
  let i = 0;
  const m0 = /^[a-zA-Z][\w-]*/.exec(s);
  if (m0) { c.tag = m0[0].toLowerCase(); i = m0[0].length; }
  while (i < s.length) {
    const rest = s.slice(i);
    let m;
    if ((m = /^#([\w-]+)/.exec(rest))) c.id = m[1];
    else if ((m = /^\.([\w-]+)/.exec(rest))) c.classes.push(m[1]);
    else if ((m = /^\[([\w-]+)(?:(\^?=)"([^"]*)")?\]/.exec(rest))) c.attrs.push({ name: m[1], op: m[2] || null, value: m[3] });
    else if (rest.startsWith(':not(')) {
      let depth = 0;
      let j = 4;
      for (; j < rest.length; j++) {
        if (rest[j] === '(') depth++;
        else if (rest[j] === ')') { depth--; if (!depth) break; }
      }
      c.nots.push(parseCompound(rest.slice(5, j)));
      m = [rest.slice(0, j + 1)];
    } else throw new Error(`迷你 DOM 不支持的选择器：${s}`);
    i += m[0].length;
  }
  return c;
}
function matchCompound(el, c) {
  if (!el || el.nodeType !== 1) return false;
  if (c.tag && el.localName.toLowerCase() !== c.tag) return false;
  if (c.id && el.id !== c.id) return false;
  if (c.classes.length) { const cls = el._classes(); if (!c.classes.every((x) => cls.has(x))) return false; }
  for (const a of c.attrs) {
    const v = el.getAttribute(a.name);
    if (v === null) return false;
    if (a.op === '=' && v !== a.value) return false;
    if (a.op === '^=' && !v.startsWith(a.value)) return false;
  }
  return !c.nots.some((n) => matchCompound(el, n));
}
const selectorCache = new Map();
function matchSelector(el, sel) {
  let parts = selectorCache.get(sel);
  if (!parts) {
    const raw = [];
    let cur = '';
    let bracket = 0;
    let quote = false;
    for (const ch of sel.trim()) {
      if (ch === '"') quote = !quote;
      if (!quote && ch === '[') bracket++;
      if (!quote && ch === ']') bracket--;
      if (!quote && !bracket && /\s/.test(ch)) { if (cur) raw.push(cur); cur = ''; continue; }
      cur += ch;
    }
    if (cur) raw.push(cur);
    parts = raw.map(parseCompound);
    selectorCache.set(sel, parts);
  }
  if (!matchCompound(el, parts[parts.length - 1])) return false;
  let k = parts.length - 2;
  let n = el.parentNode;
  while (k >= 0 && n) { if (n.nodeType === 1 && matchCompound(n, parts[k])) k--; n = n.parentNode; }
  return k < 0;
}

/* ---------- 元素 ---------- */
function makeElementClass(state) {
  const dashed = (k) => 'data-' + k.replace(/[A-Z]/g, (m) => '-' + m.toLowerCase());
  return class El extends Node0 {
    constructor(tag, attrs) {
      super(1);
      this.localName = tag;
      this.tagName = tag.toUpperCase();
      this.attrs = new Map(attrs || []);
      this.listeners = {};
      const self = this;
      const styleStore = {};
      this.style = new Proxy(styleStore, {
        get(t, k) {
          if (k === 'setProperty') return (n, v) => { t[n] = String(v); };
          if (k === 'getPropertyValue') return (n) => t[n] || '';
          return t[k] === undefined ? '' : t[k];
        },
        set(t, k, v) { t[k] = String(v); return true; }
      });
      this.classList = {
        add: (...c) => { const s = self._classes(); c.forEach((x) => s.add(x)); self._setClasses(s); },
        remove: (...c) => { const s = self._classes(); c.forEach((x) => s.delete(x)); self._setClasses(s); },
        toggle: (c, force) => { const s = self._classes(); const on = force === undefined ? !s.has(c) : !!force; if (on) s.add(c); else s.delete(c); self._setClasses(s); return on; },
        contains: (c) => self._classes().has(c)
      };
      this.dataset = new Proxy({}, {
        get(t, k) { if (typeof k !== 'string') return undefined; const v = self.getAttribute(dashed(k)); return v === null ? undefined : v; },
        set(t, k, v) { self.setAttribute(dashed(k), String(v)); return true; }
      });
    }
    _classes() { return new Set((this.getAttribute('class') || '').split(/\s+/).filter(Boolean)); }
    _setClasses(s) { this.setAttribute('class', Array.from(s).join(' ')); }
    get className() { return this.getAttribute('class') || ''; }
    set className(v) { this.setAttribute('class', String(v)); }
    getAttribute(n) { return this.attrs.has(n) ? this.attrs.get(n) : null; }
    setAttribute(n, v) { this.attrs.set(n, String(v)); }
    removeAttribute(n) { this.attrs.delete(n); }
    hasAttribute(n) { return this.attrs.has(n); }
    get id() { return this.getAttribute('id') || ''; }
    get hidden() { return this.hasAttribute('hidden'); }
    set hidden(v) { if (v) this.setAttribute('hidden', ''); else this.removeAttribute('hidden'); }
    get disabled() { return this.hasAttribute('disabled'); }
    set disabled(v) { if (v) this.setAttribute('disabled', ''); else this.removeAttribute('disabled'); }
    get title() { return this.getAttribute('title') || ''; }
    set title(v) { this.setAttribute('title', v); }
    get tabIndex() {
      const t = this.getAttribute('tabindex');
      if (t !== null) return parseInt(t, 10);
      return ['button', 'input', 'select', 'a'].includes(this.localName) ? 0 : -1;
    }
    set tabIndex(v) { this.setAttribute('tabindex', String(v)); }
    get textContent() { return this.childNodes.map((c) => c.textContent).join(''); }
    set textContent(v) { this.childNodes.slice().forEach(detach); const s = String(v); if (s) this.appendChild(new TextNode(s)); }
    appendChild(c) { detach(c); c.parentNode = this; this.childNodes.push(c); return c; }
    append(...cs) { cs.forEach((c) => this.appendChild(typeof c === 'string' ? new TextNode(c) : c)); }
    replaceChildren(...cs) { this.childNodes.slice().forEach(detach); this.append(...cs); }
    remove() { detach(this); }
    contains(n) { while (n) { if (n === this) return true; n = n.parentNode; } return false; }
    closest(sel) { let n = this; while (n && n.nodeType === 1) { if (matchSelector(n, sel)) return n; n = n.parentNode; } return null; }
    querySelectorAll(sel) { const out = []; walk(this, (n) => { if (matchSelector(n, sel)) out.push(n); }); return out; }
    querySelector(sel) { return this.querySelectorAll(sel)[0] || null; }
    addEventListener(type, fn) { (this.listeners[type] = this.listeners[type] || []).push(fn); }
    removeEventListener() {}
    dispatchEvent(ev) {
      if (!ev.target) ev.target = this;
      let n = this;
      while (n) { ((n.listeners && n.listeners[ev.type]) || []).slice().forEach((fn) => fn.call(n, ev)); n = n.parentNode; }
      return !ev.defaultPrevented;
    }
    click() {
      if (this.disabled) return;
      const box = this.localName === 'input' && this.getAttribute('type') === 'checkbox';
      if (box) this.checked = !this.checked;
      this.dispatchEvent(evt('click'));
      if (box) this.dispatchEvent(evt('change'));
    }
    focus() { state.doc.activeElement = this; }
    blur() { if (state.doc.activeElement === this) state.doc.activeElement = state.doc.body; }
    getBoundingClientRect() { return { left: 0, top: 0, right: state.stageW, bottom: state.stageH, width: state.stageW, height: state.stageH, x: 0, y: 0 }; }
    get clientWidth() { return this.id === 'stage' ? state.stageW : 0; }
    get clientHeight() { return this.id === 'stage' ? state.stageH : 0; }
    get offsetWidth() { return 0; }
    get offsetParent() { let n = this; while (n && n.nodeType === 1) { if (n.hidden) return null; n = n.parentNode; } return this.parentNode; }
    scrollIntoView() { state.scrolled.push(this.id); }
    get value() {
      if (this.localName === 'select') {
        const opts = this.querySelectorAll('option');
        const i = this.selectedIndex;
        return i >= 0 && opts[i] ? opts[i].getAttribute('value') : '';
      }
      return this._value !== undefined ? this._value : (this.getAttribute('value') || '');
    }
    set value(v) {
      if (this.localName === 'select') { this._selected = this.querySelectorAll('option').findIndex((o) => o.getAttribute('value') === String(v)); }
      else this._value = String(v);
    }
    get selectedIndex() { return this._selected === undefined ? 0 : this._selected; }
    set selectedIndex(i) { this._selected = i; }
    get checked() { return this._checked !== undefined ? this._checked : this.hasAttribute('checked'); }
    set checked(v) { this._checked = !!v; }
  };
}

class Doc extends Node0 {
  constructor(El) { super(9); this.El = El; this.listeners = {}; this.activeElement = null; }
  get body() { return this.querySelector('body'); }
  querySelectorAll(sel) { const out = []; walk(this, (n) => { if (matchSelector(n, sel)) out.push(n); }); return out; }
  querySelector(sel) { return this.querySelectorAll(sel)[0] || null; }
  getElementById(id) { return this.querySelector(`#${id}`); }
  createElement(tag) { return new this.El(tag, []); }
  createTextNode(t) { return new TextNode(t); }
  addEventListener(type, fn) { (this.listeners[type] = this.listeners[type] || []).push(fn); }
  appendChild(c) { detach(c); c.parentNode = this; this.childNodes.push(c); return c; }
}

/* ---------- HTML 解析（仅针对本方案页面这类结构规整的文件） ---------- */
function createDocument(html, options) {
  const state = { doc: null, scrolled: [], stageW: (options && options.stageW) || 1000, stageH: (options && options.stageH) || 625 };
  const El = makeElementClass(state);
  const doc = new Doc(El);
  state.doc = doc;
  const stack = [doc];
  const re = /<!--[\s\S]*?-->|<!doctype[^>]*>|<\/([a-zA-Z][\w:-]*)\s*>|<([a-zA-Z][\w:-]*)((?:\s+[^\s"'>/=]+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s"'=<>`]+))?)*)\s*(\/?)>|([^<]+)/gi;
  let m;
  while ((m = re.exec(html))) {
    const top = stack[stack.length - 1];
    if (m[1]) {
      const name = m[1].toLowerCase();
      for (let i = stack.length - 1; i > 0; i--) if (stack[i].localName.toLowerCase() === name) { stack.length = i; break; }
    } else if (m[2]) {
      const attrs = [];
      const ar = /([^\s"'>/=]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g;
      let a;
      while ((a = ar.exec(m[3] || ''))) attrs.push([a[1], a[2] ?? a[3] ?? a[4] ?? '']);
      const el = new El(m[2], attrs);
      top.appendChild(el);
      if (!VOID.has(m[2].toLowerCase()) && !m[4]) stack.push(el);
    } else if (m[5]) top.appendChild(new TextNode(m[5]));
  }
  doc.activeElement = doc.body;
  return { doc, state };
}

module.exports = { createDocument, createClock, evt };
