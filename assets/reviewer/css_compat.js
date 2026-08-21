(function () {
  'use strict';

  /*
   * Generic CSS compatibility for Kindle's WebKit 534 generation.
   *
   * This module never recognizes a deck, field, logo or vocabulary concept.
   * It translates browser features, not card designs:
   *   - custom properties used through var();
   *   - simple calc() arithmetic commonly emitted by note templates;
   *   - modern flexbox declarations to the WebKit box model;
   *   - flex gap to child margins after the card enters #qa.
   *
   * Media queries are preserved. Unlike the historical renderer, this module
   * never rewrites width breakpoints or invents a logical viewport.
   */

  function trim(value) {
    return String(value == null ? '' : value).replace(/^\s+|\s+$/g, '');
  }

  function copyMap(source) {
    var output = {};
    var key;
    for (key in source) {
      if (Object.prototype.hasOwnProperty.call(source, key)) output[key] = source[key];
    }
    return output;
  }

  function matchingBrace(text, opening) {
    var depth = 0;
    var quote = '';
    var comment = false;
    var i;
    for (i = opening; i < text.length; i += 1) {
      var ch = text.charAt(i);
      var next = text.charAt(i + 1);
      if (comment) {
        if (ch === '*' && next === '/') {
          comment = false;
          i += 1;
        }
        continue;
      }
      if (!quote && ch === '/' && next === '*') {
        comment = true;
        i += 1;
        continue;
      }
      if (quote) {
        if (ch === '\\') i += 1;
        else if (ch === quote) quote = '';
        continue;
      }
      if (ch === '"' || ch === "'") {
        quote = ch;
      } else if (ch === '{') {
        depth += 1;
      } else if (ch === '}') {
        depth -= 1;
        if (depth === 0) return i;
      }
    }
    return -1;
  }

  function topLevelRules(text) {
    var rules = [];
    var cursor = 0;
    while (cursor < text.length) {
      var opening = text.indexOf('{', cursor);
      if (opening < 0) break;
      var closing = matchingBrace(text, opening);
      if (closing < 0) break;
      rules.push({
        start: cursor,
        opening: opening,
        closing: closing,
        prelude: trim(text.substring(cursor, opening)),
        body: text.substring(opening + 1, closing)
      });
      cursor = closing + 1;
    }
    return rules;
  }

  function declarations(text) {
    var output = [];
    var start = 0;
    var quote = '';
    var parentheses = 0;
    var i;
    for (i = 0; i <= text.length; i += 1) {
      var ch = text.charAt(i);
      if (quote) {
        if (ch === '\\') i += 1;
        else if (ch === quote) quote = '';
      } else if (ch === '"' || ch === "'") {
        quote = ch;
      } else if (ch === '(') {
        parentheses += 1;
      } else if (ch === ')' && parentheses > 0) {
        parentheses -= 1;
      } else if ((ch === ';' && parentheses === 0) || i === text.length) {
        var raw = trim(text.substring(start, i));
        var colon = raw.indexOf(':');
        if (colon > 0) {
          output.push({name: trim(raw.substring(0, colon)), value: trim(raw.substring(colon + 1))});
        }
        start = i + 1;
      }
    }
    return output;
  }

  function rootVariables(text, inherited) {
    var vars = copyMap(inherited || {});
    var rules = topLevelRules(text);
    var i;
    var j;
    for (i = 0; i < rules.length; i += 1) {
      if (rules[i].prelude.indexOf('@') === 0) continue;
      var selectors = rules[i].prelude.split(',');
      var isRoot = false;
      for (j = 0; j < selectors.length; j += 1) {
        var selector = trim(selectors[j]);
        if (selector === ':root' || selector === 'html' || selector === '.card') {
          isRoot = true;
          break;
        }
      }
      if (!isRoot) continue;
      var list = declarations(rules[i].body);
      for (j = 0; j < list.length; j += 1) {
        if (list[j].name.indexOf('--') === 0) vars[list[j].name.substring(2)] = list[j].value;
      }
    }
    return vars;
  }

  function resolveValue(value, vars) {
    var previous = '';
    var rounds = 0;
    value = String(value || '');
    while (value !== previous && rounds < 16) {
      previous = value;
      value = value.replace(/var\(\s*--([A-Za-z0-9_-]+)\s*(?:,\s*([^\)]+))?\)/g,
        function (whole, name, fallback) {
          if (Object.prototype.hasOwnProperty.call(vars, name)) return vars[name];
          return fallback == null ? whole : trim(fallback);
        });
      rounds += 1;
    }
    return value;
  }

  function number(value) {
    var parsed = parseFloat(value);
    return isFinite(parsed) ? parsed : null;
  }

  function formatNumber(value) {
    var text = String(Math.round(value * 10000) / 10000);
    return text === '-0' ? '0' : text;
  }

  function simplifyCalc(value) {
    var previous = '';
    var rounds = 0;
    while (value !== previous && rounds < 8) {
      previous = value;
      value = value.replace(/calc\(\s*(-?[0-9.]+)(px|em|rem|%)\s*([+\-])\s*(-?[0-9.]+)\2\s*\)/g,
        function (whole, left, unit, operator, right) {
          var a = number(left);
          var b = number(right);
          if (a == null || b == null) return whole;
          return formatNumber(operator === '+' ? a + b : a - b) + unit;
        });
      value = value.replace(/calc\(\s*(-?[0-9.]+)(px|em|rem|%)\s*([*\/])\s*(-?[0-9.]+)\s*\)/g,
        function (whole, left, unit, operator, right) {
          var a = number(left);
          var b = number(right);
          if (a == null || b == null || (operator === '/' && b === 0)) return whole;
          return formatNumber(operator === '*' ? a * b : a / b) + unit;
        });
      value = value.replace(/calc\(\s*(-?[0-9.]+)px\s*\*\s*\(\s*(-?[0-9.]+)\s*\/\s*(-?[0-9.]+)\s*\)\s*\)/g,
        function (whole, left, numerator, denominator) {
          var a = number(left);
          var b = number(numerator);
          var c = number(denominator);
          if (a == null || b == null || c == null || c === 0) return whole;
          return formatNumber(a * b / c) + 'px';
        });
      rounds += 1;
    }
    return value;
  }

  function boxPack(value) {
    value = trim(value).toLowerCase();
    if (value === 'flex-start' || value === 'start') return 'start';
    if (value === 'flex-end' || value === 'end') return 'end';
    if (value === 'space-between') return 'justify';
    return value === 'center' ? 'center' : '';
  }

  function boxAlign(value) {
    value = trim(value).toLowerCase();
    if (value === 'flex-start') return 'start';
    if (value === 'flex-end') return 'end';
    return /^(start|end|center|stretch|baseline)$/.test(value) ? value : '';
  }

  function boxOrdinalGroup(value) {
    value = trim(value);
    if (!/^[+-]?[0-9]+$/.test(value)) return '';
    var order = parseInt(value, 10);
    /*
     * Modern order starts at zero, while the 2009 box model starts at one.
     * Negative order has no equivalent natural-number group unless every
     * unstyled sibling is rewritten too, so do not emit an invalid group.
     */
    if (order < 0 || order >= 2147483647) return '';
    return String(order + 1);
  }

  function transformDeclarations(body, vars) {
    var list = declarations(body);
    var output = [];
    var i;
    for (i = 0; i < list.length; i += 1) {
      var name = list[i].name;
      var lower = name.toLowerCase();
      var value = simplifyCalc(resolveValue(list[i].value, vars));
      if (lower.indexOf('--') === 0) {
        output.push(name + ':' + value);
      } else if (lower === 'display' && value.toLowerCase() === 'flex') {
        output.push('display:-webkit-box');
        output.push('display:flex');
      } else if (lower === 'display' && value.toLowerCase() === 'inline-flex') {
        output.push('display:-webkit-inline-box');
        output.push('display:inline-flex');
      } else if (lower === 'flex-direction') {
        var vertical = /column/i.test(value);
        output.push('-webkit-box-orient:' + (vertical ? 'vertical' : 'horizontal'));
        output.push('-webkit-box-direction:' + (/reverse/i.test(value) ? 'reverse' : 'normal'));
        output.push(name + ':' + value);
      } else if (lower === 'align-items') {
        var align = boxAlign(value);
        if (align) output.push('-webkit-box-align:' + align);
        output.push(name + ':' + value);
      } else if (lower === 'justify-content') {
        var pack = boxPack(value);
        if (pack) output.push('-webkit-box-pack:' + pack);
        output.push(name + ':' + value);
      } else if (lower === 'order') {
        var ordinal = boxOrdinalGroup(value);
        if (ordinal) output.push('-webkit-box-ordinal-group:' + ordinal);
        output.push(name + ':' + value);
      } else if (lower === 'flex-grow') {
        output.push('-webkit-box-flex:' + value);
        output.push(name + ':' + value);
      } else if (lower === 'flex' && /^\s*[0-9.]+\s*(?:$|\s)/.test(value)) {
        output.push('-webkit-box-flex:' + parseFloat(value));
        output.push(name + ':' + value);
      } else {
        output.push(name + ':' + value);
      }
    }
    return output.join(';') + (output.length ? ';' : '');
  }

  function resolvedPx(value, vars) {
    value = simplifyCalc(resolveValue(value, vars));
    return /^\s*-?[0-9.]+px\s*$/.test(value) ? parseFloat(value) : null;
  }

  function collectGapRule(selector, body, vars, media, gaps) {
    var list = declarations(body);
    var display = '';
    var direction = 'row';
    var gap = '';
    var rowGap = '';
    var columnGap = '';
    var i;
    for (i = 0; i < list.length; i += 1) {
      var name = list[i].name.toLowerCase();
      if (name === 'display') display = trim(list[i].value).toLowerCase();
      else if (name === 'flex-direction') direction = trim(list[i].value).toLowerCase();
      else if (name === 'gap') gap = list[i].value;
      else if (name === 'row-gap') rowGap = list[i].value;
      else if (name === 'column-gap') columnGap = list[i].value;
    }
    if (display !== 'flex' && display !== 'inline-flex') return;
    var column = /column/.test(direction);
    var value = column ? (rowGap || gap) : (columnGap || gap);
    var pixels = resolvedPx(value, vars);
    if (pixels != null && pixels >= 0) {
      gaps.push({selector: selector, gap: pixels, column: column, media: media || ''});
    }
  }

  function transformScope(text, inherited, media, gaps) {
    var vars = rootVariables(text, inherited);
    var output = '';
    var cursor = 0;
    var rules = topLevelRules(text);
    var i;
    for (i = 0; i < rules.length; i += 1) {
      var rule = rules[i];
      output += text.substring(cursor, rule.start);
      if (rule.prelude.indexOf('@media') === 0) {
        var condition = trim(rule.prelude.substring(6));
        output += rule.prelude + '{' + transformScope(rule.body, vars, condition, gaps) + '}';
      } else if (rule.prelude.indexOf('@supports') === 0 || rule.prelude.indexOf('@layer') === 0) {
        output += rule.prelude + '{' + transformScope(rule.body, vars, media, gaps) + '}';
      } else if (rule.prelude.indexOf('@keyframes') === 0 || rule.prelude.indexOf('@-webkit-keyframes') === 0) {
        output += rule.prelude + '{' + rule.body + '}';
      } else {
        collectGapRule(rule.prelude, rule.body, vars, media, gaps);
        output += rule.prelude + '{' + transformDeclarations(rule.body, vars) + '}';
      }
      cursor = rule.closing + 1;
    }
    output += text.substring(cursor);
    return output;
  }

  function transform(css) {
    var gaps = [];
    var transformed = transformScope(String(css || ''), {}, '', gaps);
    return {css: transformed, gaps: gaps};
  }

  function mediaMatches(condition) {
    if (!condition) return true;
    if (!window.matchMedia) return true;
    try {
      return window.matchMedia(condition).matches;
    } catch (error) {
      return true;
    }
  }

  function apply(root, result) {
    var rules = result && result.gaps || [];
    var i;
    var j;
    var k;
    for (i = 0; i < rules.length; i += 1) {
      if (!mediaMatches(rules[i].media)) continue;
      var nodes;
      try {
        nodes = root.querySelectorAll(rules[i].selector);
      } catch (error) {
        continue;
      }
      for (j = 0; j < nodes.length; j += 1) {
        var children = nodes[j].children;
        for (k = 0; k < children.length; k += 1) {
          if (rules[i].column) {
            children[k].style.marginBottom = k + 1 < children.length ? rules[i].gap + 'px' : '';
          } else {
            children[k].style.marginRight = k + 1 < children.length ? rules[i].gap + 'px' : '';
          }
        }
      }
    }
  }

  window.kankiCssCompat = {
    protocolVersion: 1,
    transform: transform,
    apply: apply
  };
}());
