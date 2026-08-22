(function () {
  'use strict';

  var TYPESET_TIMEOUT_MS = 20000;

  function containsMath(root) {
    var source;
    var scripts;
    var i;
    if (!root) return false;
    source = root.innerHTML || '';
    if (/\\\(|\\\[|\\begin\s*\{/.test(source)) return true;
    scripts = root.getElementsByTagName('script');
    for (i = 0; i < scripts.length; i += 1) {
      if (/^math\/tex(?:;|$)/i.test(scripts[i].type || '')) return true;
    }
    return false;
  }

  function clear(root) {
    var jax;
    var i;
    if (!root || !window.MathJax || !window.MathJax.Hub ||
        !window.MathJax.Hub.getAllJax) return;
    try {
      jax = window.MathJax.Hub.getAllJax(root) || [];
    } catch (error) {
      return;
    }
    for (i = 0; i < jax.length; i += 1) {
      try {
        if (jax[i] && jax[i].Remove) jax[i].Remove();
      } catch (error) {}
    }
  }

  function typeset(root, done, failed) {
    var finished = false;
    var timer;

    function finish(callback, value) {
      if (finished) return;
      finished = true;
      if (timer) window.clearTimeout(timer);
      callback(value);
    }

    if (!containsMath(root)) {
      done();
      return false;
    }
    if (!window.MathJax || !window.MathJax.Hub || !window.MathJax.Hub.Queue) {
      failed('MathJax runtime is unavailable');
      return true;
    }
    timer = window.setTimeout(function () {
      finish(failed, 'MathJax typesetting timed out');
    }, TYPESET_TIMEOUT_MS);
    try {
      window.MathJax.Hub.Queue(
        ['Typeset', window.MathJax.Hub, root],
        function () {
          finish(done);
        }
      );
    } catch (error) {
      finish(failed, String(error));
    }
    return true;
  }

  window.kankiMathjax = {
    clear: clear,
    containsMath: containsMath,
    typeset: typeset,
    protocolVersion: 1
  };
}());
