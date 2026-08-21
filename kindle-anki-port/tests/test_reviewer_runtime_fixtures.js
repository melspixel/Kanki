'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'web/reviewer.js'), 'utf8');

class Node {
  constructor(type, tag, doc) {
    this.nodeType = type;
    this.tagName = tag ? tag.toUpperCase() : '';
    this.ownerDocument = doc;
    this.parentNode = null;
    this.childNodes = [];
    this.attributes = [];
    this._attrs = Object.create(null);
    this.className = '';
    this.id = '';
    this.style = {};
    this.nodeValue = type === 3 ? '' : null;
    this.text = '';
    this.textContent = '';
    this.innerHTML = '';
    this.scrollHeight = 0;
    this.clientHeight = 0;
    this.scrollIntoViewCalls = 0;
  }
  get firstChild() { return this.childNodes[0] || null; }
  get nextSibling() {
    if (!this.parentNode) return null;
    const i = this.parentNode.childNodes.indexOf(this);
    return i >= 0 ? this.parentNode.childNodes[i + 1] || null : null;
  }
  appendChild(child) {
    if (child.nodeType === 11) {
      while (child.childNodes.length) this.appendChild(child.childNodes.shift());
      return child;
    }
    if (child.parentNode) child.parentNode.removeChild(child);
    child.parentNode = this;
    this.childNodes.push(child);
    return child;
  }
  removeChild(child) {
    const i = this.childNodes.indexOf(child);
    if (i >= 0) this.childNodes.splice(i, 1);
    child.parentNode = null;
    return child;
  }
  replaceChild(replacement, oldChild) {
    const i = this.childNodes.indexOf(oldChild);
    assert(i >= 0, 'replaceChild target missing');
    oldChild.parentNode = null;
    if (replacement.nodeType === 11) {
      const items = replacement.childNodes.slice();
      replacement.childNodes.length = 0;
      items.forEach((item) => { item.parentNode = this; });
      this.childNodes.splice(i, 1, ...items);
    } else {
      if (replacement.parentNode) replacement.parentNode.removeChild(replacement);
      replacement.parentNode = this;
      this.childNodes[i] = replacement;
    }
    return oldChild;
  }
  setAttribute(name, value) {
    value = String(value);
    this._attrs[name] = value;
    if (name === 'id') this.id = value;
    if (name === 'class') this.className = value;
    const existing = this.attributes.find((attribute) => attribute.name === name);
    if (existing) existing.value = value;
    else this.attributes.push({name, value});
  }
  getAttribute(name) {
    return Object.prototype.hasOwnProperty.call(this._attrs, name) ? this._attrs[name] : null;
  }
  getElementsByTagName(tag) {
    tag = String(tag).toLowerCase();
    const out = [];
    function walk(node) {
      node.childNodes.forEach((child) => {
        if (child.nodeType === 1 && (tag === '*' || String(child.tagName).toLowerCase() === tag)) out.push(child);
        walk(child);
      });
    }
    walk(this);
    return out;
  }
  querySelectorAll(selector) {
    const all = this.getElementsByTagName('*');
    if (selector === '.replay-button') return all.filter((node) => (` ${node.className} `).includes(' replay-button '));
    if (selector === '.soundLink') return all.filter((node) => (` ${node.className} `).includes(' soundLink '));
    if (selector === '[data-av-tag]') return all.filter((node) => node.getAttribute('data-av-tag') !== null);
    return [];
  }
  scrollIntoView() { this.scrollIntoViewCalls += 1; }
  focus() { this.focused = true; }
}

