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
    var changed = false;
    if (applying || !window.kankiCssCompat) return;
    var current = styleText();
    if (current !== source && current !== result.css) {
      source = current;
      result = window.kankiCssCompat.transform(current);
      changed = true;
      if (result.css !== current) {
        applying = true;
        setStyleText(result.css);
        applying = false;
      }
    }
    if (changed) scheduleLayout();
  }

  function domChanged() {
    scheduleLayout();
  }

  if (style.addEventListener) style.addEventListener('DOMSubtreeModified', refresh, false);
  if (qa.addEventListener) {
    qa.addEventListener('DOMNodeInserted', domChanged, false);
    qa.addEventListener('DOMNodeRemoved', domChanged, false);
  }

  /* Mutation events are available on the target WebKit. The bounded poll is a
     compatibility fallback for engines that coalesce style-text mutations.
     Importantly, an idle poll no longer re-runs all gap selectors every 100ms;
     layout work only happens when CSS or the card DOM actually changed. */
  window.setInterval(refresh, 250);
  refresh();
}());
