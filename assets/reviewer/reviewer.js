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

  function installAudioLinks(packet) {
    var links = qa.querySelectorAll ? qa.querySelectorAll('[data-kanki-audio]') : [];
    var i;
    for (i = 0; i < links.length; i += 1) {
      links[i].onclick = function () {
        var source = this.getAttribute('data-kanki-audio') || '';
        if (window.kankiBridge && window.kankiBridge.playAudio) {
          window.kankiBridge.playAudio(source);
        }
        return false;
      };
    }
    if (packet.audio && packet.audio.length && window.kankiBridge && window.kankiBridge.playAudio) {
      window.kankiBridge.playAudio(packet.audio[0].source);
    }
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
      installAudioLinks(packet);
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
