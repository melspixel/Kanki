const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {JSDOM, VirtualConsole} = require('jsdom');

const root = path.resolve(__dirname, '..');
const css = fs.readFileSync(path.join(root, 'assets/reviewer/reviewer.css'), 'utf8');
const runtime = fs.readFileSync(path.join(root, 'assets/reviewer/reviewer.js'), 'utf8');
const virtualConsole = new VirtualConsole();
virtualConsole.on('jsdomError', () => {});

const documentSource = `<!doctype html>
<html class="kindle"><head><meta charset="utf-8">
<style id="kanki-reviewer-style">${css}</style>
<style id="kanki-deck-style"></style></head>
<body class="card card1 isLin kindle"><main id="qa"></main>
<script>${runtime}</script></body></html>`;

const dom = new JSDOM(documentSource, {
  runScripts: 'dangerously',
  url: 'file:///mnt/us/extensions/kanki/assets/device/reviewer-shell.html',
  virtualConsole,
  beforeParse(window) {
    window.scrollTo = function () {};
    if (window.HTMLElement && window.HTMLElement.prototype) {
      window.HTMLElement.prototype.scrollIntoView = function () {};
    }
  },
});

const {window} = dom;
const {document} = window;
const qa = document.getElementById('qa');
const deckStyle = document.getElementById('kanki-deck-style');
const audio = [];
window.kankiBridge.playAudio = (source) => audio.push(['sound', source]);
window.kankiBridge.playTts = (text, lang, voices, speed) =>
  audio.push(['tts', text, lang, voices, speed]);
window.kankiBridge.stopAudio = () => audio.push(['stop']);
window.kankiBridge.renderComplete = () => {};
window.kankiBridge.renderFailed = (message) => {
  throw new Error(message);
};

function hostValue(value) {
  return JSON.parse(JSON.stringify(value));
}

const card = {
  finished: false,
  card_id: 77,
  template_ordinal: 1,
  question_html:
    '<section class="row"><script>window.__questionRuns=(window.__questionRuns||0)+1;<\/script>' +
    '<span id="sound-marker">[anki:play:q:0]</span><input id="typeans" value="typed">' +
    '<svg id="illustration" width="123" height="77" viewBox="0 0 123 77"><rect width="123" height="77"></rect></svg>' +
    '</section>',
  answer_html:
    '<section><hr id="answer"><script>window.__answerRuns=(window.__answerRuns||0)+1;<\/script>' +
    '<span>[anki:play:a:0]</span><strong id="answer-text">answer</strong></section>',
  css: '.row{display:flex;gap:8px}#illustration{width:123px;height:77px}',
  question_audio: [{kind: 'sound', source: 'word.mp3'}],
  answer_audio: [{kind: 'tts', text: 'answer', lang: 'en_US', voices: [], speed: 1.0}],
  counts: {new: 1, learning: 2, review: 3},
  intervals: ['1m', '6m', '1d', '4d'],
};

window.kankiDevice.nativeResponse(
  'next_card',
  JSON.stringify({ok: true, data: card, error: null}),
);

assert.strictEqual(document.getElementById('qa'), qa, 'reviewer must keep one #qa node');
assert.strictEqual(document.body.className, 'card card2 isLin kindle');
assert.strictEqual(deckStyle.textContent, card.css, 'note type CSS must be preserved verbatim');
assert.strictEqual(window.__questionRuns, 1, 'question scripts must execute after insertion');
assert.strictEqual(document.querySelectorAll('.replay-button').length, 1);
assert.strictEqual(document.querySelector('.replay-button > svg').getAttribute('viewBox'), '0 0 40 40');
assert.strictEqual(document.getElementById('illustration').getAttribute('width'), '123');
assert.strictEqual(document.getElementById('illustration').getAttribute('height'), '77');
assert.deepStrictEqual(hostValue(audio[0]), ['sound', 'word.mp3']);

const replay = document.querySelector('.replay-button');
replay.onclick();
assert.deepStrictEqual(hostValue(audio[1]), ['sound', 'word.mp3']);

const typeInput = document.getElementById('typeans');
assert.ok(typeInput, 'typed-answer input must remain usable in the question');
assert.strictEqual(typeof typeInput.onkeypress, 'function');

window.kankiDevice.nativeResponse(
  'show_answer',
  JSON.stringify({
    ok: true,
    data: {html: card.answer_html, audio: card.answer_audio},
    error: null,
  }),
);
assert.strictEqual(document.getElementById('qa'), qa, 'answer must not reload the page');
assert.strictEqual(window.__answerRuns, 1, 'answer scripts must execute after insertion');
assert.strictEqual(document.getElementById('answer-text').textContent, 'answer');
assert.deepStrictEqual(hostValue(audio[2]), ['tts', 'answer', 'en_US', [], 1]);
assert.strictEqual(document.querySelectorAll('.replay-button').length, 1);

window.kankiDevice.nativeResponse(
  'next_card',
  JSON.stringify({ok: true, data: {finished: true}, error: null}),
);
assert.match(qa.textContent, /Review complete/);
assert.strictEqual(document.getElementById('qa'), qa);
assert.deepStrictEqual(hostValue(audio[audio.length - 1]), ['stop']);

assert.ok(!/^\s*svg\s*\{/m.test(css), 'generic SVG rules are forbidden');
assert.ok(css.includes('.replay-button > svg'));
assert.ok(!runtime.includes('LOGICAL_VIEWPORT_PX'));
assert.ok(!runtime.includes('COCA-English'));
console.log('renderer contract: pass');
