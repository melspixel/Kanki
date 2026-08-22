(function () {
    /*
     * Per-render diagnostics for Kindle's legacy WebKit.
     *
     * The native preload shim already saves the exact HTML handed to WebKit
     * before and after Kanki injection. This script records what WebKit actually
     * produced from that HTML: viewport metrics, body/platform classes, and the
     * computed layout of visible elements. Output goes to WebKit's console and
     * therefore to ranki.log.
     *
     * Keep this ES5-only so the diagnostic path itself works on old JSCore.
     */
    var MAX_ELEMENTS = 120;

    function trim(s) {
        return String(s || '').replace(/^\s+|\s+$/g, '');
    }

    function compactText(s, limit) {
        s = trim(String(s || '').replace(/\s+/g, ' '));
        if (s.length > limit) s = s.substring(0, limit) + '…';
        return s;
    }

    function safeNumber(n) {
        if (typeof n !== 'number' || !isFinite(n)) return 0;
        return Math.round(n * 100) / 100;
    }

    function logRecord(kind, payload) {
        try {
            var rid = window.__kankiRenderId || 0;
            console.log('KANKI_RENDER|' + rid + '|' + kind + '|' + JSON.stringify(payload));
        } catch (e) {
            try { console.log('KANKI_RENDER|error|' + String(e)); } catch (ignored) {}
        }
    }

    function sideName() {
        try {
            if (document.getElementById('answer')) return 'answer';
            if (document.querySelector && document.querySelector('[id="answer"]')) return 'answer';
        } catch (e) {}
        return 'question';
    }

    function browserSnapshot(phase) {
        var de = document.documentElement || {};
        var body = document.body || {};
        var screenObj = window.screen || {};
        var adaptive = window.__kankiAdaptiveV2 || {};
        return {
            phase: phase,
            side: sideName(),
            href: String(location.href || ''),
            ua: String(navigator.userAgent || ''),
            htmlClass: String(de.className || ''),
            bodyClass: String(body.className || ''),
            innerWidth: window.innerWidth || 0,
            innerHeight: window.innerHeight || 0,
            clientWidth: de.clientWidth || 0,
            clientHeight: de.clientHeight || 0,
            screenWidth: screenObj.width || 0,
            screenHeight: screenObj.height || 0,
            devicePixelRatio: window.devicePixelRatio || 1,
            scrollWidth: body.scrollWidth || 0,
            scrollHeight: body.scrollHeight || 0,
            styleBlocks: document.getElementsByTagName('style').length,
            legacyRemoved: adaptive.legacyBlocksRemoved || 0,
            mediaRewritten: adaptive.mediaQueriesRewritten || 0,
            fontFallbacks: adaptive.fontFallbacksAdded || 0,
            nestedCardShell: adaptive.nestedCardShell || 0,
            bodyText: compactText(body.innerText || body.textContent || '', 180)
        };
    }

    function styleValue(cs, camel, cssName) {
        try {
            if (typeof cs[camel] !== 'undefined' && cs[camel] !== '') return String(cs[camel]);
            if (cs.getPropertyValue) return String(cs.getPropertyValue(cssName) || '');
        } catch (e) {}
        return '';
    }

    function elementSnapshot(el, index) {
        var cs = null;
        var r = null;
        try { cs = window.getComputedStyle ? window.getComputedStyle(el, null) : el.currentStyle; } catch (e1) {}
        try { r = el.getBoundingClientRect ? el.getBoundingClientRect() : null; } catch (e2) {}
        if (!cs) return null;

        var display = styleValue(cs, 'display', 'display');
        var visibility = styleValue(cs, 'visibility', 'visibility');
        var width = r ? safeNumber(r.width || (r.right - r.left)) : safeNumber(el.offsetWidth || 0);
        var height = r ? safeNumber(r.height || (r.bottom - r.top)) : safeNumber(el.offsetHeight || 0);
        if (display === 'none' || visibility === 'hidden' || (width <= 0 && height <= 0)) return null;

        return {
            i: index,
            tag: String(el.tagName || '').toLowerCase(),
            id: String(el.id || ''),
            cls: String(el.className || ''),
            text: compactText(el.innerText || el.textContent || '', 90),
            inline: compactText(el.getAttribute ? (el.getAttribute('style') || '') : '', 120),
            left: r ? safeNumber(r.left) : 0,
            top: r ? safeNumber(r.top) : 0,
            width: width,
            height: height,
            display: display,
            position: styleValue(cs, 'position', 'position'),
            fontFamily: styleValue(cs, 'fontFamily', 'font-family'),
            fontSize: styleValue(cs, 'fontSize', 'font-size'),
            fontWeight: styleValue(cs, 'fontWeight', 'font-weight'),
            lineHeight: styleValue(cs, 'lineHeight', 'line-height'),
            textAlign: styleValue(cs, 'textAlign', 'text-align'),
            whiteSpace: styleValue(cs, 'whiteSpace', 'white-space'),
            marginTop: styleValue(cs, 'marginTop', 'margin-top'),
            marginRight: styleValue(cs, 'marginRight', 'margin-right'),
            marginBottom: styleValue(cs, 'marginBottom', 'margin-bottom'),
            marginLeft: styleValue(cs, 'marginLeft', 'margin-left'),
            paddingTop: styleValue(cs, 'paddingTop', 'padding-top'),
            paddingRight: styleValue(cs, 'paddingRight', 'padding-right'),
            paddingBottom: styleValue(cs, 'paddingBottom', 'padding-bottom'),
            paddingLeft: styleValue(cs, 'paddingLeft', 'padding-left'),
            overflow: styleValue(cs, 'overflow', 'overflow')
        };
    }

    function dumpElements(phase) {
        var all = document.getElementsByTagName('*');
        var emitted = 0;
        var i;
        for (i = 0; i < all.length && emitted < MAX_ELEMENTS; i++) {
            var tag = String(all[i].tagName || '').toLowerCase();
            if (tag === 'html' || tag === 'head' || tag === 'meta' || tag === 'style' || tag === 'script' || tag === 'link') continue;
            var snap = elementSnapshot(all[i], i);
            if (!snap) continue;
            snap.phase = phase;
            logRecord('element', snap);
            emitted++;
        }
        logRecord('element-summary', { phase: phase, visibleLogged: emitted, domElements: all.length, cap: MAX_ELEMENTS });
    }

    function dump(phase) {
        logRecord('page', browserSnapshot(phase));
        dumpElements(phase);
    }

    function ready() {
        /* Run after adaptive + base compatibility DOMContentLoaded listeners. */
        setTimeout(function () { dump('initial'); }, 25);
        /* Images, fonts and card JS can alter geometry shortly after paint. */
        setTimeout(function () { dump('settled'); }, 350);
    }

    if (document.addEventListener) document.addEventListener('DOMContentLoaded', ready, false);
    else if (window.attachEvent) window.attachEvent('onload', ready);
    else window.onload = ready;
})();
