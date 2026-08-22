const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {JSDOM, VirtualConsole} = require('jsdom');

const root = path.resolve(__dirname, '..');
const css = fs.readFileSync(path.join(root, 'assets/reviewer/reviewer.css'), 'utf8');
const mathjaxRuntime = fs.readFileSync(
  path.join(root, 'assets/reviewer/mathjax_runtime.js'),
  'utf8',
);
const runtime = fs.readFileSync(path.join(root, 'assets/reviewer/reviewer.js'), 'utf8');
const virtualConsole = new VirtualConsole();
virtualConsole.on('jsdomError', () => {});

const documentSource = `<!doctype html>
<html class="kindle"><head><meta charset="utf-8">
<style id="kanki-reviewer-style">${css}</style>
<style id="kanki-deck-style"></style></head>
<body class="card card1 isLin kindle"><main id="qa"></main>
<script>
window.__mathjaxTypesets=[];
window.__mathjaxRemoved=0;
window.__mathjaxHasOutput=false;
window.MathJax={Hub:{
  getAllJax:function(root){
    if(root===document.getElementById('qa')&&window.__mathjaxHasOutput){
      return [{Remove:function(){
        window.__mathjaxRemoved+=1;
        window.__mathjaxHasOutput=false;
      }}];
    }
    return [];
  },
  Queue:function(){
    var i;
    var item;
    for(i=0;i<arguments.length;i+=1){
      item=arguments[i];
      if(typeof item==='function') item();
      else if(item&&item[0]==='Typeset'){
        window.__mathjaxTypesets.push(item[2]);
        window.__mathjaxHasOutput=true;
      }
    }
  }
}};
</script>
<script>${mathjaxRuntime}</script>
<script>${runtime}</script></body></html>`;

