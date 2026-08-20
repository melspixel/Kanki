(function () {
    /* ES5 only: Kindle's WebKit is old enough to reject modern card JS. */
    function trim(s) {
        return String(s || '').replace(/^\s+|\s+$/g, '');
    }

    function addClass(el, name) {
        if (!el) return;
        var cls = ' ' + (el.className || '') + ' ';
        if (cls.indexOf(' ' + name + ' ') < 0) {
            el.className = trim((el.className || '') + ' ' + name);
        }
    }

    /* Modern Anki exposes platform classes on <html>. Kindle is closer to a
       compact/mobile reviewer than a desktop layout, so expose .mobile while
       keeping .linux/.kindle available for template authors. */
    addClass(document.documentElement, 'mobile');
    addClass(document.documentElement, 'linux');
    addClass(document.documentElement, 'kindle');
    window.anki = window.anki || {};
    window.ankiPlatform = 'kindle';

    function styleText(style) {
        if (typeof style.textContent === 'string') return style.textContent;
        if (style.styleSheet && typeof style.styleSheet.cssText === 'string') return style.styleSheet.cssText;
        return '';
    }

    function setStyleText(style, text) {
        if (style.styleSheet) style.styleSheet.cssText = text;
        else style.textContent = text;
    }

    function resolveVarsInValue(value, vars) {
        var previous = null;
        var rounds = 0;
        while (value !== previous && rounds < 12) {
            previous = value;
            value = value.replace(/var\(\s*--([A-Za-z0-9_-]+)\s*(?:,\s*([^\)]+))?\)/g,
                function (_, name, fallback) {
                    if (typeof vars[name] !== 'undefined') return vars[name];
                    return typeof fallback !== 'undefined' ? trim(fallback) : '';
                });
            rounds++;
        }
        return value;
    }

    function simplifyCalc(text) {
        var prev = null;
        var rounds = 0;
        while (text !== prev && rounds < 6) {
            prev = text;
            text = text.replace(/calc\(\s*([0-9.]+)px\s*\*\s*\(\s*([0-9.]+)\s*\/\s*([0-9.]+)\s*\)\s*\)/g,
                function (_, a, b, c) { return ((parseFloat(a) * parseFloat(b) / parseFloat(c)).toFixed(2).replace(/\.00$/, '')) + 'px'; });
            text = text.replace(/calc\(\s*([0-9.]+)px\s*\/\s*([0-9.]+)\s*\)/g,
                function (_, a, b) { return ((parseFloat(a) / parseFloat(b)).toFixed(2).replace(/\.00$/, '')) + 'px'; });
            text = text.replace(/calc\(\s*([0-9.]+)px\s*\+\s*([0-9.]+)px\s*\+\s*([0-9.]+)px\s*\)/g,
                function (_, a, b, c) { return (parseFloat(a) + parseFloat(b) + parseFloat(c)) + 'px'; });
            text = text.replace(/calc\(\s*([0-9.]+)px\s*\+\s*([0-9.]+)px\s*\)/g,
                function (_, a, b) { return (parseFloat(a) + parseFloat(b)) + 'px'; });
            rounds++;
        }
        return text;
    }

    function preferCompactMedia(text) {
        /* A PW6 reports a >1000px device viewport to old WebKit, which can
           accidentally select desktop-only card rules. Keep very wide-screen
           media blocks out of the Kindle layout. */
        return text.replace(/@media\s*\(\s*min-width\s*:\s*([0-9]+)px\s*\)/g,
            function (all, n) {
                return parseInt(n, 10) >= 800 ? '@media (min-width: 9999px)' : all;
            });
    }

    function polyfillCssVariables() {
        try {
            var styles = document.getElementsByTagName('style');
            var vars = {};
            var texts = [];
            var i, m, re;

            /* First occurrence wins. This intentionally chooses the deck's
               base/mobile values instead of later desktop/night-mode overrides. */
            for (i = 0; i < styles.length; i++) {
                var t = styleText(styles[i]);
                texts.push(t);
                re = /--([A-Za-z0-9_-]+)\s*:\s*([^;{}]+);/g;
                while ((m = re.exec(t)) !== null) {
                    if (typeof vars[m[1]] === 'undefined') vars[m[1]] = trim(m[2]);
                }
            }

            for (var name in vars) {
                if (Object.prototype.hasOwnProperty.call(vars, name)) {
                    vars[name] = resolveVarsInValue(vars[name], vars);
                }
            }

            for (i = 0; i < styles.length; i++) {
                var resolved = preferCompactMedia(texts[i]);
                resolved = resolveVarsInValue(resolved, vars);
                resolved = simplifyCalc(resolved);
                setStyleText(styles[i], resolved);
            }
        } catch (e) {
            /* Layout should still render with the browser's native CSS support. */
        }
    }

    /* Run while the head is still being parsed, before the card body paints. */
    polyfillCssVariables();

    function PingPromise() {}
    PingPromise.prototype.then = function () { return this; };
    PingPromise.prototype['catch'] = function () { return this; };

    function ping(path, src) {
        try {
            var i = new Image();
            i.style.display = 'none';
            i.src = 'http://127.0.0.1:17392/' + path + '?src=' + encodeURIComponent(src || '') + '&t=' + (new Date().getTime());
            (document.body || document.documentElement).appendChild(i);
            setTimeout(function () {
                try { if (i.parentNode) i.parentNode.removeChild(i); } catch (e) {}
            }, 1500);
        } catch (e) {}
    }
    window.__kankiAudioPing = ping;

    if (typeof window.Audio === 'undefined') {
        function KankiAudio(src) {
            this.src = src || '';
            this.currentSrc = this.src;
            this.currentTime = 0;
            this.duration = 0;
            this.paused = true;
            this.ended = false;
            this.autoplay = false;
            this.loop = false;
            this.muted = false;
            this.volume = 1;
            this.preload = 'auto';
        }
        KankiAudio.prototype.play = function () {
            this.paused = false;
            this.ended = false;
            ping('play', this.src);
            return new PingPromise();
        };
        KankiAudio.prototype.pause = function () {
            this.paused = true;
            ping('stop', '');
        };
        KankiAudio.prototype.load = function () {};
        KankiAudio.prototype.addEventListener = function () {};
        KankiAudio.prototype.removeEventListener = function () {};
        window.Audio = KankiAudio;
    }

    function replaySvg() {
        return '<svg viewBox="0 0 40 40" xmlns="http://www.w3.org/2000/svg">' +
            '<circle cx="20" cy="20" r="18" stroke-width="2"></circle>' +
            '<path d="M11 16v8h6l8 7V9l-8 7h-6zm17.2-1.9v11.8c2.4-1.1 4-3.3 4-5.9s-1.6-4.8-4-5.9z"></path>' +
            '</svg>';
    }

    function replaceSoundText(node, sounds) {
        if (!node || !node.nodeValue) return;
        var text = node.nodeValue;
        var re = /\[sound:([^\]]+)\]/g;
        var m, last = 0, frag = null;
        while ((m = re.exec(text)) !== null) {
            if (!frag) frag = document.createDocumentFragment();
            if (m.index > last) frag.appendChild(document.createTextNode(text.substring(last, m.index)));
            var src = m[1];
            sounds.push(src);
            var a = document.createElement('a');
            a.href = '#';
            a.className = 'replay-button kanki-replay-button';
            a.setAttribute('data-src', src);
            a.setAttribute('title', 'Replay audio');
            a.innerHTML = replaySvg();
            a.onclick = function () {
                ping('play', this.getAttribute('data-src'));
                return false;
            };
            frag.appendChild(a);
            last = re.lastIndex;
        }
        if (frag) {
            if (last < text.length) frag.appendChild(document.createTextNode(text.substring(last)));
            node.parentNode.replaceChild(frag, node);
        }
    }

    function walk(node, sounds) {
        if (!node) return;
        if (node.nodeType === 3) {
            replaceSoundText(node, sounds);
            return;
        }
        if (node.nodeType !== 1) return;
        var tag = (node.tagName || '').toLowerCase();
        if (tag === 'script' || tag === 'style' || tag === 'textarea') return;
        var c = node.firstChild;
        while (c) {
            var n = c.nextSibling;
            walk(c, sounds);
            c = n;
        }
    }

    function unwrapRankiContainer() {
        if (!document.body) return;
        addClass(document.body, 'card');
        addClass(document.body, 'isLin');
        addClass(document.body, 'kindle');

        /* Ranki adds a .card.kindle wrapper that desktop Anki does not have.
           Move its children into the body so deck selectors see the same DOM
           depth as Anki's #qa reviewer. */
        var children = document.body.childNodes;
        var wrapper = null;
        for (var i = 0; i < children.length; i++) {
            var el = children[i];
            if (el.nodeType === 1 && String(el.tagName).toLowerCase() === 'div') {
                var cls = ' ' + (el.className || '') + ' ';
                if (cls.indexOf(' card ') >= 0 && cls.indexOf(' kindle ') >= 0) {
                    wrapper = el;
                    break;
                }
            }
        }
        if (!wrapper) return;
        while (wrapper.firstChild) document.body.insertBefore(wrapper.firstChild, wrapper);
        wrapper.parentNode.removeChild(wrapper);
    }

    function polyfillFlexGap() {
        /* Old WebKit understands flex layouts better than flex gap. For simple
           top-level flex rules, reproduce horizontal/vertical gap with margins. */
        try {
            var styles = document.getElementsByTagName('style');
            for (var s = 0; s < styles.length; s++) {
                var text = styleText(styles[s]);
                var block = /([^{}]+)\{([^{}]+)\}/g;
                var m;
                while ((m = block.exec(text)) !== null) {
                    if (!/display\s*:\s*(?:-webkit-)?flex\s*;?/i.test(m[2])) continue;
                    var gm = /(?:^|;)\s*gap\s*:\s*([0-9.]+)px/i.exec(m[2]);
                    if (!gm) continue;
                    var gap = parseFloat(gm[1]);
                    if (!(gap > 0)) continue;
                    var column = /flex-direction\s*:\s*column/i.test(m[2]);
                    var selector = trim(m[1]);
                    var nodes;
                    try { nodes = document.querySelectorAll(selector); } catch (e1) { continue; }
                    for (var n = 0; n < nodes.length; n++) {
                        var kids = nodes[n].children;
                        for (var k = 0; k < kids.length - 1; k++) {
                            if (column) kids[k].style.marginBottom = gap + 'px';
                            else kids[k].style.marginRight = gap + 'px';
                        }
                    }
                }
            }
        } catch (e) {}
    }

    function setup() {
        try {
            unwrapRankiContainer();
            /* Catch style tags embedded inside a template body as well. */
            polyfillCssVariables();
            polyfillFlexGap();
            var sounds = [];
            walk(document.body, sounds);
            if (sounds.length) setTimeout(function () { ping('play', sounds[0]); }, 120);
            window.scrollTo(0, 0);
        } catch (e) {}
    }

    if (document.addEventListener) document.addEventListener('DOMContentLoaded', setup, false);
    else if (window.attachEvent) window.attachEvent('onload', setup);
    else window.onload = setup;
})();
