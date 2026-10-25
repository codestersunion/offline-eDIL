// eDIL in the browser, with no server: the dictionary comes from data.js
// (gzipped JSON, built by bin/build-static) and every page is drawn here.
// Pages live in the URL hash (#/entries/123) so links, Back and bookmarks
// work from a file:// page.
//
// The markup rendering, search and page logic mirror lib/markup.rb,
// lib/dictionary.rb and the views/ templates of the Sinatra version.
(function () {
  'use strict';

  let D;                                  // the decoded dictionary
  let entryXml = [];                      // entry index -> source XML
  const targets = Object.create(null);    // xml:id -> entry id, for cross-references
  const sectionIndex = Object.create(null);
  const columnCache = [];                 // section index -> Map(column -> lines)
  let defsKeys, sourceEntries, firstEntry;

  // ---- Text helpers (mirror Dictionary.normalize / headword_key) ----

  const ESC = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ESC[c]);

  const normalize = (s) => String(s).normalize('NFD').replace(/\p{Mn}/gu, '')
    .toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim();

  const headwordKey = (s) => normalize(String(s).replace(/[⁰¹²³⁴⁵⁶⁷⁸⁹()]/g, '')
    .replace(/^[?\s]*\d+\??(?:,\s*\d+)*\s+/, ''));

  // ---- Markup (mirrors lib/markup.rb) ----
  // Every element becomes <span class="name">; cross-references become links.

  const NATIVE = { sup: 'sup', b: 'b' };

  // With `withSources`, source abbreviations also carry their full title in
  // data-source, shown on hover by entry.css (mirrors lib/source_markup.rb).
  function tagsFor(name, attrs, withSources) {
    if (name === 'sample' || name === 'br') return ['', ''];
    if (NATIVE[name]) return [`<${NATIVE[name]}>`, `</${NATIVE[name]}>`];
    if ((name === 'ref' || name === 'xref') && targets[attrs.target]) {
      return [`<a class="${name}" href="#/entries/${targets[attrs.target]}">`, '</a>'];
    }
    const lang = attrs.lang ? ` lang="${attrs.lang.toLowerCase()}"` : '';
    let open = `<span class="${name}"${lang}>`;
    if (withSources) {
      const key = name === 'title' ? attrs.target : name === 'orphanScope' ? attrs.source : null;
      const desc = key && D.sources[key.toLowerCase()];
      if (desc) open = open.replace(/^<span class="/, `<span data-source="${esc(desc)}" tabindex="0" class="source `);
    }
    return [open, '</span>'];
  }

  // Attribute values with character references decoded, as lib/markup.rb
  // does ("a&#xED;" -> "aí", "&amp;" -> "&").
  const NAMED = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" };
  const decodeRefs = (v) => v.replace(/&(#x[0-9a-f]+|#\d+|amp|lt|gt|quot|apos);/gi, (_, r) =>
    (r[0] === '#' ? String.fromCodePoint(r[1].toLowerCase() === 'x' ? parseInt(r.slice(2), 16) : parseInt(r.slice(1), 10)) : NAMED[r.toLowerCase()]));

  function parseAttrs(tok) {
    const attrs = {};
    const re = /([\w:.-]+)="([^"]*)"/g;
    let m;
    while ((m = re.exec(tok))) attrs[m[1]] = decodeRefs(m[2]);
    return attrs;
  }

  // Calls cb(kind, html, attrs) per token. `stack` holds
  // [name, openHtml, closeHtml] for the elements currently open.
  function walk(xml, stack, cb, withSources = false) {
    const re = /<!--[\s\S]*?-->|<\?[\s\S]*?\?>|<![^>]*>|<[^>]+>|[^<]+/g;
    let m;
    while ((m = re.exec(xml))) {
      const tok = m[0];
      if (tok[0] !== '<') { cb('text', tok); continue; }
      if (tok[1] === '!' || tok[1] === '?') continue;
      if (tok[1] === '/') {
        const name = tok.slice(2, -1).trim();
        let idx = -1;
        for (let i = stack.length - 1; i >= 0; i--) if (stack[i][0] === name) { idx = i; break; }
        if (idx < 0) continue;
        cb('close', stack.splice(idx).reverse().map((s) => s[2]).join(''));
        continue;
      }
      const nm = /^<([\w:.-]+)/.exec(tok);
      if (!nm) continue;
      const attrs = parseAttrs(tok);
      if (nm[1] === 'br' && attrs.column) { cb('br', '', attrs); continue; }
      const [open, close] = tagsFor(nm[1], attrs, withSources);
      if (tok.endsWith('/>')) {
        cb('empty', open + close, attrs);
      } else {
        stack.push([nm[1], open, close]);
        cb('open', open, attrs);
      }
    }
  }

  function toHtml(xml, withSources = false) {
    let out = '';
    walk(xml, [], (kind, html) => { if (kind !== 'br') out += html; }, withSources);
    return out;
  }

  // ---- Entry layout (mirrors lib/entry_layout.rb rule for rule;
  // test/layout_parity.rb checks both give the same HTML) ----
  // One line per grammatical form and per example, references inline.
  //
  // Ruby and JavaScript differ in ways that matter here, so: whitespace is
  // matched as Ruby's ASCII \s (JavaScript's \s also matches no-break
  // spaces), trimming is Ruby's strip, and a found position of 0 is checked
  // with `!== null` (Ruby treats 0 as true).

  const SP = '[ \\t\\r\\n\\f\\v]';
  const strip = (s) => s.replace(/^[ \t\r\n\f\v\0]+|[ \t\r\n\f\v\0]+$/g, '');
  const lstrip = (s) => s.replace(/^[ \t\r\n\f\v\0]+/, '');
  const LABELS = ['case', 'number', 'gram'];
  const FORM_LABELS = ['case', 'number', 'per', 'tns', 'mood', 'voice'];
  const BOUNDARY = new RegExp(`[.;](?=${SP}*(?:$|\\p{Lu}|\\?))`, 'gu');
  const HAS_LETTER = /\p{L}/u;
  const isText = (n) => n.nodeType === 3;
  const isEl = (n, name) => n != null && n.nodeType === 1 && (name === undefined || n.nodeName === name);
  const blank = (n) => isText(n) && strip(n.data) === '';
  const textOf = (n) => (isText(n) ? n.data : n.textContent);
  const parenDelta = (t) => t.split('(').length - t.split(')').length;
  const serializer = new XMLSerializer();

  // Positions of BOUNDARY matches in `t`.
  function boundaries(t) {
    const re = new RegExp(BOUNDARY.source, 'gu');
    const out = [];
    let m;
    while ((m = re.exec(t))) out.push(m.index);
    return out;
  }

  // The first boundary in `t` that is outside brackets, given the bracket
  // depth before `t`; null if none.
  function firstStop(t, depth) {
    const pos = boundaries(t).find((p) => depth + parenDelta(t.slice(0, p + 1)) <= 0);
    return pos === undefined ? null : pos;
  }

  const hasRefs = (nodes) => nodes.some((n) => isEl(n, 'bibl'));
  const allBlank = (nodes) => nodes.every(blank);

  class EntryLayout {
    // `xml` is one <entry> element of cleaned source text.
    constructor(xml) {
      // A hyphen at the end of a printed line ("dis-|pute") is followed by
      // the line marker and a space; close the gap so it reads "dis-pute".
      xml = xml.replace(new RegExp(`(\\p{L})-${SP}*(<br [^>]*\\/>)${SP}*(?=\\p{L})`, 'gu'), '$1-$2');
      this.doc = new DOMParser().parseFromString(xml, 'application/xml');
      if (this.doc.getElementsByTagName('parsererror').length) throw new Error('unparsable entry');
      this.entry = this.doc.documentElement;
      Array.from(this.doc.getElementsByTagName('br')).forEach((b) => b.remove());
      // Shortened references ("12d44") point at the reference that names
      // their source: id -> title ("Wb.") and id -> source key.
      this.titles = {};
      const keys = {};
      for (const t of Array.from(this.doc.getElementsByTagName('title'))) {
        const id = t.getAttribute('xml:id');
        if (!id) continue;
        this.titles[id] = strip(t.textContent);
        if (t.getAttribute('target')) keys[id] = t.getAttribute('target');
      }
      for (const o of Array.from(this.doc.getElementsByTagName('orphanScope'))) {
        const key = keys[o.getAttribute('target')];
        if (key) o.setAttribute('source', key);
      }
    }

    html() {
      return this.blocksOf(this.entry).map(([kind, nodes]) => {
        if (kind === 'grammar') return this.grammarHtml(nodes);
        if (kind === 'sense') return `<div class="sense-block">${this.senseHtml(nodes)}</div>`;
        return `<div class="note raw">${this.render(nodes)}</div>`;
      }).join('\n');
    }

    // [kind, node(s)] per paragraph: grammar for <form><p>, sense for
    // other paragraphs, raw for anything else.
    blocksOf(node, out = []) {
      for (const el of Array.from(node.children)) {
        if (el.nodeName === 'form') {
          for (const c of Array.from(el.children)) {
            if (c.nodeName === 'p') out.push(['grammar', c]);
            else if (c.nodeName !== 'orth') out.push(['raw', [c]]);
          }
        } else if (el.nodeName === 'p') {
          out.push(['sense', el]);
        } else if (['sense', 'eg', 'egForm'].includes(el.nodeName)) {
          this.blocksOf(el, out);
        } else {
          out.push(['raw', [el]]);
        }
      }
      return out;
    }

    // Collapses whitespace and removes spaces before punctuation, leaving
    // ".i." alone; the source's `quoted translation' gets curly quotes.
    render(nodes) {
      return strip(toHtml(nodes.map((n) => serializer.serializeToString(n)).join(''), true)
        .replace(new RegExp(`${SP}+`, 'g'), ' ')
        .replace(/ ((?:<\/[^>]+>)+)/g, '$1 ')
        .replace(new RegExp(`${SP}+(?=[,;:)]|\\.(?:${SP}|<|$))`, 'g'), '')
        .replace(new RegExp(`(?<=[\\p{L}>])${SP}+(?=\\?)`, 'gu'), '')
        .replace(new RegExp(`\\(${SP}+`, 'g'), '(')
        .replace(/`/g, '‘')
        .replace(new RegExp(`(?<=<\\/span>)${SP}*'`, 'g'), '’')
        .replace(new RegExp(`‘((?:<[^>]+>)*)${SP}+`, 'g'), '‘$1'));
    }

    // Grammar headers and notes run abbreviations together ("ā,f.").
    renderLabel(nodes) {
      return this.render(nodes).replace(/,(?=\p{L}|<)/gu, ', ');
    }

    textNode(s) {
      return this.doc.createTextNode(s);
    }

    withoutTrailingSeparators(nodes) {
      nodes = nodes.slice();
      while (nodes.length && isText(nodes[nodes.length - 1]) && new RegExp(`^[${SP.slice(1, -1)},.;:]*$`).test(nodes[nodes.length - 1].data)) nodes.pop();
      if (nodes.length && isText(nodes[nodes.length - 1])) {
        const last = nodes.pop();
        nodes.push(this.textNode(last.data.replace(new RegExp(`[${SP.slice(1, -1)},.;:]+$`), '')));
      }
      return nodes;
    }

    // Where a line starts with a shortened reference, show its source
    // title in grey ("Wb. 12d44" rather than "12d44").
    hintOrphans(bibls) {
      const first = bibls[0];
      if (!first || first.getElementsByTagName('title').length) return;
      const scope = first.getElementsByTagName('orphanScope')[0];
      const title = scope && this.titles[scope.getAttribute('target')];
      if (!title) return;
      const hint = this.doc.createElement('hint');
      hint.textContent = `${title} `;
      first.insertBefore(hint, first.firstChild);
    }

    // Natural break: nothing yet, a reference, or text ending in . : ; ) ? !
    // (ignoring a trailing "cf." aside).
    atPause(nodes) {
      const sig = nodes.filter((n) => !blank(n));
      while (sig.length && isEl(sig[sig.length - 1], 'lbl')) sig.pop();
      const last = sig[sig.length - 1];
      if (!last || isEl(last, 'bibl')) return true;
      return /[.:;)?!]$/.test(strip(textOf(last)));
    }

    // "(b)" or "b" in bold: the letter of a sense or sub-sense.
    senseLetter(node) {
      return isEl(node, 'b') && /^\(?[a-z0-9]{1,4}\)?$/i.test(strip(node.textContent));
    }

    // ---- Grammar block: rows, text kept in source order ----

    grammarRows(p) {
      const rows = [{ kind: 'head', label: [], nodes: [], closed: false }];
      let depth = 0;
      let carry = null;
      const add = (row) => {
        if (carry !== null) row.nodes.unshift(this.textNode(carry));
        carry = null;
        rows.push(row);
      };
      for (const n of Array.from(p.childNodes)) {
        const cur = rows[rows.length - 1];
        if (n.nodeType === 1 && FORM_LABELS.includes(n.nodeName) && depth === 0) {
          if (cur.kind === 'row' && !cur.closed && allBlank(cur.nodes)) {
            cur.label.push(n);
            continue;
          } else if (cur.closed || this.atPause(cur.nodes)) {
            add({ kind: 'row', label: [n], nodes: [], closed: false });
            continue;
          }
        }
        if (isEl(n, 'pos') && strip(n.textContent) === '') continue;

        if (isText(n)) {
          const t = n.data;
          if (cur.kind === 'row' && allBlank(cur.nodes) && !cur.closed && !HAS_LETTER.test(t)) {
            cur.label.push(n);
            continue;
          }
          const stop = firstStop(t, depth);
          depth = Math.max(depth + parenDelta(t), 0);
          const nextEl = n.nextElementSibling;
          if (stop !== null && cur.kind !== 'head' && !cur.closed && hasRefs(cur.nodes) && !isEl(nextEl, 'bibl')) {
            cur.nodes.push(this.textNode(t.slice(0, stop + 1)));
            cur.closed = true;
            const rest = lstrip(t.slice(stop + 1));
            if (HAS_LETTER.test(rest)) add({ kind: 'more', label: [], nodes: [this.textNode(rest)], closed: false });
            else if (strip(rest) !== '') carry = rest;
            continue;
          }
        }
        if (cur.closed) {
          if (!blank(n)) add({ kind: 'more', label: [], nodes: [n], closed: false });
        } else {
          cur.nodes.push(n);
        }
      }
      return rows.filter((r) => !(allBlank(r.nodes) && r.label.length === 0));
    }

    grammarHtml(p) {
      let html = '';
      let table = false;
      for (const r of this.grammarRows(p)) {
        this.hintOrphans(r.nodes.filter((n) => isEl(n, 'bibl')));
        if (r.kind === 'head') {
          html += `<div class="gram-head">${this.renderLabel(r.nodes)}</div>`;
          continue;
        }
        if (!table) html += '<table class="grammar">';
        table = true;
        const content = this.render(this.withoutTrailingSeparators(r.nodes));
        const form = r.nodes.some((n) => isEl(n, 'oVar') || isEl(n, 'q'));
        html += r.kind === 'more' && !form
          ? `<tr><td colspan="2" class="gram-note">${this.renderLabel(r.nodes)}</td></tr>`
          : `<tr><td class="gram-label">${this.renderLabel(r.label)}</td><td class="gram-form">${content}</td></tr>`;
      }
      if (table) html += '</table>';
      return html;
    }

    // ---- Senses: intro, notes and one line per example ----

    segment(p) {
      const units = [{ type: 'intro', nodes: [], closed: false }];
      let carry = null;
      const add = (unit) => {
        if (carry !== null) unit.nodes.unshift(this.textNode(carry));
        carry = null;
        units.push(unit);
      };
      const bracketDepth = (u) => u.nodes.filter(isText).reduce((s, n) => s + parenDelta(n.data), 0);
      const afterReference = (u) => {
        const sig = u.nodes.filter((n) => !blank(n));
        const last = sig[sig.length - 1];
        const before = sig[sig.length - 2];
        if (isEl(last, 'bibl')) return true;
        return last != null && isText(last) && strip(last.data) === ',' && isEl(before, 'bibl');
      };
      const takeTrailingLabel = (u) => {
        let idx = -1;
        for (let k = u.nodes.length - 1; k >= 0; k--) if (!blank(u.nodes[k])) { idx = k; break; }
        if (idx < 0 || !isEl(u.nodes[idx], 'lbl')) return [];
        return u.nodes.splice(idx).filter((n) => !blank(n));
      };

      for (const n of Array.from(p.childNodes)) {
        const cur = units[units.length - 1];
        if (isText(n)) {
          const t = n.data;
          const next = n.nextElementSibling;
          const beforeHeading = (next != null && LABELS.includes(next.nodeName) && new RegExp(`[.;]${SP}*$`).test(t)) ||
            (this.senseLetter(next) && new RegExp(`[.;]${SP}*\\(?${SP}*$`).test(t));
          let i = firstStop(t, bracketDepth(cur));
          if (i === null && beforeHeading) {
            const last = Math.max(t.lastIndexOf('.'), t.lastIndexOf(';'));
            i = last < 0 ? null : last;
          }
          if (cur.type === 'citation' && !cur.closed && (hasRefs(cur.nodes) || beforeHeading) && i !== null) {
            cur.nodes.push(this.textNode(t.slice(0, i + 1)));
            cur.closed = true;
            const rest = lstrip(t.slice(i + 1));
            if (HAS_LETTER.test(rest)) add({ type: 'note', nodes: [this.textNode(rest)], closed: false });
            else if (strip(rest) !== '') carry = rest;
          } else if (cur.closed) {
            if (HAS_LETTER.test(t)) add({ type: 'note', nodes: [n], closed: false });
            else if (strip(t) !== '') carry = `${carry || ''}${t}`;
          } else {
            cur.nodes.push(n);
          }
        } else if (isEl(n, 'q') && cur.type !== 'citation' && !cur.closed && !this.atPause(cur.nodes)) {
          // A form quoted mid-sentence: the line is prose, not a heading.
          cur.nodes.push(n);
          cur.type = 'intro';
        } else if (isEl(n, 'q') && (cur.type !== 'citation' || cur.closed)) {
          const label = takeTrailingLabel(cur);
          if (label.length) label.push(this.textNode(' '));
          add({ type: 'citation', nodes: label.concat([n]), closed: false });
        } else if (isEl(n, 'q') && afterReference(cur)) {
          // A quotation straight after a reference is a new example.
          cur.closed = true;
          add({ type: 'citation', nodes: [n], closed: false });
        } else if (cur.closed && isEl(n, 'bibl') && cur.type === 'citation' && carry === null) {
          // More references after the full stop belong to the same example.
          cur.closed = false;
          cur.nodes.push(this.textNode(' '), n);
        } else if (cur.closed) {
          let type = 'citation';
          if (this.senseLetter(n)) type = 'intro';
          else if (LABELS.includes(n.nodeName) || (n.nodeName === 'trans' && n.getElementsByTagName('def').length)) type = 'note';
          add({ type, nodes: [n], closed: false });
        } else {
          cur.nodes.push(n);
        }
      }
      return units.filter((u) => !allBlank(u.nodes));
    }

    senseHtml(p) {
      let html = '';
      let listOpen = false;
      for (const u of this.segment(p)) {
        this.hintOrphans(u.nodes.filter((n) => isEl(n, 'bibl')));
        if (u.type === 'citation') {
          if (!listOpen) html += '<ul class="cites">';
          listOpen = true;
          html += `<li class="cite">${this.render(u.nodes).replace(/[,;]$/, '')}</li>`;
        } else {
          if (listOpen) html += '</ul>';
          listOpen = false;
          html += `<div class="${u.type}">${this.render(u.nodes)}</div>`;
        }
      }
      if (listOpen) html += '</ul>';
      return html;
    }
  }

  // Entry i laid out; falls back to the plain rendering if the browser
  // can't parse the entry.
  function layoutEntry(i) {
    try {
      return new EntryLayout(entryXml[i]).html();
    } catch (e) {
      console.warn(`eDIL: entry ${i + 1} shown unformatted (${e.message})`);
      return toHtml(entryXml[i], true);
    }
  }

  // The printed text of a section: Map(column -> [{n, html}]). Elements open
  // at the end of a line are closed there and reopened on the next line.
  function columnsOf(si) {
    if (columnCache[si]) return columnCache[si];
    const cols = new Map();
    const stack = [];
    let cur = null;
    const finish = () => {
      cur.html += stack.slice().reverse().map((s) => s[2]).join('');
      if (!cols.has(cur.col)) cols.set(cur.col, []);
      cols.get(cur.col).push(cur);
    };
    walk(D.sections[si].parts.join(''), stack, (kind, html, attrs) => {
      if (kind === 'br') {
        if (cur) finish();
        cur = { col: +attrs.column, n: +attrs.line, html: stack.map((s) => s[1]).join('') };
      } else if (cur) {
        cur.html += html;
      }
    });
    if (cur) finish();
    return (columnCache[si] = cols);
  }

  // ---- Data ----

  async function loadData() {
    const b64 = window.EDIL_DATA;
    if (!b64) throw new Error('data.js is missing or empty. Run bin/build-static to create it.');
    delete window.EDIL_DATA;
    const bin = atob(b64);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'));
    return JSON.parse(await new Response(stream).text());
  }

  function index(data) {
    D = data;
    const E = D.entries;
    D.sections.forEach((s, i) => { sectionIndex[s.name] = i; });
    const seen = D.sections.map(() => 0);
    entryXml = E.label.map((_, i) => {
      const si = E.section[i];
      const x = E.xmlId[i];
      if (x && !(x in targets)) targets[x] = i + 1;
      return D.sections[si].parts[2 * seen[si]++ + 1];
    });
  }

  const count = () => D.entries.label.length;
  const sectionName = (i) => D.sections[D.entries.section[i]].name;

  // ---- Search (mirrors Dictionary#search / #search_definitions) ----

  function searchHeadwords(query, limit = 200) {
    const q = headwordKey(query);
    if (!q) return [];
    const exact = [];
    const prefix = [];
    D.entries.key.forEach((k, i) => {
      if (k === q) exact.push(i);
      else if (k.startsWith(q)) prefix.push(i);
    });
    return exact.concat(prefix).slice(0, limit);
  }

  function searchDefinitions(query, limit = 200) {
    const q = normalize(query);
    if (!q) return [];
    defsKeys = defsKeys || D.entries.defs.map((ds) => ' ' + ds.map(normalize).join(' | '));
    const out = [];
    for (let i = 0; i < defsKeys.length && out.length < limit; i++) {
      if (defsKeys[i].includes(' ' + q)) out.push(i);
    }
    return out;
  }

  // ---- Links ----

  const entryHref = (i) => `#/entries/${i + 1}`;
  const columnHref = (section, col) => `#/columns/${encodeURIComponent(section)}/${col}`;
  const sourceHref = (t) => `#/bibliography/${encodeURIComponent(D.titles[t])}`;
  const entryLink = (i) => `<a href="${entryHref(i)}">${esc(D.entries.label[i])}</a>`;

  // ---- Pages (mirror views/*.erb) ----

  const notFound = () => ({
    title: 'Not found',
    html: '<h1>Not found</h1><p>That page doesn\'t exist. Try the <a href="#/search">search</a> or <a href="#/columns">browse by column</a>.</p>'
  });

  function sectionButtons(current, href) {
    return '<p class="section-links">' + D.sections.map((s) =>
      `<a class="btn btn-small${s.name === current ? ' active' : ''}" href="${href(s.name)}">${esc(s.name)}</a>`
    ).join(' ') + '</p>';
  }

  function columnPage(section, number, line) {
    const si = sectionIndex[section];
    if (si === undefined) return notFound();
    const cols = D.sections[si].cols;
    const has = (c) => cols.includes(c);
    let n = number;
    if (!has(n)) return notFound();
    if (n % 2 === 0 && has(n - 1)) n -= 1;
    const right = has(n + 1) ? n + 1 : null;

    let prev = null;
    let next = null;
    if (has(n - 2)) {
      prev = [section, n - 2];
    } else if (si > 0) {
      const s = D.sections[si - 1];
      const last = s.cols[s.cols.length - 1];
      prev = [s.name, last % 2 === 0 ? last - 1 : last];
    }
    if (has(n + 2)) next = [section, n + 2];
    else if (si + 1 < D.sections.length) next = [D.sections[si + 1].name, D.sections[si + 1].cols[0]];

    const progress = Math.round((cols.indexOf(right || n) + 1) * 100 / cols.length);
    const highlight = line ? `c${number}l${line}` : null;
    const heading = right ? `columns ${n} & ${right}` : `column ${n}`;
    const lines = columnsOf(si);

    let html = `<div class="row"><div class="span8"><h1>${esc(section)} <small>${heading}</small></h1></div>
      <div class="span4 column-nav">
        <div class="progress progress-striped"><div class="bar" style="width: ${progress}%"></div></div>
        <div class="btn-group">`;
    if (prev) html += `<a class="btn" href="${columnHref(...prev)}">&larr; Previous</a>`;
    if (next) html += `<a class="btn" href="${columnHref(...next)}">Next &rarr;</a>`;
    html += '</div></div></div><div class="row page">';
    for (const col of [n, right]) {
      if (col === null) continue;
      html += '<div class="span6 column"><ol>';
      for (const l of lines.get(col) || []) {
        const anchor = `c${col}l${l.n}`;
        html += `<li id="${anchor}" value="${l.n}"${anchor === highlight ? ' class="highlight"' : ''}><p>${l.html}</p></li>`;
      }
      html += '</ol></div>';
    }
    html += '</div>';
    return { title: `${section}: ${heading}`, html };
  }

  function columnsIndexPage() {
    if (!firstEntry) {
      firstEntry = new Map();
      D.entries.col.forEach((c, i) => {
        const k = `${D.entries.section[i]}:${c}`;
        if (c !== null && !firstEntry.has(k)) firstEntry.set(k, i);
      });
    }
    let html = '<h1>Browse by column</h1><p class="section-links">' +
      D.sections.map((s) => `<a class="btn btn-small" href="#/columns#section-${esc(s.name)}" data-scroll="section-${esc(s.name)}">${esc(s.name)}</a>`).join(' ') + '</p>';
    D.sections.forEach((s, si) => {
      html += `<h2 id="section-${esc(s.name)}">${esc(s.name)}</h2><ul class="column-index">`;
      for (let j = 0; j < s.cols.length; j += 2) {
        const left = s.cols[j];
        const right = s.cols[j + 1];
        const e = firstEntry.get(`${si}:${left}`);
        html += `<li><a href="${columnHref(s.name, left)}">${right !== undefined ? `${left}–${right}` : left}</a>` +
          (e !== undefined ? ` <span class="muted">${esc(D.entries.label[e])}</span>` : '') + '</li>';
      }
      html += '</ul>';
    });
    return { title: 'Browse', html };
  }

  function entriesPage(section) {
    const name = sectionIndex[section] !== undefined ? section : D.sections[0].name;
    const si = sectionIndex[name];
    const items = [];
    D.entries.section.forEach((s, i) => { if (s === si) items.push(`<li>${entryLink(i)}</li>`); });
    return {
      title: `Headwords: ${name}`,
      html: `<h1>Headwords <small>${items.length} entries in ${esc(name)}</small></h1>` +
        sectionButtons(name, (s) => `#/entries?section=${encodeURIComponent(s)}`) +
        `<ul class="headword-index">${items.join('')}</ul>`
    };
  }

  // For a "see X" entry, the entries it points to, each in a box under it;
  // a target that is itself a "see" entry is followed, up to three steps.
  // D.entries.see[i] lists targets as [id, nearest, id, nearest, ...].
  function seeAlsoHtml(i, depth = 1, seen = [i + 1]) {
    if (depth > 3) return '';
    const see = D.entries.see[i];
    let html = '';
    for (let k = 0; k < see.length; k += 2) {
      const id = see[k];
      if (seen.includes(id)) continue;
      const note = see[k + 1] ? ' <span class="muted">· nearest match: the headword is spelled differently</span>' : '';
      html += `<div class="see-also"><div class="see-also-head">↳ <a class="see-also-label" href="${entryHref(id - 1)}">${esc(D.entries.label[id - 1])}</a>${note}</div>` +
        `<div class="see-also-body">${layoutEntry(id - 1)}${seeAlsoHtml(id - 1, depth + 1, seen.concat([id]))}</div></div>`;
    }
    return html;
  }

  function entryPage(id) {
    const i = id - 1;
    const E = D.entries;
    if (!(i >= 0 && i < count())) return notFound();
    let html = `<div class="row"><div class="span8"><h1>${esc(E.label[i])}</h1></div>
      <div class="span4 entry-nav"><div class="btn-group pull-right">`;
    if (i > 0) html += `<a class="btn" href="${entryHref(i - 1)}" title="${esc(E.label[i - 1])}">&larr; Prev</a>`;
    if (i + 1 < count()) html += `<a class="btn" href="${entryHref(i + 1)}" title="${esc(E.label[i + 1])}">Next &rarr;</a>`;
    html += `</div></div></div><div class="entry-body layout-a">${layoutEntry(i)}${seeAlsoHtml(i)}</div>`;
    if (E.col[i] !== null) {
      const sec = sectionName(i);
      html += `<p class="muted">Printed edition: <a href="${columnHref(sec, E.col[i])}?line=${E.line[i]}">` +
        `${esc(sec)}, column ${E.col[i]}, line ${E.line[i]}</a></p>`;
    }
    const list = (title, items) => `<dl class="span4"><dt>${title}</dt>${items.map((x) => `<dd>${x}</dd>`).join('')}</dl>`;
    html += '<div class="row">' +
      list('Part of speech', E.pos[i].map((p) => esc(D.posNames[p]))) +
      list('Definitions', E.defs[i].map(esc)) +
      list('Bibliographic references', E.bibls[i].map((t) => `<a href="${sourceHref(t)}">${esc(D.titles[t])}</a>`)) +
      '</div>';
    return { title: E.label[i], html };
  }

  function searchPage(query, where) {
    const inDefs = where === 'definitions';
    const results = inDefs ? searchDefinitions(query) : searchHeadwords(query);
    if (!inDefs) {
      const k = headwordKey(query);
      const exact = results.filter((i) => D.entries.key[i] === k);
      if (exact.length === 1) return { redirect: entryHref(exact[0]) };
    }
    let html = `<h1>Search</h1>
      <form class="form-search search-page">
        <input type="text" name="q" class="input-xlarge search-query" value="${esc(query)}" autofocus>
        <label class="radio inline"><input type="radio" name="in" value="headwords"${inDefs ? '' : ' checked'}> Headwords</label>
        <label class="radio inline"><input type="radio" name="in" value="definitions"${inDefs ? ' checked' : ''}> Definitions</label>
        <button type="submit" class="btn">Search</button>
      </form>`;
    if (query.trim()) {
      const n = results.length;
      html += `<p>${n}${n === 200 ? '+' : ''} ${n === 1 ? 'result' : 'results'} for <strong>${esc(query)}</strong> in ${inDefs ? 'definitions' : 'headwords'}.</p><ul class="results">`;
      for (const i of results) {
        const defs = D.entries.defs[i];
        html += `<li>${entryLink(i)}${defs.length ? ` <span class="muted">— ${esc(defs.slice(0, 3).join('; '))}</span>` : ''}</li>`;
      }
      html += '</ul>';
    }
    return { title: 'Search', html };
  }

  function sources() {
    if (!sourceEntries) {
      sourceEntries = D.titles.map(() => []);
      D.entries.bibls.forEach((ts, i) => ts.forEach((t) => sourceEntries[t].push(i)));
    }
    return sourceEntries;
  }

  function bibliographyPage() {
    const src = sources();
    return {
      title: 'Bibliography',
      html: `<h1>Bibliography <small>${D.titles.length} sources cited</small></h1><ul class="bibliography">` +
        D.titles.map((t, k) => `<li><a href="${sourceHref(k)}">${esc(t)}</a> <span class="muted">(${src[k].length})</span></li>`).join('') +
        '</ul>'
    };
  }

  function sourcePage(title) {
    const k = D.titles.indexOf(title);
    if (k < 0) return notFound();
    const list = sources()[k];
    return {
      title,
      html: `<h1>${esc(title)} <small>cited in ${list.length} ${list.length === 1 ? 'entry' : 'entries'}</small></h1>` +
        `<ul class="headword-index">${list.map((i) => `<li>${entryLink(i)}</li>`).join('')}</ul>`
    };
  }

  const aboutPage = () => ({ title: 'About', html: document.getElementById('about-page').innerHTML });

  const contactPage = () => ({
    title: 'Contact',
    html: '<h1>Contact</h1><p>This is a local, browser-only reconstruction of the 2012 eDIL prototype ' +
      '(<a href="https://github.com/e-dil/eDIL">github.com/e-dil/eDIL</a>), using the XML from ' +
      '<a href="https://github.com/e-dil/dil">github.com/e-dil/dil</a>.</p>'
  });

  // ---- Router ----

  function page(path, params) {
    const p = path.split('/').filter(Boolean).map(decodeURIComponent);
    switch (p[0]) {
      case undefined: return { redirect: columnHref(D.sections[0].name, D.sections[0].cols[0]) };
      case 'browse': return { redirect: '#/columns' };
      case 'columns':
        return p.length === 1 ? columnsIndexPage() : columnPage(p[1], parseInt(p[2], 10), params.get('line'));
      case 'entries':
        return p.length === 1 ? entriesPage(params.get('section')) : entryPage(parseInt(p[1], 10));
      case 'search': return searchPage(params.get('q') || '', params.get('in'));
      case 'bibliography': return p.length === 1 ? bibliographyPage() : sourcePage(p[1]);
      case 'about': return aboutPage();
      case 'contact': return contactPage();
      default: return notFound();
    }
  }

  function route() {
    const hash = location.hash.replace(/^#/, '');
    const [path, query] = hash.split('?');
    const params = new URLSearchParams(query || '');
    const result = page(path || '/', params);
    if (result.redirect) { location.replace(result.redirect); return; }
    document.getElementById('site').innerHTML = result.html;
    document.title = `${result.title ? result.title + ' · ' : ''}Dictionary of the Irish Language`;
    const hl = document.querySelector('li.highlight');
    if (hl) window.scrollTo(0, hl.getBoundingClientRect().top + window.scrollY - 120);
    else window.scrollTo(0, 0);
  }

  // ---- Search box ----

  function search(query, where) {
    let hash = `#/search?q=${encodeURIComponent(query)}`;
    if (where === 'definitions') hash += '&in=definitions';
    location.hash = hash;
  }

  // Headword typeahead (Bootstrap 2): accent-insensitive, matches the start
  // of the headword. Picking a suggestion opens it; Enter searches the text.
  function setUpTypeahead() {
    const $box = $('#nav-search .typeahead');
    const labels = [];
    const byLabel = Object.create(null);
    D.entries.label.forEach((l, i) => {
      let label = l;
      let n = 2;
      while (byLabel[label]) label = `${l} (${n++})`;
      labels.push(label);
      byLabel[label] = { key: D.entries.key[i], i };
    });

    $box.typeahead({
      source: labels,
      items: 10,
      matcher(item) {
        const q = headwordKey(this.query);
        return q.length > 0 && byLabel[item].key.startsWith(q);
      },
      sorter(items) {
        const q = headwordKey(this.query);
        return items.sort((a, b) => {
          const A = byLabel[a];
          const B = byLabel[b];
          return (B.key === q) - (A.key === q) || A.key.length - B.key.length || A.i - B.i;
        });
      },
      highlighter: (item) => esc(item),
      updater(item) {
        location.hash = entryHref(byLabel[item].i);
        return item;
      }
    });

    const ta = $box.data('typeahead');
    const render = ta.render;
    ta.render = function (items) {
      render.call(this, items);
      this.$menu.find('.active').removeClass('active');
      return this;
    };
    const select = ta.select;
    ta.select = function () {
      if (this.$menu.find('.active').length) return select.call(this);
      this.hide();
      search($box.val(), 'headwords');
      return this;
    };
    $box.on('input', () => ta.lookup());
  }

  function setUpForms() {
    $('#nav-search').on('submit', (e) => {
      e.preventDefault();
      search($(e.target).find('input[name=q]').val(), 'headwords');
    });
    $(document).on('submit', 'form.search-page', (e) => {
      e.preventDefault();
      const $f = $(e.target);
      search($f.find('input[name=q]').val(), $f.find('input[name=in]:checked').val());
    });
    // In-page jumps on the Browse page (a second # would break the router).
    $(document).on('click', 'a[data-scroll]', (e) => {
      e.preventDefault();
      const target = document.getElementById(e.currentTarget.dataset.scroll);
      if (target) window.scrollTo(0, target.getBoundingClientRect().top + window.scrollY - 60);
    });
  }

  // ---- Start ----

  const started = performance.now();
  loadData().then((data) => {
    index(data);
    console.log(`eDIL: ${count()} entries ready in ${Math.round(performance.now() - started)} ms`);
    setUpForms();
    setUpTypeahead();
    window.addEventListener('hashchange', route);
    route();
    // For test/layout_parity.rb: an entry's laid-out HTML, by entry id.
    window.edilLayout = (id) => layoutEntry(id - 1);
  }).catch((err) => {
    document.getElementById('site').innerHTML =
      `<h1>Couldn't load the dictionary</h1><p>${esc(err.message)}</p>` +
      '<p>This page needs a recent browser (Chrome, Edge, Firefox or Safari from 2023 on).</p>';
    console.error(err);
  });
}());
