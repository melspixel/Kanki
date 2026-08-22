const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {JSDOM, VirtualConsole} = require('jsdom');

(async () => {
  const root = path.resolve(__dirname, '..');
  const runtime = fs.readFileSync(path.join(root, 'assets/reviewer/diagnostics.js'), 'utf8');
  const requests = [];
  const virtualConsole = new VirtualConsole();
  virtualConsole.on('jsdomError', () => {});

  const dom = new JSDOM(`<!doctype html><html><body>
    <main id="qa"><section class="secret-card"><span class="label">PRIVATE NOTE TEXT</span></section></main>
    <script>window.kankiDiagnostics={rawCapture:false,protocolVersion:1};</script>
    <script>${runtime}</script>
  </body></html>`, {
    runScripts: 'dangerously',
    url: 'file:///mnt/us/extensions/kanki/assets/device/reviewer-shell.html',
    virtualConsole,
    beforeParse(window) {
      const rect = {left: 10, top: 20, right: 310, bottom: 220};
      if (window.HTMLElement && window.HTMLElement.prototype) {
        window.HTMLElement.prototype.getBoundingClientRect = function () {
          return rect;
        };
      }
      if (window.SVGElement && window.SVGElement.prototype) {
        window.SVGElement.prototype.getBoundingClientRect = function () {
          return rect;
        };
      }
      if (window.HTMLImageElement && window.HTMLImageElement.prototype) {
        Object.defineProperty(window.HTMLImageElement.prototype, 'src', {
          configurable: true,
          set(value) {
            requests.push(String(value));
            setTimeout(() => {
              if (typeof this.onerror === 'function') this.onerror(new Error('diagnostic test transport'));
            }, 0);
          },
          get() {
            return '';
          },
        });
      }
    },
  });

  const {window} = dom;
  assert.equal(window.kankiRendererDiagnostics.protocolVersion, 1);
  assert.equal(window.kankiRendererDiagnostics.rawCaptureEnabled(), false);

  const packet = {
    side: 'question',
    body_class: 'card card1 isLin kindle',
    html: '<div>PRIVATE NOTE TEXT</div>',
    css: '.secret-card{font-size:20px}',
    audio: [{kind: 'sound', source: 'private-file.mp3'}],
  };

  window.kankiRendererDiagnostics.begin(packet, 77);
  await new Promise((resolve) => setTimeout(resolve, 360));

  assert.ok(requests.some((url) => url.includes('127.0.0.1:17393/metric?')),
    'privacy-safe page metrics should always be emitted');
  assert.ok(requests.some((url) => url.includes('127.0.0.1:17393/element?')),
    'bounded computed element metrics should be emitted after settling');
  assert.ok(!requests.some((url) => url.includes('/capture?')),
    'raw HTML/CSS capture must be off by default');
  assert.ok(!requests.some((url) => decodeURIComponent(url).includes('PRIVATE NOTE TEXT')),
    'default metric transport must not contain element/note text');
  assert.ok(!requests.some((url) => decodeURIComponent(url).includes('private-file.mp3')),
    'default metric transport must not contain AV source metadata');

  requests.length = 0;
  window.kankiDiagnostics.rawCapture = true;
  assert.equal(window.kankiRendererDiagnostics.rawCaptureEnabled(), true);
  window.kankiRendererDiagnostics.begin(packet, 78);
  await new Promise((resolve) => setTimeout(resolve, 500));

  const captureRequests = requests.filter((url) => url.includes('/capture?'));
  assert.ok(captureRequests.length > 0, 'explicit raw-capture mode should emit bounded capture chunks');
  assert.ok(captureRequests.some((url) => decodeURIComponent(url).includes('PRIVATE NOTE TEXT')),
    'raw capture should preserve source content only after explicit opt-in');
  assert.ok(captureRequests.some((url) => decodeURIComponent(url).includes('kind=css')),
    'raw capture should include card CSS');
  assert.ok(captureRequests.some((url) => decodeURIComponent(url).includes('kind=meta')),
    'raw capture should include render metadata');

  assert.ok(!runtime.includes('textContent'),
    'privacy-safe diagnostics runtime should not scrape element text');
  assert.ok(runtime.includes('RAW_RENDER_LIMIT = 12'), 'raw capture must be bounded');
  assert.ok(runtime.includes('METRIC_RENDER_LIMIT = 200'), 'session metrics must be bounded');
  assert.ok(runtime.includes('ELEMENT_LIMIT = 40'), 'computed element logging must be bounded');

  window.close();
  console.log('renderer diagnostics contract: pass');
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
