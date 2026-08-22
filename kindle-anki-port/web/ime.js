(function () {
  'use strict';

  var bridge = window.kapBridge;
  var originalSend;
  var requested = false;

  if (!bridge || typeof bridge.send !== 'function') return;
  originalSend = bridge.send;

  function isTypedAnswer(node) {
    return !!node && node.id === 'kap-type-answer';
  }

  function open() {
    if (requested) return;
    requested = true;
    originalSend('ime/open', {});
  }

  function close() {
    if (!requested) return;
    requested = false;
    originalSend('ime/close', {});
  }

  function onFocus(event) {
    event = event || window.event;
    if (isTypedAnswer(event && (event.target || event.srcElement))) open();
  }

  function onBlur(event) {
    event = event || window.event;
    if (isTypedAnswer(event && (event.target || event.srcElement))) close();
  }

  if (document.addEventListener) {
    /* focus/blur do not bubble, so use capture. focusin/focusout are retained
     * as a WebKitGTK1 fallback; the requested flag de-duplicates both paths. */
    document.addEventListener('focus', onFocus, true);
    document.addEventListener('blur', onBlur, true);
    document.addEventListener('focusin', onFocus, false);
    document.addEventListener('focusout', onBlur, false);
  }

  bridge.send = function (operation, values) {
    values = values || {};
    if (operation === 'review/reveal' ||
        operation === 'app/back' ||
        operation === 'app/close' ||
        (operation === 'ui/state' && values.mode && values.mode !== 'question')) {
      close();
    }
    return originalSend(operation, values);
  };

  window.kapIme = {
    protocolVersion: 1,
    open: open,
    close: close,
    requested: function () { return requested; }
  };
}());
