(function () {
  'use strict';

  var qa = document.getElementById('qa');
  var deckStyle = document.getElementById('kanki-deck-style');
  var currentCard = null;
  var shownAt = 0;

  function command(name, values) {
    var parts = [];
    var key;
    values = values || {};
    values.nonce = String(new Date().getTime()) + String(Math.random());
    for (key in values) {
      if (Object.prototype.hasOwnProperty.call(values, key)) {
        parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(String(values[key])));
      }
    }
    window.location.href = 'kanki://' + name + '?' + parts.join('&');
  }

  function audioPing(path, values) {
    var query = [];
    var key;
    var image = new Image();
    values = values || {};
    values.nonce = String(new Date().getTime()) + String(Math.random());
    for (key in values) {
      if (Object.prototype.hasOwnProperty.call(values, key)) {
        query.push(encodeURIComponent(key) + '=' + encodeURIComponent(String(values[key])));
      }
    }
    image.style.display = 'none';
    image.src = 'http://127.0.0.1:17392/' + path + '?' + query.join('&');
    (document.body || document.documentElement).appendChild(image);
    window.setTimeout(function () {
      if (image.parentNode) image.parentNode.removeChild(image);
    }, 1500);
  }

  window.kankiBridge = {
    playAudio: function (source) {
      audioPing('play', {src: source || ''});
    },
    playTts: function (text, lang, voices, speed) {
      audioPing('tts', {
        text: text || '',
        lang: lang || '',
        voices: voices && voices.length ? voices.join(',') : '',
        speed: typeof speed === 'number' ? speed : 1.0
      });
    },
    stopAudio: function () {
      audioPing('stop', {});
    },
    renderComplete: function () {},
    renderFailed: function (message) {
      command('ui/render-failed', {message: message || 'unknown render failure'});
    }
  };

  /* Old Kindle WebKit may expose no HTML5 Audio constructor at all. Card
     templates are still allowed to use `new Audio(src).play()`, so Kanki
     supplies that standard-shaped entry point and routes it through the same
     native service used for semantic Anki AV tags. */
  function KankiAudio(source) {
    this.src = source || '';
    this.currentSrc = this.src;
    this.paused = true;
    this.ended = false;
  }

  KankiAudio.prototype.play = function () {
    this.currentSrc = this.src || this.currentSrc || '';
    this.paused = false;
    this.ended = false;
    window.kankiBridge.playAudio(this.currentSrc);
  };

  KankiAudio.prototype.pause = function () {
    this.paused = true;
    window.kankiBridge.stopAudio();
  };

  KankiAudio.prototype.load = function () {};
  KankiAudio.prototype.addEventListener = function () {};
  KankiAudio.prototype.removeEventListener = function () {};
  window.Audio = KankiAudio;

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
      var value = node.nodeValue || '';
      var expression = /\[anki:play:[qa]:(\d+)\]/g;
      var match;
      var last = 0;
      var fragment = null;
      while ((match = expression.exec(value)) !== null) {
        if (!fragment) fragment = document.createDocumentFragment();
        if (match.index > last) {
          fragment.appendChild(document.createTextNode(value.substring(last, match.index)));
        }
        fragment.appendChild(makeReplayButton(parseInt(match[1], 10), packet));
        last = expression.lastIndex;
      }
      if (fragment) {
        if (last < value.length) {
          fragment.appendChild(document.createTextNode(value.substring(last)));
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

  function showError(error) {
    clearNode(qa);
    var box = document.createElement('div');
    box.className = 'kanki-render-error';
    box.appendChild(document.createTextNode('Card rendering failed: ' + String(error)));
    qa.appendChild(box);
  }

  function showMessage(message) {
    clearNode(qa);
    var box = document.createElement('div');
    box.className = 'kanki-review-message';
    box.appendChild(document.createTextNode(message));
    qa.appendChild(box);
  }

  function requestShowAnswer() {
    if (!currentCard) return false;
    var input = document.getElementById('typeans');
    command('review/show-answer', {typed: input ? input.value : ''});
    return false;
  }

  function wireTypeAnswer() {
    var input = document.getElementById('typeans');
    if (!input) return;
    input.onkeypress = function (event) {
      event = event || window.event;
      if (event && (event.keyCode === 13 || event.which === 13)) {
        return requestShowAnswer();
      }
      return true;
    };
    if (input.focus) input.focus();
  }

  function showCard(packet) {
    try {
      document.body.className = packet.body_class;
      deckStyle.textContent = packet.css || '';
      qa.innerHTML = packet.html || '';
      executeScripts(qa);
      installSemanticAudio(packet);
      if (packet.side === 'question') wireTypeAnswer();
      if (packet.side === 'answer') {
        var answer = document.getElementById('answer');
        if (answer && answer.scrollIntoView) answer.scrollIntoView(true);
        else window.scrollTo(0, 0);
      } else {
        window.scrollTo(0, 0);
      }
      if (window.kankiRendererDiagnostics && window.kankiRendererDiagnostics.begin) {
        window.kankiRendererDiagnostics.begin(
          packet,
          currentCard && currentCard.card_id != null ? currentCard.card_id : null
        );
      }
      if (window.kankiBridge && window.kankiBridge.renderComplete) {
        window.kankiBridge.renderComplete(packet.side, qa.scrollWidth, qa.scrollHeight);
      }
    } catch (error) {
      showError(error);
      if (window.kankiBridge && window.kankiBridge.renderFailed) {
        window.kankiBridge.renderFailed(String(error));
      }
    }
  }

  function packet(card, side) {
    return {
      side: side,
      body_class: 'card card' + (Number(card.template_ordinal || 0) + 1) + ' isLin kindle',
      html: side === 'answer' ? card.answer_html : card.question_html,
      css: card.css || '',
      audio: side === 'answer' ? (card.answer_audio || []) : (card.question_audio || [])
    };
  }

  function showQuestion(card) {
    currentCard = card;
    shownAt = new Date().getTime();
    showCard(packet(card, 'question'));
    command('ui/state', {mode: 'question'});
  }

  function showPreparedAnswer(prepared) {
    if (!currentCard || !prepared) return;
    showCard({
      side: 'answer',
      body_class: 'card card' + (Number(currentCard.template_ordinal || 0) + 1) + ' isLin kindle',
      html: prepared.html || '',
      css: currentCard.css || '',
      audio: prepared.audio || []
    });
    command('ui/state', {
      mode: 'answer',
      again: currentCard.intervals && currentCard.intervals[0] || '',
      hard: currentCard.intervals && currentCard.intervals[1] || '',
      good: currentCard.intervals && currentCard.intervals[2] || '',
      easy: currentCard.intervals && currentCard.intervals[3] || '',
      ms: Math.max(0, new Date().getTime() - shownAt)
    });
  }

  function nativeResponse(name, jsonText) {
    var envelope;
    try {
      envelope = JSON.parse(jsonText);
      if (!envelope.ok) {
        showError(envelope.error || 'Backend operation failed');
        command('ui/state', {mode: 'none'});
        return;
      }
      if (name === 'show_answer') {
        showPreparedAnswer(envelope.data);
      } else if (name === 'next_card') {
        if (!envelope.data || envelope.data.finished) {
          currentCard = null;
          window.kankiBridge.stopAudio();
          showMessage('Review complete');
          command('ui/state', {mode: 'finished'});
        } else {
          showQuestion(envelope.data);
        }
      }
    } catch (error) {
      showError(error);
      command('ui/state', {mode: 'none'});
    }
  }

  window.kankiReviewer = {
    showCard: showCard,
    protocolVersion: 1
  };
  window.kankiDevice = {
    nativeResponse: nativeResponse,
    requestShowAnswer: requestShowAnswer,
    currentElapsedMilliseconds: function () {
      return Math.max(0, new Date().getTime() - shownAt);
    }
  };

  command('ready', {view: 'reviewer'});
}());
