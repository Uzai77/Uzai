// Uzai – Laufzeit für Plugin-Scraper (JavaScript) wie in Nuvio TV.
//
// Uzai startet dieses Skript mit Deno (oder zum Testen mit Node 22):
//   deno run --no-prompt --no-config --allow-net --allow-read=<ordner> runner.js <auftrag.json>
//   node runner.js <auftrag.json>
//
// Jeder Scraper bekommt dieselbe Umgebung wie in Nuvios PluginRuntime (QuickJS):
// fetch (mit Kopfzeilen, Standard-User-Agent, redirect: "manual"), cheerio (load, $(…), find, text,
// html, attr, each, map …), CryptoJS (echte crypto-js 4.2.0), require('cheerio' | 'crypto-js'),
// console, URL, URLSearchParams, atob/btoa, AbortController, SCRAPER_ID, SCRAPER_SETTINGS,
// TMDB_API_KEY, module/exports. Aufgerufen wird getStreams(tmdbId, mediaType, season, episode).
//
// Ausgabe: eine JSON-Zeile pro Scraper auf stdout, sobald er fertig ist:
//   {"event":"result","id":"…","ok":true,"streams":[…],"ms":123}
//   {"event":"result","id":"…","ok":false,"error":"…","ms":123}
// und zum Schluss {"event":"done"}. Meldungen der Scraper (console.*) gehen nach stderr.
//
// Uzai baut keine Quellen ein: welche Scraper laufen, bestimmt allein der Nutzer.

'use strict';

const IS_DENO = typeof Deno !== 'undefined';
const DEFAULT_UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
const MAX_BODY_BYTES = 4 * 1024 * 1024;
const FETCH_TIMEOUT_MS = 30000;
const MAX_PARALLEL = 10;

// --- Plattform (Deno oder Node) -------------------------------------------------------------

function readText(path) {
  if (IS_DENO) return Deno.readTextFileSync(path);
  return require('fs').readFileSync(path, 'utf8');
}

function args() {
  return IS_DENO ? Deno.args : process.argv.slice(2);
}

function out(obj) {
  const line = JSON.stringify(obj) + '\n';
  if (IS_DENO) {
    Deno.stdout.writeSync(new TextEncoder().encode(line));
  } else {
    process.stdout.write(line);
  }
}

function log(id, level, parts) {
  let text = parts.map((p) => {
    if (typeof p === 'string') return p;
    try { return JSON.stringify(p); } catch (e) { return String(p); }
  }).join(' ');
  if (text.length > 2000) text = text.slice(0, 2000) + ' …';
  const line = '[' + id + '] ' + level + ': ' + text + '\n';
  try {
    if (IS_DENO) Deno.stderr.writeSync(new TextEncoder().encode(line));
    else process.stderr.write(line);
  } catch (e) { /* stderr zu – egal */ }
}

function quit(code) {
  if (IS_DENO) Deno.exit(code);
  process.stdout.write('', () => process.exit(code));
}

// --- HTML lesen (Ersatz für Jsoup/cheerio) --------------------------------------------------

const VOID = new Set(['area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param', 'source', 'track', 'wbr', 'keygen', 'command', 'basefont', 'frame', 'isindex']);
const RAW = new Set(['script', 'style', 'textarea', 'title', 'xmp', 'noscript', 'plaintext']);
const BLOCK = new Set(['address', 'article', 'aside', 'blockquote', 'details', 'div', 'dl', 'fieldset', 'figcaption', 'figure', 'footer', 'form', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'header', 'hr', 'main', 'menu', 'nav', 'ol', 'p', 'pre', 'section', 'table', 'ul', 'li', 'tr', 'td', 'th', 'dt', 'dd', 'br', 'option', 'tbody', 'thead', 'tfoot', 'center', 'body', 'html', 'head', 'title']);
const CLOSES = {
  li: ['li'], dt: ['dt', 'dd'], dd: ['dt', 'dd'], option: ['option'], optgroup: ['optgroup', 'option'],
  tr: ['tr', 'td', 'th'], td: ['td', 'th'], th: ['td', 'th'],
  thead: ['tbody', 'tfoot', 'tr', 'td', 'th'], tbody: ['thead', 'tbody', 'tr', 'td', 'th'], tfoot: ['tbody', 'tr', 'td', 'th'],
};
const P_CLOSERS = new Set(['address', 'article', 'aside', 'blockquote', 'div', 'dl', 'fieldset', 'footer', 'form', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'header', 'hr', 'main', 'nav', 'ol', 'p', 'pre', 'section', 'table', 'ul']);
const ENTITIES = {
  amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', copy: '©', reg: '®', trade: '™',
  hellip: '…', ndash: '–', mdash: '—', laquo: '«', raquo: '»', lsquo: '‘', rsquo: '’', ldquo: '“', rdquo: '”',
  bull: '•', middot: '·', times: '×', euro: '€', pound: '£', yen: '¥', cent: '¢', deg: '°', para: '¶', sect: '§',
  auml: 'ä', ouml: 'ö', uuml: 'ü', Auml: 'Ä', Ouml: 'Ö', Uuml: 'Ü', szlig: 'ß', eacute: 'é', egrave: 'è',
  aacute: 'á', agrave: 'à', iacute: 'í', oacute: 'ó', uacute: 'ú', ntilde: 'ñ', ccedil: 'ç', ecirc: 'ê',
  zwnj: '‌', zwj: '‍', ensp: ' ', emsp: ' ', thinsp: ' ',
};

