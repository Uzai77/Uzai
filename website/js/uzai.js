/* Uzai website: bedient sich wie Uzai (docs/DESIGN.md › Bewegung, Bedienung).
   Maus, Tastatur und Controller (Gamepad-API) gehen durch dieselbe Navigation. Kein Framework,
   keine Anfrage ins Netz, nichts wird gespeichert außer den Guide-Einstellungen für diesen Tab. */
(() => {
  'use strict';

  const d = document;
  const html = d.documentElement;
  const $ = (s, r = d) => r.querySelector(s);
  const $$ = (s, r = d) => Array.from(r.querySelectorAll(s));
  const CFG = Object.assign({
    REPO: 'https://github.com/Uzai77/Uzai',
    DOWNLOAD: 'https://github.com/Uzai77/Uzai/releases/latest',
  }, window.UZAI_CONFIG || {});

  // --- Takt (src/ui/u.gd): fünf Zeiten mit Bedeutung, Wege in logischen Punkten ---------------
  const T = { antwort: 90, weg: 160, ort: 200, raum: 360, licht: 800 };
  const W = { anstoss: 6, ort: 24, bereich: 56, leiste: 72, nach: 26 };
  const STAFFEL = 30;
  const STAFFEL_MAX = 4;
  const NACH_WEG = 17;
  const NACH_FLAECHE = 40;
  const E = {
    an: 'cubic-bezier(.33,1,.68,1)',          // Ankommen: ease-out cubic
    raum: 'cubic-bezier(.25,1,.5,1)',         // ab T_RAUM: quart
    weg: 'cubic-bezier(.5,1,.89,1)',          // Gehen: ease-out quad
    kreuz: 'cubic-bezier(.37,0,.63,1)',       // Kreuzen: sine in-out
    hinaus: 'cubic-bezier(.5,0,.75,0)',       // nur für Wege ganz aus dem Bild
    flug: 'cubic-bezier(.16,1,.3,1)',         // geteilte Elemente: nach 0,3 s gut 95 % da
    reise: 'cubic-bezier(.5,0,.15,1)',        // geteilte Elemente quer über den Schirm: sanft los, weich an
  };
  const AREAS = ['home', 'features', 'get', 'privacy'];
  const ACCENT = '#a47bff';
  const FOCUSABLE = 'a[href], button:not([disabled]), summary, [tabindex="0"]';

  const mqConsole = matchMedia('(min-width: 900px) and (min-height: 560px)');
  const mqReduce = matchMedia('(prefers-reduced-motion: reduce)');
  const store = {
    get(key) { try { return sessionStorage.getItem('uzai-' + key); } catch (e) { return null; } },
    set(key, v) { try { sessionStorage.setItem('uzai-' + key, v); } catch (e) { /* ohne Speicher geht es auch */ } },
  };

  const S = {
    area: 'home', // jedes Laden beginnt auf Home (Kopfskript in index.html)
    input: 'mouse',
    pad: 'xbox',
    padName: '',
    glyphs: store.get('glyphs') || 'auto',
    motion: store.get('motion') || 'auto',
    sound: store.get('sound') === 'on',
    layer: null,
    booting: false,
    remember: {},
    feature: null,
    back: null,
  };

  const isConsole = () => mqConsole.matches;
  const calm = () => S.motion === 'reduced' || (S.motion === 'auto' && mqReduce.matches);
  const kpx = () => parseFloat(getComputedStyle(html).getPropertyValue('--k')) || 0.8;
  const dur = ms => (calm() ? Math.round(ms / 2) : ms);
  const way = px => (calm() ? 0 : px * kpx());
  const staffel = i => (calm() ? 0 : Math.min(i, STAFFEL_MAX - 1) * STAFFEL);

  const markEl = $('.mark');
  const barEl = $('.bar');
  const tabsEl = $('.tabs');
  const mainEl = $('#main');
  const hintsEl = $('.hints');
  const veil = $('.veil');
  const guide = $('#guide');
  const quick = $('.quick');
  const detail = $('.detail');
  const shelf = $('.shelf');
  const tabs = $$('.tab');
  const items = $$('.shelf .card, .shelf .more');
  const cards = $$('.shelf .card');
  const chips = $$('.chip');
  const gtabs = $$('.gtab');
  const gpanes = $$('.guide-pane');
  const areaEl = a => d.getElementById(a);
  const tabFor = a => tabs.find(t => t.dataset.area === a);

  // --- Laufende Bewegungen werden ersetzt, nie gestapelt (U.tw) --------------------------------
  const laeuft = new WeakMap();
  function play(el, key, frames, opts) {
    let m = laeuft.get(el);
    if (!m) laeuft.set(el, (m = {}));
    if (m[key]) m[key].cancel();
    const a = el.animate(frames, Object.assign({ fill: 'both' }, opts));
    m[key] = a;
    a.finished.then(() => { if (m[key] === a) { delete m[key]; a.cancel(); } }, () => {});
    return a;
  }
  function stopAll(el) {
    const m = laeuft.get(el);
    if (!m) return;
    for (const k of Object.keys(m)) m[k].cancel();
    laeuft.set(el, {});
  }
  const tweens = {};
  function tween(a, b, ms, cb, key) {
    if (tweens[key]) cancelAnimationFrame(tweens[key].raf);
    if (ms <= 0) { cb(b); return; }
    const t0 = performance.now();
    const tw = (tweens[key] = { raf: 0 });
    const step = now => {
      const t = Math.min(1, (now - t0) / ms);
      cb(a + (b - a) * (1 - Math.pow(1 - t, 3)));
      if (t < 1) tw.raf = requestAnimationFrame(step);
      else delete tweens[key];
    };
    tw.raf = requestAnimationFrame(step);
  }

  // --- Klang: Uzais echte Handpan-Klänge (assets/sounds/handpan, fürs Web als MP3 in sounds/) ------
  // Aus, bis man ihn anschaltet; geladen wird erst dann (ein Druck ist nötig, damit der Browser spielt).
  const Klang = (() => {
    let ctx = null;
    let out = null;
    const puffer = {};
    const NAMEN = ['move', 'select', 'back', 'tab', 'guide', 'guide_close', 'bump', 'notify', 'unlock', 'unlock_rare', 'power_off', 'boot', 'done'];
    const ALIAS = { raste: 'tab', open: 'guide', close: 'guide_close' };
    // MP3 beginnt mit ein paar Millisekunden Stille (Kodierer): gespielt wird ab dem ersten Ton.
    function beginn(buf) {
      const dd = buf.getChannelData(0);
      for (let i = 0; i < dd.length; i++) if (Math.abs(dd[i]) > 0.002) return Math.max(0, i - 24) / buf.sampleRate;
      return 0;
    }
    function init() {
      if (ctx) return true;
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return false;
      try { ctx = new AC(); } catch (e) { return false; }
      out = ctx.createGain();
      out.gain.value = 0.8;
      out.connect(ctx.destination);
      NAMEN.forEach(n => {
        fetch(`sounds/${n}.mp3`).then(r => r.arrayBuffer()).then(b => ctx.decodeAudioData(b))
          .then(buf => { puffer[n] = { buf, ab: beginn(buf) }; }, () => {});
      });
      return true;
    }
    function spiel(name, o = {}) {
      if (!S.sound || !ctx) return;
      if (ctx.state === 'suspended') ctx.resume();
      const p = puffer[ALIAS[name] || name];
      if (!p) return;
      const src = ctx.createBufferSource();
      src.buffer = p.buf;
      if (o.rate) src.playbackRate.value = o.rate;
      const g = ctx.createGain();
      g.gain.value = o.vol === undefined ? 1 : o.vol;
      src.connect(g);
      g.connect(out);
      src.start(ctx.currentTime + (o.at || 0), p.ab);
    }
    return { init, spiel };
  })();
  const klang = (name, o) => Klang.spiel(name, o);

  // --- Tastensymbole: folgen dem zuletzt benutzten Gerät (src/ui/components/glyph.gd) ---------
  const GLYPH = {
    keys: { a: 'Enter', b: 'Esc', x: 'X', y: 'Y', lb: 'Q', rb: 'E', lt: 'PgUp', rt: 'PgDn', guide: 'G', menu: 'M', view: 'V', r3: 'F' },
    xbox: { a: 'A', b: 'B', x: 'X', y: 'Y', lb: 'LB', rb: 'RB', lt: 'LT', rt: 'RT', r3: 'RS' },
    ps: { lb: 'L1', rb: 'R1', lt: 'L2', rt: 'R2', r3: 'R3' },
    nintendo: { a: 'A', b: 'B', x: 'X', y: 'Y', lb: 'L', rb: 'R', lt: 'ZL', rt: 'ZR', r3: 'RS' },
  };
  const ZEICHEN = {
    a: '<path d="M7.6 7.6l8.8 8.8M16.4 7.6l-8.8 8.8"/>',
    b: '<circle cx="12" cy="12" r="5.6"/>',
    x: '<rect x="6.7" y="6.7" width="10.6" height="10.6" rx="1"/>',
    y: '<path d="M12 6.3 18.1 16.5H5.9Z"/>',
    menu: '<path d="M6.5 8h11M6.5 12h11M6.5 16h11"/>',
    view: '<rect x="5" y="5" width="10" height="10" rx="2"/><path d="M9 19h8a2 2 0 0 0 2-2V9"/>',
    lr: '<path d="M8.5 7.5 4 12l4.5 4.5M15.5 7.5 20 12l-4.5 4.5"/>',
    ud: '<path d="M7.5 8.5 12 4l4.5 4.5M7.5 15.5 12 20l4.5-4.5"/>',
    guide: '<path class="u-mini" d="M7.6 5.4v6.9a4.4 4.4 0 0 0 8.8 0V5.4"/>',
  };
  const svgG = body => `<svg viewBox="0 0 24 24" aria-hidden="true">${body}</svg>`;
  const glyphSet = () => (S.glyphs !== 'auto' ? S.glyphs : S.input === 'pad' ? S.pad : 'keys');
  const SCHULTER = ['lb', 'rb', 'lt', 'rt', 'r3'];
  function renderGlyph(el) {
    const k = el.dataset.k;
    const set = glyphSet();
    if (el.dataset.base === undefined) el.dataset.base = el.className.replace(/\b(g|key|sh)\b/g, '').trim();
    let art = '';
    let inner;
    if (set === 'keys') {
      art = 'key';
      inner = ZEICHEN[k] && (k === 'lr' || k === 'ud') ? svgG(ZEICHEN[k]) : GLYPH.keys[k] || k.toUpperCase();
    } else if (k === 'guide' || k === 'lr' || k === 'ud' || k === 'menu' || k === 'view') {
      inner = svgG(ZEICHEN[k]);
    } else if (SCHULTER.includes(k)) {
      art = 'sh';
      inner = GLYPH[set][k] || GLYPH.xbox[k];
    } else if (set === 'ps') {
      inner = svgG(ZEICHEN[k]);
    } else {
      inner = (GLYPH[set] && GLYPH[set][k]) || k.toUpperCase();
    }
    el.className = ['g', art, el.dataset.base].filter(Boolean).join(' ');
    el.innerHTML = inner;
  }
  function alleGlyphen() { $$('[data-k]').forEach(renderGlyph); }

  // --- Hinweisleiste: Glyphe und ein Wort, höchstens vier, B zuletzt -------------------------
  function hintHTML(list) {
    return list.map(h => `<button type="button" class="hint" tabindex="-1" data-act="${h.act}">${h.k.split(' ').map(k => `<span class="g" data-k="${k}"></span>`).join('')}<span>${h.t}</span></button>`).join('');
  }
  function setHints(el, list) {
    const key = JSON.stringify(list) + glyphSet();
    if (el._key === key) return;
    const alt = el._list || [];
    el._key = key;
    el._list = list;
    el.innerHTML = hintHTML(list);
    $$('.g', el).forEach(renderGlyph);
    $$('.hint', el).forEach((b, i) => {
      const o = alt[i];
      const n = list[i];
      if (!o || o.k !== n.k || o.t !== n.t) b.animate([{ opacity: 0 }, { opacity: 1 }], { duration: dur(T.ort), easing: E.an });
    });
  }
  function hintFor(el) {
    if (el.matches('[data-weiter]')) return S.layer === 'guide' ? 'Continue' : 'Start';
    if (el.matches('[data-los]')) return 'Download';
    if (el.matches('[data-aus]')) return 'Turn off';
    if (el.matches('.card, .tab, [data-goto]')) return 'Open';
    if (el.matches('summary')) return el.parentElement.open ? 'Close' : 'Show';
    if (el.matches('[data-set="sound"]')) return S.sound ? 'Sounds off' : 'Sounds on';
    if (el.matches('[data-set]')) return 'Change';
    if (el.matches('[data-q], [data-feature], .qtile')) return 'Open';
    if (el === markEl) return 'Guide';
    return 'Select';
  }
  function updateHints() {
    if (S.layer === 'quick') {
      const el = d.activeElement;
      const list = [];
      if (el && quick.contains(el) && el.matches('a, button')) list.push({ k: 'a', t: hintFor(el), act: 'a' });
      list.push({ k: 'b', t: 'Close', act: 'b' });
      setHints($('.quick-hints'), list);
      return;
    }
    if (S.layer === 'guide') {
      setHints($('.guide-hints'), [{ k: 'a', t: 'Select', act: 'a' }, { k: 'b', t: 'Close', act: 'b' }]);
      return;
    }
    let list;
    if (S.layer === 'detail') {
      list = [{ k: 'lr', t: 'Browse', act: 'rb' }, { k: 'b', t: 'Close', act: 'b' }];
    } else {
      const el = d.activeElement;
      const drin = el && el !== d.body && candidates().includes(el);
      list = [];
      if (drin && el.matches('a, button, summary')) list.push({ k: 'a', t: hintFor(el), act: 'a' });
      if (drin && el.matches('.more') && el.scrollHeight > el.clientHeight + 2) list.push({ k: 'ud', t: 'Scroll', act: 'rollen' });
      if (drin && el.closest('.area')) list.push({ k: 'b', t: 'Up', act: 'b' });
      if (!drin) list.push({ k: 'lt rt', t: 'Area', act: 'rt' });
      if (S.area === 'features' && isConsole() && list.length < 3) list.splice(list.length - (drin && el.closest('.area') ? 1 : 0), 0, { k: 'lb rb', t: 'Group', act: 'rb' });
      if (list.length < 4) list.push({ k: 'guide', t: 'Guide', act: 'guide' });
    }
    setHints(hintsEl, list.slice(0, 4));
  }

  // --- Navigation: ein Cursor, Steuerkreuz und Pfeile wandern räumlich --------------------------
  function scopes() {
    if (S.layer === 'guide') return [guide];
    if (S.layer === 'detail') return [detail];
    if (S.layer === 'quick') return [quick];
    return [markEl, tabsEl, isConsole() ? areaEl(S.area) : mainEl];
  }
  function sichtbar(el) {
    if (!el || el.closest('[hidden], [inert], .is-leaving')) return false;
    const r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0;
  }
  function candidates() {
    const out = [];
    for (const s of scopes()) {
      if (s.matches(FOCUSABLE)) out.push(s);
      out.push(...$$(FOCUSABLE, s));
    }
    // In der Bühne ist nur das große Bild ein Ziel; die anderen holt ein Schritt nach vorn.
    return out.filter(el => sichtbar(el) && !(isConsole() && S.feature && el !== S.feature && el.closest('.shelf')));
  }
  function score(a, b, dir) {
    const ax = (a.left + a.right) / 2;
    const ay = (a.top + a.bottom) / 2;
    const bx = (b.left + b.right) / 2;
    const by = (b.top + b.bottom) / 2;
    if (dir === 'left' || dir === 'right') {
      const s = dir === 'right' ? 1 : -1;
      if ((bx - ax) * s <= 2) return Infinity;
      const gap = Math.max(0, s > 0 ? b.left - a.right : a.left - b.right);
      const ov = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top);
      const quer = ov > Math.min(a.height, b.height) * 0.3 ? 0 : Math.abs(by - ay);
      return gap + quer * 4 + Math.abs(by - ay) * 0.05;
    }
    const s = dir === 'down' ? 1 : -1;
    if ((by - ay) * s <= 2) return Infinity;
    const gap = Math.max(0, s > 0 ? b.top - a.bottom : a.top - b.bottom);
    const ov = Math.min(a.right, b.right) - Math.max(a.left, b.left);
    const quer = ov > 0 ? 0 : Math.min(Math.abs(b.left - a.right), Math.abs(a.left - b.right));
    return gap + quer * 1.2 + Math.abs(bx - ax) * 0.08;
  }
  // Kommt der Cursor von außen in eine Gruppe, landet er auf dem, was dort zuletzt gewählt bzw. aktiv war.
  function eintritt(best, cur) {
    const area = best.closest('.area');
    if (area && !(cur && area.contains(cur))) {
      const m = S.remember[area.id];
      if (m && area.contains(m) && sichtbar(m)) return m;
      const def = $('[data-default]', area);
      if (def && sichtbar(def)) return def;
    }
    // Zeichen und Reiter sind eine Leiste: wer von unten hineingeht, landet auf dem aktiven Reiter.
    const g0 = best.closest('[data-nav-group]');
    const g = g0 === markEl && !(cur && barEl.contains(cur)) && cur !== markEl ? tabsEl : g0;
    if (!g || (cur && g.contains(cur))) return best;
    if (g.dataset.entry === 'active') {
      const a = $('[aria-current="page"], [aria-selected="true"], .is-active', g);
      if (a && sichtbar(a)) return a;
    }
    if (g.dataset.entry === 'last') {
      const m = S.remember['g:' + g.dataset.navGroup];
      if (m && g.contains(m) && sichtbar(m)) return m;
    }
    return best;
  }
  function startZiel() {
    if (S.layer) {
      const pane = S.layer === 'guide' ? gpanes.find(p => !p.hidden) : S.layer === 'quick' ? quick : detail;
      return $('[data-default]', pane) || candidates()[0];
    }
    const area = areaEl(S.area);
    if (isConsole()) {
      // Auf der Bühne ist das Ziel, was vorn steht (auch wenn es mit der Maus nach vorn kam).
      if (S.area === 'features' && S.feature && sichtbar(S.feature)) return S.feature;
      const m = S.remember[area.id];
      if (m && sichtbar(m)) return m;
      const def = $('[data-default]', area);
      if (def && sichtbar(def)) return def;
    }
    return tabFor(S.area);
  }
  function move(dir) {
    if (S.aus) { anschalten(); return; }
    if (S.layer === 'detail' && (dir === 'left' || dir === 'right')) { blaettern(dir === 'right' ? 1 : -1); return; }
    const cur = d.activeElement;
    if (isConsole() && !S.layer && cur && cur.closest && cur.closest('.shelf')) {
      if (dir === 'left' || dir === 'right') { regalSchritt(dir === 'right' ? 1 : -1); return; }
      if ((dir === 'up' || dir === 'down') && cur.matches('.more') && tafelRollen(cur, dir)) return;
      if (dir === 'down') { anstoss(cur, 'down'); return; }
      fokus($('.chip.is-active') || chips[0]);
      klang('move');
      return;
    }
    const list = candidates();
    if (!list.includes(cur)) { fokus(startZiel()); klang('move'); return; }
    const a = cur.getBoundingClientRect();
    let best = null;
    let bs = Infinity;
    // Seitwärts bleibt der Cursor, wo er ist: in die Leiste geht es nur nach oben (wie in Uzai).
    const quer = dir === 'left' || dir === 'right';
    const obenCur = barEl.contains(cur);
    for (const c of list) {
      if (c === cur || (quer && barEl.contains(c) !== obenCur)) continue;
      const s = score(a, c.getBoundingClientRect(), dir);
      if (s < bs) { bs = s; best = c; }
    }
    if (!best) { if (!rollen(dir)) anstoss(cur, dir); return; }
    fokus(eintritt(best, cur));
    klang('move');
  }
  // „Also inside“ vorn: hoch und runter rollt die Liste, bis sie am Ende ist (dann wie sonst).
  function tafelRollen(el, dir) {
    const max = el.scrollHeight - el.clientHeight;
    if (max < 2 || (dir === 'down' && el.scrollTop >= max - 1) || (dir === 'up' && el.scrollTop <= 0)) return false;
    feder(el, 'y', el.scrollTop + (dir === 'down' ? 1 : -1) * el.clientHeight * 0.45);
    klang('move');
    return true;
  }
  // Nichts mehr zum Wählen, aber noch Text: die Fläche rollt weiter, statt anzustoßen.
  function rollen(dir) {
    if (S.layer || !isConsole() || (dir !== 'up' && dir !== 'down')) return false;
    const a = areaEl(S.area);
    const max = a.scrollHeight - a.clientHeight;
    if (max < 2) return false;
    const ziel = a.scrollTop + (dir === 'down' ? 1 : -1) * a.clientHeight * 0.45;
    if ((dir === 'down' && a.scrollTop >= max - 1) || (dir === 'up' && a.scrollTop <= 0)) return false;
    feder(a, 'y', ziel);
    return true;
  }
  function fokus(el, o = {}) {
    if (!el) return;
    // Bilder, die auf der Bühne ausgeblendet sind, sind unsichtbar; vor dem Fokus wieder sichtbar.
    const weg = el.closest && el.closest('.shelf-list > li.weg');
    if (weg) weg.classList.remove('weg');
    el.focus({ preventScroll: true });
    // Ohne Fensterfokus (Controller, Fenster im Hintergrund) kommt kein focusin: dann selbst nachziehen.
    if (d.activeElement === el && !d.hasFocus()) nachFokus(el);
    zeigen(el, o.instant);
  }
  function zeigen(el, instant) {
    if (isConsole() && el.closest('.shelf')) return;
    const sc = el.closest('.guide-body') || (isConsole() ? el.closest('.area') : null);
    if (sc) { senkrecht(sc, el, instant); return; }
    if (!isConsole() && mainEl.contains(el)) el.scrollIntoView({ block: 'nearest', behavior: calm() || instant ? 'auto' : 'smooth' });
  }
  function senkrecht(sc, el, instant) {
    const r = el.getBoundingClientRect();
    const s = sc.getBoundingClientRect();
    const oben = sc.classList.contains('area') ? barEl.getBoundingClientRect().bottom + 16 : s.top + 12;
    const unten = s.bottom - (sc.classList.contains('area') ? 130 * kpx() : 12);
    if (r.top < oben) feder(sc, 'y', sc.scrollTop - (oben - r.top), instant);
    else if (r.bottom > unten) feder(sc, 'y', sc.scrollTop + (r.bottom - unten), instant);
  }
  // Bühne der Funktionen: das gewählte Bild groß (960 × 540 Punkte), die nächsten drei weichen nach
  // rechts in die Tiefe zurück, kleiner und dunkler; das vorige tritt nach links weg und blendet aus.
  const STUFE = [1, 0.42, 0.28, 0.18, 0.12];
  const HELL = [1, 0.6, 0.44, 0.32, 0.25];
  // So weit stehen sie schräg (Grad): je weiter hinten, desto mehr zur Seite gedreht.
  const DREH = [0, 30, 38, 44, 48];
  function platz(o) {
    if (o === 0) return { x: 0, y: 0, s: 1, o: 1, z: 6, b: 1, r: 0 };
    if (o < 0) return { x: -300, y: 22, s: 0.92, o: 0, z: 5 + Math.max(o, -3), b: 0.6, r: -26 };
    const n = Math.min(o, 4);
    let x = 1000;
    for (let i = 1; i < n; i++) x += 960 * STUFE[i] + 24;
    const sc = STUFE[n];
    return { x, y: (540 - 540 * sc) / 2, s: sc, o: o <= 3 ? 1 : 0, z: 6 - n, b: HELL[n], r: DREH[n] };
  }
  function layoutRegal(sofort) {
    if (!isConsole() || !S.feature) return;
    const cur = items.indexOf(S.feature);
    if (sofort) shelf.classList.add('still');
    items.forEach((it, i) => {
      const li = it.closest('li');
      const p = platz(i - cur);
      li.style.setProperty('--x', p.x.toFixed(1));
      li.style.setProperty('--y', p.y.toFixed(1));
      li.style.setProperty('--s', String(p.s));
      li.style.setProperty('--o', String(p.o));
      li.style.setProperty('--z', String(p.z));
      li.style.setProperty('--b', String(p.b));
      li.style.setProperty('--r', String(p.r));
      li.style.pointerEvents = p.o ? '' : 'none';
      li.classList.toggle('weg', !p.o);
      li.classList.toggle('is-cur', i === cur);
      if (Math.abs(i - cur) <= 1) gross(it);
    });
    if (sofort) { void shelf.offsetWidth; shelf.classList.remove('still'); }
  }
  // Groß und nah: das Bild kommt in voller Größe, sobald es vorn steht oder gleich drankommt.
  function gross(it) {
    const img = $('img', it);
    if (!img || img.dataset.gross) return;
    img.dataset.gross = '1';
    const src = it.getAttribute('href');
    const pre = new Image();
    pre.src = src;
    (pre.decode ? pre.decode() : Promise.resolve()).then(() => { img.src = src; }, () => {});
  }
  function regalSchritt(step) {
    const i = items.indexOf(S.feature) + step;
    if (i < 0 || i >= items.length) { anstoss(S.feature, step > 0 ? 'right' : 'left'); return; }
    regalZu(i);
  }
  // Ein bestimmtes Bild nach vorn holen; ist es schon vorn, rücken alle auf ihre Plätze zurück.
  function regalZu(i) {
    const el = items[Math.max(0, Math.min(items.length - 1, i))];
    if (el === S.feature) { layoutRegal(); return; }
    const drin = d.activeElement && d.activeElement.closest && d.activeElement.closest('.shelf');
    // Ein ausgeblendetes Bild ist unsichtbar und nähme keinen Fokus: erst sichtbar machen.
    el.closest('li').classList.remove('weg');
    if (html.classList.contains('cursor') || drin) fokus(el);
    else waehle(el);
    if (S.feature !== el) waehle(el);
    klang('move');
  }
  // Zwischen zwei Plätzen (beim Ziehen): jede Größe gleitet linear vom einen zum anderen.
  function platzF(p) {
    const a = Math.floor(p);
    const t = p - a;
    const A = platz(a);
    if (t < 1e-4) return A;
    const B = platz(a + 1);
    const m = k => A[k] + (B[k] - A[k]) * t;
    return { x: m('x'), y: m('y'), s: m('s'), o: m('o'), z: t < 0.5 ? A.z : B.z, b: m('b'), r: m('r') };
  }

  // Kritisch gedämpfte Feder (U.SPRING 22, beim Halten weicher 16): ein neues Ziel übernimmt das Tempo.
  const federn = new Map();
  let federRaf = 0;
  let federT = 0;
  function feder(el, achse, ziel, instant) {
    const prop = achse === 'x' ? 'scrollLeft' : 'scrollTop';
    const max = achse === 'x' ? el.scrollWidth - el.clientWidth : el.scrollHeight - el.clientHeight;
    ziel = Math.max(0, Math.min(max, Math.round(ziel)));
    if (instant || calm()) { federn.delete(el); el[prop] = ziel; return; }
    let f = federn.get(el);
    const jetzt = performance.now();
    if (!f) { f = { x: el[prop], v: 0, last: 0 }; federn.set(el, f); }
    else if (Math.abs(el[prop] - Math.round(f.x)) > 2) f.x = el[prop];
    f.ziel = ziel;
    f.prop = prop;
    f.halt = jetzt - f.last < 260;
    f.last = jetzt;
    if (!federRaf) { federT = jetzt; federRaf = requestAnimationFrame(federSchritt); }
  }
  function federSchritt(now) {
    const dt = Math.min(0.04, Math.max(0.001, (now - federT) / 1000));
    federT = now;
    for (const [el, f] of federn) {
      const w = f.halt ? 16 : 22;
      const a = -2 * w * f.v - w * w * (f.x - f.ziel);
      f.v += a * dt;
      f.x += f.v * dt;
      if (Math.abs(f.x - f.ziel) < 0.5 && Math.abs(f.v) < 8) { el[f.prop] = f.ziel; federn.delete(el); continue; }
      el[f.prop] = Math.round(f.x);
    }
    federRaf = federn.size ? requestAnimationFrame(federSchritt) : 0;
  }

  // Rand-Anstoß: nichts in dieser Richtung, das Element stößt W_ANSTOSS an und kommt zurück.
  function anstoss(el, dir) {
    klang('bump');
    if (!el || el === d.body || calm()) return;
    const p = way(W.anstoss);
    const v = { left: [-p, 0], right: [p, 0], up: [0, -p], down: [0, p] }[dir] || [0, 0];
    el.animate([{ transform: 'translate(0, 0)' }, { transform: `translate(${v[0]}px, ${v[1]}px)`, offset: 0.35 }, { transform: 'translate(0, 0)' }],
      { duration: T.antwort + T.ort, easing: E.an, composite: 'add' });
  }
  // Beim Bestätigen drückt das Element kurz ein (96 %).
  function druecken(el) {
    if (!el || calm()) return;
    el.animate([{ transform: 'scale(1)' }, { transform: 'scale(.96)', offset: 0.3 }, { transform: 'scale(1)' }],
      { duration: T.antwort + T.ort, easing: E.an, composite: 'add' });
  }

  // --- Leiste: der Punkt gleitet als Tropfen, die Cursor-Pille folgt dem Fokus -----------------
  // Wie in Uzai stehen oben nur Symbole; unter dem Cursor (und der Maus) klappt der Name auf. Weil
  // sich dabei die Reiter verschieben, folgen Punkt und Pille ihrem Ziel in jedem Bild: der Punkt
  // als Tropfen (die Vorderkante eilt voraus, die Hinterkante folgt), die Pille weich.
  const dot = $('.tab-dot');
  const pill = $('.tab-pill');
  const L = { dl: 0, dr: 0, da: false, pl: 0, pw: 0, pa: 0, pDa: false, tab: null, sofort: true, raf: 0, t: 0, bis: 0 };
  const punktSichtbar = () => !(html.classList.contains('cursor') && html.dataset.zone === 'bar');
  function leisteLos(ms = 420) {
    L.bis = Math.max(L.bis, performance.now() + ms);
    if (!L.raf) { L.t = performance.now(); L.raf = requestAnimationFrame(leisteSchritt); }
  }
  function punktZiel() {
    const t = tabFor(S.area);
    if (!t || !t.offsetWidth) return null;
    const n = tabsEl.getBoundingClientRect();
    const ic = $('.i', t);
    const ir = ic ? ic.getBoundingClientRect() : null;
    const r = ir && ir.width ? ir : t.getBoundingClientRect();
    const size = parseFloat(getComputedStyle(dot).height) || 7;
    const c = r.left - n.left + r.width / 2;
    return { l: c - size / 2, r: c + size / 2 };
  }
  function leisteSchritt(now) {
    const dt = Math.min(0.05, Math.max(0.001, (now - L.t) / 1000));
    L.t = now;
    let ruhig = true;
    const z = punktZiel();
    if (z) {
      if (L.sofort || calm() || !L.da) { L.dl = z.l; L.dr = z.r; L.da = true; L.sofort = false; }
      else {
        const schnell = 1 - Math.exp(-dt * 26);
        const langsam = 1 - Math.exp(-dt * 12);
        const rechts = z.l > L.dl + 0.5;
        const links = z.l < L.dl - 0.5;
        L.dl += (z.l - L.dl) * (rechts ? langsam : schnell);
        L.dr += (z.r - L.dr) * (links ? langsam : schnell);
      }
      if (Math.abs(z.l - L.dl) > 0.3 || Math.abs(z.r - L.dr) > 0.3) ruhig = false;
    }
    const zeigt = L.tab && html.classList.contains('cursor') && L.tab.offsetWidth;
    if (zeigt) {
      const n = tabsEl.getBoundingClientRect();
      const r = L.tab.getBoundingClientRect();
      const zl = r.left - n.left;
      if (!L.pDa || calm()) { L.pl = zl; L.pw = r.width; L.pa = Math.max(L.pa, 0.7); L.pDa = true; }
      else {
        const k = 1 - Math.exp(-dt * 22);
        L.pl += (zl - L.pl) * k;
        L.pw += (r.width - L.pw) * k;
      }
      L.pa += (1 - L.pa) * (1 - Math.exp(-dt * 40));
      if (Math.abs(zl - L.pl) > 0.3 || Math.abs(r.width - L.pw) > 0.3 || L.pa < 0.99) ruhig = false;
    } else {
      L.pa = L.pDa ? Math.min(L.pa, 0.3) * Math.exp(-dt * 30) : 0;
      if (L.pa < 0.01) { L.pa = 0; L.pDa = false; } else ruhig = false;
    }
    dot.style.transform = `translateX(${L.dl.toFixed(2)}px)`;
    dot.style.width = `${Math.max(1, L.dr - L.dl).toFixed(2)}px`;
    dot.style.opacity = L.da && punktSichtbar() ? '1' : '0';
    pill.style.transform = `translateX(${L.pl.toFixed(2)}px)`;
    pill.style.width = `${L.pw.toFixed(2)}px`;
    pill.style.opacity = L.pa.toFixed(3);
    L.raf = !ruhig || now < L.bis ? requestAnimationFrame(leisteSchritt) : 0;
  }
  function zeichnePunkt() { leisteLos(0); }
  function setzePunkt(bewegt) {
    if (!bewegt) L.sofort = true;
    leisteLos(bewegt ? 600 : 0);
  }
  function setzePille(tab) {
    L.tab = tab || null;
    leisteLos(T.ort + 160);
  }
  // Strich im Akzent unter dem ganzen Wort (Unterbereiche, Guide-Reiter), gleitet wie der Punkt.
  const striche = new Map();
  function setzeStrich(linie, el, bewegt) {
    if (!linie || !el || !el.offsetWidth) return;
    const box = linie.parentElement.getBoundingClientRect();
    const r = el.getBoundingClientRect();
    const pad = parseFloat(getComputedStyle(el).paddingLeft) || 0;
    const sx = linie.parentElement.scrollLeft || 0;
    const l = r.left - box.left + pad + sx;
    const rr = r.right - box.left - pad + sx;
    let st = striche.get(linie);
    const malen = () => { linie.style.transform = `translateX(${st.l}px)`; linie.style.width = `${Math.max(1, st.r - st.l)}px`; };
    if (!st || !bewegt || calm()) { st = { l, r: rr }; striche.set(linie, st); malen(); return; }
    const nachRechts = l > st.l;
    const key = 'st' + (linie.dataset.sid || (linie.dataset.sid = String(Math.random()).slice(2, 8)));
    tween(st.l, l, nachRechts ? T.raum : T.ort, v => { st.l = v; malen(); }, key + 'l');
    tween(st.r, rr, nachRechts ? T.ort : T.raum, v => { st.r = v; malen(); }, key + 'r');
  }

  // --- Raum: Lichter in der Farbe des Gewählten, das große Bild oben rechts ----------------------
  function hexHsl(hex) {
    const m = /^#?([\da-f]{2})([\da-f]{2})([\da-f]{2})$/i.exec(hex || '');
    if (!m) return null;
    const [r, g, b] = [m[1], m[2], m[3]].map(x => parseInt(x, 16) / 255);
    const max = Math.max(r, g, b);
    const min = Math.min(r, g, b);
    const l = (max + min) / 2;
    if (max === min) return { h: 0, s: 0, l };
    const dd = max - min;
    const s = l > 0.5 ? dd / (2 - max - min) : dd / (max + min);
    let h;
    if (max === r) h = (g - b) / dd + (g < b ? 6 : 0);
    else if (max === g) h = (b - r) / dd + 2;
    else h = (r - g) / dd + 4;
    return { h: Math.round(h * 60), s, l };
  }
  function raumFarbe(hex) {
    let c = hexHsl(hex);
    if (!c || c.s < 0.12) c = hexHsl(ACCENT);
    const s = Math.round(Math.min(0.8, Math.max(0.5, c.s * 1.25)) * 100);
    // Die Farbe und zwei Nachbarn: oben links die stärkste, oben rechts, Mitte.
    const f = [`hsl(${c.h} ${s}% 58%)`, `hsl(${(c.h + 18) % 360} ${s}% 55%)`, `hsl(${(c.h + 342) % 360} ${s}% 52%)`];
    if (f.join() === lichtJetzt) return;
    lichtJetzt = f.join();
    // Der andere Satz bekommt die neue Farbe (einmal gemalt) und blendet über den alten.
    lichtSatz = 1 - lichtSatz;
    const neu = lichtSaetze[lichtSatz];
    f.forEach((v, i) => neu.style.setProperty('--l' + (i + 1), v));
    neu.classList.add('an');
    lichtSaetze[1 - lichtSatz].classList.remove('an');
  }
  const lichtSaetze = $$('.lichtsatz');
  let lichtSatz = 0;
  let lichtJetzt = '';
  const stageEl = $('.stage');
  let stageSrc = null;
  let stageTimer = 0;
  function buehne(src, sofort) {
    clearTimeout(stageTimer);
    // Beim Zappen bleibt das letzte Bild ruhig stehen; das neue kommt, wenn der Cursor kurz ruht.
    if (sofort) buehneZeigen(src);
    else stageTimer = setTimeout(() => buehneZeigen(src), 130);
  }
  function buehneZeigen(src) {
    if (src === stageSrc) return;
    stageSrc = src;
    const alte = $$('.stage-img', stageEl);
    if (!src) {
      alte.forEach(i => i.animate([{ opacity: 1 }, { opacity: 0 }], { duration: dur(T.weg), easing: E.weg, fill: 'forwards' }).finished.then(() => i.remove(), () => i.remove()));
      return;
    }
    const img = new Image();
    img.className = 'stage-img';
    img.alt = '';
    img.decoding = 'async';
    img.src = src;
    // Das neue Bild legt sich deckend über das alte; das alte geht erst, wenn das neue ganz da ist.
    const zeig = () => {
      if (stageSrc !== src) return;
      const darunter = $$('.stage-img', stageEl);
      stageEl.append(img);
      const ein = img.animate([{ opacity: 0 }, { opacity: 1 }], { duration: dur(260), easing: E.kreuz, fill: 'backwards' });
      if (!calm()) img.animate([{ transform: 'scale(1.035)' }, { transform: 'scale(1)' }], { duration: T.licht, easing: E.an });
      ein.finished.then(() => { if (img.isConnected) darunter.forEach(i => i.remove()); }, () => {});
    };
    (img.decode ? img.decode() : Promise.resolve()).then(zeig, zeig);
  }
  function raumFuer(area) {
    if (area === 'features' && S.feature) {
      const i = info(S.feature);
      raumFarbe(i.color);
      if (isConsole()) buehne(i.bg, true);
    } else {
      raumFarbe(null);
    }
    // Die Lichter schwenken langsam mit (je Bereich 34 Punkte, Parallaxe).
    $('.lights').style.transform = isConsole() ? `translateX(${-AREAS.indexOf(area) * 34 * kpx()}px)` : '';
  }

  // --- Bereiche: LT/RT, Klick oder Pfeile auf der Leiste -------------------------------------
  function markTabs(bewegt) {
    tabs.forEach(t => { if (t.dataset.area === S.area) t.setAttribute('aria-current', 'page'); else t.removeAttribute('aria-current'); });
    setzePunkt(bewegt);
  }
  function go(area, o = {}) {
    if (!AREAS.includes(area)) return;
    const from = S.area;
    if (!isConsole()) {
      S.area = area;
      html.dataset.area = area;
      markTabs(true);
      raumFuer(area);
      areaEl(area).scrollIntoView({ behavior: calm() ? 'auto' : 'smooth', block: 'start' });
      if (o.focus === 'content') { const t = $('[data-default], ' + FOCUSABLE, areaEl(area)); if (t) t.focus({ preventScroll: true }); }
      updateHints();
      return;
    }
    if (area === from) { if (o.focus === 'content') fokus(startZiel(), { instant: true }); return; }
    const dir = Math.sign(AREAS.indexOf(area) - AREAS.indexOf(from)) || 1;
    const alt = areaEl(from);
    const neu = areaEl(area);
    flugAbbruch();
    const flug = flugPlan(from, area);
    const imBalken = d.activeElement === markEl || barEl.contains(d.activeElement);
    const imInhalt = mainEl.contains(d.activeElement) && d.activeElement !== mainEl;
    S.area = area;
    html.dataset.area = area;
    // Das Alte gleitet sofort W_ORT zur Gegenseite und kreuzt ein Bild später (sine in-out).
    stopAll(alt);
    alt.classList.add('is-leaving');
    play(alt, 'weg', [{ transform: 'translateX(0)' }, { transform: `translateX(${-dir * way(W.ort)}px)` }], { duration: dur(T.weg) + NACH_WEG, easing: E.an });
    play(alt, 'aus', [{ opacity: 1 }, { opacity: 0 }], { duration: dur(T.weg), delay: NACH_WEG, easing: E.kreuz })
      .finished.then(() => { if (S.area !== from) alt.classList.remove('is-leaving'); }, () => {});
    // Das Neue kommt W_BEREICH aus der Richtung des Wechsels, seine Teile gestaffelt (T_RAUM).
    stopAll(neu);
    neu.classList.remove('is-leaving');
    if (flug && !flug.hin) flug.zu = tvRect();
    // Fliegt die Bibliothek zurück in den Fernseher, steht er still und blendet nur ein.
    $$('[data-rise]', neu).forEach((t, i) => play(t, 'ein',
      flug && !flug.hin && t.matches('.home-shot') ? [{ opacity: 0 }, { opacity: 1 }]
        : [{ opacity: 0, transform: `translateX(${dir * way(W.bereich)}px)` }, { opacity: 1, transform: 'translateX(0)' }],
      { duration: dur(T.raum), delay: staffel(i), easing: E.raum }));
    play(neu, 'ein', [{ opacity: 0 }, { opacity: 1 }], { duration: dur(T.ort), easing: E.an });
    markTabs(true);
    if (area === 'features' && !S.feature) waehle(items[0], { sofort: true });
    else if (area === 'features') waehle(S.feature, { force: true });
    if (area === 'features') kaskade(dir, flug && flug.card);
    besuchen(area);
    guideJetzt();
    raumFuer(area);
    if (o.focus === 'content' || (imInhalt && html.classList.contains('cursor'))) fokus(startZiel(), { instant: true });
    else if (imBalken) fokus(tabFor(area), { instant: true });
    else if (imInhalt) mainEl.focus({ preventScroll: true });
    if (flug) {
      if (flug.hin) flug.zu = $('.card-img', flug.card).getBoundingClientRect();
      flugStart(flug);
    }
    klang('raste');
    updateHints();
  }
  // Beim Wechsel nach Features kommen die Bilder einzeln aus der Richtung des Wechsels: das vordere
  // zuerst, die hinteren mit etwas mehr Weg (wie die Cover in der Einrichtung).
  function kaskade(dir, ohne) {
    if (!isConsole() || calm() || !S.feature) return;
    const cur = items.indexOf(S.feature);
    for (let o = 0; o <= 3; o++) {
      const it = items[cur + o];
      if (!it) break;
      if (it === ohne) continue;
      it.animate([{ opacity: 0, transform: `translateX(${dir * way(W.bereich + o * 30)}px)` }, { opacity: 1, transform: 'none' }],
        { duration: T.raum + o * 40, delay: 20 + staffel(o), easing: E.raum, fill: 'backwards' });
    }
  }
  // Home ⇄ Features: Der Fernseher auf Home zeigt Uzais Bibliothek, und genau die steht als erstes
  // Bild auf der Bühne („One library“, data-tv). Steht sie dort vorn, fliegt sie beim Wechsel als
  // geteiltes Element aus dem Fernseher an ihren Platz und zurück; der Bildschirm bleibt so lange
  // dunkel. Nur transform und opacity bewegen sich (der Flug läuft im Compositor und stockt nicht,
  // wenn die Seite gerade rechnet); das Bild ist vorher dekodiert, sonst gibt es keinen Flug.
  const tvKarte = $('.card[data-tv]');
  const flieger = d.createElement('div');
  flieger.className = 'flieger';
  flieger.setAttribute('aria-hidden', 'true');
  const fKarte = d.createElement('img');
  const fTv = d.createElement('img');
  fKarte.className = 'flieger-karte';
  fTv.className = 'flieger-tv';
  fKarte.alt = fTv.alt = '';
  flieger.append(fKarte, fTv);
  d.body.appendChild(flieger);
  const tvAus = d.createElement('i');
  tvAus.className = 'tv-aus';
  $('.home-shot').appendChild(tvAus);
  let flugAnims = [];
  let flugBereit = false;
  function flugVorbereiten() {
    if (!tvKarte || !fKarte.decode) return;
    fKarte.src = fTv.src = tvKarte.getAttribute('href');
    Promise.all([fKarte.decode(), fTv.decode()]).then(() => { flugBereit = true; }, () => {});
  }
  // Der Bildschirm im Fernseher-Bild, in Bildpunkten des Fensters (Maße in TV, siehe Einschalten).
  function tvRect() {
    const r = $('.home-shot img').getBoundingClientRect();
    const f = r.width / TV.w;
    return { left: r.left + TV.sx0 * f, top: r.top + TV.sy0 * f, width: (TV.sx1 - TV.sx0) * f, height: (TV.sy1 - TV.sy0) * f };
  }
  function flugPlan(from, area) {
    const hin = from === 'home' && area === 'features';
    if (!flugBereit || calm() || S.layer || kinoAnim || S.feature !== tvKarte || !(hin || (from === 'features' && area === 'home'))) return null;
    const von = hin ? tvRect() : $('.card-img', tvKarte).getBoundingClientRect();
    if (!von.width) return null;
    tvKarte.classList.add('is-flying');
    return { hin, von, zu: null, card: tvKarte };
  }
  function flugStart(f) {
    const zu = f.zu;
    if (!zu || !zu.width) { flugAbbruch(); return; }
    const bild = $('.home-shot img');
    const k = bild.offsetWidth / TV.w;
    Object.assign(tvAus.style, { left: bild.offsetLeft + TV.sx0 * k + 'px', top: bild.offsetTop + TV.sy0 * k + 'px',
      width: (TV.sx1 - TV.sx0) * k + 'px', height: (TV.sy1 - TV.sy0) * k + 'px' });
    tvAus.classList.add('an');
    Object.assign(flieger.style, { left: zu.left + 'px', top: zu.top + 'px', width: zu.width + 'px', height: zu.height + 'px' });
    flieger.classList.add('an');
    const lauf = { duration: 760, fill: 'both' };
    // Hin: unter dem Bildschirm (mit Blende) blendet die Karte auf, dann geht der Bildschirm; zurück
    // umgekehrt kurz vor der Landung. In der Mitte sind beide gleich, man sieht nur die Ränder wechseln.
    const [karte, tv] = f.hin
      ? [[{ opacity: 0 }, { opacity: 1, offset: 0.2 }, { opacity: 1 }], [{ opacity: 1 }, { opacity: 1, offset: 0.2 }, { opacity: 0, offset: 0.3 }, { opacity: 0 }]]
      : [[{ opacity: 1 }, { opacity: 1, offset: 0.8 }, { opacity: 0, offset: 0.95 }, { opacity: 0 }], [{ opacity: 0 }, { opacity: 0, offset: 0.6 }, { opacity: 1, offset: 0.8 }, { opacity: 1 }]];
    flugAnims = [
      flieger.animate([{ transform: flugVon(f.von, zu) }, { transform: 'none' }], { ...lauf, easing: E.reise }),
      fKarte.animate(karte, lauf),
      fTv.animate(tv, lauf),
    ];
    flugAnims[0].finished.then(flugAbbruch, () => {});
  }
  // Landen oder abbrechen: das echte Bild zeigt sich wieder, der Fernseher geht an.
  function flugAbbruch() {
    const alle = flugAnims;
    flugAnims = [];
    alle.forEach(a => a.cancel());
    flieger.classList.remove('an');
    tvAus.classList.remove('an');
    if (tvKarte) tvKarte.classList.remove('is-flying');
  }
  function bereichSchritt(dir) {
    const i = AREAS.indexOf(S.area) + dir;
    if (i < 0 || i >= AREAS.length) { anstoss(tabFor(S.area), dir > 0 ? 'right' : 'left'); return; }
    go(AREAS[i]);
  }

  // --- Funktionen: Bühne, Regal, Gruppen --------------------------------------------------
  const CAT = { all: 'Every game', game: 'In a game', library: 'Library', watch: 'Watch', room: 'Your Room', more: 'Also inside' };
  const stage = { cat: $('[data-stage="cat"]'), title: $('[data-stage="title"]'), text: $('[data-stage="text"]') };
  function info(item) {
    const g = item.closest('.shelf-group');
    const cat = g ? g.dataset.cat : '';
    const img = $('img', item);
    return {
      cat,
      catName: item.matches('.more') ? '' : CAT[cat] || '',
      title: item.matches('.more') ? '' : $('.card-title', item).textContent.trim(),
      text: $('.card-text', item).textContent.trim(),
      img: item.matches('.card') ? item.getAttribute('href') : null,
      // Der Schein hinter der Bühne, fertig weichgezeichnet (media/*-b.webp, 192 × 108).
      bg: item.matches('.card') ? item.getAttribute('href').replace(/\.webp$/, '-b.webp') : null,
      thumb: img ? img.dataset.klein || img.getAttribute('src') : null,
      alt: img ? img.alt : '',
      color: item.dataset.color || null,
    };
  }
  function waehle(item, o = {}) {
    if (!item) return;
    const neu = S.feature !== item;
    S.feature = item;
    const i = info(item);
    if (neu || o.force) {
      // Wechselt die Auswahl, blenden Angabe, Titel und Text versetzt neu ein.
      [[stage.cat, i.catName], [stage.title, i.title], [stage.text, i.text]].forEach(([el, wert], n) => {
        el.getAnimations().forEach(a => a.cancel());
        el.textContent = wert;
        if (!o.sofort && !calm()) {
          el.animate([{ opacity: 0, transform: `translateY(${way(8)}px)` }, { opacity: 1, transform: 'none' }],
            { duration: dur(T.ort), delay: staffel(n), easing: E.an, fill: 'backwards' });
        }
      });
      $('.shelf-count').textContent = `${items.indexOf(item) + 1} of ${items.length}`;
    }
    chipAktiv(i.cat, !o.sofort);
    layoutRegal(o.sofort);
    if (S.area === 'features' && isConsole()) {
      buehne(i.bg, o.sofort);
      raumFarbe(i.color);
    }
  }
  function chipAktiv(cat, bewegt) {
    let aktiv = null;
    chips.forEach(c => { const on = c.dataset.cat === cat; c.classList.toggle('is-active', on); if (on) aktiv = c; });
    if (aktiv) setzeStrich($('.chips .chip-line'), aktiv, bewegt);
  }
  function springeZu(cat, nurZeigen) {
    const first = $(`.shelf-group[data-cat="${cat}"] .card, .shelf-group[data-cat="${cat}"] .more`);
    if (!first) return;
    if (html.classList.contains('cursor') && !nurZeigen) fokus(first);
    else waehle(first);
    klang('raste');
  }
  function abschnitt(dir) {
    const cats = chips.map(c => c.dataset.cat);
    const cur = S.feature ? info(S.feature).cat : cats[0];
    const i = cats.indexOf(cur) + dir;
    if (i < 0 || i >= cats.length) { anstoss(chips[Math.max(0, Math.min(cats.length - 1, cats.indexOf(cur)))], dir > 0 ? 'right' : 'left'); return; }
    springeZu(cats[i], d.activeElement && d.activeElement.matches('.chip'));
  }

  // --- Seite einer Funktion: das Bild fliegt aus der Karte an seinen Platz (src/ui/flug.gd) -------
  const dShot = $('.detail-shot');
  const dImg = $('.detail-shot img');
  const dCopy = $('.detail-copy');
  const dNav = $('.detail-nav');
  const dTeil = { cat: $('[data-d="cat"]'), pos: $('[data-d="pos"]'), title: $('[data-d="title"]'), text: $('[data-d="text"]') };
  let dIndex = -1;
  let dZiel = null;
  let dRaus = false;
  function seiteFuellen(card) {
    const i = info(card);
    dIndex = cards.indexOf(card);
    dTeil.cat.textContent = i.catName;
    dTeil.pos.textContent = `${dIndex + 1} of ${cards.length}`;
    dTeil.title.textContent = i.title;
    dTeil.text.textContent = i.text;
    dImg.alt = i.alt;
    dImg.src = i.thumb || i.img;
    const gross = new Image();
    gross.src = i.img;
    (gross.decode ? gross.decode() : Promise.resolve()).then(() => { if (cards[dIndex] === card) dImg.src = i.img; }, () => {});
  }
  function flugVon(rect, zu) {
    return `translate(${rect.left - zu.left}px, ${rect.top - zu.top}px) scale(${rect.width / zu.width}, ${rect.height / zu.height})`;
  }
  function oeffneSeite(card) {
    if (S.layer || !card) return;
    flugAbbruch();
    S.layer = 'detail';
    S.back = card;
    erfolg('seite');
    seiteFuellen(card);
    detail.hidden = false;
    ebeneAn('detail');
    const von = $('.card-img', card).getBoundingClientRect();
    const zu = dShot.getBoundingClientRect();
    if (calm()) {
      play(dShot, 'flug', [{ opacity: 0 }, { opacity: 1 }], { duration: dur(T.raum), easing: E.an });
    } else {
      card.classList.add('is-flying');
      play(dShot, 'flug', [{ transform: flugVon(von, zu) }, { transform: 'none' }], { duration: 450, easing: E.flug })
        .finished.then(() => card.classList.remove('is-flying'), () => {});
    }
    // Der Inhalt der Seite blendet ein und gleitet 26 Punkte nach (Fläche vor Schrift).
    [dCopy, dNav].forEach((el, n) => play(el, 'ein', [{ opacity: 0, transform: `translateX(${way(W.nach)}px)` }, { opacity: 1, transform: 'none' }],
      { duration: dur(T.raum), delay: calm() ? 0 : NACH_FLAECHE + 80 + n * STAFFEL, easing: E.raum }));
    detail.focus({ preventScroll: true });
    klang('open');
    updateHints();
  }
  function schliesseSeite(sofort) {
    if (S.layer !== 'detail') return;
    const card = cards[dIndex] || S.back;
    S.layer = null;
    dZiel = null;
    ebeneAus();
    const fertig = () => {
      detail.hidden = true;
      card.classList.remove('is-flying');
      [dShot, dCopy, dNav, detail].forEach(stopAll);
    };
    // Erst die Karte, auf der man jetzt steht, ins Bild holen; dann fliegt das Bild zu ihr zurück.
    card.classList.add('is-flying');
    waehle(card, { sofort: true });
    fokus(card, { instant: true });
    if (sofort || calm()) {
      play(detail, 'aus', [{ opacity: 1 }, { opacity: 0 }], { duration: dur(T.weg), easing: E.weg }).finished.then(fertig, fertig);
    } else {
      [dCopy, dNav].forEach(el => play(el, 'ein', [{ opacity: 1 }, { opacity: 0 }], { duration: T.antwort, easing: E.weg }));
      const zu = dShot.getBoundingClientRect();
      const ziel = $('.card-img', card).getBoundingClientRect();
      play(dShot, 'flug', [{ transform: 'none' }, { transform: flugVon(ziel, zu) }], { duration: 400, easing: E.flug }).finished.then(fertig, fertig);
    }
    klang('back');
    updateHints();
  }
  function blaettern(step) {
    const basis = dZiel === null ? dIndex : dZiel;
    const n = basis + step;
    if (n < 0 || n >= cards.length) { anstoss(dShot, step > 0 ? 'right' : 'left'); return; }
    dZiel = n;
    klang('move');
    if (dRaus) return;
    dRaus = true;
    const aus = [{ opacity: 1, transform: 'translateX(0)' }, { opacity: 0, transform: `translateX(${-step * way(W.ort)}px)` }];
    Promise.all([dShot, dCopy].map(el => play(el, 'blatt', aus, { duration: dur(T.weg), easing: E.weg }).finished.catch(() => {}))).then(() => {
      dRaus = false;
      if (S.layer !== 'detail' || dZiel === null) return;
      const card = cards[dZiel];
      dZiel = null;
      seiteFuellen(card);
      [dShot, dCopy].forEach((el, i) => play(el, 'blatt', [{ opacity: 0, transform: `translateX(${step * way(W.ort)}px)` }, { opacity: 1, transform: 'none' }],
        { duration: dur(T.ort), delay: i * STAFFEL, easing: E.an }));
    });
  }

  // --- Ebenen: Guide und Seite legen sich über die Oberfläche, die zurücktritt -------------------
  function ebeneAn(art) {
    html.classList.add('layer-open');
    veil.style.setProperty('--vx', art === 'guide' ? '16%' : '50%');
    const stark = art === 'quick' ? 0.55 : 1;
    const von = parseFloat(veil.style.opacity) || 0;
    veil.style.opacity = String(stark);
    play(veil, 'v', [{ opacity: von }, { opacity: stark }], { duration: dur(art === 'guide' ? T.ort : T.raum), easing: E.an });
    mainEl.inert = true;
    barEl.inert = true;
    hintsEl.classList.toggle('over', art === 'detail');
  }
  function ebeneAus() {
    const von = parseFloat(veil.style.opacity) || 1;
    veil.style.opacity = '0';
    play(veil, 'v', [{ opacity: von }, { opacity: 0 }], { duration: dur(T.weg), easing: E.weg })
      .finished.then(() => { if (!S.layer) html.classList.remove('layer-open'); }, () => {});
    mainEl.inert = false;
    barEl.inert = false;
  }
  // Ein Licht läuft einmal durch die Fuge des Zeichens (pulse()).
  function puls() {
    if (calm()) {
      $('.mark .u-line').animate([{ stroke: '#ddd0ff' }, { stroke: ACCENT }], { duration: T.raum, easing: E.weg });
      return;
    }
    $('.mark .u-pulse').animate([
      { strokeDashoffset: 0.16, opacity: 0 },
      { opacity: 1, offset: 0.12 },
      { strokeDashoffset: -0.9, opacity: 0.95, offset: 0.82 },
      { strokeDashoffset: -1.02, opacity: 0 },
    ], { duration: 440, easing: 'cubic-bezier(.4,0,.3,1)' });
  }
  let gIndex = 0;
  function oeffneGuide() {
    if (S.layer === 'guide' || S.booting) return;
    if (S.layer === 'detail') schliesseSeite(true);
    let vorher = d.activeElement;
    if (S.layer === 'quick') { vorher = S.back; schliesseQuick({ keinFokus: true, still: true }); }
    S.layer = 'guide';
    S.back = vorher;
    erfolg('guide');
    guideJetzt();
    guide.hidden = false;
    html.classList.add('guide-open');
    ebeneAn('guide');
    puls();
    uhr();
    stopAll(guide);
    play(guide, 'zug', [{ transform: 'translateX(-100%)' }, { transform: 'translateX(0)' }], { duration: calm() ? 1 : T.ort, easing: E.an });
    $$('.guide-head, .guide-tabs, .guide-body, .guide-hints', guide).forEach((el, i) => play(el, 'ein', [{ opacity: 0 }, { opacity: 1 }],
      { duration: dur(T.ort), delay: calm() ? 0 : NACH_FLAECHE + staffel(i), easing: E.an }));
    setzeStrich($('.guide-tablist .chip-line'), gtabs[gIndex], false);
    fokus(startZiel(), { instant: true });
    klang('open');
    updateHints();
  }
  function schliesseGuide(o = {}) {
    if (S.layer !== 'guide') return;
    S.layer = null;
    html.classList.remove('guide-open');
    if (!o.still) ebeneAus();
    // Schrift zuerst, dann gleitet nur die Leiste ganz hinaus.
    $$('.guide-head, .guide-tabs, .guide-body, .guide-hints', guide).forEach(el => play(el, 'ein', [{ opacity: 1 }, { opacity: 0 }], { duration: T.antwort, easing: E.weg }));
    play(guide, 'zug', [{ transform: 'translateX(0)' }, { transform: 'translateX(-100%)' }], { duration: dur(T.weg), delay: calm() ? 0 : 40, easing: E.hinaus })
      .finished.then(() => { if (S.layer !== 'guide') { guide.hidden = true; stopAll(guide); } }, () => {});
    if (!o.keinFokus) {
      const b = S.back;
      if (b && b !== d.body && d.contains(b) && sichtbar(b)) fokus(b, { instant: true });
      else if (html.classList.contains('cursor')) fokus(startZiel(), { instant: true });
      else mainEl.focus({ preventScroll: true });
    }
    if (!o.still) klang('close');
    updateHints();
  }
  function guideTab(i, o = {}) {
    if (i < 0 || i >= gtabs.length) { anstoss(gtabs[gIndex], o.dir || 'right'); return; }
    if (i === gIndex) return;
    const dir = Math.sign(i - gIndex);
    const alt = gpanes[gIndex];
    const neu = gpanes[i];
    gIndex = i;
    gtabs.forEach((t, n) => t.setAttribute('aria-selected', String(n === i)));
    alt.hidden = true;
    neu.hidden = false;
    play(neu, 'ein', [{ opacity: 0, transform: `translateX(${dir * way(W.ort)}px)` }, { opacity: 1, transform: 'none' }], { duration: dur(T.ort), easing: E.an });
    if (gtabs[i].parentElement.scrollWidth > gtabs[i].parentElement.clientWidth) gtabs[i].scrollIntoView({ block: 'nearest', inline: 'nearest' });
    setzeStrich($('.guide-tablist .chip-line'), gtabs[i], true);
    // Steht der Cursor auf den Reitern, geht er mit (LB/RB); sonst landet er im neuen Inhalt.
    if (d.activeElement && d.activeElement.matches('.gtab')) { if (d.activeElement !== gtabs[i]) fokus(gtabs[i], { instant: true }); }
    else fokus($('[data-default]', neu) || $(FOCUSABLE, neu) || gtabs[i], { instant: true });
    klang('raste');
    updateHints();
  }

  // --- Schnellmenü (Guide-Taste halten): eine Karte unten in der Mitte, wie in Uzai --------------
  function oeffneQuick() {
    if (S.booting || S.layer === 'quick') return;
    let vorher = d.activeElement;
    if (S.layer === 'detail') { vorher = S.back; schliesseSeite(true); }
    if (S.layer === 'guide') { vorher = S.back; schliesseGuide({ keinFokus: true, still: true }); }
    S.layer = 'quick';
    S.back = vorher;
    erfolg('quick');
    quick.hidden = false;
    html.classList.add('quick-open');
    erfolgPlatz();
    ebeneAn('quick');
    uhr();
    zeigeEinstellungen();
    // Dialoge wachsen von unten her auf (96 → 100 %), die Schrift folgt ihrer Fläche.
    play($('.quick-card'), 'ein', [{ opacity: 0, transform: `translateY(${way(W.ort)}px) scale(${calm() ? 1 : 0.96})` }, { opacity: 1, transform: 'none' }],
      { duration: dur(T.raum), easing: E.raum });
    $$('.quick-head, .qtile', quick).forEach((el, i) => play(el, 'ein', [{ opacity: 0, transform: `translateY(${way(10)}px)` }, { opacity: 1, transform: 'none' }],
      { duration: dur(T.ort), delay: calm() ? 0 : NACH_FLAECHE + staffel(i), easing: E.an }));
    puls();
    fokus($('[data-default]', quick), { instant: true });
    klang('open');
    updateHints();
  }
  function schliesseQuick(o = {}) {
    if (S.layer !== 'quick') return;
    S.layer = null;
    html.classList.remove('quick-open');
    erfolgPlatz();
    if (!o.still) ebeneAus();
    play($('.quick-card'), 'ein', [{ opacity: 1 }, { opacity: 0, transform: `translateY(${way(10)}px)` }], { duration: dur(T.weg), easing: E.weg })
      .finished.then(() => { if (S.layer !== 'quick') { quick.hidden = true; } }, () => {});
    if (!o.keinFokus) {
      const b = S.back;
      if (b && b !== d.body && d.contains(b) && sichtbar(b)) fokus(b, { instant: true });
      else if (html.classList.contains('cursor')) fokus(startZiel(), { instant: true });
      else mainEl.focus({ preventScroll: true });
    }
    if (!o.still) klang('back');
    updateHints();
  }
  // Halten öffnet das Schnellmenü, kurz drücken den Guide (Taste G, Guide-Taste, Zeichen).
  const HALTEN = 450;

  // --- Einstellungen im Guide (nur für diesen Tab) ------------------------------------------
  const SET = {
    sound() {
      S.sound = !S.sound;
      store.set('sound', S.sound ? 'on' : 'off');
      if (S.sound && Klang.init()) klang('select');
      zeigeEinstellungen();
    },
    motion() {
      S.motion = { auto: 'reduced', reduced: 'full', full: 'auto' }[S.motion] || 'auto';
      store.set('motion', S.motion);
      bewegung();
      zeigeEinstellungen();
    },
    glyphs() {
      S.glyphs = { auto: 'xbox', xbox: 'ps', ps: 'keys', keys: 'auto' }[S.glyphs] || 'auto';
      store.set('glyphs', S.glyphs);
      alleGlyphen();
      hintsEl._key = '';
      $('.guide-hints')._key = '';
      $('.quick-hints')._key = '';
      updateHints();
      zeigeEinstellungen();
    },
    intro() {
      schliesseGuide({ keinFokus: true });
      setTimeout(() => boot(true), dur(T.weg) + 60);
    },
  };
  function zeigeEinstellungen() {
    $$('[data-set="sound"]').forEach(s => {
      s.setAttribute('aria-checked', String(S.sound));
      $('[data-val]', s).textContent = S.sound ? 'On' : 'Off';
    });
    $$('[data-set="motion"] [data-val]').forEach(v => { v.textContent = { auto: 'Like your system', reduced: 'Reduced', full: 'Full' }[S.motion]; });
    $$('[data-set="glyphs"] [data-val]').forEach(v => { v.textContent = { auto: 'Automatic', xbox: 'Xbox', ps: 'PlayStation', keys: 'Keyboard' }[S.glyphs]; });
    if (S.layer) { hintsEl._key = ''; updateHints(); }
  }
  function bewegung() {
    html.classList.toggle('calm', calm());
    html.classList.toggle('motion-full', S.motion === 'full');
  }

  // --- Mitteilungen: oben rechts, eine Zeitlinie, höchstens drei --------------------------------
  const toastsEl = $('.toasts');
  function mitteilung(icon, titel, zeile, ms = 4200) {
    const el = d.createElement('div');
    el.className = 'toast';
    el.style.setProperty('--dauer', ms + 'ms');
    el.innerHTML = `<span class="toast-ic"><svg class="i" aria-hidden="true"><use href="#i-${icon}"/></svg></span><span class="toast-t"></span><span class="toast-s"></span><span class="toast-time" aria-hidden="true"><i></i></span>`;
    $('.toast-t', el).textContent = titel;
    $('.toast-s', el).textContent = zeile;
    toastsEl.prepend(el);
    while (toastsEl.children.length > 3) toastsEl.lastElementChild.remove();
    el.animate([{ opacity: 0, transform: `translateX(${way(W.leiste)}px)` }, { opacity: 1, transform: 'none' }], { duration: dur(T.ort), easing: E.an });
    klang('notify');
    setTimeout(() => {
      el.animate([{ opacity: 1 }, { opacity: 0, transform: `translateX(${way(W.ort)}px)` }], { duration: dur(T.weg), easing: E.weg, fill: 'forwards' })
        .finished.then(() => el.remove(), () => el.remove());
    }, ms);
  }

  // --- Eingabegerät: Maus, Tastatur, Touch, Controller ---------------------------------------
  function eingabe(mode) {
    if (S.input === mode) return;
    S.input = mode;
    html.dataset.input = mode;
    html.classList.toggle('cursor', mode === 'keys' || mode === 'pad');
    alleGlyphen();
    einladung();
    const el = d.activeElement;
    setzePille(el && el.matches && el.matches('.tab') ? el : null);
    updateHints();
  }
  // Home lädt Schritt für Schritt zum Ausprobieren ein: Guide drücken, halten, Controller anstecken.
  function einladung() {
    const p = $('.invite');
    if (!p) return;
    let text;
    let icon = false;
    let fertig = false;
    if (S.input === 'touch') text = hatErfolg('guide') ? 'Hold the U. That opens the quick menu.' : 'Tap the U. The Guide opens over any game.';
    else if (!hatErfolg('guide')) text = 'The Guide opens over any game. Try it.';
    else if (!hatErfolg('quick')) text = 'Now hold it. That opens the quick menu.';
    else if (!Pad.da.size && !hatErfolg('pad')) { text = 'Plug in a controller. This page follows it.'; icon = true; }
    else { text = 'All set. Start when you like.'; icon = true; fertig = true; }
    $('.invite-text', p).textContent = text;
    p.classList.toggle('mit-icon', icon);
    p.classList.toggle('geschafft', fertig);
  }
  let mausWeg = 0;
  addEventListener('mousemove', e => {
    if (S.input === 'mouse') return;
    mausWeg += Math.abs(e.movementX || 0) + Math.abs(e.movementY || 0);
    if (mausWeg > 30) { mausWeg = 0; eingabe('mouse'); }
  }, { passive: true });
  addEventListener('pointerdown', e => {
    mausWeg = 0;
    if (S.aus) { anschalten(); return; }
    if (S.booting) { bootEnde(); return; }
    if (kinoAnim) kinoEnde();
    if (e.pointerType === 'touch' || e.pointerType === 'pen') eingabe('touch');
    else eingabe('mouse');
  }, { passive: true });
  addEventListener('wheel', () => { if (S.booting) bootEnde(); }, { passive: true });

  // --- Tastatur: Pfeile wie das Steuerkreuz, Enter A, Esc B, Q/E LB/RB, Bild↑/↓ LT/RT, G Guide -----
  const TASTE = { Enter: 'a', ' ': 'a', Escape: 'b', x: 'x', y: 'y', q: 'lb', e: 'rb', PageUp: 'lt', PageDown: 'rt', g: 'guide', f: 'r3', v: 'view', m: 'menu' };
  const PFEIL = { ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'left', ArrowRight: 'right' };
  d.addEventListener('keydown', e => {
    if (e.defaultPrevented || e.altKey || e.ctrlKey || e.metaKey) return;
    if (S.aus) { if (!['Shift', 'Control', 'Alt', 'Meta'].includes(e.key)) { e.preventDefault(); anschalten(); } return; }
    if (kinoAnim && !['Shift', 'Control', 'Alt', 'Meta', 'Tab'].includes(e.key)) kinoEnde();
    if (S.booting) {
      if (!['Shift', 'Control', 'Alt', 'Meta', 'Tab'].includes(e.key)) { e.preventDefault(); bootEnde(); }
      return;
    }
    if (e.key === 'Tab') { eingabe('keys'); if (S.layer) falle(e); return; }
    const dir = PFEIL[e.key];
    if (dir) {
      eingabe('keys');
      if (isConsole() || S.layer) { e.preventDefault(); move(dir); }
      return;
    }
    if (e.key === 'g' || e.key === 'G') {
      e.preventDefault();
      eingabe('keys');
      if (e.repeat) return;
      leuchten('guide');
      if (S.layer === 'quick') { schliesseQuick(); return; }
      if (S.layer === 'guide') { schliesseGuide(); return; }
      clearTimeout(gHalt);
      gHalt = setTimeout(() => { gHalt = 0; oeffneQuick(); }, HALTEN);
      return;
    }
    const k = TASTE[e.key.length === 1 ? e.key.toLowerCase() : e.key];
    if (!k) return;
    eingabe('keys');
    if (e.repeat) { if (k !== 'a') e.preventDefault(); return; }
    if (k === 'a') {
      leuchten('a');
      const el = d.activeElement;
      if (e.key === ' ' && el && el.matches('a[href]')) { e.preventDefault(); el.click(); }
      return;
    }
    if ((k === 'lt' || k === 'rt') && !isConsole() && !S.layer) return;
    e.preventDefault();
    act(k);
  });
  let gHalt = 0;
  d.addEventListener('keyup', e => {
    if ((e.key === 'g' || e.key === 'G') && gHalt) { clearTimeout(gHalt); gHalt = 0; oeffneGuide(); }
  });
  // Tab bleibt in der offenen Ebene.
  function falle(e) {
    const list = candidates();
    if (!list.length) return;
    const i = list.indexOf(d.activeElement);
    const n = e.shiftKey ? (i <= 0 ? list.length - 1 : i - 1) : (i < 0 || i === list.length - 1 ? 0 : i + 1);
    e.preventDefault();
    fokus(list[n]);
  }

  // --- Was jede Taste tut (Tastatur, Controller, Hinweise) ----------------------------------
  function act(k) {
    if (S.aus) { anschalten(); return; }
    leuchten(k);
    if (S.booting) { bootEnde(); return; }
    switch (k) {
      case 'a': aktivieren(); break;
      case 'b': zurueck(); break;
      case 'guide':
        if (S.layer === 'guide') schliesseGuide();
        else if (S.layer === 'quick') schliesseQuick();
        else oeffneGuide();
        break;
      case 'menu': if (S.layer === 'guide') schliesseGuide(); else if (S.layer === 'quick') schliesseQuick(); break;
      case 'lb': case 'rb': schulter(k === 'rb' ? 1 : -1); break;
      case 'rollen': { const t = $('.shelf .more'); if (t && !tafelRollen(t, 'down')) feder(t, 'y', 0); break; }
      case 'lt': case 'rt':
        if (S.layer === 'guide') guideTab(gIndex + (k === 'rt' ? 1 : -1), { dir: k === 'rt' ? 'right' : 'left' });
        else if (S.layer === 'detail') blaettern(k === 'rt' ? 1 : -1);
        else if (S.layer === 'quick') anstoss(d.activeElement, k === 'rt' ? 'right' : 'left');
        else bereichSchritt(k === 'rt' ? 1 : -1);
        break;
      case 'y': {
        const el = d.activeElement;
        if (!S.layer && el && el.matches('.card')) oeffneSeite(el);
        break;
      }
      default: break;
    }
  }
  function aktivieren() {
    const el = d.activeElement;
    if (S.layer === 'detail' && (!el || el === detail)) return;
    if (!el || el === d.body || !candidates().includes(el)) { fokus(startZiel()); klang('move'); return; }
    if (el.matches('a, button, summary')) el.click();
    else druecken(el);
  }
  function zurueck() {
    if (S.layer === 'detail') { schliesseSeite(); return; }
    if (S.layer === 'guide') { schliesseGuide(); return; }
    if (S.layer === 'quick') { schliesseQuick(); return; }
    const el = d.activeElement;
    if (el && mainEl.contains(el) && el !== mainEl) { fokus(tabFor(S.area)); klang('back'); return; }
    anstoss(el && el !== d.body ? el : tabFor(S.area), 'up');
  }
  function schulter(dir) {
    if (S.layer === 'guide') { guideTab(gIndex + dir, { dir: dir > 0 ? 'right' : 'left' }); return; }
    if (S.layer === 'detail') { blaettern(dir); return; }
    if (S.layer === 'quick') { anstoss(d.activeElement, dir > 0 ? 'right' : 'left'); return; }
    if (S.area === 'features' && isConsole()) { abschnitt(dir); return; }
    bereichSchritt(dir);
  }
  // Guide › Controls: die Zeile zur gedrückten Taste leuchtet auf.
  const steuerZeilen = $$('.controls-list .row');
  function leuchten(k) {
    if (S.layer !== 'guide' || !gpanes[gIndex] || gpanes[gIndex].id !== 'gp-controls') return;
    for (const r of steuerZeilen) {
      if (!r.dataset.keys.split(' ').includes(k)) continue;
      r.classList.remove('lit');
      void r.offsetWidth;
      r.classList.add('lit');
    }
  }

  // --- Controller (Gamepad-API, Standardbelegung) ------------------------------------------
  const Pad = { prev: new Map(), raf: 0, da: new Set() };
  const KNOPF = { 0: 'a', 1: 'b', 2: 'x', 3: 'y', 4: 'lb', 5: 'rb', 6: 'lt', 7: 'rt', 8: 'view', 9: 'menu', 10: 'l3', 11: 'r3' };
  function padArt(id) {
    if (/xbox|xinput|045e/i.test(id)) return 'xbox';
    if (/054c|playstation|dualsense|dualshock|wireless controller/i.test(id)) return 'ps';
    if (/057e|nintendo|pro controller|joy-?con/i.test(id)) return 'nintendo';
    return 'xbox';
  }
  function padName(art, id) {
    if (art === 'ps') return 'PlayStation controller';
    if (art === 'nintendo') return 'Nintendo controller';
    return /xbox|xinput|045e/i.test(id) ? 'Xbox controller' : 'Controller';
  }
  function padStatus() {
    const st = $('.pad-state');
    st.hidden = Pad.da.size === 0;
    $('.pad-name', st).textContent = S.padName && S.padName !== 'Controller' ? S.padName.replace(' controller', '') : '';
  }
  addEventListener('gamepadconnected', e => {
    const gp = e.gamepad;
    Pad.da.add(gp.index);
    S.pad = padArt(gp.id);
    S.padName = padName(S.pad, gp.id);
    padStatus();
    mitteilung('controller', `${S.padName} connected`, S.pad === 'ps' ? 'Cross selects, circle goes back.' : 'A selects, B goes back.');
    erfolg('pad');
    eingabe('pad');
    padLos();
    if (!S.booting && !S.layer && !candidates().includes(d.activeElement)) fokus(startZiel(), { instant: true });
    updateHints();
  });
  addEventListener('gamepaddisconnected', e => {
    Pad.da.delete(e.gamepad.index);
    Pad.prev.delete(e.gamepad.index);
    padStatus();
    mitteilung('controller', 'Controller disconnected', 'Keyboard and mouse still work.');
    if (!Pad.da.size && S.input === 'pad') eingabe('keys');
  });
  function padLos() { if (!Pad.raf) Pad.raf = requestAnimationFrame(padSchritt); }
  function padSchritt(now) {
    Pad.raf = 0;
    const list = navigator.getGamepads ? navigator.getGamepads() : [];
    let any = false;
    for (const gp of list) {
      if (!gp || !gp.connected) continue;
      any = true;
      if (!d.hidden) padLesen(gp, now);
    }
    if (any || Pad.da.size) Pad.raf = requestAnimationFrame(padSchritt);
  }
  function padDruck(gp) {
    if (S.input === 'pad') return;
    S.pad = padArt(gp.id);
    S.padName = padName(S.pad, gp.id);
    eingabe('pad');
  }
  function padLesen(gp, now) {
    let p = Pad.prev.get(gp.index);
    if (!p) Pad.prev.set(gp.index, (p = { b: {}, dir: null, next: 0, n: 0, stick: false }));
    const an = i => { const b = gp.buttons[i]; return !!b && (b.pressed || b.value > 0.5); };
    let dir = an(12) ? 'up' : an(13) ? 'down' : an(14) ? 'left' : an(15) ? 'right' : null;
    if (!dir) {
      // Der Stick zählt nur in seiner Hauptrichtung und muss für den nächsten Druck erst zurück.
      const x = gp.axes[0] || 0;
      const y = gp.axes[1] || 0;
      const m = Math.max(Math.abs(x), Math.abs(y));
      if (m > 0.55) dir = Math.abs(x) > Math.abs(y) ? (x > 0 ? 'right' : 'left') : (y > 0 ? 'down' : 'up');
      else if (m > 0.3 && p.stick) dir = p.dir;
      p.stick = !!dir;
    } else p.stick = false;
    // Halten wartet 400 ms, dann ein Schritt alle 160 ms, nach einigen etwas schneller.
    if (dir !== p.dir) {
      p.dir = dir;
      if (dir) { padDruck(gp); if (S.booting) bootEnde(); else move(dir); p.next = now + 400; p.n = 0; }
    } else if (dir && now >= p.next && !S.booting) {
      p.n++;
      move(dir);
      p.next = now + (p.n > 5 ? 110 : 160);
    }
    // Guide-Taste: kurz drücken öffnet den Guide (beim Loslassen), halten das Schnellmenü.
    const gOn = an(16);
    if (gOn && !p.g) {
      padDruck(gp);
      leuchten('guide');
      p.gAb = now;
      p.gFertig = false;
      if (S.booting) { bootEnde(); p.gFertig = true; }
      else if (S.layer === 'quick') { schliesseQuick(); p.gFertig = true; }
      else if (S.layer === 'guide') { schliesseGuide(); p.gFertig = true; }
    } else if (gOn && p.g && !p.gFertig && now - p.gAb >= HALTEN) {
      p.gFertig = true;
      oeffneQuick();
    } else if (!gOn && p.g && !p.gFertig) {
      oeffneGuide();
    }
    p.g = gOn;
    for (const i of Object.keys(KNOPF)) {
      const on = an(+i);
      if (on && !p.b[i]) {
        padDruck(gp);
        const k = KNOPF[i];
        if ((k === 'view' && an(9)) || (k === 'menu' && an(8))) act('guide');
        else act(k);
      }
      p.b[i] = on;
    }
  }

  // --- Klicks ---------------------------------------------------------------------------
  d.addEventListener('click', e => {
    const vorn = e.target.closest('.shelf .card, .shelf .more');
    if (vorn && isConsole() && vorn !== S.feature) {
      e.preventDefault();
      if (html.classList.contains('cursor')) fokus(vorn); else vorn.focus({ preventScroll: true });
      klang('move');
      return;
    }
    const t = e.target.closest('a, button, summary');
    if (!t) return;
    if (t.matches('.hint')) return;
    if (t === markEl) { if (markLang) { markLang = false; return; } act('guide'); return; }
    if (t.hasAttribute('data-weiter')) { e.preventDefault(); druecken(t); weiter(); return; }
    if (t.hasAttribute('data-aus')) { e.preventDefault(); ausschalten(); return; }
    if (t.hasAttribute('data-los') && los(t, e)) return;
    if (t.dataset.q === 'features') { e.preventDefault(); schliesseQuick({ keinFokus: true }); go('features', { focus: 'content' }); return; }
    if (t.dataset.q === 'guide') { e.preventDefault(); oeffneGuide(); return; }
    if (t.matches('.tab')) { e.preventDefault(); go(t.dataset.area); return; }
    if (t.dataset.goto) {
      e.preventDefault();
      if (S.layer === 'guide') schliesseGuide({ keinFokus: true });
      if (S.layer === 'quick') schliesseQuick({ keinFokus: true });
      go(t.dataset.goto, { focus: 'content' });
      return;
    }
    if (t.matches('.card') && !e.ctrlKey && !e.metaKey && !e.shiftKey && e.button === 0) {
      e.preventDefault();
      t.focus({ preventScroll: true });
      oeffneSeite(t);
      return;
    }
    if (t.matches('.chip')) { springeZu(t.dataset.cat, true); return; }
    if (t.matches('.gtab')) { guideTab(gtabs.indexOf(t)); return; }
    if (t.dataset.gtab) { e.preventDefault(); guideTab(gtabs.findIndex(g => g.id === 'gt-' + t.dataset.gtab)); return; }
    if (t.dataset.set) { druecken(t); SET[t.dataset.set](); return; }
    if (t.hasAttribute('data-d-step')) { blaettern(Number(t.dataset.dStep)); return; }
    if (t.hasAttribute('data-d-close')) { schliesseSeite(); return; }
    druecken(t);
    klang('select');
  });
  // Klappt ein Name auf oder zu, verschieben sich die Reiter: Punkt und Pille folgen so lange.
  tabsEl.addEventListener('transitionrun', () => leisteLos(T.ort + 200));
  // Das Zeichen lange drücken (Maus, Finger) öffnet das Schnellmenü.
  let markHalt = 0;
  let markLang = false;
  markEl.addEventListener('pointerdown', e => {
    if (e.button !== 0) return;
    markLang = false;
    clearTimeout(markHalt);
    markHalt = setTimeout(() => { markHalt = 0; markLang = true; oeffneQuick(); }, HALTEN);
  });
  ['pointerup', 'pointerleave', 'pointercancel'].forEach(t => markEl.addEventListener(t, () => { clearTimeout(markHalt); markHalt = 0; }));
  markEl.addEventListener('contextmenu', e => e.preventDefault());
  $('.quick-hints').addEventListener('mousedown', e => e.preventDefault());
  hintsEl.addEventListener('mousedown', e => e.preventDefault());
  $('.guide-hints').addEventListener('mousedown', e => e.preventDefault());
  const hintKlick = e => { const b = e.target.closest('.hint'); if (b) act(b.dataset.act); };
  hintsEl.addEventListener('click', hintKlick);
  $('.guide-hints').addEventListener('click', hintKlick);
  $('.quick-hints').addEventListener('click', hintKlick);
  // Ein Klick neben die Karte schließt das Schnellmenü.
  quick.addEventListener('click', e => { if (!e.target.closest('.quick-card, .quick-hints')) schliesseQuick(); });
  veil.addEventListener('click', () => zurueck());
  // Aufgeklappt rollt die Fläche weich so weit, dass der neue Inhalt ganz zu sehen ist.
  $('.build').addEventListener('toggle', e => {
    const b = e.currentTarget;
    const a = b.closest('.area');
    updateHints();
    randZeigen(a);
    if (b.open && isConsole()) requestAnimationFrame(() => senkrecht(a, b));
  });

  // Ein Cursor: er bleibt auf dem Gewählten, auch wenn das Fenster kurz den Fokus verliert.
  let gewaehlt = null;
  function markiere(el) {
    if (gewaehlt && gewaehlt !== el) gewaehlt.classList.remove('is-sel');
    gewaehlt = el;
    if (el) el.classList.add('is-sel');
  }
  // Fokus: Zone (Leiste ruht, wenn man unten arbeitet), Gedächtnis je Bereich und Gruppe, Bühne.
  d.addEventListener('focusin', e => nachFokus(e.target));
  function nachFokus(el) {
    markiere(el === mainEl || el === detail || el === d.body ? null : el);
    html.dataset.zone = el === markEl || barEl.contains(el) ? 'bar' : mainEl.contains(el) && el !== mainEl ? 'content' : 'layer';
    const area = el.closest && el.closest('.area');
    if (area) S.remember[area.id] = el;
    const g = el.closest && el.closest('[data-nav-group]');
    if (g && g.dataset.navGroup) S.remember['g:' + g.dataset.navGroup] = el;
    if (el.matches('.shelf .card, .shelf .more')) waehle(el);
    setzePille(el.matches('.tab') ? el : null);
    updateHints();
  }
  d.addEventListener('focusout', () => setTimeout(() => {
    const el = d.activeElement;
    if (!el || el === d.body || el === mainEl) {
      if (d.hasFocus()) markiere(null);
      html.dataset.zone = 'none';
      setzePille(null);
      updateHints();
    }
  }, 0));

  // Das Rad über der Bühne blättert Schritt für Schritt (Touchpads liefern viele kleine Schritte).
  let radSumme = 0;
  let radZeit = 0;
  let radLetzt = 0;
  shelf.addEventListener('wheel', e => {
    if (!isConsole() || S.layer) return;
    // Über „Also inside“ vorn rollt das Rad die Liste (senkrecht); seitwärts blättert es weiter.
    const tafel = e.target.closest && e.target.closest('.more');
    if (tafel && tafel === S.feature && Math.abs(e.deltaY) >= Math.abs(e.deltaX) && tafel.scrollHeight > tafel.clientHeight + 2) { federn.delete(tafel); return; }
    e.preventDefault();
    const jetzt = performance.now();
    if (jetzt - radLetzt > 260) radSumme = 0;
    radLetzt = jetzt;
    const dl = Math.abs(e.deltaX) > Math.abs(e.deltaY) ? e.deltaX : e.deltaY;
    radSumme += dl * (e.deltaMode === 1 ? 32 : 1);
    if (Math.abs(radSumme) >= 50 && jetzt - radZeit > 200) {
      regalSchritt(radSumme > 0 ? 1 : -1);
      radSumme = 0;
      radZeit = jetzt;
    }
  }, { passive: false });
  // Ein Klick auf ein Bild rechts holt es erst nach vorn: der Fokus darf beim Drücken noch nicht
  // springen, sonst wäre es beim Klick schon vorn und die Seite ginge gleich auf.
  shelf.addEventListener('mousedown', e => {
    const it = e.target.closest('.card, .more');
    if (it && isConsole() && it !== S.feature) e.preventDefault();
  });
  // Ziehen (Maus, Finger, Stift): die Bühne folgt der Hand in beide Richtungen – nach links holt die
  // nächsten Bilder nach vorn, nach rechts die vorigen zurück – und rastet beim Loslassen auf dem
  // nächsten Platz ein; Schwung zählt mit, an den Enden gibt sie nur noch zäh nach. Ein kurzer Klick
  // bleibt ein Klick.
  const ZUG = { id: null, x0: 0, y0: 0, f: 0, cur: 0, an: false, spur: [], raf: 0 };
  let gezogen = false;
  const zugSchritt = () => 760 * kpx();
  function zugMalen() {
    ZUG.raf = 0;
    items.forEach((it, i) => {
      const li = it.closest('li');
      const rel = i - ZUG.cur - ZUG.f;
      const p = platzF(rel);
      li.style.setProperty('--x', p.x.toFixed(1));
      li.style.setProperty('--y', p.y.toFixed(1));
      li.style.setProperty('--s', p.s.toFixed(4));
      li.style.setProperty('--o', p.o.toFixed(3));
      li.style.setProperty('--z', String(p.z));
      li.style.setProperty('--b', p.b.toFixed(3));
      li.style.setProperty('--r', p.r.toFixed(2));
      li.classList.toggle('weg', p.o <= 0.002);
      if (Math.abs(rel) < 1.6) gross(it);
    });
  }
  shelf.addEventListener('pointerdown', e => {
    gezogen = false;
    if (!isConsole() || S.layer || !S.feature || e.button > 0) return;
    Object.assign(ZUG, { id: e.pointerId, x0: e.clientX, y0: e.clientY, f: 0, an: false, cur: items.indexOf(S.feature), spur: [[performance.now(), e.clientX]] });
  });
  shelf.addEventListener('pointermove', e => {
    if (e.pointerId !== ZUG.id) return;
    const dx = e.clientX - ZUG.x0;
    if (!ZUG.an) {
      // Erst ab ein paar Punkten und eher waagrecht wird gezogen; sonst bleibt es ein Klick.
      if (Math.abs(dx) < 8 || Math.abs(dx) < Math.abs(e.clientY - ZUG.y0)) return;
      ZUG.an = true;
      ZUG.x0 = e.clientX;
      try { shelf.setPointerCapture(e.pointerId); } catch (err) { /* schon losgelassen */ }
      shelf.classList.add('ziehen');
    }
    const jetzt = performance.now();
    ZUG.spur.push([jetzt, e.clientX]);
    while (ZUG.spur.length > 2 && jetzt - ZUG.spur[0][0] > 120) ZUG.spur.shift();
    let f = -(e.clientX - ZUG.x0) / zugSchritt();
    const lo = -ZUG.cur;
    const hi = items.length - 1 - ZUG.cur;
    if (f < lo) f = lo - (lo - f) * 0.3;
    if (f > hi) f = hi + (f - hi) * 0.3;
    ZUG.f = f;
    if (!ZUG.raf) ZUG.raf = requestAnimationFrame(zugMalen);
  });
  function zugEnde(e, abbruch) {
    if (e.pointerId !== ZUG.id) return;
    ZUG.id = null;
    if (!ZUG.an) return;
    ZUG.an = false;
    gezogen = true;
    if (ZUG.raf) { cancelAnimationFrame(ZUG.raf); ZUG.raf = 0; }
    zugMalen();
    void shelf.offsetWidth;
    shelf.classList.remove('ziehen');
    // Schwung: wohin die Bewegung in den letzten 120 ms ging, zählt etwa 0,2 s weiter.
    const [t0, x0] = ZUG.spur[0];
    const [t1, x1] = ZUG.spur[ZUG.spur.length - 1];
    const v = t1 > t0 ? (x1 - x0) / (t1 - t0) : 0;
    const ziel = abbruch ? 0 : Math.round(ZUG.f - (v * 200) / zugSchritt());
    regalZu(ZUG.cur + Math.max(-ZUG.cur, Math.min(items.length - 1 - ZUG.cur, ziel)));
  }
  shelf.addEventListener('pointerup', e => zugEnde(e, false));
  shelf.addEventListener('pointercancel', e => zugEnde(e, true));
  // Nach dem Ziehen kein Klick (sonst ginge das Bild unter der Hand gleich auf); Bilder und Links
  // werden nicht als Datei gezogen.
  shelf.addEventListener('click', e => { if (gezogen) { gezogen = false; e.preventDefault(); e.stopPropagation(); } }, true);
  shelf.addEventListener('dragstart', e => e.preventDefault());
  $$('.area').forEach(a => {
    a.addEventListener('wheel', () => federn.delete(a), { passive: true });
    a.addEventListener('scroll', () => randZeigen(a), { passive: true });
  });
  // „Also inside“: Ränder wie bei den Flächen; steht es nicht mehr vorn, geht es zurück an den Anfang.
  $$('.shelf .more').forEach(t => {
    t.addEventListener('scroll', () => randZeigen(t), { passive: true });
    if ('ResizeObserver' in window) {
      new ResizeObserver(() => {
        if (!t.closest('li').classList.contains('is-cur')) { federn.delete(t); t.scrollTop = 0; }
        randZeigen(t);
        updateHints();
      }).observe(t);
    }
  });
  // Ränder einer Fläche: oben blendet aus, wenn gerollt ist; unten, solange noch etwas folgt.
  function randZeigen(a) {
    a.classList.toggle('scrolled', a.scrollTop > 2);
    a.classList.toggle('hat-mehr', a.scrollTop < a.scrollHeight - a.clientHeight - 2);
  }

  // --- Uhr (die eigene Zeit des Besuchers, wie oben rechts in Uzai) -------------------------
  const uhrFmt = new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' });
  function uhr() {
    const t = uhrFmt.format(new Date());
    $$('.clock').forEach(c => { if (c.textContent !== t) c.textContent = t; });
  }
  function uhrTakt() {
    uhr();
    setTimeout(uhrTakt, 60000 - (Date.now() % 60000) + 40);
  }

  // --- Startanimation (src/ui/boot.gd): Linie, Bänder, Name, dann gleitet das Zeichen heim -------
  const bootEl = $('.boot');
  let bootTimer = 0;
  let bootKlang = 0;
  let bootAnims = [];
  let gleitet = false;
  function bootAt(sel, frames, o) {
    const el = typeof sel === 'string' ? $(sel, bootEl) : sel;
    const a = el.animate(frames, Object.assign({ fill: 'both' }, o));
    bootAnims.push(a);
    return a;
  }
  function boot(wieder) {
    if (!wieder && !html.classList.contains('boot-on')) return false;
    S.booting = true;
    gleitet = false;
    html.classList.add('boot-on');
    bootAnims.forEach(a => a.cancel());
    bootAnims = [];
    clearTimeout(bootTimer);
    // Uzais Startklang (sfx.gd: „boot“), wenn das Zeichen sich füllt; übersprungen bleibt es still.
    clearTimeout(bootKlang);
    bootKlang = setTimeout(() => { if (S.booting && !gleitet) klang('boot'); }, calm() ? 200 : 700);
    if (calm()) {
      // Ruhig: Zeichen und Name blenden nur ein.
      bootAt('.boot-line', [{ strokeDashoffset: 0 }, { strokeDashoffset: 0 }], { duration: 1 });
      bootAt('.boot-u', [{ opacity: 0 }, { opacity: 1 }], { delay: 200, duration: 400, easing: E.an });
      bootAt('.boot-out', [{ opacity: 1 }, { opacity: 1 }], { duration: 1 });
      bootAt('.boot-in', [{ opacity: 1 }, { opacity: 1 }], { duration: 1 });
      bootAt('.boot-word', [{ opacity: 0 }, { opacity: 1 }], { delay: 500, duration: 400, easing: E.an });
      bootTimer = setTimeout(bootGleiten, 1400);
    } else {
      bootAt('.boot-line', [{ strokeDashoffset: 1 }, { strokeDashoffset: 0 }], { delay: 350, duration: 750, easing: 'cubic-bezier(.45,.05,.25,1)' });
      bootAt('.boot-out', [{ opacity: 0, transform: 'scale(1.07)' }, { opacity: 1, transform: 'scale(1)' }], { delay: 750, duration: 550, easing: E.an });
      bootAt('.boot-in', [{ opacity: 0, transform: 'scale(.9)' }, { opacity: 1, transform: 'scale(1)' }], { delay: 750, duration: 550, easing: E.an });
      bootAt('.boot-whole', [{ transform: 'scale(1.06)' }, { transform: 'scale(1)' }], { duration: 1650, easing: E.raum });
      bootAt('.boot-gloss', [{ transform: 'translateX(-90px)' }, { transform: 'translateX(240px)' }], { delay: 1350, duration: 900, easing: 'cubic-bezier(.45,0,.55,1)' });
      bootAt('.boot-word', [{ opacity: 0 }, { opacity: 1 }], { delay: 1550, duration: 600, easing: E.an });
      bootTimer = setTimeout(bootGleiten, 2550);
    }
    updateHints();
    return true;
  }
  function bootGleiten() {
    if (!S.booting || gleitet) return;
    gleitet = true;
    clearTimeout(bootTimer);
    const u = $('.boot-u', bootEl);
    const ziel = $('.mark .u').getBoundingClientRect();
    const von = u.getBoundingClientRect();
    const dauer = calm() ? 0 : 640;
    if (dauer && ziel.height > 0) {
      const s = ziel.height / von.height;
      bootAt(u, [{ transform: 'none' }, { transform: `translate(${ziel.left - von.left}px, ${ziel.top - von.top}px) scale(${s})` }], { duration: dauer, easing: E.flug });
      $$('.b-flat', bootEl).forEach(p => bootAt(p, [{ opacity: 0 }, { opacity: 1 }], { duration: dauer * 0.6, easing: E.an }));
      $$('.b-elox', bootEl).forEach(p => bootAt(p, [{ opacity: 1 }, { opacity: 0 }], { duration: dauer * 0.6, easing: E.an }));
    } else {
      bootAt(u, [{ opacity: 1 }, { opacity: 0 }], { duration: dur(T.raum), easing: E.weg });
    }
    bootAt('.boot-word', [{ opacity: 1 }, { opacity: 0 }], { duration: T.weg, easing: E.weg });
    bootAt(bootEl, [{ backgroundColor: 'rgb(4 4 6)' }, { backgroundColor: 'rgb(4 4 6 / 0)' }], { duration: T.raum, delay: dauer ? 140 : 0, easing: E.weg });
    if (dauer && einschaltenBild()) ankunft(KINO_HALT + 380, $('.home-shot'));
    else ankunft();
    bootTimer = setTimeout(bootFertig, Math.max(dauer, T.raum + 140) + 30);
  }
  function bootEnde() {
    kinoEnde();
    if (!S.booting || gleitet) return;
    gleitet = true;
    clearTimeout(bootTimer);
    bootAt(bootEl, [{ opacity: 1 }, { opacity: 0 }], { duration: T.weg, easing: E.weg });
    ankunft();
    bootTimer = setTimeout(bootFertig, T.weg + 30);
  }
  function bootFertig() {
    html.classList.remove('boot-on');
    bootAnims.forEach(a => a.cancel());
    bootAnims = [];
    S.booting = false;
    gleitet = false;
    if (S.input === 'pad' && !candidates().includes(d.activeElement)) fokus(startZiel(), { instant: true });
    updateHints();
  }
  // Einschalten: Nach dem Intro füllt Uzais Startseite (der Bildschirm im Fernseher-Bild) den ganzen
  // Schirm, ihr Zeichen genau unter unserem; dann fährt die Kamera zurück, das Bild sinkt in den
  // Fernseher, und die Seite baut sich drumherum auf. Maße aus media/hero.webp (2000 × 1250):
  // Bildschirm 219–1781 × 117–996, Uzais Zeichen in der Mitte bei 305, 161.
  const TV = { w: 2000, sx0: 219, sy0: 117, sx1: 1781, sy1: 996, ux: 305, uy: 161 };
  const KINO_HALT = 520;
  const KINO_FAHRT = 1150;
  let kinoAnim = null;
  function einschaltenBild() {
    if (!isConsole() || calm() || S.area !== 'home') return false;
    const fig = $('.home-shot');
    const img = $('img', fig);
    if (!img.complete || !img.naturalWidth) return false;
    const r = fig.getBoundingClientRect();
    const m = $('.mark .u').getBoundingClientRect();
    if (!r.width || !m.width) return false;
    const f = r.width / TV.w;
    const mx = m.left + m.width / 2;
    const my = m.top + m.height / 2;
    const vw = innerWidth;
    const vh = innerHeight;
    // So groß, dass der Bildschirm den Schirm ganz deckt, während sein Zeichen auf unserem liegt.
    const s = 1.004 * Math.max(mx / ((TV.ux - TV.sx0) * f), my / ((TV.uy - TV.sy0) * f),
      (vw - mx) / ((TV.sx1 - TV.ux) * f), (vh - my) / ((TV.sy1 - TV.uy) * f));
    const tx = mx - r.left - s * TV.ux * f;
    const ty = my - r.top - s * TV.uy * f;
    const voll = `translate(${tx.toFixed(1)}px, ${ty.toFixed(1)}px) scale(${s.toFixed(4)})`;
    const gesamt = KINO_HALT + KINO_FAHRT;
    kinoAnim = fig.animate([
      { transform: voll, '--hm': '260%', easing: 'linear' },
      { transform: voll, '--hm': '260%', offset: KINO_HALT / gesamt, easing: 'cubic-bezier(.62,0,.22,1)' },
      { transform: 'none', '--hm': '70%' },
    ], { duration: gesamt, fill: 'backwards' });
    kinoAnim.finished.then(() => { kinoAnim = null; }, () => { kinoAnim = null; });
    return true;
  }
  function kinoEnde() {
    if (kinoAnim) kinoAnim.finish();
    ankunftAnims.forEach(a => { try { a.finish(); } catch (e) { /* schon fertig */ } });
    ankunftAnims = [];
  }

  // Danach baut sich die Seite auf: die Leiste gleitet von oben herein, der Inhalt steigt gestaffelt.
  let ankunftAnims = [];
  function ankunft(spaeter = 0, ohne = null) {
    ankunftAnims = [];
    const merk = a => { ankunftAnims.push(a); return a; };
    const teile = $$('[data-rise]', isConsole() ? areaEl(S.area) : areaEl('home')).filter(el => el !== ohne).slice(0, 6);
    if (calm()) {
      [barEl, mainEl].forEach(el => el.animate([{ opacity: 0 }, { opacity: 1 }], { duration: dur(T.raum), easing: E.an }));
      return;
    }
    [...tabs, $('.status')].forEach((el, i) => merk(el.animate([{ opacity: 0, transform: `translateY(${-way(W.ort)}px)` }, { opacity: 1, transform: 'none' }],
      { duration: T.raum, delay: spaeter + 120 + staffel(i), easing: E.raum, fill: 'backwards' })));
    teile.forEach((el, i) => merk(el.animate([{ opacity: 0, transform: `translateY(${way(W.ort)}px)` }, { opacity: 1, transform: 'none' }],
      { duration: T.raum + 100, delay: spaeter + 200 + i * 45, easing: E.raum, fill: 'backwards' })));
    merk(hintsEl.animate([{ opacity: 0 }, { opacity: 1 }], { duration: T.raum, delay: spaeter + 460, easing: E.an, fill: 'backwards' }));
    merk(dot.animate([{ opacity: 0 }, { opacity: 1 }], { duration: T.raum, delay: spaeter + 300, easing: E.an, fill: 'backwards' }));
  }

  // --- Seite ohne Konsole (Handy, schmale Fenster): der Punkt folgt dem Abschnitt im Bild --------
  if ('IntersectionObserver' in window) {
    const io = new IntersectionObserver(es => {
      if (isConsole()) return;
      for (const en of es) {
        if (!en.isIntersecting || en.target.id === S.area) continue;
        S.area = en.target.id;
        html.dataset.area = S.area;
        markTabs(true);
        besuchen(S.area);
        guideJetzt();
      }
    }, { rootMargin: '-35% 0px -60% 0px' });
    AREAS.forEach(a => io.observe(areaEl(a)));
  }
  function neuLayout() {
    flugAbbruch();
    federn.clear();
    markTabs(false);
    const sel = d.activeElement;
    setzePille(sel && sel.matches && sel.matches('.tab') ? sel : null);
    if (S.feature) chipAktiv(info(S.feature).cat, false);
    raumFuer(S.area);
    layoutRegal(true);
    if (!isConsole()) items.forEach(it => { it.closest('li').style.pointerEvents = ''; });
    if (!isConsole()) areaEl(S.area).scrollIntoView({ block: 'start' });
    updateHints();
  }
  mqConsole.addEventListener('change', neuLayout);
  mqReduce.addEventListener('change', () => { bewegung(); zeigeEinstellungen(); });
  let resizeT = 0;
  addEventListener('resize', () => {
    clearTimeout(resizeT);
    resizeT = setTimeout(() => {
      markTabs(false);
      if (S.feature) chipAktiv(info(S.feature).cat, false);
      setzeStrich($('.guide-tablist .chip-line'), gtabs[gIndex], false);
      raumFuer(S.area);
    }, 120);
  });

  // --- Weiter: vom Ort, an dem man ist, zum nächsten (Start auf Home, Continue im Guide) ----------
  const BEREICH = { home: ['home', 'Home'], features: ['apps', 'Features'], get: ['download', 'Get Uzai'], privacy: ['lock', 'Privacy'] };
  const naechster = a => AREAS[(AREAS.indexOf(a) + 1) % AREAS.length];
  function weiter() {
    const ziel = naechster(S.area);
    if (S.layer === 'guide') schliesseGuide({ keinFokus: true, still: true });
    if (S.layer === 'quick') schliesseQuick({ keinFokus: true, still: true });
    if (!S.layer) ebeneAus();
    klang('select');
    go(ziel, { focus: 'content' });
  }
  function guideJetzt() {
    const [ic, name] = BEREICH[S.area] || BEREICH.home;
    const nach = (BEREICH[naechster(S.area)] || BEREICH.home)[1];
    const use = $('[data-now-icon]');
    if (use) use.setAttribute('href', '#i-' + ic);
    $('[data-now-title]').textContent = name;
    $('[data-now-sub]').textContent = 'Next: ' + nach;
  }

  // --- Erfolge: wie in jedem Spiel in Uzai, mit Uzais Pop-up und Uzai-Punkten (nur für diesen Tab) ---
  const ERFOLGE = [
    { id: 'guide', name: 'Over any game', desc: 'Opened the Guide.', p: 10 },
    { id: 'quick', name: 'Hold it', desc: 'Held the Guide button for the quick menu.', p: 10 },
    { id: 'seite', name: 'Up close', desc: 'Opened a feature full size.', p: 10 },
    { id: 'pad', name: 'Player one', desc: 'Connected a controller.', p: 25, selten: true },
    { id: 'aus', name: 'Lights out', desc: 'Turned it off and on again.', p: 25 },
    { id: 'tour', name: 'Grand tour', desc: 'Saw every area.', p: 50, selten: true },
  ];
  const lies = (key, ersatz) => { try { return JSON.parse(store.get(key) || '') || ersatz; } catch (e) { return ersatz; } };
  const erreicht = lies('erfolge', {});
  const besucht = new Set(lies('besucht', []));
  const hatErfolg = id => !!erreicht[id];
  const punkte = () => ERFOLGE.reduce((n, e) => n + (erreicht[e.id] ? e.p : 0), 0);
  function erfolg(id) {
    if (erreicht[id]) return;
    const e = ERFOLGE.find(x => x.id === id);
    if (!e) return;
    erreicht[id] = Date.now();
    store.set('erfolge', JSON.stringify(erreicht));
    erfolgeZeigen();
    einladung();
    Popup.zeigen(e);
  }
  function besuchen(area) {
    if (besucht.has(area)) return;
    besucht.add(area);
    store.set('besucht', JSON.stringify([...besucht]));
    if (AREAS.every(a => besucht.has(a))) erfolg('tour');
  }
  function erfolgeZeigen() {
    const n = ERFOLGE.filter(e => erreicht[e.id]).length;
    const pts = punkte();
    $('[data-erfolg-n]').textContent = `${n}/${ERFOLGE.length}`;
    $('[data-stufe]').textContent = `Level ${1 + Math.floor(pts / 50)} · ${pts} points`;
    const ul = $('.erfolg-liste');
    ul.textContent = '';
    ERFOLGE.forEach(e => {
      const li = d.createElement('li');
      li.className = 'erow' + (erreicht[e.id] ? ' is-da' : '') + (e.selten ? ' selten' : '');
      li.innerHTML = '<span class="e-ic"><svg class="i" aria-hidden="true"><use href="#i-trophy"/></svg></span><span class="e-copy"><span class="e-t"></span><span class="e-s"></span></span><span class="e-p"></span>';
      $('.e-t', li).textContent = e.name;
      $('.e-s', li).textContent = e.desc;
      $('.e-p', li).textContent = '+' + e.p;
      ul.append(li);
    });
  }

  // Uzais Erfolgs-Pop-up (src/ui/components/achievement_toast.gd), dieselbe Zeitfunktion frame(t):
  // der Kreis springt auf (115 %), ein Lichtring läuft aus, er öffnet sich zur Pille, die Schrift
  // gleitet herein, die Punkte zählen hoch und pulsieren, ein Schimmer läuft; dann schließt sie sich.
  // Steht das Schnellmenü unten, rückt das Pop-up über seine Karte statt sie zu verdecken.
  const erfolgEl = $('.erfolg');
  function erfolgPlatz() {
    if (html.classList.contains('quick-open') && !quick.hidden) {
      const ek = Math.max(0.62, kpx());
      erfolgEl.style.bottom = Math.round(innerHeight - $('.quick-card').offsetTop + 70 * ek) + 'px';
    } else erfolgEl.style.bottom = '';
  }
  addEventListener('resize', erfolgPlatz);

  const Popup = (() => {
    const el = $('.ach');
    const q = c => $(c, el);
    const pille = q('.ach-pille');
    const schatten = q('.ach-schatten');
    const glanz = q('.ach-glanz');
    const ring = q('.ach-ring');
    const disc = q('.ach-disc');
    const text = q('.ach-text');
    const l1 = q('.ach-l1');
    const l1b = q('.ach-l1b');
    const l2 = q('.ach-l2');
    const pts = q('.ach-pts');
    const ptsB = $('b', pts);
    const H = 92, R = 46, INSET = 7, TEXT_GAP = 18, PTS_GAP = 44, PAD_R = 34, MIN_W = 600, MAX_W = 1060, IN_END = 1.0, OUT_LEN = 0.8, HALTEN = 3.4;
    const seg = (t, a, b) => Math.min(1, Math.max(0, (t - a) / (b - a)));
    const oc = x => 1 - Math.pow(1 - x, 3);
    const oq = x => 1 - Math.pow(1 - x, 5);
    const ioc = x => (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2);
    const ios = x => -(Math.cos(Math.PI * x) - 1) / 2;
    const oe = x => (x >= 1 ? 1 : 1 - Math.pow(2, -10 * x));
    const lerp = (a, b, k) => a + (b - a) * k;
    function frame(t, hold, sweeps) {
      const he = IN_END + hold;
      const f = {};
      let sc = t < 0.22 ? 1.15 * oc(seg(t, 0, 0.22)) : t < 0.38 ? lerp(1.15, 1, ios(seg(t, 0.22, 0.38))) : 1;
      const o0 = he + 0.52;
      if (t >= o0) {
        if (t < o0 + 0.09) sc = lerp(1, 1.08, oc(seg(t, o0, o0 + 0.09)));
        else { const k = seg(t, o0 + 0.09, o0 + 0.28); sc = 1.08 * (1 - k * k); }
      }
      f.s = Math.max(sc, 0);
      f.a = Math.min(1, t / 0.06) * (1 - seg(t, o0 + 0.17, o0 + 0.28));
      f.wk = oq(seg(t, 0.3, 0.88)) * (1 - ioc(seg(t, he + 0.12, he + 0.52)));
      const ok = seg(t, he, he + 0.2);
      f.l1a = oc(seg(t, 0.52, 0.86)) * (1 - ok);
      f.l1x = -16 * (1 - oe(seg(t, 0.52, 0.98))) - 10 * ok * ok;
      f.l2a = oc(seg(t, 0.6, 0.94)) * (1 - ok);
      f.l2x = -16 * (1 - oe(seg(t, 0.6, 1.06))) - 10 * ok * ok;
      f.pa = oc(seg(t, 0.62, 0.9)) * (1 - ok);
      f.pk = oc(seg(t, 0.7, 1.3));
      f.pb = 1 + 0.16 * Math.sin(Math.PI * seg(t, 1.3, 1.5));
      f.ring = t >= 0.08 && t < 0.83 ? seg(t, 0.08, 0.83) : -1;
      f.sweep = t >= 1 && t < 1.8 ? seg(t, 1, 1.8) : sweeps > 1 && he - 0.25 >= 3.1 && t >= 2.3 && t < 3.1 ? seg(t, 2.3, 3.1) : -1;
      f.dk = seg(t, IN_END + 1.0, IN_END + 1.3);
      f.done = t >= he + OUT_LEN;
      return f;
    }
    // Ruhige Bewegung: kein Federn, kein Ring, kein Glanz – nur ein- und ausblenden.
    function frameRuhig(t, hold) {
      const he = IN_END + hold;
      const aus = seg(t, he, he + 0.3);
      return { s: 1, a: Math.min(1, t / 0.25) * (1 - aus), wk: 1, l1a: 1, l1x: 0, l2a: 1, l2x: 0, pa: 1, pk: 1, pb: 1,
        ring: -1, sweep: -1, dk: seg(t, IN_END + 1.0, IN_END + 1.3), done: t >= he + 0.3 };
    }
    const schlange = [];
    let laeuft = false;
    let jetzt = null;
    let t0 = 0;
    let wVoll = MIN_W;
    let ek = 1;
    function zeigen(e) {
      schlange.push(e);
      if (!laeuft) naechstes();
    }
    function naechstes() {
      if (!schlange.length) { laeuft = false; return; }
      laeuft = true;
      if (S.booting || S.aus || d.hidden) { setTimeout(naechstes, 500); return; }
      jetzt = schlange.shift();
      el.classList.toggle('selten', !!jetzt.selten);
      l1.textContent = 'Achievement unlocked';
      l1b.textContent = jetzt.desc;
      l2.textContent = jetzt.name;
      ptsB.textContent = '+' + jetzt.p;
      erfolgEl.style.removeProperty('--ek');
      el.hidden = false;
      el.style.opacity = '0';
      ek = Math.max(0.62, kpx());
      const tw = Math.max(l1.scrollWidth, l2.scrollWidth, l1b.scrollWidth) / ek;
      const pw = Math.max(ptsB.scrollWidth, $('small', pts).scrollWidth) / ek;
      wVoll = Math.min(MAX_W, Math.max(MIN_W, H + TEXT_GAP + PTS_GAP + pw + PAD_R + tw));
      if (wVoll * ek > innerWidth - 24) {
        ek = (innerWidth - 24) / wVoll;
        erfolgEl.style.setProperty('--ek', ek.toFixed(3) + 'px');
      }
      klang(jetzt.selten ? 'unlock_rare' : 'unlock');
      t0 = performance.now();
      requestAnimationFrame(schritt);
    }
    function schritt(now) {
      const t = (now - t0) / 1000;
      const f = calm() ? frameRuhig(t, HALTEN) : frame(t, HALTEN, jetzt.selten ? 2 : 1);
      setze(f, t);
      if (f.done) { el.hidden = true; setTimeout(naechstes, 260); return; }
      requestAnimationFrame(schritt);
    }
    function setze(f) {
      const w = H + (wVoll - H) * f.wk;
      const px = v => (v * ek).toFixed(2) + 'px';
      el.style.opacity = f.a.toFixed(3);
      el.style.transform = `scale(${f.s.toFixed(4)})`;
      const links = -w / 2;
      // Geschlossen ein Kreis, offen mit der Rundung des Themes (Graphit: fast eckig, 8).
      const rad = lerp(8, R, Math.min(1, Math.max(0, 1 - (w / 2 - R) / R)));
      for (const b of [pille, schatten]) { b.style.left = px(links); b.style.width = px(w); b.style.borderRadius = px(rad); }
      const dr = R - INSET;
      const cx = links + R;
      disc.style.left = px(cx - dr);
      disc.style.top = px(-dr);
      disc.style.width = disc.style.height = px(dr * 2);
      if (f.ring >= 0) {
        const rr = lerp(dr + 2, R * 2.25, f.ring);
        ring.style.left = px(cx - rr);
        ring.style.top = px(-rr);
        ring.style.width = ring.style.height = px(rr * 2);
        ring.style.borderWidth = px(lerp(2.6, 0.8, f.ring));
        ring.style.opacity = (Math.pow(1 - f.ring, 1.7) * 0.8).toFixed(3);
      } else ring.style.opacity = '0';
      text.style.left = px(links + H + TEXT_GAP);
      l1.style.opacity = (f.l1a * (1 - f.dk)).toFixed(3);
      l1b.style.opacity = (f.l1a * f.dk).toFixed(3);
      l1.style.transform = l1b.style.transform = `translateX(${px(f.l1x)})`;
      l2.style.opacity = f.l2a.toFixed(3);
      l2.style.transform = `translateX(${px(f.l2x)})`;
      pts.style.left = px(w / 2 - PAD_R);
      pts.style.transform = 'translateX(-100%)';
      pts.style.opacity = f.pa.toFixed(3);
      ptsB.textContent = '+' + Math.round(jetzt.p * f.pk);
      ptsB.style.transform = `scale(${f.pb.toFixed(3)})`;
      if (f.sweep >= 0) {
        glanz.style.opacity = '1';
        glanz.style.transform = `translateX(${px((f.sweep * 1.5 - 0.45) * w)})`;
      } else glanz.style.opacity = '0';
    }
    return { zeigen };
  })();

  // --- Ausschalten wie in Uzai (power_off.gd): die Oberfläche tritt zurück, fällt wie bei einem
  // Röhrenfernseher zur hellen Linie zusammen, die Linie zum Punkt im Akzent, der verglimmt. Danach
  // schwarz, bis eine Taste sie wieder anschaltet – mit Startanimation und Einschalten.
  const welt = $('.welt');
  const powerEl = $('.power');
  const punktEl = $('.power-punkt');
  const powerHint = $('.power-hint');
  let ausAnims = [];
  let ausZeit = 0;
  function ausschalten() {
    if (S.booting || S.aus) return;
    if (S.layer === 'quick') schliesseQuick({ keinFokus: true, still: true });
    if (S.layer === 'guide') schliesseGuide({ keinFokus: true, still: true });
    if (S.layer === 'detail') schliesseSeite(true);
    S.aus = true;
    ausZeit = performance.now();
    klang('power_off');
    html.style.background = '#000';
    powerEl.hidden = false;
    powerEl.style.background = 'transparent';
    const merk = a => { ausAnims.push(a); return a; };
    merk(erfolgEl.animate([{ opacity: 1 }, { opacity: 0 }], { duration: dur(T.weg), easing: E.weg, fill: 'forwards' }));
    if (!calm() && isConsole()) {
      merk(welt.animate([
        { transform: 'none', filter: 'brightness(1)', clipPath: 'inset(0 round 0px)', opacity: 1, offset: 0 },
        { transform: 'scale(0.94)', filter: 'brightness(0.55)', clipPath: 'inset(0 round 30px)', opacity: 1, offset: 0.39, easing: 'cubic-bezier(.4,0,.2,1)' },
        { transform: 'scale(0.94, 0.0045)', filter: 'brightness(3.2) saturate(0)', clipPath: 'inset(0 round 30px)', opacity: 1, offset: 0.51, easing: 'cubic-bezier(.4,0,.2,1)' },
        { transform: 'scale(0.012, 0.0045)', filter: 'brightness(3.2) saturate(0)', clipPath: 'inset(0 round 30px)', opacity: 1, offset: 0.63 },
        { transform: 'scale(0.012, 0.0045)', opacity: 0, offset: 0.66 },
        { transform: 'scale(0.012, 0.0045)', opacity: 0, offset: 1 },
      ], { duration: 1400, fill: 'forwards' }));
      merk(punktEl.animate([
        { opacity: 0, transform: 'scale(0.25, 0.1)' },
        { opacity: 1, transform: 'scale(1)', offset: 0.25 },
        { opacity: 1, transform: 'scale(1)', offset: 0.5 },
        { opacity: 0, transform: 'scale(0.8)' },
      ], { duration: 640, delay: 860, easing: 'cubic-bezier(.33,1,.68,1)', fill: 'both' }));
      merk(powerEl.animate([{ backgroundColor: 'rgb(0 0 0 / 0)' }, { backgroundColor: 'rgb(0 0 0)' }], { duration: 120, delay: 900, fill: 'forwards' }));
    } else {
      merk(welt.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 420, easing: E.weg, fill: 'forwards' }));
      merk(powerEl.animate([{ backgroundColor: 'rgb(0 0 0 / 0)' }, { backgroundColor: 'rgb(0 0 0)' }], { duration: 420, fill: 'forwards' }));
      merk(punktEl.animate([{ opacity: 0 }, { opacity: 1, offset: 0.4 }, { opacity: 0 }], { duration: 900, delay: 300, fill: 'both' }));
    }
    merk(powerHint.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 600, delay: 2200, easing: E.an, fill: 'both' }));
    updateHints();
  }
  function anschalten() {
    if (!S.aus || performance.now() - ausZeit < 500) return;
    S.aus = false;
    ausAnims.forEach(a => a.cancel());
    ausAnims = [];
    html.style.background = '';
    powerEl.hidden = true;
    html.classList.remove('layer-open', 'guide-open', 'quick-open');
    veil.style.opacity = '0';
    mainEl.inert = false;
    barEl.inert = false;
    // Eine Konsole kommt auf ihrer Startseite an.
    if (S.area !== 'home') {
      AREAS.forEach(a => areaEl(a).classList.remove('is-leaving'));
      S.area = 'home';
      html.dataset.area = 'home';
      markTabs(false);
      raumFuer('home');
    }
    if (d.activeElement && d.activeElement !== d.body) d.activeElement.blur();
    boot(true);
    erfolg('aus');
  }
  powerEl.addEventListener('click', () => anschalten());

  // --- Download: „Los“ wie am Ende der Einrichtung – der Kern zündet an der Taste, ein Lichtring
  // läuft über den Schirm, dann geht es zu GitHub.
  function los(a, e) {
    if (e.ctrlKey || e.metaKey || e.shiftKey || e.altKey || (e.button && e.button > 0)) return false;
    e.preventDefault();
    const ziel = a.href;
    if (calm()) { location.href = ziel; return true; }
    const r = a.getBoundingClientRect();
    const cx = r.left + r.width / 2;
    const cy = r.top + r.height / 2;
    const ringEl = $('.los');
    ringEl.style.left = cx + 'px';
    ringEl.style.top = cy + 'px';
    // Der Ring hat schon seine volle Größe und wächst aus der Taste: so bleibt sein Licht dünn.
    const weit = Math.ceil(Math.hypot(Math.max(cx, innerWidth - cx), Math.max(cy, innerHeight - cy)) * 1.06);
    ringEl.style.width = ringEl.style.height = weit * 2 + 'px';
    ringEl.style.margin = `${-weit}px 0 0 ${-weit}px`;
    ringEl.animate([
      { opacity: 0, transform: `scale(${(r.width / 2 / weit).toFixed(4)})` },
      { opacity: 1, transform: `scale(${(r.width / weit).toFixed(4)})`, offset: 0.12 },
      { opacity: 0.85, transform: 'scale(0.42)', offset: 0.45 },
      { opacity: 0, transform: 'scale(1)' },
    ], { duration: 1000, easing: 'cubic-bezier(.25,.7,.25,1)', fill: 'forwards' });
    a.animate([{ boxShadow: '0 0 0 0 rgb(164 123 255 / 0)' }, { boxShadow: '0 0 70px 14px rgb(164 123 255 / 0.7)', offset: 0.25 }, { boxShadow: '0 0 0 0 rgb(164 123 255 / 0)' }],
      { duration: 800, easing: E.an });
    klang('done');
    setTimeout(() => { location.href = ziel; }, 640);
    return true;
  }

  // --- Start --------------------------------------------------------------------------
  function start() {
    window.UZAI_READY = true;
    // Eine Sprungmarke von Hand (#get …) führt hin; in der Adresse bleibt sie nicht stehen, damit
    // Neuladen wieder mit dem Intro auf Home beginnt.
    addEventListener('hashchange', () => {
      const a = location.hash.slice(1);
      if (!AREAS.includes(a)) return;
      history.replaceState(null, '', location.pathname + location.search);
      if (a !== S.area) go(a);
    });
    const LINKS = {
      download: CFG.DOWNLOAD,
      repo: CFG.REPO,
      releases: CFG.REPO + '/releases',
      manual: CFG.REPO + '/blob/main/docs/README.de.md',
      license: CFG.REPO + '/blob/main/LICENSE',
      security: CFG.REPO + '/blob/main/SECURITY.md',
    };
    $$('[data-link]').forEach(a => { const u = LINKS[a.dataset.link]; if (u) a.href = u; });
    // Externe Seiten: kein Opener, kein Referrer-Pfad.
    $$('a[href^="http"]').forEach(a => a.setAttribute('rel', 'noopener'));
    html.dataset.input = S.input;
    html.dataset.zone = 'none';
    erfolgeZeigen();
    guideJetzt();
    besuchen(S.area);
    bewegung();
    zeigeEinstellungen();
    alleGlyphen();
    einladung();
    uhrTakt();
    markTabs(false);
    waehle(items[0], { sofort: true });
    flugVorbereiten();
    raumFuer(S.area);
    if (S.sound) Klang.init();
    updateHints();
    if (!boot(false)) ankunft();
    // Schon verbundene Controller (die Seite war offen, als einer kam).
    const pads = navigator.getGamepads ? Array.from(navigator.getGamepads()).filter(Boolean) : [];
    if (pads.length) { pads.forEach(p => Pad.da.add(p.index)); S.pad = padArt(pads[0].id); S.padName = padName(S.pad, pads[0].id); padStatus(); padLos(); }
    // Schriften kommen nach: Punkt und Striche neu setzen, wenn sie da sind.
    if (d.fonts && d.fonts.ready) {
      d.fonts.ready.then(() => {
        markTabs(false);
        if (S.feature) chipAktiv(info(S.feature).cat, false);
      });
    }
  }
  start();
})();