class Document {
  constructor() {
    this._listeners = Object.create(null);
    this.body = new Node(1, 'body', this);
    this.documentElement = {clientHeight: 800};
    this.qa = new Node(1, 'div', this);
    this.qa.id = 'qa';
    this.noteStyle = new Node(1, 'style', this);
    this.noteStyle.id = 'kap-note-style';
    this.body.appendChild(this.noteStyle);
    this.body.appendChild(this.qa);
    const qa = this.qa;
    Object.defineProperty(qa, 'innerHTML', {
      get() { return this._innerHTML || ''; },
      set: (html) => {
        qa._innerHTML = String(html);
        this.parseFixtureHtml(qa, String(html));
      }
    });
  }
  createElement(tag) { return new Node(1, tag, this); }
  createTextNode(text) {
    const node = new Node(3, '', this);
    node.nodeValue = String(text);
    node.textContent = String(text);
    return node;
  }
  createDocumentFragment() { return new Node(11, '', this); }
  addEventListener(name, handler) { this._listeners[name] = handler; }
  getElementById(id) {
    if (id === 'qa') return this.qa;
    if (id === 'kap-note-style') return this.noteStyle;
    let found = null;
    function walk(node) {
      if (found) return;
      if (node.id === id) { found = node; return; }
      node.childNodes.forEach(walk);
    }
    walk(this.body);
    return found;
  }
  parseFixtureHtml(rootNode, html) {
    while (rootNode.firstChild) rootNode.removeChild(rootNode.firstChild);
    const wrapper = this.createElement('div');
    rootNode.appendChild(wrapper);
    if (html.includes('data-scroll-fixture')) {
      const scroll = this.createElement('div');
      scroll.setAttribute('data-scroll-fixture', '1');
      scroll._computedStyle = {overflowY: 'auto', overflow: 'auto', height: '100px', maxHeight: '100px'};
      scroll.scrollHeight = 400;
      scroll.clientHeight = 100;
      wrapper.appendChild(scroll);
    }
    if (html.includes('replay-button')) {
      const node = this.createElement('button');
      node.className = 'replay-button';
      wrapper.appendChild(node);
    }
    if (html.includes('soundLink')) {
      const node = this.createElement('a');
      node.className = 'soundLink';
      wrapper.appendChild(node);
    }
    if (html.includes('data-av-tag')) {
      const node = this.createElement('span');
      node.setAttribute('data-av-tag', 'x');
      wrapper.appendChild(node);
    }
    if (html.includes('kap-type-answer-slot')) {
      const slot = this.createElement('span');
      slot.id = 'kap-type-answer-slot';
      wrapper.appendChild(slot);
    }
    if (html.includes('id=answer') || html.includes('id="answer"')) {
      const separator = this.createElement('hr');
      separator.id = 'answer';
      wrapper.appendChild(separator);
    }
    const scriptMatch = html.match(/<script([^>]*)>([\s\S]*?)<\/script>/i);
    if (scriptMatch) {
      const script = this.createElement('script');
      script.text = scriptMatch[2];
      script.textContent = scriptMatch[2];
      script.setAttribute('data-fixture', 'inline');
      wrapper.appendChild(script);
    }
    const marker = html.match(/(before)?\[anki:play:[qa]:(\d+)\](after)?/);
    if (marker) {
      wrapper.appendChild(this.createTextNode(
        (marker[1] || '') + `[anki:play:q:${marker[2]}]` + (marker[3] || '')
      ));
    }
  }
}

function makeHarness() {
  const document = new Document();
  const calls = [];
  const scrolls = [];
  let now = 1000;
  function FakeDate() {}
  FakeDate.prototype.getTime = () => now;
  const window = {
    innerHeight: 1000,
    event: null,
    kapBridge: {send(operation, data) { calls.push({operation, data}); }},
    kapCssCompat: {
      transform(css) {
        if (css === 'THROW') throw new Error('fixture css failure');
        return {css: `x:${css}`, gaps: [{selector: '.x'}]};
      },
      apply(renderRoot, gaps) {
        calls.push({operation: 'css/apply', data: {root: renderRoot.id, gaps: gaps.length}});
      }
    },
    setTimeout(handler) { handler(); return 1; },
    scrollTo(x, y) { scrolls.push(['to', x, y]); },
    scrollBy(x, y) { scrolls.push(['by', x, y]); },
    getComputedStyle(node) {
      return node._computedStyle || {overflowY: 'visible', overflow: 'visible', height: 'auto', maxHeight: 'none'};
    }
  };
  window.window = window;
  const context = {window, document, Date: FakeDate, JSON, Math, Number, String, parseInt, isNaN, Error};
  vm.runInNewContext(source, context, {filename: 'reviewer.js'});
  return {window, document, calls, scrolls, setNow(value) { now = value; }};
}

function lastCall(harness, operation) {
  const matches = harness.calls.filter((call) => call.operation === operation);
  return matches[matches.length - 1];
}

function envelope(data) {
  return JSON.stringify({ok: true, data, error: null});
}

let harness = makeHarness();
assert.deepStrictEqual(JSON.parse(JSON.stringify(harness.calls[0])), {
  operation: 'ready', data: {view: 'reviewer'}
});

harness.window.kapReviewer.nativeResponse('next_question', envelope({
  kind: 'question',
  body_class: 'card card2 isLin kindle kap',
  html: '<div>你好 Vocabulary</div>',
  css: '.card{font-size:18px}',
  audio: [{kind: 'sound', source: 'fixture.mp3'}],
  intervals: ['1m', '6m', '1d', '4d']
}));
assert.strictEqual(harness.document.body.className, 'card card2 isLin kindle kap');
assert.strictEqual(harness.document.noteStyle.textContent, 'x:.card{font-size:18px}');
assert.strictEqual(lastCall(harness, 'audio/play').data.source, 'fixture.mp3');
assert.deepStrictEqual(JSON.parse(JSON.stringify(lastCall(harness, 'ui/state').data)), {
  mode: 'question', again: '1m', hard: '6m', good: '1d', easy: '4d'
});

