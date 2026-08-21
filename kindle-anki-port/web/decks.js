(function () {
  'use strict';
  var root = document.getElementById('kap-decks');

  function clear() { while (root.firstChild) root.removeChild(root.firstChild); }

  function row(deck) {
    var container = document.createElement('div');
    var line = document.createElement('div');
    line.className = 'kap-deck-row';
    var collapse = document.createElement('button');
    collapse.type = 'button';
    collapse.className = 'kap-collapse';
    collapse.appendChild(document.createTextNode(deck.children && deck.children.length ?
      (deck.collapsed ? '+' : '−') : ''));
    collapse.onclick = function () {
      if (deck.children && deck.children.length) {
        window.kapBridge.send('deck/collapse', {id: deck.id, collapsed: deck.collapsed ? 0 : 1});
      }
      return false;
    };
    var select = document.createElement('button');
    select.type = 'button';
    select.className = 'kap-deck-select';
    select.appendChild(document.createTextNode(deck.name || 'Unnamed deck'));
    var counts = document.createElement('span');
    counts.className = 'kap-deck-counts';
    counts.appendChild(document.createTextNode(
      String(deck.counts && deck.counts.new || 0) + ' + ' +
      String(deck.counts && deck.counts.learning || 0) + ' + ' +
      String(deck.counts && deck.counts.review || 0)));
    select.appendChild(counts);
    select.onclick = function () {
      window.kapBridge.send('deck/select', {id: deck.id});
      return false;
    };
    line.appendChild(collapse);
    line.appendChild(select);
    container.appendChild(line);
    if (!deck.collapsed && deck.children && deck.children.length) {
      var children = document.createElement('div');
      children.className = 'kap-deck-children';
      var i;
      for (i = 0; i < deck.children.length; i += 1) children.appendChild(row(deck.children[i]));
      container.appendChild(children);
    }
    return container;
  }

  function render(tree) {
    clear();
    var decks = tree && tree.children ? tree.children : [tree];
    var i;
    for (i = 0; i < decks.length; i += 1) root.appendChild(row(decks[i]));
  }

  function nativeResponse(operation, jsonText) {
    try {
      var envelope = JSON.parse(jsonText);
      if (!envelope.ok) throw new Error(envelope.error || 'Deck operation failed');
      if (operation === 'deck_tree') render(envelope.data);
    } catch (error) {
      clear();
      var box = document.createElement('div');
      box.className = 'kap-error';
      box.appendChild(document.createTextNode(String(error)));
      root.appendChild(box);
    }
  }

  window.kapDecks = {protocolVersion: 1, nativeResponse: nativeResponse};
  window.kapBridge.send('ready', {view: 'decks'});
}());
