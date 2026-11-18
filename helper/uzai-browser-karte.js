// Uzai-Browser: Sprung-Skript (Wunschliste 120, docs/SECURITY.md „Uzai-Browser“).
// Der Wirt (uzai-browser-wirt.cs) legt es über die DevTools-Schnittstelle von WebView2 in eine EIGENE,
// isolierte Welt „uzai“ jeder Seite (Page.addScriptToEvaluateOnNewDocument mit worldName). Die Seite
// teilt mit ihr nur den DOM-Baum, nie ihre Variablen: Sie sieht dieses Skript nicht, kann es nicht
// rufen und nichts darin ändern. Melden kann das Skript nur über die Bindung __uzaiMeldung, die es
// nur in dieser Welt gibt (Runtime.addBinding mit executionContextName) – an den Wirt, der jede
// Meldung gegen sein Schema prüft (zweite Mauer: Uzai prüft noch einmal).
//
// Was es tut: eine „Fokus-Karte“ der Seite bauen (anklickbare Ziele mit Rechteck, Art und Bereich;
// Unsichtbares, Winziges und Verdecktes nicht), auf Wunsch ein Ziel ins Bild rollen, ein Ziel
// aktivieren (Klickpunkt an den Wirt – der Klick selbst ist ein echter Mausklick nur in diese Seite),
// weich rollen mit Trägheit, das Hauptvideo steuern (Pause, Spulen, Lautstärke, Tempo, Untertitel) und den
// Text für den Lesemodus sammeln. Dazu (0.17): die Gliederung der Seite (Überschriften als Sprungmarken),
// Auswahlfelder als Liste (Optionen melden, Wert setzen), Formulare (nächstes/voriges Feld), Suche auf der
// Seite (window.find, Treffer anspringen) und der Text der Seite (Diagnose). Befehle für den Blocker reicht
// es an uzai-browser-filter.js weiter (gleiche Welt).
// Was es nie tut: Code aus Text bauen, Netz, Speicher der Seite, Cookies, Fenster öffnen, Inhalte von
// Feldern melden (außer dem Wert eines Feldes, das du gerade bearbeitest – nie eines Passwortfeldes).
(function () {
  'use strict';
  if (window.top !== window) return;
  if (globalThis.__uzai) return;

  var MAX_ZIELE = 800;
  // rahmen: ein <iframe> (z. B. Einwilligungs-Banner fremder Herkunft) – hinein kommt nur der Zeiger (Uzai schaltet ihn mit A ein).
  var ARTEN = { link: 0, knopf: 1, feld: 2, wahl: 3, video: 4, bild: 5, reiter: 6, sonst: 7, rahmen: 8 };
  var BEREICHE = { kopf: 0, navigation: 1, inhalt: 2, seite: 3, fuss: 4, dialog: 5, sonst: 6 };
  var SELEKTOR = 'a[href], area[href], button, input:not([type="hidden"]), select, textarea, summary, video, iframe, ' +
    '[role="button"], [role="link"], [role="tab"], [role="menuitem"], [role="menuitemcheckbox"], [role="menuitemradio"], ' +
    '[role="option"], [role="checkbox"], [role="radio"], [role="switch"], [role="treeitem"], [role="textbox"], ' +
    '[role="searchbox"], [role="combobox"], [contenteditable=""], [contenteditable="true"], [tabindex]:not([tabindex="-1"]), [onclick]';
  var TEXTFELDER = { text: 'text', search: 'suche', email: 'email', number: 'zahl', password: 'passwort', url: 'url', tel: 'tel' };

  var ids = new WeakMap();
  var elemente = new Map();
  var naechsteId = 1;
  var fokusId = 0;
  var letzteKarte = '';
  var kartePlan = 0;
  var karteZuletzt = 0;
  // Rollen: soll = Wunsch des Sticks, v = jetzt (folgt weich); zeiger = letzte echte Mausbewegung (Uzais Zeiger kommt
  // über den Kern als echte Maus) – kam sie nach dem letzten Fokus, rollt der Bereich unter dem Zeiger.
  var rollen = { vx: 0, vy: 0, sx: 0, sy: 0, halten: false, laeuft: false, t: 0, ziel: null };
  var zeigerPos = null;
  var fokusZeit = 0;
  var verfolgen = 0;

  function melden(o) {
    try {
      if (typeof __uzaiMeldung === 'function') __uzaiMeldung(JSON.stringify(o));
    } catch (e) { /* Meldung verworfen */ }
  }

  function ganz(v, lo, hi) {
    v = Math.round(Number(v) || 0);
    return v < lo ? lo : (v > hi ? hi : v);
  }

  function idVon(el) {
    var id = ids.get(el);
    if (!id) {
      id = naechsteId++;
      ids.set(el, id);
    }
    elemente.set(id, new WeakRef(el));
    return id;
  }

  function element(id) {
    var r = elemente.get(id);
    var el = r ? r.deref() : null;
    if (!el || !el.isConnected) {
      elemente.delete(id);
      return null;
    }
    return el;
  }

  function sichtbar(el, r) {
    if (r.width < 10 || r.height < 10 || r.width * r.height < 140) return false;
    var st = getComputedStyle(el);
    if (st.visibility === 'hidden' || st.visibility === 'collapse' || st.display === 'none') return false;
    if (Number(st.opacity) < 0.05 || st.pointerEvents === 'none') return false;
    if (el.closest('[aria-hidden="true"], [inert]')) return false;
    if (el.disabled) return false;
    return true;
  }

  // Liegt etwas anderes darüber (Banner, Dialog)? Geprüft nur für Ziele im Bild, an drei Punkten.
  function verdeckt(el, r) {
    var vw = innerWidth, vh = innerHeight;
    var punkte = [[r.left + r.width / 2, r.top + r.height / 2], [r.left + 4, r.top + 4], [r.right - 4, r.bottom - 4]];
    var geprueft = 0;
    for (var i = 0; i < punkte.length; i++) {
      var x = punkte[i][0], y = punkte[i][1];
      if (x < 0 || y < 0 || x >= vw || y >= vh) continue;
      geprueft++;
      var hit = document.elementFromPoint(x, y);
      if (!hit || hit === el || el.contains(hit) || hit.contains(el)) return false;
    }
    return geprueft > 0;
  }

  function art(el) {
    var tag = el.tagName;
    var role = (el.getAttribute('role') || '').toLowerCase();
    if (tag === 'VIDEO') return ARTEN.video;
    if (tag === 'IFRAME') return ARTEN.rahmen;
    if (tag === 'TEXTAREA' || el.isContentEditable || role === 'textbox' || role === 'searchbox' || role === 'combobox') return ARTEN.feld;
    if (tag === 'INPUT') {
      var t = (el.type || 'text').toLowerCase();
      if (TEXTFELDER[t]) return ARTEN.feld;
      if (t === 'button' || t === 'submit' || t === 'reset' || t === 'image') return ARTEN.knopf;
      return ARTEN.wahl;
    }
    if (tag === 'SELECT' || role === 'checkbox' || role === 'radio' || role === 'switch' || role === 'option') return ARTEN.wahl;
    if (role === 'tab' || role.indexOf('menuitem') === 0 || role === 'treeitem') return ARTEN.reiter;
    if (tag === 'BUTTON' || tag === 'SUMMARY' || role === 'button') return ARTEN.knopf;
    if (tag === 'A' || tag === 'AREA' || role === 'link') {
      var img = el.querySelector('img, picture, svg, video');
      if (img) {
        var ri = img.getBoundingClientRect(), re = el.getBoundingClientRect();
        if (ri.width * ri.height > re.width * re.height * 0.4 && ri.width * ri.height > 6000) return ARTEN.bild;
      }
      return ARTEN.link;
    }
    return ARTEN.sonst;
  }

  function bereich(el, r) {
    if (el.closest('dialog[open], [role="dialog"], [role="alertdialog"], [aria-modal="true"]')) return BEREICHE.dialog;
    if (el.closest('nav, [role="navigation"], [role="menubar"]')) return BEREICHE.navigation;
    var inArtikel = el.closest('article, main, [role="main"]');
    if (!inArtikel && el.closest('header, [role="banner"]')) return BEREICHE.kopf;
    if (!inArtikel && el.closest('footer, [role="contentinfo"]')) return BEREICHE.fuss;
    if (el.closest('aside, [role="complementary"]')) return BEREICHE.seite;
    if (inArtikel) return BEREICHE.inhalt;
    var docY = r.top + scrollY;
    var sh = document.documentElement.scrollHeight;
    if (docY < 140) return BEREICHE.kopf;
    if (docY > sh - 360 && sh > innerHeight * 1.5) return BEREICHE.fuss;
    if (r.left > innerWidth * 0.68 && r.width < innerWidth * 0.32) return BEREICHE.seite;
    return BEREICHE.inhalt;
  }

  function eigenesZiel(el, r, aussenFlaeche) {
    if (aussenFlaeche < r.width * r.height * 4) return false;
    var tag = el.tagName;
    if (tag === 'A' || tag === 'BUTTON' || tag === 'INPUT' || tag === 'SELECT' || tag === 'TEXTAREA' || tag === 'SUMMARY') return true;
    var role = (el.getAttribute('role') || '').toLowerCase();
    return role === 'button' || role === 'link' || role === 'checkbox' || role === 'switch' || role === 'tab' || role === 'menuitem';
  }

  function karteBauen() {
    var vw = innerWidth, vh = innerHeight;
    // Lange offene Seiten (endloses Rollen): alte Einträge nicht ewig behalten, die Kennungen bleiben gleich.
    if (elemente.size > 4000) {
      var f = fokusId ? element(fokusId) : null;
      elemente.clear();
      if (f) elemente.set(fokusId, new WeakRef(f));
    }
    var kandidaten = document.querySelectorAll(SELEKTOR);
    var drin = new Set();
    var flaechen = new Map();
    var liste = [];
    var n = Math.min(kandidaten.length, 6000);
    for (var i = 0; i < n; i++) {
      var el = kandidaten[i];
      var r = el.getBoundingClientRect();
      if (r.bottom < -vh || r.top > vh * 2 || r.right < 0 || r.left > vw) continue;
      if (!sichtbar(el, r)) continue;
      var a = art(el);
      // Kleine Rahmen (Zähler, Werbe-Pixel) sind kein Ziel.
      if (a === ARTEN.rahmen && (r.width < 120 || r.height < 40)) continue;
      // Große Behälter mit tabindex (Inhalt, Rollbereiche) sind kein Ziel.
      if ((a === ARTEN.sonst || a === ARTEN.reiter) && r.width * r.height > vw * vh * 0.5) continue;
      // Ein Ziel in einem Ziel (Bild im Link, Text im Knopf): nur das äußere – außer einem eigenen Bedienelement in
      // einer viel größeren Fläche (Merken-Knopf in einer Karte, Link in einem anklickbaren Kasten): beide.
      var aussen = el.parentElement ? el.parentElement.closest(SELEKTOR) : null;
      if (aussen && drin.has(aussen) && a !== ARTEN.feld && !eigenesZiel(el, r, flaechen.get(aussen) || 0)) continue;
      var imBild = r.bottom > 0 && r.top < vh;
      if (imBild && verdeckt(el, r)) continue;
      drin.add(el);
      flaechen.set(el, r.width * r.height);
      liste.push({ el: el, r: r, art: a });
    }
    var mx = vw / 2, my = vh / 2;
    liste.sort(function (p, q) {
      var dp = Math.abs(p.r.top + p.r.height / 2 - my) + Math.abs(p.r.left + p.r.width / 2 - mx) * 0.3;
      var dq = Math.abs(q.r.top + q.r.height / 2 - my) + Math.abs(q.r.left + q.r.width / 2 - mx) * 0.3;
      return dp - dq;
    });
    var ziele = [];
    for (var k = 0; k < liste.length && ziele.length < MAX_ZIELE; k++) {
      var z = liste[k];
      ziele.push([idVon(z.el), ganz(z.r.left, -100000, 100000), ganz(z.r.top, -100000, 100000), ganz(z.r.width, 1, 20000),
        ganz(z.r.height, 1, 20000), z.art, bereich(z.el, z.r)]);
    }
    return {
      t: 'karte', vw: ganz(vw, 1, 20000), vh: ganz(vh, 1, 20000), sy: ganz(scrollY, 0, 10000000),
      sh: ganz(document.documentElement.scrollHeight, 0, 10000000), ziele: ziele
    };
  }

  function karteSenden(immer) {
    kartePlan = 0;
    karteZuletzt = Date.now();
    var k = karteBauen();
    var s = JSON.stringify(k);
    if (!immer && s === letzteKarte) return;
    letzteKarte = s;
    melden(k);
  }

  // Nach Änderungen: höchstens alle 400 ms, gesammelt über 250 ms.
  function karteBald() {
    if (kartePlan) return;
    var warte = Math.max(250, 400 - (Date.now() - karteZuletzt));
    kartePlan = setTimeout(function () { karteSenden(false); }, warte);
  }

  function zielMelden(id) {
    var el = element(id);
    if (!el) return;
    var r = el.getBoundingClientRect();
    melden({ t: 'ziel', id: id, x: ganz(r.left, -100000, 100000), y: ganz(r.top, -100000, 100000), w: ganz(r.width, 1, 20000), h: ganz(r.height, 1, 20000) });
  }

  // Den Rahmen beim Rollen mitführen: jedes Bild das Rechteck, bis es drei Bilder still steht.
  function verfolge(id) {
    var gen = ++verfolgen;
    var alt = '', still = 0, start = Date.now();
    function schritt() {
      if (gen !== verfolgen) return;
      var el = element(id);
      if (!el) return;
      var r = el.getBoundingClientRect();
      var s = Math.round(r.left) + ',' + Math.round(r.top) + ',' + Math.round(r.width) + ',' + Math.round(r.height);
      if (s !== alt) { alt = s; still = 0; zielMelden(id); } else still++;
      if (still < 3 && Date.now() - start < 1600) requestAnimationFrame(schritt);
      else karteSenden(false);
    }
    requestAnimationFrame(schritt);
  }

  function insBild(el, weich) {
    var r = el.getBoundingClientRect();
    var vh = innerHeight, vw = innerWidth;
    if (r.top >= 64 && r.bottom <= vh - 32 && r.left >= 0 && r.right <= vw) return false;
    el.scrollIntoView({ block: r.height > vh * 0.7 ? 'start' : 'center', inline: 'nearest', behavior: weich ? 'smooth' : 'instant' });
    return true;
  }

  function feldTyp(el) {
    if (el.tagName === 'INPUT') return TEXTFELDER[(el.type || 'text').toLowerCase()] || 'text';
    return 'bereich';
  }

  function feldWert(el) {
    if (feldTyp(el) === 'passwort') return '';
    var v = (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') ? el.value : el.textContent;
    return String(v || '').slice(0, 2000);
  }

  function feldWaehlen(el) {
    try { el.focus({ preventScroll: true }); } catch (e) { /* nichts */ }
    if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') {
      try { el.select(); } catch (e2) { /* manche Felder können nicht markieren */ }
    } else if (el.isContentEditable) {
      var sel = getSelection();
      var range = document.createRange();
      range.selectNodeContents(el);
      sel.removeAllRanges();
      sel.addRange(range);
    }
  }

  function linkVon(el) {
    var a = el.closest('a[href], area[href]');
    if (!a) return '';
    var h = String(a.href || '');
    return /^https?:\/\//i.test(h) && h.length <= 4096 ? h : '';
  }

  // Klickpunkt: Mitte des sichtbaren Teils, geprüft, dass dort wirklich dieses Ziel liegt.
  function klickpunkt(el) {
    var r = el.getBoundingClientRect();
    var x0 = Math.max(r.left, 0), y0 = Math.max(r.top, 0), x1 = Math.min(r.right, innerWidth), y1 = Math.min(r.bottom, innerHeight);
    if (x1 <= x0 || y1 <= y0) return null;
    var punkte = [[(x0 + x1) / 2, (y0 + y1) / 2], [x0 + 6, (y0 + y1) / 2], [(x0 + x1) / 2, y0 + 4]];
    for (var i = 0; i < punkte.length; i++) {
      var hit = document.elementFromPoint(punkte[i][0], punkte[i][1]);
      if (hit && (hit === el || el.contains(hit))) return punkte[i];
    }
    return null;
  }

  function aktivieren(id, neu) {
    var el = element(id);
    if (!el) return;
    if (neu) {
      var h = linkVon(el);
      if (h) { melden({ t: 'oeffnen', url: h }); return; }
    }
    var a = art(el);
    insBild(el, false);
    if (a === ARTEN.feld) {
      feldWaehlen(el);
      melden({ t: 'feld', id: id, typ: feldTyp(el), wert: feldWert(el) });
      formularStand(el);
      return;
    }
    if (a === ARTEN.wahl && (el.tagName === 'SELECT' || (el.tagName === 'INPUT' && el.type === 'radio'))) {
      var w = wahlOptionen(el);
      if (w && w.opts.length > 1) { wahl(id); return; }
    }
    if (a === ARTEN.video) { video('umschalten', el); return; }
    var p = klickpunkt(el);
    if (p) melden({ t: 'klick', x: ganz(p[0], 0, 100000), y: ganz(p[1], 0, 100000) });
    else el.click();
    karteBald();
  }

  // --- Rollen mit Trägheit -----------------------------------------------------------------------

  function rollbar(el, dy) {
    for (var n = el; n && n !== document.body && n !== document.documentElement; n = n.parentElement) {
      var st = getComputedStyle(n);
      if ((st.overflowY === 'auto' || st.overflowY === 'scroll') && n.scrollHeight > n.clientHeight + 4) {
        if ((dy > 0 && n.scrollTop + n.clientHeight < n.scrollHeight - 1) || (dy < 0 && n.scrollTop > 0)) return n;
      }
    }
    return null;
  }

  // Ein Bild Rollen: v folgt dem Wunsch weich (kein Ruck beim Anfahren), losgelassen läuft es mit Trägheit aus.
  // Am Ende der Seite (oder des Bereichs) hält es sofort an – kein unsichtbares Auslaufen gegen den Rand.
  function rollSchritt(t) {
    var dt = Math.min(0.05, Math.max(0.001, (t - rollen.t) / 1000));
    rollen.t = t;
    if (rollen.halten) {
      var f = 1 - Math.exp(-dt * 14);
      rollen.vx += (rollen.sx - rollen.vx) * f;
      rollen.vy += (rollen.sy - rollen.vy) * f;
    } else {
      var k = Math.exp(-dt * 7);
      rollen.vx *= k;
      rollen.vy *= k;
    }
    if (Math.abs(rollen.vx) < 5 && Math.abs(rollen.vy) < 5 && !(rollen.halten && (rollen.sx || rollen.sy))) {
      rollEnde();
      return;
    }
    var ziel = rollen.ziel && rollen.ziel.isConnected ? rollen.ziel : null;
    var n = ziel || document.scrollingElement || document.documentElement;
    var x0 = n.scrollLeft, y0 = n.scrollTop;
    if (ziel) ziel.scrollBy({ left: rollen.vx * dt, top: rollen.vy * dt, behavior: 'instant' });
    else window.scrollBy({ left: rollen.vx * dt, top: rollen.vy * dt, behavior: 'instant' });
    var amEnde = Math.abs(rollen.vy * dt) >= 1 && Math.abs(n.scrollTop - y0) < 0.5 && Math.abs(n.scrollLeft - x0) < 0.5;
    if (amEnde) {
      rollen.vx = 0; rollen.vy = 0; rollen.sx = 0; rollen.sy = 0;
      rollEnde();
      return;
    }
    if (fokusId) zielMelden(fokusId);
    requestAnimationFrame(rollSchritt);
  }

  function rollEnde() {
    rollen.laeuft = false;
    rollen.vx = 0;
    rollen.vy = 0;
    karteSenden(false);
    if (fokusId) zielMelden(fokusId);
  }

  function rollenSetzen(vx, vy) {
    var los = vx === 0 && vy === 0;
    if (los) { rollen.halten = false; rollen.sx = 0; rollen.sy = 0; return; }
    if (!rollen.laeuft) {
      var von = null;
      if (zeigerPos && zeigerPos.zeit > fokusZeit) von = document.elementFromPoint(zeigerPos.x, zeigerPos.y);
      if (!von) von = fokusId ? element(fokusId) : null;
      rollen.ziel = von ? rollbar(von, vy) : null;
    }
    rollen.sx = vx;
    rollen.sy = vy;
    rollen.halten = true;
    if (!rollen.laeuft) {
      rollen.laeuft = true;
      rollen.t = performance.now();
      requestAnimationFrame(rollSchritt);
    }
  }

  // --- Video ---------------------------------------------------------------------------------

  function hauptvideo() {
    var voll = document.fullscreenElement;
    if (voll) {
      var v0 = voll.tagName === 'VIDEO' ? voll : voll.querySelector('video');
      if (v0) return v0;
    }
    var best = null, flaeche = 0;
    var alle = document.querySelectorAll('video');
    for (var i = 0; i < alle.length && i < 50; i++) {
      var r = alle[i].getBoundingClientRect();
      var f = Math.max(0, Math.min(r.right, innerWidth) - Math.max(r.left, 0)) * Math.max(0, Math.min(r.bottom, innerHeight) - Math.max(r.top, 0));
      if (f > flaeche) { flaeche = f; best = alle[i]; }
    }
    return best;
  }

  function untertitelStand(v) {
    var tt = v.textTracks;
    if (!tt || !tt.length) return -1;
    for (var i = 0; i < tt.length; i++) if (tt[i].mode === 'showing') return 1;
    return 0;
  }

  function videoMelden() {
    var v = hauptvideo();
    if (!v) { melden({ t: 'video', da: false, laeuft: false, zeit: 0, dauer: 0, voll: false, laut: 0, stumm: false, tempo: 100, untertitel: -1 }); return; }
    var d = isFinite(v.duration) ? v.duration : 0;
    melden({ t: 'video', da: true, laeuft: !v.paused && !v.ended, zeit: ganz(v.currentTime, 0, 1000000), dauer: ganz(d, 0, 1000000),
      voll: !!document.fullscreenElement, laut: ganz(v.volume * 100, 0, 100), stumm: !!v.muted, tempo: ganz(v.playbackRate * 100, 25, 400),
      untertitel: untertitelStand(v) });
  }

  function video(aktion, el) {
    var v = el && el.tagName === 'VIDEO' ? el : hauptvideo();
    if (!v) return;
    try {
      if (aktion === 'umschalten') { if (v.paused) v.play(); else v.pause(); }
      else if (aktion === 'pause') v.pause();
      else if (aktion === 'spielen') v.play();
      else if (aktion === 'vor') v.currentTime = Math.min((v.duration || 1e9), v.currentTime + 10);
      else if (aktion === 'zurueck') v.currentTime = Math.max(0, v.currentTime - 10);
      else if (aktion === 'vor_lang') v.currentTime = Math.min((v.duration || 1e9), v.currentTime + 60);
      else if (aktion === 'zurueck_lang') v.currentTime = Math.max(0, v.currentTime - 60);
      else if (aktion === 'lauter') { v.muted = false; v.volume = Math.min(1, Math.round(v.volume * 20 + 1) / 20); }
      else if (aktion === 'leiser') v.volume = Math.max(0, Math.round(v.volume * 20 - 1) / 20);
      else if (aktion === 'stumm') v.muted = !v.muted;
      else if (aktion === 'tempo_auf') v.playbackRate = Math.min(4, Math.round(v.playbackRate * 4 + 1) / 4);
      else if (aktion === 'tempo_ab') v.playbackRate = Math.max(0.25, Math.round(v.playbackRate * 4 - 1) / 4);
      else if (aktion === 'untertitel') {
        var tt = v.textTracks;
        if (tt && tt.length) {
          var an = untertitelStand(v) === 1;
          for (var i = 0; i < tt.length; i++) tt[i].mode = (!an && i === 0) ? 'showing' : 'hidden';
        }
      }
      else if (aktion === 'vollbild') {
        if (document.fullscreenElement) document.exitFullscreen();
        else (v.parentElement || v).requestFullscreen();
      }
    } catch (e) { /* Seite verbietet es */ }
    setTimeout(videoMelden, 120);
  }

  var videoZuletzt = 0;
  ['play', 'pause', 'ended', 'seeked'].forEach(function (n) {
    document.addEventListener(n, function () { videoMelden(); }, true);
  });
  document.addEventListener('timeupdate', function () {
    var jetzt = Date.now();
    if (jetzt - videoZuletzt > 1000) { videoZuletzt = jetzt; videoMelden(); }
  }, true);

  // --- Lesemodus: nur Text, keine Formatierung, keine Bilder -------------------------------------

  function lesen() {
    var wurzel = document.querySelector('article') || document.querySelector('main, [role="main"]') || document.body;
    var titel = (wurzel.querySelector('h1') || {}).textContent || document.title || '';
    var absaetze = [];
    var teile = wurzel.querySelectorAll('h2, h3, p, li, blockquote, pre');
    for (var i = 0; i < teile.length && absaetze.length < 200; i++) {
      var e = teile[i];
      if (e.closest('nav, aside, footer, form, [aria-hidden="true"], [role="navigation"], [role="complementary"]')) continue;
      var t = String(e.innerText || '').replace(/\s+/g, ' ').trim();
      if (!t || ((e.tagName === 'P' || e.tagName === 'LI') && t.length < 40)) continue;
      absaetze.push(t.slice(0, 3000));
    }
    melden({ t: 'lesen', titel: String(titel).replace(/\s+/g, ' ').trim().slice(0, 300), absaetze: absaetze });
  }

  // --- Gliederung: Überschriften und Bereiche als Sprungmarken ---------------------------------------

  var gliederungIds = new WeakMap();

  function gliederung() {
    var punkte = [];
    var alle = document.querySelectorAll('h1, h2, h3, main, article, [role="main"], nav, [role="navigation"], footer, aside, section[aria-label], section[aria-labelledby]');
    var sy = scrollY;
    for (var i = 0; i < alle.length && punkte.length < 60; i++) {
      var el = alle[i];
      var r = el.getBoundingClientRect();
      if (r.width < 20 || r.height < 8) continue;
      var st = getComputedStyle(el);
      if (st.visibility === 'hidden' || st.display === 'none') continue;
      var tag = el.tagName;
      var stufe = tag === 'H1' ? 1 : (tag === 'H2' ? 2 : (tag === 'H3' ? 3 : 0));
      var txt = '';
      if (stufe) txt = String(el.innerText || el.textContent || '');
      else {
        txt = el.getAttribute('aria-label') || '';
        if (!txt && el.getAttribute('aria-labelledby')) { var lab = document.getElementById(el.getAttribute('aria-labelledby')); if (lab) txt = lab.textContent || ''; }
        if (!txt) txt = tag === 'MAIN' || el.getAttribute('role') === 'main' ? 'Inhalt' : (tag === 'NAV' || el.getAttribute('role') === 'navigation' ? 'Navigation' : (tag === 'FOOTER' ? 'Fuß' : (tag === 'ASIDE' ? 'Seitenleiste' : (tag === 'ARTICLE' ? 'Artikel' : ''))));
      }
      txt = txt.replace(/\s+/g, ' ').trim().slice(0, 80);
      if (!txt) continue;
      if (punkte.length && punkte[punkte.length - 1][3] === txt && Math.abs(punkte[punkte.length - 1][1] - (r.top + sy)) < 40) continue;
      punkte.push([idVon(el), ganz(r.top + sy, 0, 10000000), stufe, txt]);
    }
    punkte.sort(function (p, q) { return p[1] - q[1]; });
    melden({ t: 'gliederung', punkte: punkte });
  }

  // Zu einem Gliederungspunkt rollen und das erste Ziel darunter melden (Uzai setzt den Fokus darauf).
  function springe(id) {
    var el = element(id);
    if (!el) return;
    var r = el.getBoundingClientRect();
    var ziel = Math.max(0, r.top + scrollY - 24);
    scrollTo({ top: ziel, behavior: 'instant' });
    setTimeout(function () { karteSenden(true); }, 60);
  }

  // --- Auswahlfelder als Liste von Uzai (select, Radiogruppen) ----------------------------------------

  function wahlOptionen(el) {
    var opts = [];
    var aktuell = -1;
    if (el.tagName === 'SELECT') {
      for (var i = 0; i < el.options.length && opts.length < 400; i++) {
        var o = el.options[i];
        if (o.disabled || o.hidden) continue;
        if (o.selected) aktuell = opts.length;
        opts.push({ i: i, text: String(o.label || o.text || '').replace(/\s+/g, ' ').trim().slice(0, 120) });
      }
      return { opts: opts, aktuell: aktuell };
    }
    if (el.tagName === 'INPUT' && el.type === 'radio' && el.name && el.form) {
      var gruppe = el.form.querySelectorAll('input[type="radio"][name="' + el.name.replace(/["\\]/g, '') + '"]');
      for (var k = 0; k < gruppe.length && opts.length < 400; k++) {
        var g = gruppe[k];
        var lab = g.labels && g.labels[0] ? g.labels[0].innerText : (g.getAttribute('aria-label') || g.value);
        if (g.checked) aktuell = opts.length;
        opts.push({ i: k, text: String(lab || '').replace(/\s+/g, ' ').trim().slice(0, 120), el: g });
      }
      return { opts: opts, aktuell: aktuell };
    }
    return null;
  }

  function wahl(id) {
    var el = element(id);
    var w = el ? wahlOptionen(el) : null;
    if (!w || !w.opts.length) return;
    var texte = [];
    for (var i = 0; i < w.opts.length; i++) texte.push(w.opts[i].text || ('Eintrag ' + (i + 1)));
    melden({ t: 'wahl', id: id, optionen: texte, aktuell: w.aktuell });
  }

  function wahlSetzen(id, index) {
    var el = element(id);
    var w = el ? wahlOptionen(el) : null;
    if (!w || index < 0 || index >= w.opts.length) return;
    var o = w.opts[index];
    try {
      if (el.tagName === 'SELECT') {
        el.selectedIndex = o.i;
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
      } else if (o.el) {
        o.el.click();
      }
    } catch (e) { /* Seite verbietet es */ }
    karteBald();
  }

  // --- Formulare: von Feld zu Feld ------------------------------------------------------------------

  var FELD_SELEKTOR = 'input:not([type="hidden"]):not([type="submit"]):not([type="button"]):not([type="reset"]):not([type="image"]), select, textarea, [contenteditable="true"], [contenteditable=""]';

  function felderVon(el) {
    var wurzel = el.form || el.closest('form') || document;
    var alle = wurzel.querySelectorAll(FELD_SELEKTOR);
    var liste = [];
    for (var i = 0; i < alle.length && liste.length < 1000; i++) {
      var f = alle[i];
      var r = f.getBoundingClientRect();
      if (f.disabled || r.width < 4 || r.height < 4) continue;
      liste.push(f);
    }
    return liste;
  }

  function formularStand(el) {
    var liste = felderVon(el);
    var i = liste.indexOf(el);
    melden({ t: 'formular', id: idVon(el), index: i < 0 ? 0 : i, anzahl: liste.length, ende: i >= 0 && i === liste.length - 1 });
  }

  function feldWeiter(id, richtung) {
    var el = element(id);
    if (!el) return;
    var liste = felderVon(el);
    var i = liste.indexOf(el);
    var j = i + (richtung < 0 ? -1 : 1);
    if (j < 0 || j >= liste.length) { formularStand(el); return; }
    var ziel = liste[j];
    insBild(ziel, false);
    var zid = idVon(ziel);
    fokusId = zid;
    zielMelden(zid);
    if (art(ziel) === ARTEN.feld) {
      feldWaehlen(ziel);
      melden({ t: 'feld', id: zid, typ: feldTyp(ziel), wert: feldWert(ziel) });
    } else {
      // Auswahl oder Knopf: nur den Fokus dorthin, Uzai entscheidet (Liste, A).
      try { ziel.focus({ preventScroll: true }); } catch (e) { /* nichts */ }
    }
    formularStand(ziel);
  }

  // --- Suche auf der Seite ------------------------------------------------------------------------------

  var suche = { text: '', treffer: 0, aktuell: 0 };

  function sucheZaehlen(text) {
    var n = 0;
    var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    var t = text.toLowerCase();
    var knoten;
    while ((knoten = walker.nextNode()) && n < 100000) {
      var p = knoten.parentElement;
      if (!p || p.closest('script, style, noscript')) continue;
      var s = String(knoten.nodeValue || '').toLowerCase();
      var k = s.indexOf(t);
      while (k >= 0 && n < 100000) { n++; k = s.indexOf(t, k + Math.max(1, t.length)); }
    }
    return n;
  }

  function sucheTreffer(richtung) {
    if (!suche.text) return;
    var ok = false;
    try { ok = window.find(suche.text, false, richtung < 0, true, false, false, false); } catch (e) { ok = false; }
    if (ok) {
      suche.aktuell = richtung < 0 ? (suche.aktuell <= 1 ? suche.treffer : suche.aktuell - 1) : (suche.aktuell >= suche.treffer ? 1 : suche.aktuell + 1);
      var sel = getSelection();
      if (sel && sel.rangeCount) {
        var r = sel.getRangeAt(0).getBoundingClientRect();
        // Das Ziel, das dem Treffer am nächsten liegt, bekommt den Fokus; sonst nur rollen.
        var el = sel.anchorNode && sel.anchorNode.parentElement ? sel.anchorNode.parentElement.closest(SELEKTOR) : null;
        if (el) { fokusId = idVon(el); zielMelden(fokusId); }
        if (r.top < 40 || r.bottom > innerHeight - 40) scrollBy({ top: r.top - innerHeight * 0.4, behavior: 'instant' });
      }
    }
    melden({ t: 'suche', treffer: suche.treffer, aktuell: ok ? suche.aktuell : 0 });
    karteBald();
  }

  function sucheStart(text) {
    suche.text = String(text || '').slice(0, 200);
    suche.aktuell = 0;
    suche.treffer = suche.text ? sucheZaehlen(suche.text) : 0;
    try { var sel = getSelection(); if (sel) sel.removeAllRanges(); } catch (e) { /* nichts */ }
    if (!suche.treffer) { melden({ t: 'suche', treffer: 0, aktuell: 0 }); return; }
    sucheTreffer(1);
  }

  // --- Befehle vom Wirt (Runtime.callFunctionOn mit Werten, nie mit Text als Code) ----------------

  function befehl(a) {
    if (!a || typeof a !== 'object') return;
    var id = typeof a.id === 'number' ? a.id : 0;
    switch (a.t) {
      case 'karte': karteSenden(true); break;
      case 'fokus': {
        var el = element(id);
        if (!el) { karteSenden(true); break; }
        fokusId = id;
        fokusZeit = Date.now();
        var gerollt = insBild(el, true);
        zielMelden(id);
        if (gerollt) verfolge(id);
        // Aufklappmenüs (hover): die Seite bekommt einen Zeiger über dem Ziel, damit sie ihr Menü öffnet.
        if (el.matches('[aria-haspopup], [aria-expanded], nav a, nav button, [role="menuitem"]')) {
          var p0 = klickpunkt(el);
          if (p0) melden({ t: 'zeiger', x: ganz(p0[0], 0, 100000), y: ganz(p0[1], 0, 100000) });
        }
        break;
      }
      case 'aktivieren': aktivieren(id, a.neu === true); break;
      case 'link': {
        var e2 = element(id);
        var h = e2 ? linkVon(e2) : '';
        if (h) melden({ t: 'link', id: id, url: h });
        break;
      }
      case 'feld': {
        var e3 = element(id);
        if (e3 && art(e3) === ARTEN.feld) { feldWaehlen(e3); melden({ t: 'feld', id: id, typ: feldTyp(e3), wert: feldWert(e3) }); }
        break;
      }
      case 'rollen': rollenSetzen(ganz(a.vx, -30000, 30000), ganz(a.vy, -30000, 30000)); break;
      case 'video': video(String(a.aktion || ''), null); break;
      case 'lesen': lesen(); break;
      case 'text': {
        var t0 = String((document.body && document.body.innerText) || '').replace(/[ \t]+/g, ' ').replace(/\n{3,}/g, '\n\n').trim().slice(0, 3000);
        melden({ t: 'lesen', titel: String(document.title || '').slice(0, 300), absaetze: t0 ? [t0] : [] });
        break;
      }
      case 'gliederung': gliederung(); break;
      case 'springe': springe(id); break;
      case 'wahl': wahl(id); break;
      case 'wahl-setzen': wahlSetzen(id, typeof a.index === 'number' ? a.index : -1); break;
      case 'feld-weiter': feldWeiter(id, typeof a.richtung === 'number' ? a.richtung : 1); break;
      case 'suche': sucheStart(a.text); break;
      case 'suche-weiter': sucheTreffer(typeof a.richtung === 'number' ? a.richtung : 1); break;
      case 'filter': { var fl = globalThis.__uzaiFilter; if (fl) fl.befehl(a); break; }
      case 'zoom': {
        var e4 = fokusId ? element(fokusId) : null;
        if (e4) insBild(e4, false);
        setTimeout(function () { karteSenden(true); if (fokusId) zielMelden(fokusId); }, 60);
        break;
      }
    }
  }

  Object.defineProperty(globalThis, '__uzai', { value: Object.freeze({ befehl: befehl }), writable: false, configurable: false });

  melden({ t: 'hallo' });
  var beob = new MutationObserver(function () { karteBald(); });
  function anfangen() {
    if (document.documentElement) {
      beob.observe(document.documentElement, { subtree: true, childList: true, attributes: true,
        attributeFilter: ['class', 'style', 'hidden', 'aria-hidden', 'open', 'disabled', 'aria-expanded'] });
    }
    karteSenden(true);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', anfangen, { once: true });
  else anfangen();
  addEventListener('load', function () { setTimeout(function () { karteSenden(false); }, 300); }, { once: true });
  addEventListener('pageshow', function () { karteSenden(true); });
  addEventListener('resize', karteBald);
  // Nur echte Mausbewegungen (Uzais Zeiger über den Kern, die Maus) – nie von der Seite gebaute Ereignisse.
  addEventListener('mousemove', function (e) {
    if (e.isTrusted) zeigerPos = { x: e.clientX, y: e.clientY, zeit: Date.now() };
  }, { passive: true, capture: true });
  var rollPlan = 0;
  addEventListener('scroll', function () {
    if (rollen.laeuft) return;
    clearTimeout(rollPlan);
    rollPlan = setTimeout(function () { karteSenden(false); if (fokusId) zielMelden(fokusId); }, 150);
  }, { passive: true, capture: true });
})();
