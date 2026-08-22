#!/usr/bin/env bash
# tests/board-dom-helpers.sh - drive a rendered operator board's own script the
# way a browser would.
#
# The board's answer contract lives entirely in the page's JavaScript, so
# asserting the emitted source would only restate the implementation. This helper
# instead loads the artifact, runs its real script against a small DOM, clicks the
# controls an operator clicks, and reports what the page then did: the payload it
# handed the review bridge and the state each card ended in.
#
# It lives beside the suite rather than in tests/lib.sh because only the board
# suite has a page to drive. Generic reporters and assertions come from lib.sh.

# shellcheck source=tests/lib.sh
# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# fm_board_drive [--no-bridge] <artifact> <card-key> <first-option> [second-option] > <json>
#
# Picks <first-option> on the card, presses Send, then - when a second option is
# given - picks it on the now-answered card and presses Send again, and finally
# presses Send once more with nothing picked. With --no-bridge the sandbox has
# no review bridge, so the page falls back to its clipboard path instead.
# Prints one JSON object:
#   sends[]        every payload handed to the bridge, in order
#   copies[]       every string handed to the clipboard, in order
#   beforeSend     the card's classes and answered note before the first send
#   afterSend      the same after the first send
#   afterRepick    the same after picking the second option
#   afterIdleSend  the same after the final empty press
fm_board_drive() {  # [--no-bridge] <artifact> <card-key> <first-option> [second-option]
  local bridge=1
  if [ "${1-}" = "--no-bridge" ]; then bridge=0; shift; fi
  local driver
  driver=$(fm_test_tmproot fm-board-driver)/drive.js
  cat > "$driver" <<'BOARD_DOM_DRIVER_JS'
'use strict';

const fs = require('fs');
const vm = require('vm');

const VOID = new Set(['area', 'base', 'br', 'col', 'hr', 'img', 'input', 'link', 'meta', 'source']);

const proto = {
  getAttribute(name) {
    return Object.prototype.hasOwnProperty.call(this.attrs, name) ? this.attrs[name] : null;
  },
  setAttribute(name, value) { this.attrs[name] = String(value); },
  removeAttribute(name) { delete this.attrs[name]; },
  get classList() {
    const el = this;
    const list = () => (el.attrs.class || '').split(/\s+/).filter(Boolean);
    const write = (v) => { el.attrs.class = v.join(' '); };
    return {
      contains: (c) => list().indexOf(c) !== -1,
      add: (c) => { const v = list(); if (v.indexOf(c) === -1) { v.push(c); write(v); } },
      remove: (c) => write(list().filter((x) => x !== c)),
      toggle: (c, force) => {
        const on = force === undefined ? list().indexOf(c) === -1 : !!force;
        if (on) { const v = list(); if (v.indexOf(c) === -1) { v.push(c); write(v); } }
        else { write(list().filter((x) => x !== c)); }
      },
    };
  },
  get parentNode() { return this.parent; },
  removeChild(child) {
    this.children = this.children.filter((c) => c !== child);
    child.parent = null;
    return child;
  },
  get hidden() { return Object.prototype.hasOwnProperty.call(this.attrs, 'hidden'); },
  set hidden(v) { if (v) { this.attrs.hidden = ''; } else { delete this.attrs.hidden; } },
  get value() { return this.attrs.value === undefined ? '' : this.attrs.value; },
  get name() { return this.attrs.name === undefined ? '' : this.attrs.name; },
  get textContent() {
    if (this.tag === '#text') return this.text;
    return this.children.map((c) => c.textContent).join('');
  },
  set textContent(v) {
    this.children = v === '' ? [] : [mk('#text', {}, String(v))];
    this.children.forEach((c) => { c.parent = this; });
  },
  cloneNode() {
    const copy = mk(this.tag, Object.assign({}, this.attrs), this.text);
    copy.children = this.children.map((c) => {
      const cc = c.cloneNode(true);
      cc.parent = copy;
      return cc;
    });
    return copy;
  },
  closest(sel) {
    let node = this;
    while (node) {
      if (node.tag !== '#root' && node.tag !== '#text' && matches(node, sel)) return node;
      node = node.parent;
    }
    return null;
  },
  querySelector(sel) { return this.querySelectorAll(sel)[0] || null; },
  querySelectorAll(sel) { return select(this, sel); },
  addEventListener(type, fn) {
    (this.listeners[type] = this.listeners[type] || []).push(fn);
  },
  dispatch(type) {
    (this.listeners[type] || []).forEach((fn) => fn.call(this, { type, target: this }));
  },
};

function mk(tag, attrs, text) {
  const el = Object.create(proto);
  el.tag = tag;
  el.attrs = attrs || {};
  el.children = [];
  el.parent = null;
  el.listeners = {};
  el.checked = false;
  if (text !== undefined) el.text = text;
  return el;
}

function parseAttrs(src) {
  const attrs = {};
  const re = /([a-zA-Z0-9_:-]+)(?:="([^"]*)")?/g;
  let m;
  while ((m = re.exec(src))) attrs[m[1].toLowerCase()] = m[2] === undefined ? '' : m[2];
  return attrs;
}

