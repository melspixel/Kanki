(function () {
  'use strict';

  var sequence = 0;

  function encode(values) {
    var parts = [];
    var key;
    values = values || {};
    for (key in values) {
      if (Object.prototype.hasOwnProperty.call(values, key) && values[key] !== undefined) {
        parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(String(values[key])));
      }
    }
    return parts.join('&');
  }

  function send(operation, values) {
    values = values || {};
    sequence += 1;
    values.request_id = String(new Date().getTime()) + '-' + String(sequence);
    window.location.href = 'kap://v1/' + operation + '?' + encode(values);
  }

  window.kapBridge = {
    protocolVersion: 1,
    send: send
  };
}());
