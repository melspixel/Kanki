const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {JSDOM} = require('jsdom');

const root = path.resolve(__dirname, '..');
const compat = fs.readFileSync(path.join(root, 'assets/reviewer/css_compat.js'), 'utf8');
const dom = new JSDOM(`<!doctype html><html><body><main id="qa">
  <div class="row"><span id="first">A</span><span id="second">B</span></div>
  <div class="column"><span id="top">C</span><span id="bottom">D</span></div>
  <div class="separate"><span id="left">E</span><span id="right">F</span></div>
  <svg id="diagram" width="123" height="77"></svg>
</main><script>${compat}</script></body></html>`, {
  runScripts: 'dangerously',
});

const {window} = dom;
const source = `
:root {
  --space: 8px;
  --row-space: 11px;
  --column-space: 13px;
  --headline: 42px;
  --scaled: calc(16px * (40 / 18));
}
.row {
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: space-between;
  gap: var(--space);
  font-size: var(--headline);
}
.column {
  display: flex;
  flex-direction: column;
  row-gap: var(--row-space);
}
.separate {
  display: inline-flex;
  flex-direction: row;
  row-gap: 99px;
  column-gap: var(--column-space);
}
.scaled { font-size: var(--scaled); }
@media (max-width: 600px) {
  :root { --headline: 36px; }
  .row { font-size: var(--headline); }
}
#diagram { width: 123px; height: 77px; }
`;

const result = window.kankiCssCompat.transform(source);
assert.match(result.css, /display:-webkit-box;display:flex;/);
assert.match(result.css, /display:-webkit-inline-box;display:inline-flex;/);
assert.match(result.css, /-webkit-box-orient:horizontal/);
assert.match(result.css, /-webkit-box-orient:vertical/);
assert.match(result.css, /-webkit-box-align:center/);
assert.match(result.css, /-webkit-box-pack:justify/);
assert.match(result.css, /gap:8px/);
assert.match(result.css, /font-size:42px/);
assert.match(result.css, /font-size:35\.5556px/);
assert.match(result.css, /@media\s*\(max-width: 600px\)/);
assert.match(result.css, /font-size:36px/);
assert.ok(!result.css.includes('9999px'));
assert.ok(!result.css.includes('420px'));

const qa = window.document.getElementById('qa');
window.kankiCssCompat.apply(qa, result);
assert.strictEqual(window.document.getElementById('first').style.marginRight, '8px');
assert.strictEqual(window.document.getElementById('second').style.marginRight, '');
assert.strictEqual(window.document.getElementById('top').style.marginBottom, '11px');
assert.strictEqual(window.document.getElementById('bottom').style.marginBottom, '');
assert.strictEqual(window.document.getElementById('left').style.marginRight, '13px');
assert.strictEqual(window.document.getElementById('right').style.marginRight, '');
assert.strictEqual(window.document.getElementById('diagram').getAttribute('width'), '123');
assert.strictEqual(window.document.getElementById('diagram').getAttribute('height'), '77');
console.log('css compatibility contract: pass');