harness = makeHarness();
harness.setNow(2000);
harness.window.kapReviewer.nativeResponse('next_question', envelope({
  kind: 'question',
  html: '<span id="kap-type-answer-slot"></span>',
  css: '', audio: [], intervals: [],
  typed: {enabled: true, field: 'Word', font: 'Serif', size: 36}
}));
const input = harness.document.getElementById('kap-type-answer');
assert(input && input.focused);
assert.strictEqual(input.style.fontFamily, 'Serif');
assert.strictEqual(input.style.fontSize, '36px');
input.value = 'typed value';
harness.setNow(2250);
harness.window.kapReviewer.requestReveal();
assert.deepStrictEqual(JSON.parse(JSON.stringify(lastCall(harness, 'review/reveal').data)), {
  typed: 'typed value', elapsed_ms: 250
});

harness = makeHarness();
harness.window.kapReviewer.nativeResponse('next_question', envelope({
  kind: 'question',
  html: '<script>window.fixture=1</script><button class="replay-button"></button>' +
        '<a class="soundLink"></a><span data-av-tag="x"></span>',
  css: '', audio: [], intervals: []
}));
const scripts = harness.document.qa.getElementsByTagName('script');
assert.strictEqual(scripts.length, 1);
assert.strictEqual(scripts[0].getAttribute('data-fixture'), 'inline');
assert.strictEqual(scripts[0].text, 'window.fixture=1');
assert.strictEqual(harness.document.qa.querySelectorAll('.replay-button').length, 0);
assert.strictEqual(harness.document.qa.querySelectorAll('.soundLink').length, 0);
assert.strictEqual(harness.document.qa.querySelectorAll('[data-av-tag]').length, 0);

harness = makeHarness();
harness.window.kapReviewer.nativeResponse('next_question', envelope({
  kind: 'question', html: 'before[anki:play:q:0]after', css: '',
  audio: [{kind: 'tts', text: 'hello', lang: 'en', voices: ['v1'], speed: 0.9}], intervals: []
}));
const buttons = harness.document.qa.getElementsByTagName('button');
assert.strictEqual(buttons.length, 1);
assert.strictEqual(buttons[0].className, 'kap-replay-button');
buttons[0].onclick.call(buttons[0]);
assert.strictEqual(lastCall(harness, 'audio/tts').data.text, 'hello');

harness = makeHarness();
harness.window.kapReviewer.nativeResponse('reveal_answer', envelope({
  kind: 'answer', html: '<div data-scroll-fixture></div><hr id=answer>', css: '', audio: [], intervals: []
}));
const scrollNode = harness.document.qa.getElementsByTagName('div')
  .find((node) => node.getAttribute('data-scroll-fixture') === '1');
assert(scrollNode && scrollNode.className.includes('kap-flattened-scroll'));
assert.strictEqual(harness.document.getElementById('answer').scrollIntoViewCalls, 1);

harness = makeHarness();
harness.window.kapReviewer.nativeResponse('next_question', envelope({kind: 'finished'}));
assert(lastCall(harness, 'audio/stop'));
assert.strictEqual(lastCall(harness, 'ui/state').data.mode, 'finished');
harness.window.kapReviewer.nativeResponse('answer', envelope({card_id: 1}));
assert(lastCall(harness, 'review/next'));
harness.window.kapReviewer.nativeResponse('bury', envelope({card_id: 1}));
assert(harness.calls.filter((call) => call.operation === 'review/next').length >= 2);

harness = makeHarness();
harness.window.kapReviewer.nativeResponse('next_question', JSON.stringify({
  ok: false, data: null, error: 'fixture backend failure'
}));
assert.strictEqual(lastCall(harness, 'ui/state').data.mode, 'error');
harness = makeHarness();
harness.window.kapReviewer.nativeResponse('next_question', envelope({
  kind: 'question', html: 'x', css: 'THROW', audio: [], intervals: []
}));
assert.strictEqual(lastCall(harness, 'ui/render-failed').data.message, 'Error: fixture css failure');

harness = makeHarness();
harness.window.kapReviewer.pageDown();
harness.window.kapReviewer.pageUp();
assert.deepStrictEqual(harness.scrolls, [['by', 0, 780], ['by', 0, -780]]);
const start = harness.document._listeners.touchstart;
const end = harness.document._listeners.touchend;
start({touches: [{clientX: 10, clientY: 500}]});
end({changedTouches: [{clientX: 12, clientY: 300}]});
assert.deepStrictEqual(harness.scrolls[harness.scrolls.length - 1], ['by', 0, 780]);
const scrollCount = harness.scrolls.length;
start({touches: [{clientX: 0, clientY: 0}]});
end({changedTouches: [{clientX: 200, clientY: 50}]});
assert.strictEqual(harness.scrolls.length, scrollCount);

console.log('test_reviewer_runtime_fixtures: ok (10 fixture groups)');
