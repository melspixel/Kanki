(function () {
  'use strict';

  var qa = document.getElementById('qa');
  var deckStyle = document.getElementById('kanki-deck-style');

  function clearNode(node) {
    while (node.firstChild) node.removeChild(node.firstChild);
  }

  function executeScripts(root) {
    var scripts = root.getElementsByTagName('script');
    var pending = [];
    var i;
    for (i = 0; i < scripts.length; i += 1) pending.push(scripts[i]);
    for (i = 0; i < pending.length; i += 1) {
      var oldScript = pending[i];
      var newScript = document.createElement('script');
      var a;
      for (a = 0; a < oldScript.attributes.length; a += 1) {
        newScript.setAttribute(oldScript.attributes[a].name, oldScript.attributes[a].value);
      }
      newScript.text = oldScript.text || oldScript.textContent || oldScript.innerHTML || '';
      oldScript.parentNode.replaceChild(newScript, oldScript);
    }
  }

  function replaySvg() {
    return '<svg viewBox="0 0 40 40" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">' +
      '<circle cx="20" cy="20" r="18" fill="none" stroke="currentColor" stroke-width="2"></circle>' +
      '<path d="M11 16v8h6l8 7V9l-8 7h-6zm17.2-1.9v11.8c2.4-1.1 4-3.3 4-5.9s-1.6-4.8-4-5.9z" fill="currentColor"></path>' +
      '</svg>';
  }

  function playTag(tag) {
    if (!tag || !window.kankiBridge) return;
    if (tag.kind === 'sound' && window.kankiBridge.playAudio) {
      window.kankiBridge.playAudio(tag.source || '');
    } else if (tag.kind === 'tts' && window.kankiBridge.playTts) {
      window.kankiBridge.playTts(
        tag.text || '',
        tag.lang || '',
        tag.voices || [],
        typeof tag.speed === 'number' ? tag.speed : 1.0
      );
    }
  }

  function makeReplayButton(index, packet) {
    var link = document.createElement('a');
    link.href = '#';
    link.className = 'replay-button';
    link.setAttribute('role', 'button');
    link.setAttribute('aria-label', 'Replay audio');
    link.setAttribute('data-kanki-av-index', String(index));
    link.innerHTML = replaySvg();
    link.onclick = function () {
      var value = parseInt(this.getAttribute('data-kanki-av-index'), 10);
      if (!isNaN(value) && packet.audio && value < packet.audio.length) {
        playTag(packet.audio[value]);
      }
      return false;
    };
    return link;
  }

  function replaceAvMarkers(node, packet) {
    if (!node) return;
    if (node.nodeType === 3) {
      var text = node.nodeValue || '';
      var re = /\[anki:play:[qa]:(\d+)\]/g;
      var match;
      var last = 0;
      var fragment = null;
      while ((match = re.exec(text)) !== null) {
        if (!fragment) fragment = document.createDocumentFragment();
        if (match.index > last) {
          fragment.appendChild(document.createTextNode(text.substring(last, match.index)));
        }
        fragment.appendChild(makeReplayButton(parseInt(match[1], 10), packet));
        last = re.lastIndex;
      }
      if (fragment) {
        if (last < text.length) {
          fragment.appendChild(document.createTextNode(text.substring(last)));
        }
        node.parentNode.replaceChild(fragment, node);
      }
      return;
    }
    if (node.nodeType !== 1) return;
    var tagName = String(node.tagName || '').toLowerCase();
    if (tagName === 'script' || tagName === 'style' || tagName === 'textarea') return;
    var child = node.firstChild;
    while (child) {
      var next = child.nextSibling;
      replaceAvMarkers(child, packet);
      child = next;
    }
  }

  function installSemanticAudio(packet) {
    replaceAvMarkers(qa, packet);
    if (packet.audio && packet.audio.length) playTag(packet.audio[0]);
  }

  function showError(err) {
    clearNode(qa);
    var box = document.createElement('div');
    box.className = 'kanki-render-error';
    box.appendChild(document.createTextNode('Card rendering failed: ' + String(err)));
    qa.appendChild(box);
  }

  function showCard(packet) {
    try {
      document.body.className = packet.body_class;
      deckStyle.textContent = packet.css || '';
      qa.innerHTML = packet.html || '';
      executeScripts(qa);
      installSemanticAudio(packet);
      if (packet.side === 'answer') {
        var answer = document.getElementById('answer');
        if (answer && answer.scrollIntoView) answer.scrollIntoView(true);
        else window.scrollTo(0, 0);
      } else {
        window.scrollTo(0, 0);
      }
      if (window.kankiBridge && window.kankiBridge.renderComplete) {
        window.kankiBridge.renderComplete(packet.side, qa.scrollWidth, qa.scrollHeight);
      }
    } catch (err) {
      showError(err);
      if (window.kankiBridge && window.kankiBridge.renderFailed) {
        window.kankiBridge.renderFailed(String(err));
      }
    }
  }

  window.kankiReviewer = {
    showCard: showCard,
    protocolVersion: 1
  };
}());
