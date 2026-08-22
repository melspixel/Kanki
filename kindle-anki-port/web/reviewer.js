(function () {
  'use strict';

  var qa = document.getElementById('qa');
  var noteStyle = document.getElementById('kap-note-style');
  var current = null;
  var shownAt = 0;
  var touchStartX = 0;
  var touchStartY = 0;
  var touchStarted = false;
  var audioQueue = window.kapCreateAudioQueue(function (operation, values) {
    window.kapBridge.send(operation, values);
  });

  function setStyleText(value) {
    if (noteStyle.styleSheet) noteStyle.styleSheet.cssText = value;
    else noteStyle.textContent = value;
  }

  function clearNode(node) {
    while (node.firstChild) node.removeChild(node.firstChild);
  }

  function textBox(className, text) {
    clearNode(qa);
    var box = document.createElement('div');
    box.className = className;
    box.appendChild(document.createTextNode(text));
    qa.appendChild(box);
  }

  function showError(error) {
    textBox('kap-render-error', 'Card rendering failed: ' + String(error));
  }

  function executeScripts(root) {
    var found = root.getElementsByTagName('script');
    var scripts = [];
    var i, oldScript, replacement, a;
    for (i = 0; i < found.length; i += 1) scripts.push(found[i]);
    for (i = 0; i < scripts.length; i += 1) {
      oldScript = scripts[i];
      replacement = document.createElement('script');
      for (a = 0; a < oldScript.attributes.length; a += 1) {
        replacement.setAttribute(oldScript.attributes[a].name, oldScript.attributes[a].value);
      }
      replacement.text = oldScript.text || oldScript.textContent || oldScript.innerHTML || '';
      if (oldScript.parentNode) oldScript.parentNode.replaceChild(replacement, oldScript);
    }
  }

  function replayButton(index, packet) {
    var button = document.createElement('button');
    button.type = 'button';
    button.className = 'kap-replay-button';
    button.setAttribute('data-kap-audio-index', String(index));
    button.setAttribute('aria-label', 'Replay audio');
    button.appendChild(document.createTextNode('▶'));
    button.onclick = function () {
      var value = parseInt(this.getAttribute('data-kap-audio-index'), 10);
      if (!isNaN(value) && packet.audio && value < packet.audio.length) {
        audioQueue.playOne(packet.audio[value]);
      }
      return false;
    };
    return button;
  }

  function replaceAudioMarkers(node, packet) {
    if (!node) return;
    if (node.nodeType === 3) {
      var value = node.nodeValue || '';
      var expression = /\[anki:play:[qa]:(\d+)\]/g;
      var match;
      var last = 0;
      var fragment = null;
      while ((match = expression.exec(value)) !== null) {
        if (!fragment) fragment = document.createDocumentFragment();
        if (match.index > last) fragment.appendChild(document.createTextNode(value.substring(last, match.index)));
        fragment.appendChild(replayButton(parseInt(match[1], 10), packet));
        last = expression.lastIndex;
      }
      if (fragment) {
        if (last < value.length) fragment.appendChild(document.createTextNode(value.substring(last)));
        if (node.parentNode) node.parentNode.replaceChild(fragment, node);
      }
      return;
    }
    if (node.nodeType !== 1) return;
    var tagName = String(node.tagName || '').toLowerCase();
    if (tagName === 'script' || tagName === 'style' || tagName === 'textarea') return;
    var child = node.firstChild;
    while (child) {
      var next = child.nextSibling;
      replaceAudioMarkers(child, packet);
      child = next;
    }
  }

  function removeDuplicateAnkiReplayControls() {
    var selectors = ['.replay-button', '.soundLink', '[data-av-tag]'];
    var s, nodes, i, node;
    for (s = 0; s < selectors.length; s += 1) {
      try { nodes = qa.querySelectorAll(selectors[s]); } catch (error) { continue; }
      for (i = 0; i < nodes.length; i += 1) {
        node = nodes[i];
        if (node.className && String(node.className).indexOf('kap-replay-button') >= 0) continue;
        if (node.parentNode) node.parentNode.removeChild(node);
      }
    }
  }

  function installTypedInput(packet) {
    if (!packet.typed || !packet.typed.enabled) return;
    var slot = document.getElementById('kap-type-answer-slot');
    if (!slot) return;
    var input = document.createElement('input');
    input.id = 'kap-type-answer';
    input.type = 'text';
    input.autocomplete = 'off';
    input.autocapitalize = 'off';
    input.spellcheck = false;
    input.setAttribute('aria-label', 'Type answer for ' + (packet.typed.field || 'field'));
    if (packet.typed.font) input.style.fontFamily = packet.typed.font;
    input.style.fontSize = Math.max(24, Number(packet.typed.size || 32)) + 'px';
    input.onkeypress = function (event) {
      event = event || window.event;
      if ((event.keyCode || event.which) === 13) {
        requestReveal();
        return false;
      }
      return true;
    };
    slot.parentNode.replaceChild(input, slot);
    window.setTimeout(function () {
      try { input.focus(); } catch (error) {}
    }, 0);
  }

  function flattenNestedVerticalScroll() {
    var nodes = qa.getElementsByTagName('*');
    var i, node, style, overflowY, heightBounded;
    for (i = 0; i < nodes.length; i += 1) {
      node = nodes[i];
      if (!node || node.id === 'kap-type-answer') continue;
      if (String(node.tagName || '').toLowerCase() === 'textarea') continue;
      try { style = window.getComputedStyle ? window.getComputedStyle(node, null) : node.currentStyle; }
      catch (error) { style = null; }
      if (!style) continue;
      overflowY = style.overflowY || style.overflow || '';
      heightBounded = style.height !== 'auto' || (style.maxHeight && style.maxHeight !== 'none');
      if (heightBounded && /(auto|scroll)/.test(overflowY) && node.scrollHeight > node.clientHeight + 4) {
        node.className = (node.className ? String(node.className) + ' ' : '') + 'kap-flattened-scroll';
      }
    }
  }

  function applyCompatibility(css) {
    if (!window.kapCssCompat) { setStyleText(css || ''); return; }
    var result = window.kapCssCompat.transform(css || '');
    setStyleText(result.css);
    window.setTimeout(function () { window.kapCssCompat.apply(qa, result.gaps || []); }, 0);
  }

  function render(packet) {
    try {
      current = packet;
      document.body.className = packet.body_class || 'card card1 isLin kindle kap';
      applyCompatibility(packet.css || '');
      qa.innerHTML = packet.html || '';
      executeScripts(qa);
      replaceAudioMarkers(qa, packet);
      removeDuplicateAnkiReplayControls();
      installTypedInput(packet);
      flattenNestedVerticalScroll();
      if (packet.kind === 'answer') {
        var separator = document.getElementById('answer');
        if (separator && separator.scrollIntoView) separator.scrollIntoView(true);
        else window.scrollTo(0, 0);
      } else {
        window.scrollTo(0, 0);
      }
      if (packet.autoplay === false) audioQueue.stop();
      else audioQueue.start(packet.audio || []);
      window.kapBridge.send('ui/state', {
        mode: packet.kind,
        again: packet.intervals && packet.intervals[0] || '',
        hard: packet.intervals && packet.intervals[1] || '',
        good: packet.intervals && packet.intervals[2] || '',
        easy: packet.intervals && packet.intervals[3] || ''
      });
    } catch (error) {
      audioQueue.stop();
      showError(error);
      window.kapBridge.send('ui/render-failed', {message: String(error)});
    }
  }

  function typedValue() {
    var input = document.getElementById('kap-type-answer');
    return input ? input.value || '' : '';
  }

  function requestReveal() {
    if (!current || current.kind !== 'question') return;
    window.kapBridge.send('review/reveal', {
      typed: typedValue(),
      elapsed_ms: Math.max(0, new Date().getTime() - shownAt)
    });
  }

  function page(delta) {
    var viewport = window.innerHeight || document.documentElement.clientHeight || 800;
    window.scrollBy(0, Math.round(viewport * 0.78) * delta);
  }

  function nativeResponse(operation, jsonText) {
    var envelope;
    try {
      envelope = JSON.parse(jsonText);
      if (!envelope.ok) throw new Error(envelope.error || 'Backend operation failed');
      if (operation === 'next_question' || operation === 'reveal_answer') {
        if (!envelope.data || envelope.data.kind === 'finished') {
          current = null;
          textBox('kap-review-message', 'Review complete');
          audioQueue.stop();
          window.kapBridge.send('ui/state', {mode: 'finished'});
        } else {
          shownAt = new Date().getTime();
          render(envelope.data);
        }
      } else if (operation === 'answer' || operation === 'bury') {
        window.kapBridge.send('review/next', {});
      }
    } catch (error) {
      audioQueue.stop();
      showError(error);
      window.kapBridge.send('ui/state', {mode: 'error'});
    }
  }

  function onTouchStart(event) {
    if (!event.touches || event.touches.length !== 1) return;
    touchStarted = true;
    touchStartX = event.touches[0].clientX;
    touchStartY = event.touches[0].clientY;
  }

  function onTouchEnd(event) {
    if (!touchStarted || !event.changedTouches || event.changedTouches.length !== 1) return;
    touchStarted = false;
    var dx = event.changedTouches[0].clientX - touchStartX;
    var dy = event.changedTouches[0].clientY - touchStartY;
    if (Math.abs(dy) >= 48 && Math.abs(dy) > Math.abs(dx) * 1.25) page(dy < 0 ? 1 : -1);
  }

  if (document.addEventListener) {
    document.addEventListener('touchstart', onTouchStart, false);
    document.addEventListener('touchend', onTouchEnd, false);
  }

  window.kapReviewer = {
    protocolVersion: 1,
    nativeResponse: nativeResponse,
    requestReveal: requestReveal,
    pageDown: function () { page(1); },
    pageUp: function () { page(-1); },
    typedValue: typedValue,
    audioFinished: function () { audioQueue.finished(); }
  };

  window.kapBridge.send('ready', {view: 'reviewer'});
}());
