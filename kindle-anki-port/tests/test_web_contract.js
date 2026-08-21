'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..');
const read = (name) => fs.readFileSync(path.join(root, name), 'utf8');

function legacySyntaxGate(source, name) {
  const forbidden = [
    /=>/, /\bconst\b/, /\blet\b/, /\bclass\s+[A-Za-z_$]/,
    /\?\./, /\?\?/, /`/, /\bPromise\b/, /\basync\s+function\b/
  ];
  forbidden.forEach((pattern) => assert(!pattern.test(source), `${name}: ${pattern}`));
}

const cssCompatSource = read('web/css_compat.js');
const bridgeSource = read('web/bridge.js');
const reviewerSource = read('web/reviewer.js');
const reviewerHtml = read('web/reviewer.html');
const platformCss = read('web/platform.css');

legacySyntaxGate(cssCompatSource, 'css_compat.js');
legacySyntaxGate(bridgeSource, 'bridge.js');
legacySyntaxGate(reviewerSource, 'reviewer.js');

const cssWindow = {matchMedia: () => ({matches: true})};
vm.runInNewContext(cssCompatSource, {window: cssWindow});
const transformed = cssWindow.kapCssCompat.transform(
  ':root{--space:12px}.row{display:flex;gap:8px;width:calc(20px + 5px);margin:var(--space)}' +
  '@media (max-width:420px){.column{display:flex;flex-direction:column;gap:6px}}'
);
assert(transformed.css.includes('display:-webkit-box'));
assert(transformed.css.includes('width:25px'));
assert(transformed.css.includes('margin:12px'));
assert(transformed.css.includes('-webkit-box-orient:vertical'));
assert.strictEqual(transformed.gaps.length, 2);
assert.strictEqual(transformed.gaps[0].pixels, 8);
assert.strictEqual(transformed.gaps[1].column, true);

const location = {href: ''};
const bridgeWindow = {location};
function FakeDate() {}
FakeDate.prototype.getTime = function () { return 1234; };
vm.runInNewContext(bridgeSource, {window: bridgeWindow, Date: FakeDate, encodeURIComponent});
bridgeWindow.kapBridge.send('review/reveal', {typed: 'a b&c'});
assert(location.href.startsWith('kap://v1/review/reveal?'));
assert(location.href.includes('typed=a%20b%26c'));
assert(location.href.includes('request_id=1234-1'));

assert.strictEqual((reviewerHtml.match(/id="qa"/g) || []).length, 1);
assert(reviewerSource.includes("document.getElementById('qa')"));
assert(reviewerSource.includes("packet.body_class || 'card card1 isLin kindle kap'"));
assert(reviewerSource.includes('replaceAudioMarkers'));
assert(reviewerSource.includes('removeDuplicateAnkiReplayControls'));
assert(reviewerSource.includes('kap-type-answer'));
assert(reviewerSource.includes('viewport * 0.78'));
assert(reviewerSource.includes('executeScripts(qa)'));
assert(!reviewerSource.includes('load_html_string'));
assert(/\.kap-replay-button\s*\{[\s\S]*?width:\s*42px\s*!important;[\s\S]*?height:\s*42px\s*!important;/m.test(platformCss));
assert(!/(^|\n)\s*(svg|img)\s*\{[^}]*width:\s*42px/m.test(platformCss));

console.log('test_web_contract: ok');
