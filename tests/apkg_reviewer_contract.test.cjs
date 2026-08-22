const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {JSDOM, VirtualConsole} = require('jsdom');

if (process.argv.length !== 3) {
  throw new Error(`usage: ${process.argv[1]} APKG_PACKET_EVIDENCE`);
}

const root = path.resolve(__dirname, '..');
const evidence = JSON.parse(fs.readFileSync(path.resolve(process.argv[2]), 'utf8'));
const fixtures = evidence.fixtures || [];
const expectedNames = [
  'diffmodels2-1.apkg',
  'diffmodels2-2.apkg',
  'diffmodeltemplates-1.apkg',
  'diffmodeltemplates-2.apkg',
  'media.apkg',
  'update1.apkg',
  'update2.apkg',
];
assert.deepStrictEqual(fixtures.map((entry) => entry.fixture), expectedNames);

const css = fs.readFileSync(path.join(root, 'assets/reviewer/reviewer.css'), 'utf8');
const mathjaxRuntime = fs.readFileSync(
  path.join(root, 'assets/reviewer/mathjax_runtime.js'),
  'utf8',
);
const reviewerRuntime = fs.readFileSync(
  path.join(root, 'assets/reviewer/reviewer.js'),
  'utf8',
);
const virtualConsole = new VirtualConsole();
virtualConsole.on('jsdomError', () => {});

const documentSource = `<!doctype html><html><head><meta charset="utf-8">
<style id="kanki-reviewer-style">${css}</style>
<style id="kanki-deck-style"></style></head>
<body class="card card1 isLin kindle"><main id="qa"></main>
<script>
window.MathJax={Hub:{
  getAllJax:function(){return [];},
  Queue:function(){
    var i;
    for(i=0;i<arguments.length;i+=1){
      if(typeof arguments[i]==='function') arguments[i]();
    }
  }
}};
</script>
<script>${mathjaxRuntime}</script>
<script>${reviewerRuntime}</script></body></html>`;

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
const completed = [];
const failed = [];
window.kankiBridge.playAudio = function () {};
window.kankiBridge.playTts = function () {};
window.kankiBridge.playTags = function () {};
window.kankiBridge.stopAudio = function () {};
window.kankiBridge.renderComplete = (side) => completed.push(side);
window.kankiBridge.renderFailed = (message) => failed.push(String(message));

for (const entry of fixtures) {
  const card = entry.next_card;
  const prepared = entry.prepared_answer;
  assert.equal(card.finished, false, `${entry.fixture}: packet is unexpectedly finished`);
  assert.ok(card.question_html, `${entry.fixture}: question HTML is empty`);
  assert.ok(prepared.html, `${entry.fixture}: prepared answer HTML is empty`);

  window.kankiDevice.nativeResponse(
    'next_card',
    JSON.stringify({ok: true, data: card, error: null}),
  );
  assert.strictEqual(document.getElementById('qa'), qa, `${entry.fixture}: #qa was replaced`);
  assert.equal(
    document.body.className,
    `card card${Number(card.template_ordinal || 0) + 1} isLin kindle`,
    `${entry.fixture}: body class differs from the backend template ordinal`,
  );
  assert.equal(deckStyle.textContent, card.css, `${entry.fixture}: note type CSS changed`);
  assert.ok(qa.innerHTML, `${entry.fixture}: persistent reviewer did not insert the question`);
  assert.equal(completed[completed.length - 1], 'question');

  window.kankiDevice.nativeResponse(
    'show_answer',
    JSON.stringify({ok: true, data: prepared, error: null}),
  );
  assert.strictEqual(document.getElementById('qa'), qa, `${entry.fixture}: answer replaced #qa`);
  assert.equal(deckStyle.textContent, card.css, `${entry.fixture}: answer changed note type CSS`);
  assert.ok(qa.innerHTML, `${entry.fixture}: persistent reviewer did not insert the answer`);
  assert.equal(completed[completed.length - 1], 'answer');
}

assert.deepStrictEqual(failed, [], `review failures: ${failed.join('; ')}`);
assert.equal(completed.length, fixtures.length * 2);
assert.strictEqual(document.getElementById('qa'), qa, 'the APKG corpus must keep one #qa');
window.close();
console.log(`APKG persistent reviewer contract: pass (${fixtures.length} fixtures)`);
