(function () {
    "use strict";

    var qa = null;

    function addClass(element, className) {
        var current = element.className || "";
        if ((" " + current + " ").indexOf(" " + className + " ") === -1) {
            element.className = current ? current + " " + className : className;
        }
    }

    function setPlatformClasses() {
        addClass(document.documentElement, "linux");
        addClass(document.documentElement, "kindle");
    }

    function setBodyClasses(cardOrdinal) {
        var ordinal = parseInt(cardOrdinal, 10);
        if (!(ordinal >= 0)) {
            ordinal = 0;
        }
        document.body.className = "card card" + (ordinal + 1) + " isLin";
    }

    function executeScripts(root) {
        var scripts = root.getElementsByTagName("script");
        var copies = [];
        var index;
        for (index = 0; index < scripts.length; index += 1) {
            copies.push(scripts[index]);
        }
        for (index = 0; index < copies.length; index += 1) {
            var oldScript = copies[index];
            var newScript = document.createElement("script");
            var attrIndex;
            for (attrIndex = 0; attrIndex < oldScript.attributes.length; attrIndex += 1) {
                var attr = oldScript.attributes[attrIndex];
                newScript.setAttribute(attr.name, attr.value);
            }
            newScript.text = oldScript.text || oldScript.textContent || oldScript.innerHTML || "";
            if (oldScript.parentNode) {
                oldScript.parentNode.replaceChild(newScript, oldScript);
            }
        }
    }

    function scrollAnswerIntoView() {
        var answer = document.getElementById("answer");
        if (answer && answer.scrollIntoView) {
            window.setTimeout(function () {
                answer.scrollIntoView(true);
            }, 30);
        } else {
            window.scrollTo(0, 0);
        }
    }

    function setCard(payload, isAnswer) {
        payload = payload || {};
        setBodyClasses(payload.cardOrdinal);
        qa.innerHTML = payload.html || "";
        executeScripts(qa);
        if (isAnswer) {
            scrollAnswerIntoView();
        } else {
            window.scrollTo(0, 0);
        }
    }

    function metrics() {
        var root = document.documentElement;
        var bodyStyle = window.getComputedStyle ? window.getComputedStyle(document.body, null) : null;
        var values = {
            innerWidth: window.innerWidth || 0,
            innerHeight: window.innerHeight || 0,
            clientWidth: root ? root.clientWidth : 0,
            screenWidth: window.screen ? window.screen.width : 0,
            screenHeight: window.screen ? window.screen.height : 0,
            devicePixelRatio: window.devicePixelRatio || 0,
            bodyFontSize: bodyStyle ? bodyStyle.fontSize : "unknown",
            smallBreakpoint: document.getElementById("kanki-breakpoint-small") ?
                document.getElementById("kanki-breakpoint-small").offsetWidth > 0 : false,
            wideBreakpoint: document.getElementById("kanki-breakpoint-wide") ?
                document.getElementById("kanki-breakpoint-wide").offsetWidth > 0 : false
        };
        return values;
    }

    function metricsText(values) {
        var keys = [
            "innerWidth", "innerHeight", "clientWidth", "screenWidth",
            "screenHeight", "devicePixelRatio", "bodyFontSize",
            "smallBreakpoint", "wideBreakpoint"
        ];
        var output = [];
        var index;
        for (index = 0; index < keys.length; index += 1) {
            output.push(keys[index] + "=" + values[keys[index]]);
        }
        return output.join(" | ");
    }

    window.KankiReviewer = {
        showQuestion: function (payload) {
            setCard(payload, false);
        },
        showAnswer: function (payload) {
            setCard(payload, true);
        },
        metrics: metrics
    };

    function ready() {
        qa = document.getElementById("qa");
        setPlatformClasses();
        if (window.KANKI_PROBE_FRONT) {
            window.KankiReviewer.showQuestion({
                cardOrdinal: 0,
                html: window.KANKI_PROBE_FRONT
            });
        }
        window.setTimeout(function () {
            var values = metrics();
            var node = document.getElementById("kanki-metrics");
            var text = metricsText(values);
            if (node) {
                node.innerHTML = text;
            }
            if (window.console && window.console.log) {
                window.console.log("KANKI_PROBE|" + text);
            }
        }, 120);
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", ready, false);
    } else {
        ready();
    }
}());
