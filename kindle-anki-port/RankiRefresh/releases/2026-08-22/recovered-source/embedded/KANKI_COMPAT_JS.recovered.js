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
        flexDisplaysRewritten: 0,
        textColoursDarkened: 0,
        fontSizesScaled: 0,
        pageTurns: 0,
        lineHeightsCapped: 0,
        blocksCompacted: 0,
        fontsRaised: 0,
        fontsCapped: 0,
        typeScale: 1,
        anchorLo: 0,
        anchorHi: 0,
        anchorFallback: 0,
        carried: 0,
        dominantPx: 0,
        basePx: 0,
        pagerShown: 0,
        scrollBlocked: 0,
        fontFallbacksAdded: 0,
        nestedCardShell: 0
    };

    /*
     * Settings are read from the device's own storage first and fall back to
     * whatever the launcher injected. That is what lets the panel below change
     * them on the Kindle instead of through a file on a desktop: the launcher
     * value becomes the default rather than the law.
     *
     * The two settings that live in C - page zoom and the rating row's height
     * - are deliberately absent. They are applied before any script runs, so
     * offering them here would promise something a panel cannot deliver.
     */
    var SETTINGS = [
        {key: 'FloorPx',       label: '最小字号', min: 0, max: 48,  step: 1},
        {key: 'CeilingPx',     label: '最大字号', min: 0, max: 140, step: 2},
        {key: 'MinCjkPx',      label: '中文下限', min: 0, max: 48,  step: 1},
        {key: 'LinePercent',   label: '行高上限', min: 0, max: 250, step: 5},
        {key: 'BlockMaxPx',    label: '段落间距', min: 0, max: 60,  step: 2},
        {key: 'PageOverlapPx', label: '翻页重叠', min: 0, max: 200, step: 10}
    ];

    var storageOk = -1;
    var overrides = null;

    function storage() {
        try { return window.localStorage || null; } catch (e) { return null; }
    }

    /*
     * Three places a value can come from, in order: what the panel has changed
     * this session, what the device kept from an earlier one, and what the
     * launcher injected.
     *
     * The session copy is what makes the panel usable at all. Re-reading the
     * store on every press meant that when the store did not accept writes -
     * as it does not here - each press recomputed the same number from the
     * same unchanged default, and the value could never move more than one
     * step from where it began.
     *
     * window.name survives a document being replaced in the same view, which
     * is how a card gives way to the next one, so it carries the session
     * across cards even where storage is refused. It does not survive a
     * restart; ranki.sh is where a value goes to become permanent.
     */
    function loadOverrides() {
        var st, raw, parts, i, kv;
        if (overrides) return overrides;
        overrides = {};
        st = storage();
        if (st) {
            for (i = 0; i < SETTINGS.length; i++) {
                try {
                    raw = st.getItem('kanki.' + SETTINGS[i].key);
                    if (raw !== null && raw !== '' && !isNaN(Number(raw))) {
                        overrides[SETTINGS[i].key] = Number(raw);
                    }
                } catch (e) {}
            }
        }
        try {
            raw = String(window.name || '');
            if (raw.indexOf('kanki:') === 0) {
                stats.carried = 1;
                parts = raw.substring(6).split(',');
                for (i = 0; i < parts.length; i++) {
                    kv = parts[i].split('=');
                    if (kv.length === 2 && !isNaN(Number(kv[1]))) {
                        overrides[kv[0]] = Number(kv[1]);
                    }
                }
            }
        } catch (e2) {}
        return overrides;
    }

    function persistOverrides() {
        var st = storage(), i, key, out = [], ok = 0;
        loadOverrides();
        for (i = 0; i < SETTINGS.length; i++) {
            key = SETTINGS[i].key;
            if (typeof overrides[key] === 'number') out.push(key + '=' + overrides[key]);
        }
        try { window.name = 'kanki:' + out.join(','); } catch (e) {}
        if (st) {
            for (i = 0; i < SETTINGS.length; i++) {
                key = SETTINGS[i].key;
                try {
                    if (typeof overrides[key] === 'number') {
                        st.setItem('kanki.' + key, String(overrides[key]));
                        if (st.getItem('kanki.' + key) === String(overrides[key])) ok = 1;
                    }
                } catch (e3) {}
            }
        }
        storageOk = ok;
        return ok === 1;
    }

    function setting(key) {
        var o = loadOverrides();
        if (typeof o[key] === 'number') return o[key];
        return Number(window['__kanki' + key]);
    }

    function setSetting(key, value) {
        loadOverrides();
        overrides[key] = value;
        persistOverrides();
    }

    function clearSettings() {
        var st = storage(), i;
        overrides = {};
        try { window.name = ''; } catch (e) {}
        if (!st) return;
        for (i = 0; i < SETTINGS.length; i++) {
            try { st.removeItem('kanki.' + SETTINGS[i].key); } catch (e2) {}
        }
    }

    var tapsBound = 0;
    var pagerEl = null;
    var pagerLabel = null;
    var pagerPos = 0;

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
                if (n >= LOGICAL_VIEWPORT_PX && n < 9000) {
                    stats.mediaQueriesRewritten++;
                    return before + '9999' + after;
                }
                return all;
            });

        text = text.replace(/(\(\s*min-(?:device-)?width\s*:\s*)([0-9]+(?:\.[0-9]+)?)(px\s*\))/gi,
            function (all, before, number, after) {
                var n = parseFloat(number);
                if (n > LOGICAL_VIEWPORT_PX && n < 9000) {
                    stats.mediaQueriesRewritten++;
                    return before + '9999' + after;
                }
                return all;
            });
        return text;
    }

    function rewriteUnsupportedDisplay(text) {
        /*
         * This WebKit predates modern flexbox, so it drops `display: flex` and
         * `display: inline-flex` outright. The element then has no box of its
         * own, and a percentage width or height on a child resolves against a
         * distant ancestor instead of the intended control - which is how a
         * 24px icon ends up several hundred pixels wide. Map both to the
         * nearest box type the engine does understand.
         */
        text = text.replace(/display\s*:\s*(?:-webkit-)?inline-flex/gi, function () {
            stats.flexDisplaysRewritten++;
            return 'display: inline-block';
        });
        text = text.replace(/display\s*:\s*(?:-webkit-)?flex(?![\w-])/gi, function () {
            stats.flexDisplaysRewritten++;
            return 'display: block';
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

    var measuredScale = null;

    function collectFontWeights(node, counts) {
        var i, kids, size, text;
        if (!node) return;
        if (node.nodeType === 3) {
            text = String(node.nodeValue || '').replace(/\s+/g, '');
            if (!text.length || !node.parentNode || node.parentNode.nodeType !== 1) return;
            size = Math.round(parseFloat(computed(node.parentNode, 'font-size')));
            if (!(size > 0)) return;
            counts[size] = (counts[size] || 0) + text.length;
            return;
        }
        if (node.nodeType !== 1) return;
        var tag = String(node.tagName || '').toLowerCase();
        if (tag === 'script' || tag === 'style') return;
        if (String(node.id || '').indexOf('kanki-') === 0) return;
        kids = node.childNodes;
        for (i = 0; i < kids.length; i++) collectFontWeights(kids[i], counts);
    }

    function dominantFontSize() {
        /*
         * Anchor on the size the card is mostly written in, not on the base
         * the body happens to carry. A deck that declares a comfortable base
         * and then sets its actual prose smaller, or one that leaves the base
         * alone and sizes everything inline, would otherwise be left where it
         * started while its neighbours were pulled into line - which is how
         * two decks ended up with matching bases and visibly different text.
         *
         * Weighted by how much text each size carries, so a headword or a
         * caption cannot outvote the body of the card.
         */
        var counts = {}, key, best = 0, bestWeight = -1;
        if (!document.body) return 0;
        collectFontWeights(document.body, counts);
        for (key in counts) {
            if (!Object.prototype.hasOwnProperty.call(counts, key)) continue;
            if (counts[key] > bestWeight) { bestWeight = counts[key]; best = Number(key); }
        }
        return best;
    }

    function sizeWeights() {
        var counts = {};
        if (!document.body) return counts;
        collectFontWeights(document.body, counts);
        return counts;
    }

    function textScale() {
        /*
         * One rule for every deck: lift what is too small to read, hold back
         * what would take the page, and move everything by the same factor so
         * the author's proportions survive intact.
         *
         * The anchors are weighted by how much text each size carries. A
         * footnote marker at 11px is the smallest thing on the card and would
         * otherwise set the factor for all of it - one card here would have
         * been scaled 2.18x and pushed its headword to 98px on the strength of
         * five characters.
         *
         * When lifting the smallest would push the largest past the ceiling,
         * the two demands cannot both be met, and the factor lands between
         * them rather than satisfying one and ignoring the other.
         */
        if (measuredScale !== null) return measuredScale;

        var floorPx = setting('FloorPx');
        var ceilPx = setting('CeilingPx');
        if (!(floorPx > 0) && !(ceilPx > 0)) { measuredScale = 1; return 1; }

        var counts = sizeWeights(), key, total = 0, lo = 0, hi = 0;
        for (key in counts) {
            if (Object.prototype.hasOwnProperty.call(counts, key)) total += counts[key];
        }
        if (!total) { measuredScale = 1; return 1; }
        for (key in counts) {
            if (!Object.prototype.hasOwnProperty.call(counts, key)) continue;
            var size = Number(key), weight = counts[key];
            if (weight >= Math.max(8, total * 0.05) && (!lo || size < lo)) lo = size;
            if (weight >= Math.max(3, total * 0.01) && size > hi) hi = size;
        }
        if (!lo || !hi) { measuredScale = 1; return 1; }

        /*
         * The floor decides the factor on its own. Splitting the difference
         * with the ceiling sounded even-handed and is not: a card whose
         * headword is declared at 70px pulled its factor back to 1.01, which
         * left its body text at 19px - unreadable, to spare a headword whose
         * exact size nobody minds. Readability is the requirement; the
         * ceiling is a courtesy.
         *
         * Anything the lift then carries past the ceiling is brought back
         * individually, which touches only the few sizes above it and leaves
         * every proportion below intact.
         */
        var factor = 1;
        if (floorPx > 0 && lo < floorPx) factor = floorPx / lo;
        if (factor === 1 && ceilPx > 0 && hi > ceilPx) factor = ceilPx / hi;
        if (factor < 0.5) factor = 0.5;
        if (factor > 2.5) factor = 2.5;

        stats.anchorLo = lo;
        stats.anchorHi = hi;
        measuredScale = factor;
        stats.typeScale = Math.round(factor * 100) / 100;
        return factor;
    }

    function scaleTypeInCss(text) {
        /*
         * Scale type without scaling the page. Full-content zoom magnifies
         * boxes, images and spacing along with the letters, so on a small
         * screen it buys legibility by showing less. Multiplying only the
         * declared font sizes gives large text inside the layout the deck
         * already wrote.
         *
         * Absolute lengths only: percentages and em are relative to the root,
         * which is scaled by the same factor, so they follow on their own and
         * scaling them here as well would apply the factor twice.
         */
        var factor = textScale();
        if (factor === 1) return text;
        return text.replace(/(font-size\s*:\s*)([0-9.]+)px/gi, function (all, lead, n) {
            stats.fontSizesScaled++;
            return lead + (Math.round(parseFloat(n) * factor * 10) / 10) + 'px';
        });
    }

    function scaleRootFont() {
        var factor = textScale();
        if (factor === 1 || !document.documentElement) return;
        try {
            document.documentElement.style.fontSize =
                (Math.round(16 * factor * 10) / 10) + 'px';
        } catch (e) {}
    }



    function capImageHeight() {
        /*
         * The reviewer shell asks for a viewport-relative image cap, but this
         * engine predates vh units and drops the declaration, leaving tall
         * images free to push everything else off the page. Restore the intent
         * with a pixel value measured at load.
         */
        try {
            var view = window.innerHeight || 0;
            var head = document.getElementsByTagName('head')[0];
            if (!view || !head || document.getElementById('kanki-image-cap')) return;
            var st = document.createElement('style');
            st.id = 'kanki-image-cap';
            var css = 'img{max-height:' + Math.round(view * 0.8) + 'px;}';
            if (st.styleSheet) st.styleSheet.cssText = css;
            else st.appendChild(document.createTextNode(css));
            head.appendChild(st);
        } catch (e) {}
    }

    function preprocessStyles(allowTypeScale) {
        try {
            var styles = document.getElementsByTagName('style');
            for (var i = 0; i < styles.length; i++) {
                var style = styles[i];
                /* Our own shell already carries final values. */
                if (style.id === 'kanki-reviewer-compat') continue;
                var before = styleText(style);
                var after = removeLegacyDeckPatch(before);
                after = rewriteMediaQueries(after);
                after = rewriteUnsupportedDisplay(after);
                after = compactLineHeight(after);
                /*
                 * This pass runs again whenever the DOM settles, so that style
                 * blocks appearing inside the card body are covered too. Every
                 * other rewrite here is idempotent and can simply repeat, but
                 * multiplying font sizes is not: re-running it would apply the
                 * factor a second and third time. Scale each block once and
                 * remember that it has been done.
                 *
                 * It is also held back until the settled pass. Decks that size
                 * type through a custom property still read `var(--x)` at parse
                 * time - there is no number to multiply yet - and the value only
                 * appears once the compatibility layer has resolved it.
                 */
                if (allowTypeScale && !style.__kankiTypeScaled) {
                    after = scaleTypeInCss(after);
                    style.__kankiTypeScaled = 1;
                }
                after = addGenericFontFallbacks(after);
                if (after !== before) setStyleText(style, after);
            }
        } catch (e) {}
    }

    function colourLuminance(value) {
        var v = trim(value).toLowerCase();
        var m, r, g, b;
        if (!v || v === 'transparent' || v === 'inherit' || v === 'initial') return null;
        m = /^rgba?\(\s*([0-9]+)\s*,\s*([0-9]+)\s*,\s*([0-9]+)\s*(?:,\s*([0-9.]+)\s*)?\)$/.exec(v);
        if (m) {
            if (m[4] !== undefined && parseFloat(m[4]) === 0) return null;
            r = parseInt(m[1], 10); g = parseInt(m[2], 10); b = parseInt(m[3], 10);
        } else if (/^#[0-9a-f]{3}$/.test(v)) {
            r = parseInt(v.charAt(1) + v.charAt(1), 16);
            g = parseInt(v.charAt(2) + v.charAt(2), 16);
            b = parseInt(v.charAt(3) + v.charAt(3), 16);
        } else if (/^#[0-9a-f]{6}$/.test(v)) {
            r = parseInt(v.substr(1, 2), 16);
            g = parseInt(v.substr(3, 2), 16);
            b = parseInt(v.substr(5, 2), 16);
        } else {
            return null;
        }
        return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
    }

    function computed(el, prop) {
        try {
            if (window.getComputedStyle) {
                return window.getComputedStyle(el, null).getPropertyValue(prop) || '';
            }
            if (el.currentStyle) return el.currentStyle[prop] || '';
        } catch (e) {}
        return '';
    }

    function forceStyle(el, prop, value) {
        /*
         * Decks reach for !important, and a plain inline value loses to it. One
         * note type here declares nine sizes that way, and every adjustment
         * this pass made to that card was discarded while every other deck
         * took them - the reason one deck stayed small while the rest came
         * right. An inline declaration marked important outranks anything a
         * stylesheet can say.
         */
        var camel = prop.replace(/-([a-z])/g, function (a, c) { return c.toUpperCase(); });
        try {
            if (el.style.setProperty) {
                el.style.setProperty(prop, value, 'important');
                if (el.style.getPropertyValue && el.style.getPropertyValue(prop)) return;
            }
        } catch (e) {}
        try { el.style[camel] = value; } catch (e2) {}
    }

    function styleOf(el) {
        try {
            if (window.getComputedStyle) return window.getComputedStyle(el, null);
            return el.currentStyle || null;
        } catch (e) {}
        return null;
    }

    function readStyle(cs, prop) {
        if (!cs) return '';
        try {
            if (cs.getPropertyValue) return cs.getPropertyValue(prop) || '';
            return cs[prop.replace(/-([a-z])/g, function (a, c) { return c.toUpperCase(); })] || '';
        } catch (e) {}
        return '';
    }

    /*
     * One walk, one computed style per element.
     *
     * These adjustments used to be four separate passes, each resolving styles
     * again and one of them climbing the ancestors of every element to find
     * its effective background. That is quadratic work on a card of any size,
     * and it is paid while the reader is looking at a blank page waiting for
     * the measurement to finish. Descending the tree once carries the
     * inherited background down with it, so nothing is resolved twice.
     */
    var CJK = /[　-〿㐀-䶿一-鿿豈-﫿＀-￯]/;

    function hasCjkText(el) {
        var kids = el.childNodes, i;
        for (i = 0; i < kids.length; i++) {
            if (kids[i].nodeType === 3 && CJK.test(String(kids[i].nodeValue || ''))) return 1;
        }
        return 0;
    }

    function finishCard(el, inheritedBgLum, factor, blockCap, minCjk, ceiling, floorLimit) {
        var cs, i, kids, bgLum, v, lum, k, scaled = 0;
        var boxProps = [['margin-top', 'marginTop'], ['margin-bottom', 'marginBottom'],
                        ['padding-top', 'paddingTop'], ['padding-bottom', 'paddingBottom']];
        if (!el || el.nodeType !== 1) return;
        var tag = String(el.tagName || '').toLowerCase();
        /* Our own controls are not the deck's type and must not be measured
           or resized as if they were. Matching the prefix covers the whole
           family whatever order they happen to be built in. */
        if (tag === 'script' || tag === 'style') return;
        if (String(el.id || '').indexOf('kanki-') === 0) return;

        cs = styleOf(el);
        bgLum = colourLuminance(readStyle(cs, 'background-color'));
        if (bgLum === null) bgLum = inheritedBgLum;

        /* Type declared on the element itself, which no stylesheet rewrite can
           reach, plus a floor so a deck's small print stays readable here. */
        if (el.style) {
            if (factor !== 1 && el.style.fontSize && !el.__kankiTypeScaled) {
                var mm = /^([0-9.]+)px$/.exec(trim(el.style.fontSize));
                if (mm) {
                    scaled = Math.round(parseFloat(mm[1]) * factor * 10) / 10;
                    forceStyle(el, 'font-size', scaled + 'px');
                    el.__kankiTypeScaled = 1;
                    stats.fontSizesScaled++;
                }
            }
            /* A floor and a ceiling around what actually renders. Anchoring
               on the stylesheet keeps a deck's own proportions, which is what
               holds the type still between the two sides of a card - but it
               also preserves a headword set four times the size of the prose,
               and that is what makes one deck look larger than another. The
               clamp closes that without reintroducing any per-card
               measurement. */
            /* Han characters carry far more detail per em than Latin, so a
               size that reads cleanly in English is cramped in Chinese. A deck
               that sets its gloss smaller than its headword leaves that gloss
               below what this panel resolves, whatever the base is tuned to,
               which is why the two scripts need different floors. */
            /* Only Han text still needs an absolute floor. The scale above
               already guarantees the smallest Latin text reaches the floor,
               but Han carries more detail per em and a deck that writes its
               gloss smaller than its headword leaves it short even so. */
            /*
             * The factor carries the bulk of the card into range; these
             * truncate whatever it could not reach. The anchor deliberately
             * ignores sizes carrying almost no text, so a five-character
             * marker at 11px is not represented in the factor and would
             * still arrive unreadable - and a headword can be lifted past
             * the ceiling by a factor chosen for the body.
             *
             * Truncating costs the gradations outside the limits: that
             * marker ends the same size as the body it sits beside. Inside
             * them nothing is touched beyond the shared factor, so the
             * proportions the deck was written with survive where they can
             * be seen.
             */
            var lowLimit = floorLimit;
            if (minCjk > 0 && hasCjkText(el) && minCjk > lowLimit) lowLimit = minCjk;
            /* The size this element will actually render at. Reading the
               computed style again would report what it was before the line
               above changed it, unless the engine resolves styles on every
               access - and truncating on a stale number pulls an element that
               is already in range back to the limit. */
            v = scaled > 0 ? scaled : parseFloat(readStyle(cs, 'font-size'));
            if (v > 0) {
                if (lowLimit > 0 && v < lowLimit) {
                    forceStyle(el, 'font-size', lowLimit + 'px');
                    scaled = lowLimit;
                    stats.fontsRaised++;
                } else if (ceiling > 0 && v > ceiling) {
                    forceStyle(el, 'font-size', ceiling + 'px');
                    scaled = ceiling;
                    stats.fontsCapped++;
                }
            }
        }

        /* Pale text on a light background: greyscale turns a mid-tone into
           near-nothing. Text over a dark background is the deck's own pairing
           and is left as written. */
        lum = colourLuminance(readStyle(cs, 'color'));
        if (lum !== null && lum > 0.45 && lum < 0.95 && bgLum > 0.6 && el.style) {
            try { el.style.color = '#000'; stats.textColoursDarkened++; } catch (e) {}
        }

        /* Section gaps and separators sized for a roomier screen. */
        if (blockCap > 0 && el.style) {
            for (k = 0; k < boxProps.length; k++) {
                v = parseFloat(readStyle(cs, boxProps[k][0]));
                if (v > blockCap) {
                    try {
                        el.style[boxProps[k][1]] = blockCap + 'px';
                        stats.blocksCompacted++;
                    } catch (e) {}
                }
            }
        }

        kids = el.childNodes;
        for (i = 0; i < kids.length; i++) {
            finishCard(kids[i], bgLum, factor, blockCap, minCjk, ceiling, floorLimit);
        }
    }

    function finishCardPass() {
        if (!document.body) return;
        var blockCap = setting('BlockMaxPx');
        if (!(blockCap >= 0 && blockCap <= 60)) blockCap = 0;
        var minCjk = setting('MinCjkPx');
        if (!(minCjk >= 0 && minCjk <= 48)) minCjk = 0;
        var ceiling = setting('CeilingPx');
        if (!(ceiling >= 0 && ceiling <= 200)) ceiling = 0;
        var floorLimit = setting('FloorPx');
        if (!(floorLimit >= 0 && floorLimit <= 60)) floorLimit = 0;
        finishCard(document.body, 1, textScale(), blockCap, minCjk, ceiling, floorLimit);
    }

    function pageHeight() {
        var d = document.documentElement || {};
        var b = document.body || {};
        return Math.max(d.scrollHeight || 0, b.scrollHeight || 0);
    }

    function currentScroll() {
        if (typeof window.pageYOffset === 'number' && window.pageYOffset) return window.pageYOffset;
        var d = document.documentElement;
        if (d && d.scrollTop) return d.scrollTop;
        return (document.body && document.body.scrollTop) || 0;
    }

    function maxScroll() {
        return Math.max(0, pageHeight() - (window.innerHeight || 0));
    }

    function scrollToY(target) {
        /*
         * Which object owns the scroll offset varies for a WebView inside a
         * host container, and reading it back is not dependable either. Ask
         * all three to move, then keep our own record of where we asked to be
         * rather than trusting the read: an offset that always reports zero
         * would otherwise freeze the page indicator, and when the same reading
         * was used for placement it stranded the control mid-card.
         */
        if (target < 0) target = 0;
        var max = maxScroll();
        if (target > max) target = max;
        try { window.scrollTo(0, target); } catch (e) {}
        try { if (document.documentElement) document.documentElement.scrollTop = target; } catch (e2) {}
        try { if (document.body) document.body.scrollTop = target; } catch (e3) {}
        pagerPos = target;
        return target;
    }

    function pageStep() {
        /*
         * A screenful less an overlap, so the lines at the seam are carried
         * onto the next page rather than jumped over. The count below derives
         * from this same step, so the two agree however it is tuned.
         */
        var view = window.innerHeight || 1;
        var overlap = setting('PageOverlapPx');
        if (!(overlap >= 0 && overlap < view)) overlap = 80;
        return Math.max(1, view - overlap);
    }

    function pageBy(direction) {
        scrollToY(pagerPos + direction * pageStep());
        updatePager();
        stats.pageTurns++;
    }

    function syncPagerPos() {
        /* Dragging moves the page without going through us. Trust a reading
           only when it is plainly live; a stuck zero must not reset us. */
        var seen = currentScroll();
        if (seen > 0) pagerPos = Math.min(seen, maxScroll());
        updatePager();
    }

    function updatePager() {
        if (!pagerEl) return;
        var step = pageStep();
        var max = maxScroll();
        var total = max <= 0 ? 1 : Math.ceil(max / step) + 1;
        var here = pagerPos >= max - 1
            ? total
            : Math.min(total, Math.floor(pagerPos / step) + 1);
        var text = here + ' / ' + total;
        try {
            if (pagerLabel.firstChild) pagerLabel.firstChild.nodeValue = text;
            else pagerLabel.appendChild(document.createTextNode(text));
        } catch (e) {}
    }

    function pagerButton(glyph, direction) {
        var b = document.createElement('div');
        b.setAttribute('style',
            'display:block;width:30px;height:30px;line-height:30px;' +
            'text-align:center;font-size:16px;font-family:sans-serif;' +
            'color:#000;background:#fff;');
        b.appendChild(document.createTextNode(glyph));
        b.onclick = function () { pageBy(direction); return false; };
        return b;
    }

    function bottomGap() {
        var v = Number(window.__kankiPagerBottomPx);
        return (v >= 0 && v <= 200) ? v : 2;
    }

    function boxStyle(extra) {
        return 'display:inline-block;text-align:center;font-family:sans-serif;' +
               'color:#000;background:#fff;border:1px solid #000;' + (extra || '');
    }

    function settingRow(spec) {
        var row = document.createElement('div');
        var value = document.createElement('span');
        var minus, plus;

        row.setAttribute('style',
            'margin:0 0 10px 0;padding:0;white-space:nowrap;font-size:15px;');

        var name = document.createElement('span');
        name.setAttribute('style', 'display:inline-block;width:88px;font-size:15px;');
        name.appendChild(document.createTextNode(spec.label));

        value.setAttribute('style',
            'display:inline-block;width:52px;text-align:center;font-size:15px;');
        value.appendChild(document.createTextNode(String(setting(spec.key))));

        function bump(delta) {
            var v = setting(spec.key) + delta;
            if (v < spec.min) v = spec.min;
            if (v > spec.max) v = spec.max;
            setSetting(spec.key, v);
            value.firstChild.nodeValue = String(v);
        }

        minus = document.createElement('span');
        minus.setAttribute('style', boxStyle('width:44px;height:38px;line-height:38px;font-size:20px;'));
        minus.appendChild(document.createTextNode('−'));
        minus.onclick = function () { bump(-spec.step); return false; };

        plus = document.createElement('span');
        plus.setAttribute('style', boxStyle('width:44px;height:38px;line-height:38px;font-size:20px;'));
        plus.appendChild(document.createTextNode('+'));
        plus.onclick = function () { bump(spec.step); return false; };

        row.appendChild(name);
        row.appendChild(minus);
        row.appendChild(value);
        row.appendChild(plus);
        return row;
    }

    function openSettings() {
        var panel, i, note, actions, reset, close;
        if (document.getElementById('kanki-settings')) return;

        panel = document.createElement('div');
        panel.id = 'kanki-settings';
        panel.setAttribute('style',
            'position:fixed;left:0;top:0;right:0;bottom:0;background:#fff;' +
            'z-index:2147483600;padding:14px;overflow:auto;' +
            'font-family:sans-serif;color:#000;font-size:15px;');

        var title = document.createElement('div');
        title.setAttribute('style', 'font-size:18px;font-weight:bold;margin:0 0 12px 0;');
        title.appendChild(document.createTextNode('排版设置'));
        panel.appendChild(title);

        for (i = 0; i < SETTINGS.length; i++) panel.appendChild(settingRow(SETTINGS[i]));

        note = document.createElement('div');
        note.setAttribute('style', 'margin:4px 0 12px 0;font-size:13px;line-height:1.5;');
        note.appendChild(document.createTextNode(
            '下一张卡生效。0 表示不干预，保持牌组原样。' +
            '整体缩放和评分键高度在 ranki.sh 里，需重启。'));
        panel.appendChild(note);

        actions = document.createElement('div');
        reset = document.createElement('span');
        reset.setAttribute('style', boxStyle('padding:0 14px;height:40px;line-height:40px;margin-right:10px;'));
        reset.appendChild(document.createTextNode('恢复默认'));
        reset.onclick = function () {
            clearSettings();
            var el = document.getElementById('kanki-settings');
            if (el && el.parentNode) el.parentNode.removeChild(el);
            openSettings();
            return false;
        };
        close = document.createElement('span');
        close.setAttribute('style', boxStyle('padding:0 14px;height:40px;line-height:40px;'));
        close.appendChild(document.createTextNode('关闭'));
        close.onclick = function () {
            var el = document.getElementById('kanki-settings');
            if (el && el.parentNode) el.parentNode.removeChild(el);
            return false;
        };
        actions.appendChild(reset);
        actions.appendChild(close);
        panel.appendChild(actions);

        var state = document.createElement('div');
        state.setAttribute('style', 'margin-top:12px;font-size:12px;');
        state.appendChild(document.createTextNode(
            storageOk === 0
                ? '这台设备不保存网页数据，改动在本次运行内有效，重启后回到默认。'
                : ''));
        panel.appendChild(state);

        document.body.appendChild(panel);
    }

    function installSettingsButton() {
        if (!document.body || document.getElementById('kanki-settings-open')) return;
        var b = document.createElement('div');
        b.id = 'kanki-settings-open';
        b.setAttribute('style',
            'position:fixed;left:2px;z-index:2147483000;width:30px;height:30px;' +
            'line-height:30px;text-align:center;font-size:15px;font-family:sans-serif;' +
            'color:#000;background:#fff;border:1px solid #000;border-radius:5px;' +
            'bottom:' + bottomGap() + 'px;-webkit-user-select:none;');
        b.appendChild(document.createTextNode('⚙'));
        b.onclick = function () { openSettings(); return false; };
        document.body.appendChild(b);
    }

    function installPager() {
        /*
         * Dragging a long card is slow and imprecise on a panel that cannot
         * follow a finger, so give it the control a reader expects: an explicit
         * pair of page buttons with the position between them. It appears only
         * when the card actually overflows, so short cards are untouched.
         *
         * Positioned absolutely and moved on each scroll rather than fixed:
         * fixed elements are unreliable while scrolling in engines of this
         * vintage, and the page offset is already being tracked here.
         */
        if (pagerEl || !document.body) return;
        var view = window.innerHeight || 0;
        if (!view || pageHeight() <= view + 8) return;

        pagerEl = document.createElement('div');
        pagerEl.id = 'kanki-pager';
        pagerEl.setAttribute('style',
            /* Stacked rather than in a row: a column is narrow enough that
               the gutter reserved for it costs a fraction of the text width,
               where a horizontal bar would have taken a fifth of the page. */
            'position:fixed;right:2px;z-index:2147483000;background:#fff;' +
            'border:1px solid #000;border-radius:5px;padding:1px 0;' +
            'white-space:nowrap;-webkit-user-select:none;width:32px;' +
            'bottom:' + bottomGap() + 'px;');

        pagerLabel = document.createElement('span');
        pagerLabel.setAttribute('style',
            'display:block;text-align:center;font-size:11px;line-height:14px;' +
            'font-family:sans-serif;color:#000;');

        pagerEl.appendChild(pagerButton('▲', -1));
        pagerEl.appendChild(pagerLabel);
        pagerEl.appendChild(pagerButton('▼', 1));
        document.body.appendChild(pagerEl);

        /*
         * Reserve a gutter the width of the control. A fixed element takes no
         * space in the layout, so without this the text simply runs underneath
         * it as the card scrolls - which is what made the control look like it
         * was sitting in the middle of the content.
         */
        try { document.body.style.paddingRight = '38px'; } catch (e) {}

        pagerPos = currentScroll();
        updatePager();
        if (window.addEventListener) {
            window.addEventListener('scroll', syncPagerPos, false);
        }
        stats.pagerShown = 1;
    }

    function enablePageTaps() {
        /*
         * The buttons are the discoverable control; tapping the top or bottom
         * of the page is the shortcut, matching how the device turns pages
         * everywhere else. Cards that already fit, anything the deck made
         * interactive, and the middle band are all left alone, so a stray tap
         * never moves the page and a replay button still plays.
         */
        if (!document.body || !document.addEventListener || tapsBound) return;
        tapsBound = 1;
        document.addEventListener('click', function (ev) {
            try {
                var view = window.innerHeight || 0;
                if (!view || pageHeight() <= view + 8) return;

                var node = ev.target;
                while (node && node.nodeType === 1) {
                    var tag = String(node.tagName || '').toLowerCase();
                    if (tag === 'a' || tag === 'button' || tag === 'input' ||
                        tag === 'select' || tag === 'textarea' || node.onclick) return;
                    node = node.parentNode;
                }

                var y = ev.clientY;
                if (typeof y !== 'number') return;
                if (y > view * 0.72) pageBy(1);
                else if (y < view * 0.28) pageBy(-1);
                else return;
                if (ev.preventDefault) ev.preventDefault();
            } catch (e) {}
        }, false);
    }

    function normalizeNestedCardShell() {
        /*
         * Anki assigns .card to the reviewer body. Some modern templates also
         * use an inner article/div.card. On a narrow e-ink screen that causes
         * the same padding/max-width/card box to be applied twice. Neutralize
         * only the outer body when an actual inner card container exists.
         *
         * Before Ranki's extra wrapper is removed, a genuine nested card means
         * at least two descendants with .card. Afterwards the body itself owns
         * .card, so one descendant is sufficient.
         */
        try {
            if (!document.body || !document.body.querySelectorAll) return;
            var cards = document.body.querySelectorAll('.card');
            var hasInner = hasClass(document.body, 'card') ? cards.length > 0 : cards.length > 1;
            if (hasInner) {
                addClass(document.body, 'kanki-has-inner-card');
                stats.nestedCardShell = 1;
            }
        } catch (e) {}
    }

    function logStats() {
        try {
            if (window.console && window.console.log) {
                window.console.log(
                    'kanki-layout-v2: view=' + (window.innerWidth || 0) + 'x' +
                    (window.innerHeight || 0) +
                    ' viewport=' + LOGICAL_VIEWPORT_PX +
                    ' legacy_removed=' + stats.legacyBlocksRemoved +
                    ' media_rewritten=' + stats.mediaQueriesRewritten +
                    ' flex_rewritten=' + stats.flexDisplaysRewritten +
                    ' text_darkened=' + stats.textColoursDarkened +
                    ' font_scaled=' + stats.fontSizesScaled +
                    ' type_scale=' + stats.typeScale +
                    ' anchor_lo=' + stats.anchorLo +
                    ' anchor_hi=' + stats.anchorHi +
                    ' anchor_fb=' + stats.anchorFallback +
                    ' dominant_px=' + stats.dominantPx +
                    ' blocks_compacted=' + stats.blocksCompacted +
                    ' fonts_raised=' + stats.fontsRaised +
                    ' fonts_capped=' + stats.fontsCapped +
                    ' line_capped=' + stats.lineHeightsCapped +
                    ' pager=' + stats.pagerShown +
                    ' storage=' + storageOk +
                    ' carried=' + stats.carried +
                    ' scroll_blocked=' + stats.scrollBlocked +
                    ' font_fallbacks=' + stats.fontFallbacksAdded +
                    ' nested_card=' + stats.nestedCardShell
                );
            }
        } catch (e) {}
    }

    /* The head already contains the deck CSS when Kanki injects this script. */
    /*
     * Type can only be normalised once the deck's own size has been measured,
     * and that has to wait for custom properties to resolve. Painting before
     * then and rescaling after shows the card twice at two different sizes,
     * which on a panel that repaints in full is worse than a short pause.
     * Hold the body back until the measurement is in, with a timer that
     * reveals it regardless should anything go wrong on the way.
     */
    function revealCard() {
        try {
            var el = document.documentElement;
            if (!el) return;
            el.className = trim(String(el.className || '').replace(/\bkanki-measuring\b/g, ''));
        } catch (e) {}
    }

    try {
        document.documentElement.className += ' kanki-measuring';
        setTimeout(revealCard, 700);
    } catch (e) {}

    preprocessStyles(false);
    window.__kankiAdaptiveV2 = stats;

    function onReady() {
        /* Catch style blocks embedded in the card template before the base
           compatibility listener resolves variables and lays out the card. */
        preprocessStyles(false);
        normalizeNestedCardShell();

        /* The base Kanki listener runs later in registration order and unwraps
           Ranki's extra container. Re-check once the final reviewer DOM exists. */
        /* Not zero: on this engine the first turn of the loop can arrive
           before styles are resolved, and every measurement here depends on
           them being readable. */
        setTimeout(function () {
            scaleRootFont();
            preprocessStyles(true);
            normalizeNestedCardShell();
            finishCardPass();
            capImageHeight();
            installPager();
            installSettingsButton();
            enablePageTaps();
            revealCard();
            logStats();
        }, 60);
    }

    if (document.addEventListener) document.addEventListener('DOMContentLoaded', onReady, false);
    else if (window.attachEvent) window.attachEvent('onload', onReady);
    else window.onload = onReady;
})();


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
    /* Off unless the launcher asked for it. A release should not spend a
       walk of the card and a stream of console output on every render for
       diagnostics nobody is reading. */
    if (!window.__kankiRenderDebug) return;

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
