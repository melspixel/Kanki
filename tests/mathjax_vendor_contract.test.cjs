const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {pathToFileURL} = require('node:url');
const {JSDOM, VirtualConsole} = require('jsdom');

if (process.argv.length !== 3) {
  throw new Error(`usage: ${process.argv[1]} MATHJAX_ROOT`);
}

const vendorRoot = path.resolve(process.argv[2]);
const entry = path.join(vendorRoot, 'MathJax.js');
const config = path.join(vendorRoot, 'config', 'TeX-AMS_SVG-full.js');
const adapter = fs.readFileSync(
  path.join(__dirname, '..', 'assets', 'reviewer', 'mathjax_runtime.js'),
  'utf8',
);
assert.ok(fs.existsSync(entry), 'pinned MathJax entry point is missing');
assert.ok(fs.existsSync(config), 'pinned MathJax SVG config is missing');

const errors = [];
const virtualConsole = new VirtualConsole();
virtualConsole.on('jsdomError', (error) => errors.push(error.message));
const entryUrl = `${pathToFileURL(entry).href}?config=TeX-AMS_SVG-full`;
const dom = new JSDOM(`<!doctype html><html><body>
  <main id="qa"></main>
  <script>window.MathJax={
    showMathMenu:false,
    messageStyle:'none',
    skipStartupTypeset:true,
    SVG:{useGlobalCache:true}
  };</script>
  <script src="${entryUrl}"></script>
</body></html>`, {
  runScripts: 'dangerously',
  resources: 'usable',
  pretendToBeVisual: true,
  url: pathToFileURL(path.join(vendorRoot, 'kanki-host-smoke.html')).href,
  virtualConsole,
});

(async () => {
  const loadDeadline = Date.now() + 15000;
  while (Date.now() < loadDeadline) {
    if (dom.window.MathJax?.Hub?.Queue) break;
    await new Promise((resolve) => setTimeout(resolve, 50));
  }

  const {document} = dom.window;
  const qa = document.getElementById('qa');
  assert.ok(dom.window.MathJax?.Hub?.Queue, `MathJax loader errors: ${errors.join('; ')}`);
  dom.window.eval(adapter);
  qa.innerHTML = `
    <span id="inline">\\(x^2+1\\)</span>
    <div id="display">\\[\\frac{a}{b}\\]</div>
    <svg id="ordinary" width="123" height="77" viewBox="0 0 123 77">
      <rect width="123" height="77"></rect>
    </svg>`;
  await new Promise((resolve, reject) => {
    dom.window.kankiMathjax.typeset(qa, resolve, (message) => reject(new Error(message)));
  });
  assert.strictEqual(
    document.querySelectorAll('#qa .MathJax_SVG > svg').length,
    2,
    `pinned MathJax did not typeset both expressions; loader errors: ${errors.join('; ')}`,
  );
  const ordinary = document.getElementById('ordinary');
  assert.strictEqual(ordinary.getAttribute('width'), '123');
  assert.strictEqual(ordinary.getAttribute('height'), '77');
  assert.strictEqual(ordinary.getAttribute('viewBox'), '0 0 123 77');
  assert.match(
    document.querySelector('#inline script[type="math/tex"]').textContent,
    /x\^2\+1/,
    'MathJax must retain the semantic TeX source beside its SVG output',
  );

  dom.window.kankiMathjax.clear(qa);
  qa.innerHTML = `
    <span id="second">\\(y=mx+b\\)</span>
    <svg id="second-ordinary" width="91" height="37" viewBox="0 0 91 37"></svg>`;
  await new Promise((resolve, reject) => {
    dom.window.kankiMathjax.typeset(qa, resolve, (message) => reject(new Error(message)));
  });
  assert.strictEqual(document.getElementById('qa'), qa, 'typesetting must retain persistent #qa');
  assert.strictEqual(document.querySelectorAll('#qa .MathJax_SVG > svg').length, 1);
  const secondOrdinary = document.getElementById('second-ordinary');
  assert.strictEqual(secondOrdinary.getAttribute('width'), '91');
  assert.strictEqual(secondOrdinary.getAttribute('height'), '37');
  assert.strictEqual(secondOrdinary.getAttribute('viewBox'), '0 0 91 37');
  dom.window.close();
  console.log(
    'mathjax vendor contract: pass version=2.7.9 output=SVG ' +
      'persistent_qa=true ordinary_svg=preserved',
  );
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
