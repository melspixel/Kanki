'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'web/css_compat.js'), 'utf8');

function transform(css, matches = true) {
  const window = {matchMedia: () => ({matches})};
  vm.runInNewContext(source, {window});
  return window.kapCssCompat.transform(css);
}

const cases = [
  {
    name: 'nested variables and fallback',
    css: ':root{--a:var(--b);--b:14px}.x{margin:var(--a);padding:var(--missing, 7px)}',
    expect: ['margin:14px', 'padding:7px']
  },
  {
    name: 'simple positive and negative calc',
    css: '.x{width:calc(120px - 8px);left:calc(-4px + 10px)}',
    expect: ['width:112px', 'left:6px']
  },
  {
    name: 'row flex mapping',
    css: '.row{display:flex;flex-direction:row-reverse;justify-content:space-between;align-items:flex-end;order:2;flex-grow:3}',
    expect: [
      'display:-webkit-box',
      '-webkit-box-orient:horizontal',
      '-webkit-box-direction:reverse',
      '-webkit-box-pack:justify',
      '-webkit-box-align:end',
      '-webkit-box-ordinal-group:3',
      '-webkit-box-flex:3'
    ]
  },
  {
    name: 'inline flex mapping',
    css: '.inline{display:inline-flex;justify-content:center}',
    expect: ['display:-webkit-inline-box', '-webkit-box-pack:center']
  },
  {
    name: 'media and supports nesting preserved',
    css: '@media (max-width:420px){@supports (display:flex){.x{display:flex;gap:9px}}}',
    expect: ['@media (max-width:420px)', '@supports (display:flex)', 'display:-webkit-box']
  },
  {
    name: 'font face and keyframes remain opaque',
    css: '@font-face{font-family:"Fixture";src:url(a.woff)}@keyframes fade{0%{opacity:0}100%{opacity:1}}',
    expect: ['@font-face{font-family:"Fixture";src:url(a.woff)}', '@keyframes fade{0%{opacity:0}100%{opacity:1}}']
  }
];

for (const fixture of cases) {
  const result = transform(fixture.css);
  for (const token of fixture.expect) {
    assert(result.css.includes(token), `${fixture.name}: missing ${token}\n${result.css}`);
  }
}

const gaps = transform(
  '.row{display:flex;gap:8px}.column{display:flex;flex-direction:column;row-gap:6px}' +
  '@media (max-width:420px){.small{display:flex;column-gap:5px}}'
).gaps;
assert.deepStrictEqual(
  JSON.parse(JSON.stringify(gaps)),
  [
    {selector: '.row', pixels: 8, column: false, media: ''},
    {selector: '.column', pixels: 6, column: true, media: ''},
    {selector: '.small', pixels: 5, column: false, media: '(max-width:420px)'}
  ]
);

// Unsupported/complex calc must be left intact instead of being guessed incorrectly.
const complex = transform('.x{width:calc(100% - 20px);height:calc(2em + 4px)}').css;
assert(complex.includes('width:calc(100% - 20px)'));
assert(complex.includes('height:calc(2em + 4px)'));

// Malformed CSS must degrade without throwing; the untouched tail is retained.
const malformed = transform('.ok{color:red}.broken{width:10px').css;
assert(malformed.includes('.ok{color:red;}'));
assert(malformed.includes('.broken{width:10px'));

console.log(`test_css_compat_fixtures: ok (${cases.length + 3} fixtures)`);
