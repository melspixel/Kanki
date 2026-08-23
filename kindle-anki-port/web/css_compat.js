(function () {
  'use strict';

  function trim(value) {
    return String(value == null ? '' : value).replace(/^\s+|\s+$/g, '');
  }

  function collectVariables(css) {
    var vars = {};
    var expression = /--([A-Za-z0-9_-]+)\s*:\s*([^;}]+)[;}]/g;
    var match;
    while ((match = expression.exec(css)) !== null) {
      vars[match[1]] = trim(match[2]);
    }
    return vars;
  }

  function replaceVariables(value, vars) {
    var previous = null;
    var output = value;
    var passes = 0;
    while (output !== previous && passes < 8) {
      previous = output;
      output = output.replace(/var\(\s*--([A-Za-z0-9_-]+)\s*(?:,\s*([^\)]+))?\)/g,
        function (_, name, fallback) {
          if (Object.prototype.hasOwnProperty.call(vars, name)) return vars[name];
          return fallback == null ? '' : trim(fallback);
        });
      passes += 1;
    }
    return output;
  }

  function simpleCalc(value) {
    return value.replace(/calc\(\s*(-?[0-9.]+)px\s*([+-])\s*(-?[0-9.]+)px\s*\)/g,
      function (_, left, operator, right) {
        var a = parseFloat(left);
        var b = parseFloat(right);
        return (operator === '+' ? a + b : a - b) + 'px';
      });
  }

  function declarations(body, vars) {
    var output = [];
    var chunks = body.split(';');
    var i;
    for (i = 0; i < chunks.length; i += 1) {
      var colon = chunks[i].indexOf(':');
      if (colon < 1) continue;
      var name = trim(chunks[i].substring(0, colon));
      var value = simpleCalc(replaceVariables(trim(chunks[i].substring(colon + 1)), vars));
      if (name.indexOf('--') === 0) continue;
      if (name === 'display' && (value === 'flex' || value === 'inline-flex')) {
        output.push('display:' + (value === 'inline-flex' ? '-webkit-inline-box' : '-webkit-box'));
      }
      if (name === 'flex-direction') {
        output.push('-webkit-box-orient:' + (/column/.test(value) ? 'vertical' : 'horizontal'));
        output.push('-webkit-box-direction:' + (/reverse/.test(value) ? 'reverse' : 'normal'));
      } else if (name === 'justify-content') {
        var pack = value === 'flex-end' ? 'end' : value === 'center' ? 'center' :
          value === 'space-between' ? 'justify' : 'start';
        output.push('-webkit-box-pack:' + pack);
      } else if (name === 'align-items') {
        var align = value === 'flex-end' ? 'end' : value === 'flex-start' ? 'start' : value;
        output.push('-webkit-box-align:' + align);
      } else if (name === 'order') {
        output.push('-webkit-box-ordinal-group:' + (parseInt(value, 10) + 1));
      } else if (name === 'flex-grow' || name === 'flex') {
        var grow = parseFloat(value);
        if (!isNaN(grow)) output.push('-webkit-box-flex:' + grow);
      }
      output.push(name + ':' + value);
    }
    return output.join(';') + (output.length ? ';' : '');
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
        if (ch === '*' && next === '/') { comment = false; i += 1; }
        continue;
      }
      if (!quote && ch === '/' && next === '*') { comment = true; i += 1; continue; }
      if (quote) {
        if (ch === '\\') i += 1;
        else if (ch === quote) quote = '';
        continue;
      }
      if (ch === '"' || ch === "'") quote = ch;
      else if (ch === '{') depth += 1;
      else if (ch === '}') {
        depth -= 1;
        if (depth === 0) return i;
      }
    }
    return -1;
  }

  function transformScope(css, vars, gaps, media) {
    var output = '';
    var cursor = 0;
    while (cursor < css.length) {
      var opening = css.indexOf('{', cursor);
      if (opening < 0) { output += css.substring(cursor); break; }
      var closing = matchingBrace(css, opening);
      if (closing < 0) { output += css.substring(cursor); break; }
      var prelude = trim(css.substring(cursor, opening));
      var body = css.substring(opening + 1, closing);
      if (prelude.indexOf('@media') === 0 || prelude.indexOf('@supports') === 0 ||
          prelude.indexOf('@layer') === 0) {
        output += prelude + '{' + transformScope(body, vars, gaps,
          prelude.indexOf('@media') === 0 ? trim(prelude.substring(6)) : media) + '}';
      } else if (prelude.indexOf('@keyframes') === 0 ||
                 prelude.indexOf('@-webkit-keyframes') === 0 ||
                 prelude.indexOf('@font-face') === 0) {
        output += prelude + '{' + body + '}';
      } else {
        var displayFlex = /display\s*:\s*(?:inline-)?flex/i.test(body);
        var gapMatch = /(?:^|;)\s*(?:gap|row-gap|column-gap)\s*:\s*([0-9.]+)px/i.exec(body);
        var column = /flex-direction\s*:\s*column/i.test(body);
        if (displayFlex && gapMatch) {
          gaps.push({selector: prelude, pixels: parseFloat(gapMatch[1]), column: column, media: media || ''});
        }
        output += prelude + '{' + declarations(body, vars) + '}';
      }
      cursor = closing + 1;
    }
    return output;
  }

  function mediaMatches(condition) {
    if (!condition || !window.matchMedia) return true;
    try { return window.matchMedia(condition).matches; } catch (error) { return true; }
  }

  function applyGaps(root, gaps) {
    var i, j, children, nodes;
    for (i = 0; i < gaps.length; i += 1) {
      if (!mediaMatches(gaps[i].media)) continue;
      try { nodes = root.querySelectorAll(gaps[i].selector); } catch (error) { continue; }
      for (j = 0; j < nodes.length; j += 1) {
        children = nodes[j].children;
        var k;
        for (k = 0; k < children.length; k += 1) {
          if (gaps[i].column) {
            children[k].style.marginBottom = k + 1 < children.length ? gaps[i].pixels + 'px' : '';
          } else {
            children[k].style.marginRight = k + 1 < children.length ? gaps[i].pixels + 'px' : '';
          }
        }
      }
    }
  }

  window.kapCssCompat = {
    protocolVersion: 1,
    transform: function (css) {
      var source = String(css || '');
      var vars = collectVariables(source);
      var gaps = [];
      return {css: transformScope(source, vars, gaps, ''), gaps: gaps};
    },
    apply: applyGaps
  };
}());
