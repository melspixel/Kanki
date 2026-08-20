(function () {
    /*
     * Adaptive reviewer preprocessing for Kindle's legacy WebKit.
     *
     * This layer is intentionally note-type agnostic. It does not know about
     * COCA, vocabulary fields, logos, badges, or any deck-specific selector.
     * It only repairs differences between a modern mobile WebView and the
     * high-DPI, devicePixelRatio=1 WebKit exposed by Kindle firmware.
     */
    var LOGICAL_VIEWPORT_PX = 420;
    var stats = {
        legacyBlocksRemoved: 0,
        mediaQueriesRewritten: 0,
        fontFallbacksAdded: 0,
        nestedCardShell: 0
    };

    function trim(s) {
        return String(s || '').replace(/^\s+|\s+$/g, '');
    }

    function styleText(style) {
        if (typeof style.textContent === 'string') return style.textContent;
        if (style.styleSheet && typeof style.styleSheet.cssText === 'string') return style.styleSheet.cssText;
        return '';
    }

    function setStyleText(style, text) {
        if (style.styleSheet) style.styleSheet.cssText = text;
        else style.textContent = text;
    }

    function addClass(el, name) {
        if (!el) return;
        var current = ' ' + (el.className || '') + ' ';
        if (current.indexOf(' ' + name + ' ') < 0) {
            el.className = trim((el.className || '') + ' ' + name);
        }
    }

    function hasClass(el, name) {
        if (!el) return false;
        return (' ' + (el.className || '') + ' ').indexOf(' ' + name + ' ') >= 0;
    }

    function removeLegacyDeckPatch(text) {
        /*
         * Earlier experimental APKGs appended one of these marked blocks to
         * the note type. They can remain in a synced collection even after the
         * application is upgraded, and their !important rules override the new
         * generic renderer. Remove only our own unmistakably marked suffix.
         */
        var marker = /\/\*\s*=+\s*Kindle\s*\/\s*Kanki\s+e-ink\s+layout(?:\s+v[0-9]+)?\s*=+\s*\*\/[\s\S]*$/i;
        if (marker.test(text)) {
            stats.legacyBlocksRemoved++;
            return text.replace(marker, '');
        }
        return text;
    }

    function rewriteMediaQueries(text) {
        /*
         * Modern phone WebViews expose roughly 360-430 logical CSS pixels even
         * on a 1200px panel. Kindle's old WebKit exposes the physical pixel
         * width instead, so decks select desktop rules. Rewrite width-only
         * breakpoints as though the reviewer viewport were 420 CSS px.
         */
        text = text.replace(/(\(\s*max-(?:device-)?width\s*:\s*)([0-9]+(?:\.[0-9]+)?)(px\s*\))/gi,
            function (all, before, number, after) {
                var n = parseFloat(number);
                if (n >= LOGICAL_VIEWPORT_PX) {
                    stats.mediaQueriesRewritten++;
                    return before + '9999' + after;
                }
                return all;
            });

        text = text.replace(/(\(\s*min-(?:device-)?width\s*:\s*)([0-9]+(?:\.[0-9]+)?)(px\s*\))/gi,
            function (all, before, number, after) {
                var n = parseFloat(number);
                if (n > LOGICAL_VIEWPORT_PX) {
                    stats.mediaQueriesRewritten++;
                    return before + '9999' + after;
                }
                return all;
            });
        return text;
    }

    function addGenericFontFallbacks(text) {
        return text.replace(/font-family\s*:\s*([^;{}]+);/gi, function (all, raw) {
            var value = trim(raw);
            var lower = value.toLowerCase();
            var fallback;

            if (!value || lower.indexOf('var(') >= 0 || lower.indexOf(',') >= 0) return all;
            if (/\b(inherit|initial|unset|serif|sans-serif|monospace|cursive|fantasy|system-ui)\b/i.test(value)) return all;

            if (/(georgia|times|bookerly|baskerville|garamond|palatino|minion|noto serif)/i.test(value)) {
                fallback = 'serif';
            } else if (/(courier|consolas|menlo|monaco|mono)/i.test(value)) {
                fallback = 'monospace';
            } else {
                fallback = 'sans-serif';
            }
            stats.fontFallbacksAdded++;
            return 'font-family: ' + value + ', ' + fallback + ';';
        });
    }

    function preprocessStyles() {
        try {
            var styles = document.getElementsByTagName('style');
            for (var i = 0; i < styles.length; i++) {
                var before = styleText(styles[i]);
                var after = removeLegacyDeckPatch(before);
                after = rewriteMediaQueries(after);
                after = addGenericFontFallbacks(after);
                if (after !== before) setStyleText(styles[i], after);
            }
        } catch (e) {}
    }

    function normalizeNestedCardShell() {
        /*
         * Anki assigns .card to the reviewer body. Some modern templates also
         * use an inner article/div.card. On a narrow e-ink screen that causes
         * the same padding/max-width/card box to be applied twice. Neutralize
         * only the outer body when an actual inner card container exists.
         */
        try {
            if (!document.body || !document.body.querySelector) return;
            var inner = document.body.querySelector('.card');
            if (inner && inner !== document.body) {
                addClass(document.body, 'kanki-has-inner-card');
                stats.nestedCardShell = 1;
            }
        } catch (e) {}
    }

    function logStats() {
        try {
            if (window.console && window.console.log) {
                window.console.log(
                    'kanki-layout-v2: viewport=' + LOGICAL_VIEWPORT_PX +
                    ' legacy_removed=' + stats.legacyBlocksRemoved +
                    ' media_rewritten=' + stats.mediaQueriesRewritten +
                    ' font_fallbacks=' + stats.fontFallbacksAdded +
                    ' nested_card=' + stats.nestedCardShell
                );
            }
        } catch (e) {}
    }

    /* The head already contains the deck CSS when Kanki injects this script. */
    preprocessStyles();
    window.__kankiAdaptiveV2 = stats;

    function onReady() {
        /* Catch style blocks embedded in the card template before the base
           compatibility listener resolves variables and lays out the card. */
        preprocessStyles();

        /* The base Kanki listener runs later in registration order and unwraps
           Ranki's extra container. Defer shell detection until that is done. */
        setTimeout(function () {
            preprocessStyles();
            normalizeNestedCardShell();
            logStats();
        }, 0);
    }

    if (document.addEventListener) document.addEventListener('DOMContentLoaded', onReady, false);
    else if (window.attachEvent) window.attachEvent('onload', onReady);
    else window.onload = onReady;
})();
