const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {JSDOM, VirtualConsole} = require('jsdom');

(() => {
  const root = path.resolve(__dirname, '..');
  const reviewer = fs.readFileSync(path.join(root, 'assets/reviewer/reviewer.js'), 'utf8');
  const logs = [];
  const virtualConsole = new VirtualConsole();
  virtualConsole.on('log', (message) => logs.push(String(message)));
  virtualConsole.on('jsdomError', () => {});

  const dom = new JSDOM(`<!doctype html><html><body class="card card1 isLin kindle">
    <style id="kanki-deck-style"></style><main id="qa"></main>
    <script>${reviewer}</script></body></html>`, {
    runScripts: 'dangerously',
    url: 'file:///mnt/us/extensions/kanki/assets/device/reviewer-shell.html',
    virtualConsole,
  });

  const {window} = dom;
  const qa = window.document.getElementById('qa');
  window.kankiReviewer.showCard({
    side: 'question',
    body_class: 'card card1 isLin kindle',
    css: '',
    audio: [],
    autoplay: false,
    autoplay_audio: [],
    html: '<a id="https-link" href="https://example.invalid/dictionary?q=private">lookup</a>' +
      '<a id="mail-link" href="mailto:person@example.invalid">mail</a>' +
      '<a id="fragment-link" href="#inside">inside</a>' +
      '<div id="inside">target</div>',
  });

  const external = qa.querySelector('#https-link');
  const externalEvent = new window.MouseEvent('click', {bubbles: true, cancelable: true});
  const externalResult = external.dispatchEvent(externalEvent);
  assert.equal(externalResult, false, 'external HTTP navigation must be cancelled');
  assert.equal(externalEvent.defaultPrevented, true, 'external HTTP navigation must prevent default');
  assert.ok(
    logs.some((line) => line.includes('blocked external reviewer navigation scheme=https')),
    'blocked navigation should log only the scheme',
  );
  assert.ok(
    !logs.some((line) => line.includes('private') || line.includes('example.invalid')),
    'blocked-navigation logging must not disclose the target URL',
  );

  const mail = qa.querySelector('#mail-link');
  const mailEvent = new window.MouseEvent('click', {bubbles: true, cancelable: true});
  assert.equal(mail.dispatchEvent(mailEvent), false, 'mailto navigation must be cancelled');
  assert.equal(mailEvent.defaultPrevented, true);

  const fragment = qa.querySelector('#fragment-link');
  const fragmentEvent = new window.MouseEvent('click', {bubbles: true, cancelable: true});
  fragment.dispatchEvent(fragmentEvent);
  assert.equal(fragmentEvent.defaultPrevented, false, 'same-document fragments remain card-controlled');

  assert.equal(
    window.document.querySelector('#qa'),
    qa,
    'navigation policy must preserve the persistent reviewer root',
  );

  window.close();
  console.log('reviewer navigation contract: pass');
})();
