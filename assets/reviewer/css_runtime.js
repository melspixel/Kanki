(function () {
  'use strict';

  var style = document.getElementById('kanki-deck-style');
  var qa = document.getElementById('qa');
  var applying = false;
  var source = null;
  var result = {css: '', gaps: []};
  var scheduled = false;

  function styleText() {
    if (style.styleSheet && typeof style.styleSheet.cssText === 'string') {
      return style.styleSheet.cssText;
    }
    return typeof style.textContent === 'string' ? style.textContent : '';
  }

  function setStyleText(value) {
    if (style.styleSheet) style.styleSheet.cssText = value;
    else style.textContent = value;
  }

  function applyLayout() {
    scheduled = false;
    if (window.kankiCssCompat && window.kankiCssCompat.apply) {
      window.kankiCssCompat.apply(qa, result);
    }
  }

  function scheduleLayout() {
    if (scheduled) return;
    scheduled = true;
    window.setTimeout(applyLayout, 0);
  }

  function refresh() {
    if (applying || !window.kankiCssCompat) return;
    var current = styleText();
    if (current !== source && current !== result.css) {
      source = current;
      result = window.kankiCssCompat.transform(current);
      if (result.css !== current) {
        applying = true;
        setStyleText(result.css);
        applying = false;
      }
    }
    scheduleLayout();
  }

  if (style.addEventListener) style.addEventListener('DOMSubtreeModified', refresh, false);
  if (qa.addEventListener) {
    qa.addEventListener('DOMNodeInserted', scheduleLayout, false);
    qa.addEventListener('DOMNodeRemoved', scheduleLayout, false);
  }

  /* Mutation events are available on the target WebKit, but the bounded poll
     also covers engines that coalesce style-text mutations. It is deliberately
     small and does no work when neither CSS nor DOM changed. */
  window.setInterval(refresh, 100);
  refresh();
}());
