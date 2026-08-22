(function () {
  'use strict';

  function createAudioQueue(send) {
    var queue = [];
    var nextIndex = 0;

    function sendTag(tag) {
      if (!tag) return false;
      if (tag.kind === 'sound') {
        send('audio/play', {source: tag.source || ''});
        return true;
      }
      if (tag.kind === 'tts') {
        send('audio/tts', {
          text: tag.text || '',
          lang: tag.lang || '',
          voices: tag.voices && tag.voices.length ? tag.voices.join(',') : '',
          speed: typeof tag.speed === 'number' ? tag.speed : 1
        });
        return true;
      }
      return false;
    }

    function clear() {
      queue = [];
      nextIndex = 0;
    }

    function advance() {
      while (nextIndex < queue.length) {
        if (sendTag(queue[nextIndex])) {
          nextIndex += 1;
          return true;
        }
        nextIndex += 1;
      }
      clear();
      return false;
    }

    return {
      start: function (tags) {
        queue = tags && tags.slice ? tags.slice(0) : [];
        nextIndex = 0;
        if (!advance()) send('audio/stop', {});
      },
      playOne: function (tag) {
        clear();
        if (!sendTag(tag)) send('audio/stop', {});
      },
      finished: function () {
        advance();
      },
      stop: function () {
        clear();
        send('audio/stop', {});
      },
      pendingCount: function () {
        return queue.length - nextIndex;
      }
    };
  }

  window.kapCreateAudioQueue = createAudioQueue;
}());
