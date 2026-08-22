'use strict';

var fs = require('fs');
var path = require('path');
var vm = require('vm');
var assert = require('assert');

var root = path.resolve(__dirname, '..');
global.window = {};
vm.runInThisContext(fs.readFileSync(path.join(root, 'web', 'audio_queue.js'), 'utf8'), {
  filename: 'audio_queue.js'
});

assert.strictEqual(typeof window.kapCreateAudioQueue, 'function');

var calls = [];
var queue = window.kapCreateAudioQueue(function (operation, values) {
  calls.push({operation: operation, values: values});
});

queue.start([
  {kind: 'sound', source: 'first.mp3'},
  {kind: 'tts', text: 'second', lang: 'en', voices: ['v1', 'v2'], speed: 1.25},
  {kind: 'unknown'},
  {kind: 'sound', source: 'third.mp3'}
]);
assert.deepStrictEqual(calls.shift(), {
  operation: 'audio/play',
  values: {source: 'first.mp3'}
});
assert.strictEqual(queue.pendingCount(), 3);

queue.finished();
assert.deepStrictEqual(calls.shift(), {
  operation: 'audio/tts',
  values: {text: 'second', lang: 'en', voices: 'v1,v2', speed: 1.25}
});
assert.strictEqual(queue.pendingCount(), 2);

queue.finished();
assert.deepStrictEqual(calls.shift(), {
  operation: 'audio/play',
  values: {source: 'third.mp3'}
});
assert.strictEqual(queue.pendingCount(), 0);

queue.finished();
assert.strictEqual(calls.length, 0);
assert.strictEqual(queue.pendingCount(), 0);

queue.start([
  {kind: 'sound', source: 'old-1.mp3'},
  {kind: 'sound', source: 'old-2.mp3'}
]);
assert.strictEqual(calls.shift().values.source, 'old-1.mp3');
queue.playOne({kind: 'sound', source: 'manual.mp3'});
assert.deepStrictEqual(calls.shift(), {
  operation: 'audio/play',
  values: {source: 'manual.mp3'}
});
assert.strictEqual(queue.pendingCount(), 0);
queue.finished();
assert.strictEqual(calls.length, 0);

queue.stop();
assert.deepStrictEqual(calls.shift(), {operation: 'audio/stop', values: {}});
queue.start([]);
assert.deepStrictEqual(calls.shift(), {operation: 'audio/stop', values: {}});
queue.playOne({kind: 'invalid'});
assert.deepStrictEqual(calls.shift(), {operation: 'audio/stop', values: {}});
assert.strictEqual(calls.length, 0);

console.log('test_audio_queue: ok');
