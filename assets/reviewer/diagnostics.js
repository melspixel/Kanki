(function () {
  'use strict';

  var qa = document.getElementById('qa');
  var renderNumber = 0;
  var queue = [];
  var busy = false;
  var RAW_RENDER_LIMIT = 12;
  var METRIC_RENDER_LIMIT = 200;
  var ELEMENT_LIMIT = 40;
  var CHUNK_SIZE = 500;

  function rawCaptureEnabled() {
    return !!(window.kankiDiagnostics && window.kankiDiagnostics.rawCapture);
  }

  function rectWidth(rect) {
    if (!rect) return 0;
    if (typeof rect.width === 'number') return rect.width;
    return Number(rect.right || 0) - Number(rect.left || 0);
  }

  function rectHeight(rect) {
    if (!rect) return 0;
    if (typeof rect.height === 'number') return rect.height;
    return Number(rect.bottom || 0) - Number(rect.top || 0);
  }

  function finiteNumber(value) {
    value = Number(value);
    return isFinite(value) ? Math.round(value * 100) / 100 : 0;
  }

  function imagePing(url, done) {
    var image = new Image();
    var finished = false;
    var timer;
    function finish() {
      if (finished) return;
      finished = true;
      window.clearTimeout(timer);
      if (image.parentNode) image.parentNode.removeChild(image);
      if (done) done();
    }
    image.style.display = 'none';
    image.onload = finish;
    image.onerror = finish;
    image.src = url;
    (document.body || document.documentElement).appendChild(image);
    timer = window.setTimeout(finish, 1200);
  }

  function ping(path, values, done) {
    var query = [];
    var key;
    values = values || {};
    values.nonce = String(new Date().getTime()) + String(Math.random());
    for (key in values) {
      if (Object.prototype.hasOwnProperty.call(values, key)) {
        query.push(encodeURIComponent(key) + '=' + encodeURIComponent(String(values[key])));
      }
    }
    imagePing('http://127.0.0.1:17393/' + path + '?' + query.join('&'), done);
  }

  function nextQueued() {
    var item;
    if (busy || !queue.length) return;
    busy = true;
    item = queue.shift();
    ping(item.path, item.values, function () {
      busy = false;
      nextQueued();
    });
  }

  function enqueue(path, values) {
    queue.push({path: path, values: values});
    nextQueued();
  }

  function captureChunks(id, side, kind, value) {
    var text = String(value == null ? '' : value);
    var offset = 0;
    var part = 0;
    if (!rawCaptureEnabled()) return;
    if (!text.length) {
      enqueue('capture', {id: id, side: side, kind: kind, part: 0, data: ''});
      return;
    }
    while (offset < text.length) {
      enqueue('capture', {
        id: id,
        side: side,
        kind: kind,
        part: part,
        data: text.substring(offset, offset + CHUNK_SIZE)
      });
      offset += CHUNK_SIZE;
      part += 1;
    }
  }

  function classText(element) {
    var value = element && element.className;
    if (value && typeof value.baseVal === 'string') return value.baseVal;
    return value == null ? '' : String(value);
  }

  function elementMetrics(id, side, phase) {
    var nodes = qa.getElementsByTagName('*');
    var count = 0;
    var i;
    for (i = 0; i < nodes.length && count < ELEMENT_LIMIT; i += 1) {
      var node = nodes[i];
      var rect;
      var width;
      var height;
      var style;
      if (!node.getBoundingClientRect) continue;
      rect = node.getBoundingClientRect();
      width = rectWidth(rect);
      height = rectHeight(rect);
      if (!(width > 0 && height > 0)) continue;
      style = window.getComputedStyle ? window.getComputedStyle(node, null) : node.currentStyle;
      enqueue('element', {
        id: id,
        side: side,
        phase: phase,
        i: i,
        tag: String(node.tagName || '').toLowerCase(),
        cls: classText(node).substring(0, 180),
        g: [finiteNumber(rect.left), finiteNumber(rect.top), finiteNumber(width), finiteNumber(height)].join(','),
        font: style ? [style.fontFamily || '', style.fontSize || '', style.fontWeight || '', style.lineHeight || ''].join('|').substring(0, 170) : '',
        display: style ? [style.display || '', style.position || '', style.overflow || ''].join('|') : ''
      });
      count += 1;
    }
    return count;
  }

  function pageMetrics(id, side, phase, withElements) {
    var rect = qa.getBoundingClientRect ? qa.getBoundingClientRect() : null;
    var count = withElements ? elementMetrics(id, side, phase) : qa.getElementsByTagName('*').length;
    enqueue('metric', {
      id: id,
      side: side,
      phase: phase,
      body: String(document.body.className || '').substring(0, 180),
      iw: window.innerWidth || 0,
      ih: window.innerHeight || 0,
      qw: rect ? finiteNumber(rectWidth(rect)) : qa.clientWidth || 0,
      qh: rect ? finiteNumber(rectHeight(rect)) : qa.clientHeight || 0,
      sw: Math.max(document.documentElement.scrollWidth || 0, document.body.scrollWidth || 0),
      sh: Math.max(document.documentElement.scrollHeight || 0, document.body.scrollHeight || 0),
      dpr: window.devicePixelRatio || 1,
      elements: count
    });
  }

  function begin(packet, cardId) {
    var side = packet && packet.side || 'unknown';
    var safeCard = cardId == null ? 'none' : String(cardId).replace(/[^A-Za-z0-9_-]/g, '_');
    renderNumber += 1;
    var sequence = renderNumber;
    var id = String(sequence) + '-' + safeCard;

    if (sequence > METRIC_RENDER_LIMIT) return;

    pageMetrics(id, side, 'initial', false);

    if (sequence <= RAW_RENDER_LIMIT && rawCaptureEnabled()) {
      captureChunks(id, side, 'html', packet && packet.html || '');
      captureChunks(id, side, 'css', packet && packet.css || '');
      captureChunks(id, side, 'meta', JSON.stringify({
        side: side,
        body_class: packet && packet.body_class || '',
        audio: packet && packet.audio || []
      }));
    }

    window.setTimeout(function () {
      pageMetrics(id, side, 'settled', sequence <= RAW_RENDER_LIMIT);
    }, 300);
  }

  window.kankiRendererDiagnostics = {
    protocolVersion: 1,
    begin: begin,
    rawCaptureEnabled: rawCaptureEnabled
  };
}());
