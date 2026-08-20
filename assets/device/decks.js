(function () {
  'use strict';

  var tree = document.getElementById('deck-tree');
  var status = document.getElementById('status');
  var errorBox = document.getElementById('error');

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

  function text(value) {
    return document.createTextNode(String(value == null ? '' : value));
  }

  function clear(node) {
    while (node.firstChild) node.removeChild(node.firstChild);
  }

  function renderNode(node) {
    var item = document.createElement('li');
    var row = document.createElement('div');
    var toggle = document.createElement('button');
    var open = document.createElement('button');
    var counts = document.createElement('span');
    var children = document.createElement('ul');
    var hasChildren = node.children && node.children.length;
    var i;

    row.className = 'deck-row';
    toggle.className = 'deck-toggle';
    open.className = 'deck-open';
    counts.className = 'deck-counts';
    toggle.appendChild(text(hasChildren ? (node.collapsed ? '+' : '−') : ''));
    toggle.disabled = !hasChildren;
    open.appendChild(text(node.name));
    counts.appendChild(text(
      (node.counts ? node.counts.new : 0) + '  ' +
      (node.counts ? node.counts.learning : 0) + '  ' +
      (node.counts ? node.counts.review : 0)
    ));

    (function (deckId) {
      open.onclick = function () {
        status.textContent = 'Opening ' + node.name + '…';
        command('deck/select', {id: deckId});
        return false;
      };
    }(node.id));
    (function (deckId, collapsed) {
      toggle.onclick = function () {
        command('deck/collapse', {id: deckId, collapsed: collapsed ? 0 : 1});
        return false;
      };
    }(node.id, node.collapsed));

    row.appendChild(toggle);
    row.appendChild(open);
    row.appendChild(counts);
    item.appendChild(row);
    if (hasChildren) {
      if (node.collapsed) children.className = 'children-collapsed';
      for (i = 0; i < node.children.length; i += 1) {
        children.appendChild(renderNode(node.children[i]));
      }
      item.appendChild(children);
    }
    return item;
  }

  function renderTree(root) {
    var list = document.createElement('ul');
    var nodes = root && root.children && root.children.length ? root.children : [root];
    var i;
    clear(tree);
    for (i = 0; i < nodes.length; i += 1) {
      if (nodes[i]) list.appendChild(renderNode(nodes[i]));
    }
    tree.appendChild(list);
    status.textContent = 'New  Learning  Review';
  }

  function showError(message) {
    errorBox.hidden = false;
    errorBox.textContent = message || 'Unknown error';
    status.textContent = 'Unable to load decks';
  }

  function nativeResponse(name, jsonText) {
    var envelope;
    try {
      envelope = JSON.parse(jsonText);
      if (!envelope.ok) {
        showError(envelope.error);
        return;
      }
      if (name === 'deck_tree') renderTree(envelope.data);
    } catch (error) {
      showError(String(error));
    }
  }

  window.kankiDecks = {nativeResponse: nativeResponse};
  command('ready', {view: 'decks'});
}());
