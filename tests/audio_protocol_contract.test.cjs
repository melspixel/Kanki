const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {JSDOM, VirtualConsole} = require('jsdom');

(() => {
  const root = path.resolve(__dirname, '..');
  const reviewer = fs.readFileSync(path.join(root, 'assets/reviewer/reviewer.js'), 'utf8');
  const virtualConsole = new VirtualConsole();
  virtualConsole.on('jsdomError', () => {});
  const dom = new JSDOM(`<!doctype html><html><body>
    <style id="kanki-deck-style"></style><main id="qa"></main>
    <script>${reviewer}</script></body></html>`, {
    runScripts: 'dangerously',
    url: 'file:///mnt/us/extensions/kanki/assets/device/reviewer-shell.html',
    virtualConsole,
  });
  const {window} = dom;
  const requests = [];

  window.Image = function KankiProtocolImage() {
    const image = window.document.createElement('img');
    Object.defineProperty(image, 'src', {
      set(value) {
        requests.push(String(value));
      },
    });
    return image;
  };

  window.kankiBridge.playTags([
    {kind: 'sound', source: 'folder/a b.mp3'},
    {
      kind: 'tts',
      text: 'Bonjour & goodbye',
      lang: 'fr_FR',
      voices: ['Lea', 'Fallback'],
      speed: 0.75,
    },
  ]);
  assert.equal(requests.length, 1);
  const sequence = new URL(requests[0]);
  assert.equal(sequence.pathname, '/sequence');
  assert.equal(sequence.searchParams.get('count'), '2');
  assert.equal(sequence.searchParams.get('kind0'), 'sound');
  assert.equal(sequence.searchParams.get('value0'), 'folder/a b.mp3');
  assert.equal(sequence.searchParams.get('kind1'), 'tts');
  assert.equal(sequence.searchParams.get('value1'), 'Bonjour & goodbye');
  assert.equal(sequence.searchParams.get('lang1'), 'fr_FR');
  assert.equal(sequence.searchParams.get('voices1'), 'Lea,Fallback');
  assert.equal(sequence.searchParams.get('speed1'), '0.75');

  window.kankiBridge.playTts('single request', 'de_DE', ['Vicki'], 1.25);
  assert.equal(requests.length, 2);
  const single = new URL(requests[1]);
  assert.equal(single.pathname, '/tts');
  assert.equal(single.searchParams.get('text'), 'single request');
  assert.equal(single.searchParams.get('lang'), 'de_DE');
  assert.equal(single.searchParams.get('voices'), 'Vicki');
  assert.equal(single.searchParams.get('speed'), '1.25');

  window.close();
  console.log('audio browser protocol contract: pass');
})();
