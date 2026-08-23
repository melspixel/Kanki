'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'web/ime.js'), 'utf8');

function makeHarness() {
  const listeners = Object.create(null);
  const calls = [];
  const document = {
    addEventListener(name, handler, capture) {
      if (!listeners[name]) listeners[name] = [];
      listeners[name].push({handler, capture: !!capture});
    }
  };
  const window = {
    event: null,
    kapBridge: {
      send(operation, data) {
        calls.push({operation, data: data || {}});
      }
    }
  };
  window.window = window;
  vm.runInNewContext(source, {window, document}, {filename: 'ime.js'});
  return {
    window,
    document,
    calls,
    fire(name, target) {
      (listeners[name] || []).forEach((entry) => entry.handler({target}));
    },
    listeners
  };
}

let harness = makeHarness();
const typed = {id: 'kap-type-answer'};
const other = {id: 'ordinary-input'};

assert(harness.window.kapIme);
assert.strictEqual(harness.window.kapIme.protocolVersion, 1);
assert.strictEqual(harness.listeners.focus[0].capture, true);
assert.strictEqual(harness.listeners.blur[0].capture, true);

harness.fire('focus', other);
assert.strictEqual(harness.calls.length, 0);

harness.fire('focus', typed);
harness.fire('focusin', typed);
assert.deepStrictEqual(harness.calls.map((call) => call.operation), ['ime/open']);
assert.strictEqual(harness.window.kapIme.requested(), true);

harness.fire('blur', typed);
harness.fire('focusout', typed);
assert.deepStrictEqual(harness.calls.map((call) => call.operation), ['ime/open', 'ime/close']);
assert.strictEqual(harness.window.kapIme.requested(), false);

harness.fire('focus', typed);
harness.window.kapBridge.send('review/reveal', {typed: 'answer'});
assert.deepStrictEqual(harness.calls.slice(-3).map((call) => call.operation), [
  'ime/open', 'ime/close', 'review/reveal'
]);
assert.strictEqual(harness.window.kapIme.requested(), false);

harness.fire('focus', typed);
harness.window.kapBridge.send('ui/state', {mode: 'answer'});
assert.deepStrictEqual(harness.calls.slice(-3).map((call) => call.operation), [
  'ime/open', 'ime/close', 'ui/state'
]);

harness.fire('focus', typed);
harness.window.kapBridge.send('ui/state', {mode: 'question'});
assert.deepStrictEqual(harness.calls.slice(-2).map((call) => call.operation), [
  'ime/open', 'ui/state'
]);
harness.window.kapIme.close();

harness.fire('focus', typed);
harness.window.kapBridge.send('app/back', {});
assert.deepStrictEqual(harness.calls.slice(-3).map((call) => call.operation), [
  'ime/open', 'ime/close', 'app/back'
]);

console.log('test_ime_runtime: ok (focus, blur, reveal, state and back ordering)');