function decodeEntities(s) {
  if (s.indexOf('&') < 0) return s;
  return s.replace(/&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z][a-zA-Z0-9]*);?/g, (m, e) => {
    if (e[0] === '#') {
      const n = e[1] === 'x' || e[1] === 'X' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
      if (!isFinite(n) || n <= 0 || n > 0x10ffff) return m;
      try { return String.fromCodePoint(n); } catch (err) { return m; }
    }
    return Object.prototype.hasOwnProperty.call(ENTITIES, e) ? ENTITIES[e] : m;
  });
}

function makeNode(type, name, parent) {
  return { type: type, name: name || '', attrs: {}, children: [], parent: parent || null, data: '' };
}

function parseHtml(html) {
  html = String(html == null ? '' : html);
  const root = makeNode('root', '#document', null);
  const stack = [root];
  const top = () => stack[stack.length - 1];
  const addText = (text) => {
    if (!text) return;
    const t = makeNode('text', '#text', top());
    t.data = decodeEntities(text);
    top().children.push(t);
  };
  const closeTo = (name) => {
    for (let i = stack.length - 1; i > 0; i--) {
      if (stack[i].name === name) { stack.length = i; return true; }
    }
    return false;
  };
  const tagRe = /<\/?([a-zA-Z][a-zA-Z0-9:_-]*)((?:\s+[^\s"'>\/=]+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s"'=<>`]+))?)*)\s*(\/?)>/y;
  const attrRe = /([^\s"'>\/=]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g;
  let i = 0;
  const n = html.length;
  while (i < n) {
    const lt = html.indexOf('<', i);
    if (lt < 0) { addText(html.slice(i)); break; }
    if (lt > i) addText(html.slice(i, lt));
    i = lt;
    if (html.startsWith('<!--', i)) {
      const end = html.indexOf('-->', i + 4);
      const c = makeNode('comment', '#comment', top());
      c.data = html.slice(i + 4, end < 0 ? n : end);
      top().children.push(c);
      i = end < 0 ? n : end + 3;
      continue;
    }
    if (html[i + 1] === '!' || html[i + 1] === '?') {
      const end = html.indexOf('>', i);
      i = end < 0 ? n : end + 1;
      continue;
    }
    tagRe.lastIndex = i;
    const m = tagRe.exec(html);
    if (!m) { addText('<'); i += 1; continue; }
    i = tagRe.lastIndex;
    const name = m[1].toLowerCase();
    if (m[0][1] === '/') {
      if (name === 'p' && !stack.some((s) => s.name === 'p')) {
        top().children.push(makeNode('element', 'p', top()));
      } else if (name !== 'br') {
        closeTo(name);
      }
      continue;
    }
    if (name === 'p' || P_CLOSERS.has(name)) {
      for (let k = stack.length - 1; k > 0; k--) {
        const sn = stack[k].name;
        if (sn === 'p') { stack.length = k; break; }
        if (BLOCK.has(sn) || sn === 'button' || sn === 'td' || sn === 'th') break;
      }
    }
    const closes = CLOSES[name];
    if (closes) {
      for (let k = stack.length - 1; k > 0; k--) {
        const sn = stack[k].name;
        if (closes.indexOf(sn) >= 0) { stack.length = k; break; }
        if (sn === 'table' || sn === 'ul' || sn === 'ol' || sn === 'dl' || sn === 'select' || sn === 'tbody' && name === 'tr') break;
      }
    }
    const el = makeNode('element', name, top());
    attrRe.lastIndex = 0;
    let a;
    const raw = m[2] || '';
    while ((a = attrRe.exec(raw)) !== null) {
      const key = a[1].toLowerCase();
      if (Object.prototype.hasOwnProperty.call(el.attrs, key)) continue;
      const v = a[2] !== undefined ? a[2] : a[3] !== undefined ? a[3] : a[4] !== undefined ? a[4] : '';
      el.attrs[key] = decodeEntities(v);
    }
    top().children.push(el);
    if (VOID.has(name) || m[3] === '/') continue;
    if (RAW.has(name)) {
      const close = new RegExp('</' + name + '\\s*>', 'ig');
      close.lastIndex = i;
      const cm = close.exec(html);
      const end = cm ? cm.index : n;
      const body = html.slice(i, end);
      if (body) {
        const t = makeNode('text', '#text', el);
        t.data = name === 'script' || name === 'style' ? body : decodeEntities(body);
        el.children.push(t);
      }
      i = cm ? close.lastIndex : n;
      continue;
    }
    stack.push(el);
  }
  return root;
}

function elementChildren(node) {
  return node.children.filter((c) => c.type === 'element');
}

function descendants(node, outList) {
  for (const c of node.children) {
    if (c.type === 'element') {
      outList.push(c);
      descendants(c, outList);
    }
  }
  return outList;
}

function rawText(node) {
  if (node.type === 'text') return node.data;
  let s = '';
  for (const c of node.children) {
    if (c.type === 'text') s += c.data;
    else if (c.type === 'element') {
      if (c.name === 'br') s += ' ';
      else {
        const inner = rawText(c);
        s += BLOCK.has(c.name) ? ' ' + inner + ' ' : inner;
      }
    }
  }
  return s;
}

// Wie Jsoup text(): Leerraum zusammengefasst, außen gekürzt.
function normText(node) {
  return rawText(node).replace(/\s+/g, ' ').trim();
}

function ownText(node) {
  return node.children.filter((c) => c.type === 'text').map((c) => c.data).join('').replace(/\s+/g, ' ').trim();
}

function escText(s) {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function escAttr(s) {
  return s.replace(/&/g, '&amp;').replace(/"/g, '&quot;');
}

function outerHtml(node) {
  if (node.type === 'text') {
    const p = node.parent;
    return p && (p.name === 'script' || p.name === 'style') ? node.data : escText(node.data);
  }
  if (node.type === 'comment') return '<!--' + node.data + '-->';
  if (node.type === 'root') return innerHtml(node);
  let s = '<' + node.name;
  for (const k of Object.keys(node.attrs)) {
    s += node.attrs[k] === '' ? ' ' + k : ' ' + k + '="' + escAttr(node.attrs[k]) + '"';
  }
  s += '>';
  if (VOID.has(node.name)) return s;
  return s + innerHtml(node) + '</' + node.name + '>';
}

function innerHtml(node) {
  return node.children.map(outerHtml).join('');
}

// --- CSS-Selektoren --------------------------------------------------------------------------

function splitTop(sel, sepChar) {
  const parts = [];
  let depth = 0;
  let quote = '';
  let cur = '';
  for (let i = 0; i < sel.length; i++) {
    const ch = sel[i];
    if (quote) {
      cur += ch;
      if (ch === quote) quote = '';
      continue;
    }
    if (ch === '"' || ch === "'") { quote = ch; cur += ch; continue; }
    if (ch === '(' || ch === '[') depth++;
    if (ch === ')' || ch === ']') depth--;
    if (ch === sepChar && depth === 0) { parts.push(cur); cur = ''; continue; }
    cur += ch;
  }
  parts.push(cur);
  return parts.map((p) => p.trim()).filter((p) => p !== '');
}

const selectorCache = new Map();

// Ein Selektor wird zu einer Liste von Teilen: [{ combinator, simple: [Prüfungen] }, …]
function compileSelector(sel) {
  if (selectorCache.has(sel)) return selectorCache.get(sel);
  const groups = splitTop(sel, ',').map(compileComplex);
  selectorCache.set(sel, groups);
  return groups;
}

function compileComplex(sel) {
  const parts = [];
  let i = 0;
  let comb = ' ';
  const n = sel.length;
  while (i < n) {
    while (i < n && /\s/.test(sel[i])) { i++; if (parts.length) comb = comb === ' ' || comb === '' ? ' ' : comb; }
    if (i >= n) break;
    if ('>+~'.indexOf(sel[i]) >= 0) { comb = sel[i]; i++; continue; }
    let j = i;
    let depth = 0;
    let quote = '';
    while (j < n) {
      const ch = sel[j];
      if (quote) { if (ch === quote) quote = ''; j++; continue; }
      if (ch === '"' || ch === "'") { quote = ch; j++; continue; }
      if (ch === '(' || ch === '[') depth++;
      else if (ch === ')' || ch === ']') depth--;
      else if (depth === 0 && (/\s/.test(ch) || '>+~'.indexOf(ch) >= 0)) break;
      j++;
    }
    parts.push({ comb: parts.length ? comb : ' ', tests: compileCompound(sel.slice(i, j)) });
    comb = ' ';
    i = j;
  }
  return parts;
}

function compileCompound(s) {
  const tests = [];
  const re = /(\*)|([a-zA-Z][\w-]*)|#([\w-]+)|\.([\w-]+)|\[\s*([^\s~|^$*!=\]]+)\s*(?:([~|^$*!]?=)\s*(?:"([^"]*)"|'([^']*)'|([^\]\s]*))\s*(i)?)?\s*\]|:([\w-]+)(?:\(((?:[^()]|\([^()]*\))*)\))?/y;
  let i = 0;
  while (i < s.length) {
    re.lastIndex = i;
    const m = re.exec(s);
    if (!m) throw new Error('Selektor nicht verstanden: ' + s);
    i = re.lastIndex;
    if (m[1]) continue;
    if (m[2]) { const tag = m[2].toLowerCase(); tests.push((el) => el.name === tag); continue; }
    if (m[3]) { const id = m[3]; tests.push((el) => el.attrs.id === id); continue; }
    if (m[4]) { const cls = m[4]; tests.push((el) => (' ' + (el.attrs['class'] || '').replace(/\s+/g, ' ') + ' ').indexOf(' ' + cls + ' ') >= 0); continue; }
    if (m[5]) {
      const name = m[5].toLowerCase();
      const op = m[6];
      let val = m[7] !== undefined ? m[7] : m[8] !== undefined ? m[8] : m[9];
      const ci = !!m[10];
      if (!op) { tests.push((el) => Object.prototype.hasOwnProperty.call(el.attrs, name)); continue; }
      if (ci) val = val.toLowerCase();
      tests.push((el) => {
        if (!Object.prototype.hasOwnProperty.call(el.attrs, name)) return op === '!=';
        let v = el.attrs[name];
        if (ci) v = v.toLowerCase();
        switch (op) {
          case '=': return v === val;
          case '!=': return v !== val;
          case '~=': return v.split(/\s+/).indexOf(val) >= 0;
          case '|=': return v === val || v.startsWith(val + '-');
          case '^=': return val !== '' && v.startsWith(val);
          case '$=': return val !== '' && v.endsWith(val);
          case '*=': return val !== '' && v.indexOf(val) >= 0;
        }
        return false;
      });
      continue;
    }
    if (m[11]) tests.push(compilePseudo(m[11].toLowerCase(), m[12]));
  }
  return tests;
}

function unquote(s) {
  s = (s || '').trim();
  if ((s[0] === '"' && s[s.length - 1] === '"') || (s[0] === "'" && s[s.length - 1] === "'")) return s.slice(1, -1);
  return s;
}

function nthMatcher(expr) {
  expr = (expr || '').replace(/\s+/g, '').toLowerCase();
  let a = 0;
  let b = 0;
  if (expr === 'odd') { a = 2; b = 1; } else if (expr === 'even') { a = 2; b = 0; } else if (expr.indexOf('n') >= 0) {
    const [pa, pb] = expr.split('n');
    a = pa === '' || pa === '+' ? 1 : pa === '-' ? -1 : parseInt(pa, 10);
    b = pb ? parseInt(pb, 10) : 0;
  } else b = parseInt(expr, 10);
  return (pos) => (a === 0 ? pos === b : (pos - b) / a >= 0 && (pos - b) % a === 0);
}

function siblingsOf(el) {
  return el.parent ? elementChildren(el.parent) : [el];
}

function compilePseudo(name, arg) {
  switch (name) {
    case 'first-child': return (el) => siblingsOf(el)[0] === el;
    case 'last-child': return (el) => { const s = siblingsOf(el); return s[s.length - 1] === el; };
    case 'only-child': return (el) => siblingsOf(el).length === 1;
    case 'first-of-type': return (el) => siblingsOf(el).filter((s) => s.name === el.name)[0] === el;
    case 'last-of-type': return (el) => { const s = siblingsOf(el).filter((x) => x.name === el.name); return s[s.length - 1] === el; };
    case 'nth-child': { const f = nthMatcher(arg); return (el) => f(siblingsOf(el).indexOf(el) + 1); }
    case 'nth-last-child': { const f = nthMatcher(arg); return (el) => { const s = siblingsOf(el); return f(s.length - s.indexOf(el)); }; }
    case 'nth-of-type': { const f = nthMatcher(arg); return (el) => f(siblingsOf(el).filter((s) => s.name === el.name).indexOf(el) + 1); }
    case 'eq': { const k = parseInt(arg, 10); return (el) => siblingsOf(el).indexOf(el) === k; }
    case 'lt': { const k = parseInt(arg, 10); return (el) => siblingsOf(el).indexOf(el) < k; }
    case 'gt': { const k = parseInt(arg, 10); return (el) => siblingsOf(el).indexOf(el) > k; }
    case 'empty': return (el) => el.children.every((c) => c.type === 'comment' || (c.type === 'text' && c.data === ''));
    case 'root': return (el) => !el.parent || el.parent.type === 'root';
    case 'contains': { const t = unquote(arg).toLowerCase(); return (el) => normText(el).toLowerCase().indexOf(t) >= 0; }
    case 'containsown': { const t = unquote(arg).toLowerCase(); return (el) => ownText(el).toLowerCase().indexOf(t) >= 0; }
    case 'matches': { const r = new RegExp(unquote(arg)); return (el) => r.test(normText(el)); }
    case 'matchesown': { const r = new RegExp(unquote(arg)); return (el) => r.test(ownText(el)); }
    case 'not': { const g = compileSelector(arg); return (el) => !matchesGroups(el, g); }
    case 'is': case 'matches-any': case 'where': { const g = compileSelector(arg); return (el) => matchesGroups(el, g); }
    case 'has': { const g = compileSelector(arg); return (el) => descendants(el, []).some((d) => matchesGroups(d, g)); }
    case 'header': return (el) => /^h[1-6]$/.test(el.name);
    case 'checked': return (el) => 'checked' in el.attrs || 'selected' in el.attrs;
    case 'selected': return (el) => 'selected' in el.attrs;
    case 'disabled': return (el) => 'disabled' in el.attrs;
  }
  throw new Error('Pseudo-Klasse nicht unterstützt: :' + name);
}

function testsMatch(el, tests) {
  for (const t of tests) if (!t(el)) return false;
  return true;
}

function matchesComplex(el, parts, k) {
  if (!testsMatch(el, parts[k].tests)) return false;
  if (k === 0) return true;
  const comb = parts[k].comb;
  if (comb === '>') {
    const p = el.parent;
    return !!p && p.type === 'element' && matchesComplex(p, parts, k - 1);
  }
  if (comb === ' ') {
    for (let p = el.parent; p && p.type === 'element'; p = p.parent) {
      if (matchesComplex(p, parts, k - 1)) return true;
    }
    return false;
  }
  const sibs = siblingsOf(el);
  const idx = sibs.indexOf(el);
  if (comb === '+') return idx > 0 && matchesComplex(sibs[idx - 1], parts, k - 1);
  if (comb === '~') {
    for (let s = idx - 1; s >= 0; s--) if (matchesComplex(sibs[s], parts, k - 1)) return true;
  }
  return false;
}

function matchesGroups(el, groups) {
  for (const g of groups) if (g.length && matchesComplex(el, g, g.length - 1)) return true;
  return false;
}

function selectIn(contexts, sel) {
  let groups;
  try {
    groups = compileSelector(String(sel));
  } catch (e) {
    return [];
  }
  const seen = new Set();
  const res = [];
  for (const ctx of contexts) {
    for (const d of descendants(ctx, [])) {
      if (!seen.has(d) && matchesGroups(d, groups)) {
        seen.add(d);
        res.push(d);
      }
    }
  }
  return res;
}

// --- cheerio-artige Hülle ---------------------------------------------------------------------

function wrap(nodes, root) {
  const w = Object.create(Wrapper);
  w._nodes = nodes;
  w._root = root;
  w._elementIds = nodes;  // wie in Nuvio: $(wrapper) erkennt die Hülle daran
  w.length = nodes.length;
  for (let i = 0; i < nodes.length; i++) w[i] = nodes[i];
  return w;
}

function isWrapper(x) {
  return x && typeof x === 'object' && Array.isArray(x._nodes);
}

function asNodes(x) {
  if (isWrapper(x)) return x._nodes;
  if (x && typeof x === 'object' && x.type) return [x];
  if (Array.isArray(x)) return x.flatMap(asNodes);
  return [];
}

const Wrapper = {
  each(cb) {
    for (let i = 0; i < this._nodes.length; i++) {
      const el = wrap([this._nodes[i]], this._root);
      if (cb.call(el, i, el) === false) break;
    }
    return this;
  },
  map(cb) {
    const results = [];
    for (let i = 0; i < this._nodes.length; i++) {
      const el = wrap([this._nodes[i]], this._root);
      const r = cb.call(el, i, el);
      if (r === undefined || r === null) continue;
      if (Array.isArray(r)) results.push(...r); else results.push(r);
    }
    return {
      length: results.length,
      get(index) { return typeof index === 'number' ? results[index] : results; },
      toArray() { return results; },
      join(sep) { return results.join(sep); },
      [Symbol.iterator]() { return results[Symbol.iterator](); },
    };
  },
  filter(f) {
    if (typeof f === 'function') {
      return wrap(this._nodes.filter((n, i) => { const el = wrap([n], this._root); return f.call(el, i, el); }), this._root);
    }
    if (typeof f === 'string') {
      const g = compileSelector(f);
      return wrap(this._nodes.filter((n) => n.type === 'element' && matchesGroups(n, g)), this._root);
    }
    return this;
  },
  not(f) {
    const keep = new Set(this.filter(f)._nodes);
    return wrap(this._nodes.filter((n) => !keep.has(n)), this._root);
  },
  is(f) { return this.filter(f).length > 0; },
  find(sel) { return wrap(selectIn(this._nodes, sel), this._root); },
  children(sel) {
    let kids = [];
    for (const n of this._nodes) kids = kids.concat(elementChildren(n));
    return sel ? wrap(kids, this._root).filter(sel) : wrap(kids, this._root);
  },
  contents() {
    let kids = [];
    for (const n of this._nodes) kids = kids.concat(n.children);
    return wrap(kids, this._root);
  },
  parent(sel) {
    const ps = [];
    for (const n of this._nodes) if (n.parent && n.parent.type === 'element' && ps.indexOf(n.parent) < 0) ps.push(n.parent);
    return sel ? wrap(ps, this._root).filter(sel) : wrap(ps, this._root);
  },
  parents(sel) {
    const ps = [];
    for (const n of this._nodes) for (let p = n.parent; p && p.type === 'element'; p = p.parent) if (ps.indexOf(p) < 0) ps.push(p);
    return sel ? wrap(ps, this._root).filter(sel) : wrap(ps, this._root);
  },
  closest(sel) {
    const g = compileSelector(sel);
    const res = [];
    for (const n of this._nodes) {
      for (let p = n; p && p.type === 'element'; p = p.parent) {
        if (matchesGroups(p, g)) { if (res.indexOf(p) < 0) res.push(p); break; }
      }
    }
    return wrap(res, this._root);
  },
  next(sel) {
    const res = [];
    for (const n of this._nodes) { const s = siblingsOf(n); const i = s.indexOf(n); if (i >= 0 && i + 1 < s.length) res.push(s[i + 1]); }
    return sel ? wrap(res, this._root).filter(sel) : wrap(res, this._root);
  },
  prev(sel) {
    const res = [];
    for (const n of this._nodes) { const s = siblingsOf(n); const i = s.indexOf(n); if (i > 0) res.push(s[i - 1]); }
    return sel ? wrap(res, this._root).filter(sel) : wrap(res, this._root);
  },
  nextAll(sel) {
    const res = [];
    for (const n of this._nodes) { const s = siblingsOf(n); res.push(...s.slice(s.indexOf(n) + 1)); }
    return sel ? wrap(res, this._root).filter(sel) : wrap(res, this._root);
  },
  prevAll(sel) {
    const res = [];
    for (const n of this._nodes) { const s = siblingsOf(n); res.push(...s.slice(0, Math.max(0, s.indexOf(n))).reverse()); }
    return sel ? wrap(res, this._root).filter(sel) : wrap(res, this._root);
  },
  siblings(sel) {
    const res = [];
    for (const n of this._nodes) for (const s of siblingsOf(n)) if (s !== n && res.indexOf(s) < 0) res.push(s);
    return sel ? wrap(res, this._root).filter(sel) : wrap(res, this._root);
  },
  first() { return wrap(this._nodes.slice(0, 1), this._root); },
  last() { return wrap(this._nodes.slice(-1), this._root); },
  eq(i) { if (i < 0) i += this._nodes.length; return wrap(i >= 0 && i < this._nodes.length ? [this._nodes[i]] : [], this._root); },
  slice(a, b) { return wrap(this._nodes.slice(a, b), this._root); },
  get(i) {
    if (typeof i === 'number') { if (i < 0) i += this._nodes.length; return this._nodes[i]; }
    return this._nodes.slice();
  },
  toArray() { return this._nodes.map((n) => wrap([n], this._root)); },
  index() { if (!this._nodes.length) return -1; const s = siblingsOf(this._nodes[0]); return s.indexOf(this._nodes[0]); },
  text() { return this._nodes.map((n) => normText(n)).filter((t) => t !== '').join(' '); },
  html() { return this._nodes.length ? innerHtml(this._nodes[0]) : null; },
  attr(name) {
    const n = this._nodes[0];
    if (!n || n.type !== 'element') return undefined;
    if (name === undefined) return Object.assign({}, n.attrs);
    const v = n.attrs[String(name).toLowerCase()];
    return v === undefined || v === '' ? undefined : v;
  },
  prop(name) {
    if (name === 'outerHTML') return this._nodes.length ? outerHtml(this._nodes[0]) : undefined;
    if (name === 'innerHTML') return this.html();
    if (name === 'textContent' || name === 'innerText') return this.text();
    if (name === 'tagName' || name === 'nodeName') return this._nodes.length ? this._nodes[0].name.toUpperCase() : undefined;
    return this.attr(name);
  },
  data(name) {
    const n = this._nodes[0];
    if (!n || n.type !== 'element') return undefined;
    if (name === undefined) {
      const o = {};
      for (const k of Object.keys(n.attrs)) if (k.startsWith('data-')) o[k.slice(5)] = n.attrs[k];
      return o;
    }
    return n.attrs['data-' + name];
  },
  val() { const n = this._nodes[0]; if (!n) return undefined; if (n.name === 'textarea') return normText(n); return n.attrs.value; },
  hasClass(c) { return this._nodes.some((n) => (' ' + (n.attrs && n.attrs['class'] || '') + ' ').replace(/\s+/g, ' ').indexOf(' ' + c + ' ') >= 0); },
  [Symbol.iterator]() { return this._nodes.map((n) => wrap([n], this._root))[Symbol.iterator](); },
};

function cheerioLoad(html) {
  const root = parseHtml(html);
  const $ = function (selector, context) {
    if (isWrapper(selector)) return selector;
    if (selector && typeof selector === 'object' && selector.type) return wrap([selector], root);
    if (Array.isArray(selector)) return wrap(asNodes(selector), root);
    if (typeof selector !== 'string' || selector.trim() === '') return wrap([], root);
    if (selector.trim()[0] === '<') return wrap(elementChildren(parseHtml(selector)), root);
    if (context !== undefined && context !== null) {
      const ctx = typeof context === 'string' ? selectIn([root], context) : asNodes(context);
      return wrap(selectIn(ctx, selector), root);
    }
    return wrap(selectIn([root], selector), root);
  };
  $.html = function (el) {
    if (el === undefined) return innerHtml(root);
    const nodes = typeof el === 'string' ? selectIn([root], el) : asNodes(el);
    return nodes.map(outerHtml).join('');
  };
  $.text = function (el) { return el === undefined ? normText(root) : wrap(asNodes(el), root).text(); };
  $.root = function () { return wrap([root], root); };
  $.load = cheerioLoad;
  return $;
}

const cheerio = { load: cheerioLoad };

// --- fetch wie in Nuvio -----------------------------------------------------------------------

function normalizeBody(body) {
  if (body === undefined || body === null) return undefined;
  if (typeof body === 'string') return body;
  if (body instanceof ArrayBuffer) return new Uint8Array(body);
  if (ArrayBuffer.isView(body)) return new Uint8Array(body.buffer, body.byteOffset, body.byteLength);
  return String(body);
}

async function readLimited(res) {
  if (!res.body) return { bytes: new Uint8Array(0), truncated: false };
  const reader = res.body.getReader();
  const chunks = [];
  let size = 0;
  let truncated = false;
  while (true) {
    const r = await reader.read();
    if (r.done) break;
    if (size + r.value.length > MAX_BODY_BYTES) {
      chunks.push(r.value.subarray(0, MAX_BODY_BYTES - size));
      size = MAX_BODY_BYTES;
      truncated = true;
      try { await reader.cancel(); } catch (e) { /* egal */ }
      break;
    }
    chunks.push(r.value);
    size += r.value.length;
  }
  const bytes = new Uint8Array(size);
  let o = 0;
  for (const c of chunks) { bytes.set(c, o); o += c.length; }
  return { bytes: bytes, truncated: truncated };
}

function decodeBody(bytes, contentType) {
  const m = /charset=["']?([\w-]+)/i.exec(contentType || '');
  try {
    return new TextDecoder(m ? m[1] : 'utf-8').decode(bytes);
  } catch (e) {
    return new TextDecoder('utf-8').decode(bytes);
  }
}

function makeFetch(id) {
  return async function fetch(url, options) {
    options = options || {};
    const method = String(options.method || 'GET').toUpperCase();
    const headers = {};
    const src = options.headers || {};
    const put = (k, v) => {
      if (k == null || v == null) return;
      if (String(k).toLowerCase() === 'accept-encoding') return;
      headers[String(k)] = String(v);
    };
    if (typeof src.forEach === 'function' && !Array.isArray(src)) src.forEach((v, k) => put(k, v));
    else if (Array.isArray(src)) src.forEach((p) => put(p[0], p[1]));
    else Object.keys(src).forEach((k) => put(k, src[k]));
    if (!Object.keys(headers).some((k) => k.toLowerCase() === 'user-agent')) headers['User-Agent'] = DEFAULT_UA;
    const body = method === 'GET' || method === 'HEAD' ? undefined : normalizeBody(options.body);
    const hasType = Object.keys(headers).some((k) => k.toLowerCase() === 'content-type');
    if (!hasType && body !== undefined) {
      if (method === 'POST') headers['Content-Type'] = 'application/x-www-form-urlencoded';
      else if (method === 'PUT' || method === 'PATCH') headers['Content-Type'] = 'application/json';
    }
    if (options.signal && options.signal.aborted) {
      const e = new Error('The operation was aborted.');
      e.name = 'AbortError';
      throw e;
    }
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), FETCH_TIMEOUT_MS);
    if (options.signal && options.signal.addEventListener) options.signal.addEventListener('abort', () => ctrl.abort());
    const target = String(url && url.href ? url.href : url);
    let parsed;
    try {
      const res = await globalThis.fetch(target, {
        method: method, headers: headers, body: body, signal: ctrl.signal,
        redirect: options.redirect === 'manual' ? 'manual' : 'follow',
      });
      const read = await readLimited(res);
      const hdrs = {};
      res.headers.forEach((v, k) => { hdrs[k.toLowerCase()] = v; });
      parsed = { ok: res.ok, status: res.status, statusText: res.statusText, url: res.url || target, headers: hdrs, bytes: read.bytes, truncated: read.truncated, redirected: res.redirected };
    } catch (e) {
      if (options.signal && options.signal.aborted) {
        const err = new Error('The operation was aborted.');
        err.name = 'AbortError';
        throw err;
      }
      log(id, 'fetch', [method + ' ' + target + ' fehlgeschlagen: ' + (e && e.message ? e.message : e)]);
      parsed = { ok: false, status: 0, statusText: (e && e.message) || 'Fetch failed', url: target, headers: {}, bytes: new Uint8Array(0), truncated: false, redirected: false };
    } finally {
      clearTimeout(timer);
    }
    const text = decodeBody(parsed.bytes, parsed.headers['content-type']);
    const hdrs = parsed.headers;
    return {
      ok: parsed.ok,
      status: parsed.status,
      statusText: parsed.statusText,
      url: parsed.url,
      redirected: parsed.redirected,
      truncated: parsed.truncated,
      headers: {
        get(name) { const v = hdrs[String(name).toLowerCase()]; return v === undefined ? null : v; },
        has(name) { return String(name).toLowerCase() in hdrs; },
        forEach(cb) { Object.keys(hdrs).forEach((k) => cb(hdrs[k], k)); },
        entries() { return Object.entries(hdrs)[Symbol.iterator](); },
        keys() { return Object.keys(hdrs)[Symbol.iterator](); },
        values() { return Object.values(hdrs)[Symbol.iterator](); },
        raw() { return Object.assign({}, hdrs); },
        [Symbol.iterator]() { return Object.entries(hdrs)[Symbol.iterator](); },
      },
      text() { return Promise.resolve(text); },
      json() {
        try {
          if (text === '') return Promise.resolve(null);
          return Promise.resolve(JSON.parse(text));
        } catch (e) {
          log(id, 'fetch', ['fetch.json: kein JSON – ' + e.message]);
          return Promise.resolve(null);
        }
      },
      arrayBuffer() { return Promise.resolve(parsed.bytes.slice().buffer); },
      blob() { return Promise.resolve(new Blob([parsed.bytes])); },
    };
  };
}

// --- Scraper ausführen --------------------------------------------------------------------------

let CryptoJS = null;

function loadCryptoJs(path) {
  if (!path) return null;
  try {
    const src = readText(path);
    const mod = { exports: {} };
    new Function('module', 'exports', 'define', src)(mod, mod.exports, undefined);
    return mod.exports && mod.exports.lib ? mod.exports : null;
  } catch (e) {
    log('runner', 'error', ['crypto-js lädt nicht: ' + e.message]);
    return null;
  }
}

function makeConsole(id) {
  const c = {};
  for (const level of ['log', 'info', 'warn', 'error', 'debug', 'trace']) {
    c[level] = function () { log(id, level, Array.prototype.slice.call(arguments)); };
  }
  return c;
}

function makeRequire(id) {
  return function require(name) {
    if (name === 'cheerio' || name === 'cheerio-without-node-native' || name === 'react-native-cheerio') return cheerio;
    if (name === 'crypto-js') {
      if (CryptoJS) return CryptoJS;
      throw new Error("Module 'crypto-js' failed to load");
    }
    throw new Error("Module '" + name + "' is not available");
  };
}

function cleanResult(list) {
  // Wie Nuvio: nur Daten zurück (keine Funktionen), kaputte Einträge fallen später raus.
  if (!Array.isArray(list)) return [];
  const outList = [];
  for (const item of list) {
    try {
      const j = JSON.parse(JSON.stringify(item));
      if (j && typeof j === 'object') outList.push(j);
    } catch (e) { /* Kreis oder BigInt: überspringen */ }
  }
  return outList.slice(0, 300);
}

async function runScraper(job, sc) {
  const id = String(sc.id);
  const code = readText(sc.file);
  const settings = sc.settings && typeof sc.settings === 'object' ? sc.settings : {};
  const factory = new Function(
    'fetch', 'cheerio', 'require', 'console', 'CryptoJS', 'SCRAPER_ID', 'SCRAPER_SETTINGS', 'TMDB_API_KEY', 'global', 'window',
    'var module = { exports: {} };\nvar exports = module.exports;\n(function() {\n' + code +
    '\n;try { if (typeof getStreams === "function" && !module.exports.getStreams) { module.exports.getStreams = getStreams; } } catch (e) {}\n})();\nreturn module;'
  );
  // Ohne eigenen Schlüssel bleibt TMDB_API_KEY undefiniert, damit Scraper ihren eigenen Ersatz nehmen.
  const tmdbKey = job.tmdbKey ? String(job.tmdbKey) : undefined;
  const mod = factory(makeFetch(id), cheerio, makeRequire(id), makeConsole(id), CryptoJS, id, settings, tmdbKey, globalThis, globalThis);
  let getStreams = mod && mod.exports && mod.exports.getStreams;
  if (typeof getStreams !== 'function' && mod && typeof mod.exports === 'function') getStreams = mod.exports;
  if (typeof getStreams !== 'function') getStreams = globalThis.getStreams;
  if (typeof getStreams !== 'function') throw new Error('getStreams fehlt im Scraper');
  const mediaType = sc.mediaType || job.mediaType;
  const season = job.season === undefined ? null : job.season;
  const episode = job.episode === undefined ? null : job.episode;
  log(id, 'info', ['getStreams(' + job.tmdbId + ', ' + mediaType + ', ' + season + ', ' + episode + ')']);
  return cleanResult(await getStreams(String(job.tmdbId), mediaType, season, episode));
}

function withTimeout(promise, ms) {
  let timer;
  const t = new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('Zeitlimit (' + Math.round(ms / 1000) + ' s) überschritten')), ms); });
  return Promise.race([promise, t]).finally(() => clearTimeout(timer));
}

async function main() {
  const file = args()[0];
  if (!file) {
    out({ event: 'fatal', error: 'Kein Auftrag angegeben' });
    quit(2);
    return;
  }
  let job;
  try {
    job = JSON.parse(readText(file));
  } catch (e) {
    out({ event: 'fatal', error: 'Auftrag nicht lesbar: ' + e.message });
    quit(2);
    return;
  }
  CryptoJS = loadCryptoJs(job.cryptoJs);
  if (CryptoJS && !globalThis.CryptoJS) globalThis.CryptoJS = CryptoJS;
  const scrapers = Array.isArray(job.scrapers) ? job.scrapers : [];
  const timeoutMs = Number(job.timeoutMs) > 0 ? Number(job.timeoutMs) : 60000;
  let next = 0;
  async function worker() {
    while (next < scrapers.length) {
      const index = next++;
      const sc = scrapers[index];
      // Wie Nuvio: Scraper leicht versetzt starten.
      if (index > 0) await new Promise((r) => setTimeout(r, Math.min(index * 60, 600)));
      const t0 = Date.now();
      try {
        const streams = await withTimeout(runScraper(job, sc), timeoutMs);
        out({ event: 'result', id: sc.id, ok: true, streams: streams, ms: Date.now() - t0 });
      } catch (e) {
        log(sc.id, 'error', [(e && e.stack) || String(e)]);
        out({ event: 'result', id: sc.id, ok: false, error: String((e && e.message) || e).slice(0, 300), ms: Date.now() - t0 });
      }
    }
  }
  const workers = [];
  for (let k = 0; k < Math.min(MAX_PARALLEL, scrapers.length); k++) workers.push(worker());
  await Promise.all(workers);
  out({ event: 'done' });
  quit(0);
}

// Unbehandelte Fehler in Scrapern (vergessene Promises) beenden den Lauf nicht.
if (IS_DENO) {
  globalThis.addEventListener('unhandledrejection', (e) => { e.preventDefault(); log('runner', 'warn', ['unbehandelt: ' + (e.reason && e.reason.message || e.reason)]); });
} else {
  process.on('unhandledRejection', (r) => { log('runner', 'warn', ['unbehandelt: ' + (r && r.message || r)]); });
  process.on('uncaughtException', (e) => { log('runner', 'warn', ['Ausnahme: ' + (e && e.message || e)]); });
}

main().catch((e) => {
  out({ event: 'fatal', error: String((e && e.message) || e) });
  quit(1);
});