const dom = new JSDOM(documentSource, {
  runScripts: 'dangerously',
  url: 'file:///mnt/us/extensions/kanki/assets/device/reviewer-shell.html',
  virtualConsole,
  beforeParse(window) {
    window.__scrollCalls = [];
    window.scrollTo = function (x, y) {
      window.__scrollCalls.push(['window', x, y]);
    };
    if (window.HTMLElement && window.HTMLElement.prototype) {
      window.HTMLElement.prototype.scrollIntoView = function () {
        window.__scrollCalls.push(['element', this.id || this.tagName]);
      };
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
window.kankiBridge.playTags = (tags) => audio.push(['sequence', hostValue(tags)]);
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
    '<section class="row"><script>window.__questionRuns=(window.__questionRuns||0)+1;' +
    'window.__customAudio=new Audio("custom.mp3");window.__customAudio.play();<\/script>' +
    '<span id="sound-marker">[anki:play:q:0]</span><input id="typeans" value="typed">' +
    '<span id="inline-math">\\(x^2+1\\)</span>' +
    '<img id="photo" src="photo.png" width="160" height="90" alt="fixture">' +
    '<span id="cloze" class="cloze" data-cloze-ordinal="1">capital</span>' +
    '<svg id="illustration" width="123" height="77" viewBox="0 0 123 77"><rect width="123" height="77"></rect></svg>' +
    '<div id="long-card" dir="auto"><p lang="en">First paragraph.</p>' +
    '<p lang="zh">第二段。</p><p lang="en">Final paragraph.</p></div>' +
    '</section>',
  answer_html:
    '<section><hr id="answer"><script>window.__answerRuns=(window.__answerRuns||0)+1;<\/script>' +
    '<div id="display-math">\\[\\frac{a}{b}\\]</div>' +
    '<span id="question-replay">[anki:play:q:0]</span>' +
    '<span id="answer-replay">[anki:play:a:0]</span>' +
    '<strong id="answer-text">answer</strong></section>',
  css: '.row{display:flex;gap:8px}#illustration{width:123px;height:77px}',
  question_audio: [{kind: 'sound', source: 'word.mp3'}],
  answer_audio: [{kind: 'tts', text: 'answer', lang: 'en_US', voices: [], speed: 1.0}],
  autoplay: true,
  replay_question_audio_on_answer_side: true,
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
assert.ok(window.__customAudio, 'card scripts must be able to construct Audio');
assert.strictEqual(window.__customAudio.constructor, window.Audio);
assert.strictEqual(document.querySelectorAll('.replay-button').length, 1);
assert.strictEqual(document.querySelector('.replay-button > svg').getAttribute('viewBox'), '0 0 40 40');
assert.strictEqual(document.getElementById('illustration').getAttribute('width'), '123');
assert.strictEqual(document.getElementById('illustration').getAttribute('height'), '77');
assert.strictEqual(document.getElementById('photo').getAttribute('src'), 'photo.png');
assert.strictEqual(document.getElementById('photo').getAttribute('width'), '160');
assert.strictEqual(document.getElementById('photo').getAttribute('height'), '90');
assert.strictEqual(document.getElementById('cloze').className, 'cloze');
assert.strictEqual(document.getElementById('cloze').getAttribute('data-cloze-ordinal'), '1');
assert.deepStrictEqual(
  Array.from(document.querySelectorAll('#long-card p'), (node) => [node.lang, node.textContent]),
  [
    ['en', 'First paragraph.'],
    ['zh', '第二段。'],
    ['en', 'Final paragraph.'],
  ],
  'long bilingual card content and order must survive insertion',
);
assert.strictEqual(window.__mathjaxTypesets.length, 1);
assert.strictEqual(window.__mathjaxTypesets[0], qa, 'MathJax must be scoped to persistent #qa');
assert.deepStrictEqual(hostValue(window.__scrollCalls[0]), ['window', 0, 0]);
assert.deepStrictEqual(hostValue(audio[0]), ['sound', 'custom.mp3']);
assert.deepStrictEqual(hostValue(audio[1]), ['sequence', card.question_audio]);

const replay = document.querySelector('.replay-button');
replay.onclick();
assert.deepStrictEqual(hostValue(audio[2]), ['sound', 'word.mp3']);

const typeInput = document.getElementById('typeans');
assert.ok(typeInput, 'typed-answer input must remain usable in the question');
assert.strictEqual(typeof typeInput.onkeypress, 'function');

window.kankiDevice.nativeResponse(
  'show_answer',
  JSON.stringify({
    ok: true,
    data: {
      html: card.answer_html,
      audio: card.answer_audio,
      question_audio: card.question_audio,
      autoplay: true,
      replay_question_audio_on_answer_side: true,
    },
    error: null,
  }),
);
assert.strictEqual(document.getElementById('qa'), qa, 'answer must not reload the page');
assert.strictEqual(window.__answerRuns, 1, 'answer scripts must execute after insertion');
assert.strictEqual(document.getElementById('answer-text').textContent, 'answer');
assert.strictEqual(window.__mathjaxTypesets.length, 2);
assert.strictEqual(window.__mathjaxTypesets[1], qa);
assert.strictEqual(window.__mathjaxRemoved, 1, 'question MathJax state must be cleared in place');
assert.deepStrictEqual(
  hostValue(window.__scrollCalls[window.__scrollCalls.length - 1]),
  ['element', 'answer'],
  'answer scrolling must happen after formula typesetting',
);
assert.deepStrictEqual(
  hostValue(audio[3]),
  ['sequence', card.question_audio.concat(card.answer_audio)],
  'answer autoplay must replay question audio before answer audio when requested',
);
assert.strictEqual(document.querySelectorAll('.replay-button').length, 2);
const answerReplayButtons = document.querySelectorAll('.replay-button');
answerReplayButtons[0].onclick();
assert.deepStrictEqual(hostValue(audio[4]), ['sound', 'word.mp3']);
answerReplayButtons[1].onclick();
assert.deepStrictEqual(hostValue(audio[5]), ['tts', 'answer', 'en_US', [], 1]);

const beforeAutoplayOff = audio.length;
window.kankiReviewer.showCard({
  side: 'question',
  body_class: 'card card1 isLin kindle',
  html: '<span>[anki:play:q:0]</span>',
  css: '',
  audio: card.question_audio,
  autoplay: false,
  autoplay_audio: card.question_audio,
});
assert.strictEqual(audio.length, beforeAutoplayOff, 'autoplay=false must not infer playback from AV tags');
assert.strictEqual(document.querySelectorAll('.replay-button').length, 1, 'replay remains available');

const beforeQuestionReplayOff = audio.length;
window.kankiDevice.nativeResponse(
  'show_answer',
  JSON.stringify({
    ok: true,
    data: {
      html: card.answer_html,
      audio: card.answer_audio,
      question_audio: card.question_audio,
      autoplay: true,
      replay_question_audio_on_answer_side: false,
    },
    error: null,
  }),
);
assert.deepStrictEqual(
  hostValue(audio[beforeQuestionReplayOff]),
  ['sequence', card.answer_audio],
  'answer autoplay must omit question audio when the backend semantic is false',
);

const pendingTypesets = [];
const completedSides = [];
const synchronousTypeset = window.kankiMathjax.typeset;
window.kankiBridge.renderComplete = (side) => completedSides.push(side);
window.kankiMathjax.typeset = (root, done, failed) => {
  pendingTypesets.push({root, done, failed});
};
window.kankiReviewer.showCard({
  side: 'question',
  body_class: 'card card1 isLin kindle',
  html: '<span id="stale-math">\\(old\\)</span>',
  css: '',
  audio: [],
  autoplay: false,
  autoplay_audio: [],
});
window.kankiReviewer.showCard({
  side: 'answer',
  body_class: 'card card1 isLin kindle',
  html: '<hr id="answer"><span id="current-math">\\(new\\)</span>',
  css: '',
  audio: [],
  autoplay: false,
  autoplay_audio: [],
});
assert.strictEqual(pendingTypesets.length, 2);
assert.strictEqual(pendingTypesets[0].root, qa);
assert.strictEqual(pendingTypesets[1].root, qa);
pendingTypesets[0].done();
assert.deepStrictEqual(completedSides, [], 'stale MathJax completion must be ignored');
assert.ok(document.getElementById('current-math'), 'stale completion must not replace current DOM');
pendingTypesets[1].done();
assert.deepStrictEqual(completedSides, ['answer']);
window.kankiMathjax.typeset = synchronousTypeset;

window.__customAudio.pause();
assert.deepStrictEqual(hostValue(audio[audio.length - 1]), ['stop']);

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
assert.ok(runtime.includes('window.Audio = KankiAudio'));
console.log('renderer contract: pass');