function parse(src) {
  const root = mk('#root', {});
  let cur = root;
  let last = 0;
  const re = /<(\/?)([a-zA-Z][a-zA-Z0-9]*)((?:\s+[a-zA-Z0-9_:-]+(?:="[^"]*")?)*)\s*(\/?)>/g;
  let m;
  const addText = (parent, text) => {
    if (!text) return;
    const node = mk('#text', {}, text);
    node.parent = parent;
    parent.children.push(node);
  };
  while ((m = re.exec(src))) {
    addText(cur, src.slice(last, m.index));
    last = re.lastIndex;
    const tag = m[2].toLowerCase();
    if (m[1]) {
      let node = cur;
      while (node && node.tag !== tag) node = node.parent;
      if (node && node.parent) cur = node.parent;
      continue;
    }
    const el = mk(tag, parseAttrs(m[3] || ''));
    el.parent = cur;
    cur.children.push(el);
    if (!VOID.has(tag) && !m[4]) cur = el;
  }
  addText(cur, src.slice(last));
  return root;
}

// The selector subset the board's script actually uses: descendant chains of
// tag, .class, #id, [attr="value"] and :checked.
function matches(el, compound) {
  const re = /([a-zA-Z][a-zA-Z0-9]*)|\.([\w-]+)|#([\w-]+)|\[([\w-]+)(?:="?([^\]"]*)"?)?\]|:([\w-]+)/g;
  let m;
  while ((m = re.exec(compound))) {
    if (m[1] && el.tag !== m[1].toLowerCase()) return false;
    if (m[2] && !el.classList.contains(m[2])) return false;
    if (m[3] && el.attrs.id !== m[3]) return false;
    if (m[4]) {
      const have = el.getAttribute(m[4]);
      if (have === null) return false;
      if (m[5] !== undefined && have !== m[5]) return false;
    }
    if (m[6] === 'checked' && !el.checked) return false;
  }
  return true;
}

function descendants(el, out) {
  el.children.forEach((c) => {
    if (c.tag === '#text') return;
    out.push(c);
    descendants(c, out);
  });
  return out;
}

function select(root, sel) {
  const parts = sel.trim().split(/\s+(?![^[]*\])/).filter(Boolean);
  let scope = [root];
  parts.forEach((part) => {
    const next = [];
    scope.forEach((s) => descendants(s, []).forEach((d) => {
      if (matches(d, part) && next.indexOf(d) === -1) next.push(d);
    }));
    scope = next;
  });
  return scope;
}

// --- run the artifact's script ----------------------------------------------

const [, , artifact, cardKey, firstValue, secondValue] = process.argv;
const html = fs.readFileSync(artifact, 'utf8');
const script = (html.match(/<script>([\s\S]*?)<\/script>/) || [])[1];
if (!script) throw new Error('the artifact carries no script');
const markup = html
  .replace(/<script>[\s\S]*?<\/script>/g, '')
  .replace(/<style>[\s\S]*?<\/style>/g, '');

const root = parse(markup);
const document = {
  getElementById: (id) => select(root, '#' + id)[0] || null,
  querySelector: (sel) => select(root, sel)[0] || null,
  querySelectorAll: (sel) => select(root, sel),
};

const sends = [];
const lavish = {
  queuePrompt: (text, payload) => sends.push({ text, payload }),
  sendQueuedPrompts: () => {},
};

const copies = [];
const clipboard = {
  writeText: (text) => {
    copies.push(text);
    return { then: (onOk) => { if (onOk) onOk(); } };
  },
};

const sandbox = { document, navigator: { clipboard }, console, setInterval: () => 0, Date, JSON };
sandbox.window = sandbox;
if (process.env.FM_BOARD_BRIDGE !== '0') sandbox.window.lavish = lavish;
vm.createContext(sandbox);
vm.runInContext(script, sandbox);

function pick(value) {
  const input = document.querySelector('.opt input[name="' + cardKey + '"][value="' + value + '"]');
  if (!input) throw new Error('no option ' + value + ' on card ' + cardKey);
  document.querySelectorAll('.opt input[name="' + cardKey + '"]').forEach((i) => { i.checked = false; });
  input.checked = true;
  input.dispatch('change');
  return input;
}

function cardState() {
  const input = document.querySelector('.opt input[name="' + cardKey + '"]');
  const card = input ? input.closest('.card') : null;
  const note = card ? card.querySelector('p.answered') : null;
  return {
    classes: card ? (card.attrs.class || '') : null,
    noteHidden: note ? note.hidden : null,
    noteText: note ? note.textContent : null,
    sendDisabled: !!document.getElementById('send').disabled,
    sendLabel: document.getElementById('send').textContent,
    pending: document.getElementById('pending').textContent,
  };
}

pick(firstValue);
const beforeSend = cardState();
document.getElementById('send').dispatch('click');
const afterSend = cardState();

let afterRepick = null;
if (secondValue) {
  pick(secondValue);
  afterRepick = cardState();
  document.getElementById('send').dispatch('click');
}

document.getElementById('send').dispatch('click');
const afterIdleSend = cardState();

process.stdout.write(JSON.stringify({ sends, copies, beforeSend, afterSend, afterRepick, afterIdleSend }, null, 2));
BOARD_DOM_DRIVER_JS
  FM_BOARD_BRIDGE=$bridge node "$driver" "$@"
}
