// Uzai-Browser: Kosmetik des Blockers und der Cookie-Knopf (docs/BROWSER_PLAN.md 4, docs/SECURITY.md „Uzai-Browser“).
// Läuft wie das Sprung-Skript in der isolierten Welt „uzai“ jeder Seite (nach ihm registriert). Die Seite sieht es
// nicht. Der Kern setzt davor eine Zeile „var UZAI_COOKIES = {...};“ (assets/browser/filter/cookies.json, als JSON
// geprüft und neu geschrieben – reine Daten). Alles, was es tut:
//   - auf Befehl {t:'filter', an, selektoren} ein <style> mit „display:none !important“ für die Selektoren einsetzen
//     (nur CSS-Selektoren ohne { } ; – der Kern hat sie geprüft, hier noch einmal); Zählung, wie viele treffen;
//   - einmal je Dokument, in den ersten 12 s: einen „Ablehnen/Nur notwendige“-Knopf eines Einwilligungs-Banners drücken
//     – nur nach bekannter Regel (Dienst + Selektor) oder nach Wortliste, nie einen Knopf mit „akzeptieren“, nie in
//     Rahmen anderer Herkunft (die sieht dieses Skript gar nicht);
//   - melden: {t:'blocker', versteckt, cookies} über dieselbe Bindung wie das Sprung-Skript.
// Nie: Netz, Speicher, Cookies lesen, Code aus Text, Formulare absenden.
(function () {
  'use strict';
  if (window.top !== window) return;
  if (globalThis.__uzaiFilter) return;

  var regeln = (typeof UZAI_COOKIES === 'object' && UZAI_COOKIES) ? UZAI_COOKIES : { dienste: [], ablehnen: [], nie: [], banner: [] };
  var an = false;
  var selektoren = [];
  var style = null;
  var versteckt = 0;
  var cookies = '';
  var geklickt = false;
  var versuche = 0;
  var start = Date.now();

  function melden(o) {
    try { if (typeof __uzaiMeldung === 'function') __uzaiMeldung(JSON.stringify(o)); } catch (e) { /* verworfen */ }
  }

  function stand() {
    melden({ t: 'blocker', versteckt: versteckt > 1000000 ? 1000000 : versteckt, cookies: cookies });
  }

  function selektorOk(s) {
    if (typeof s !== 'string' || s.length < 2 || s.length > 300) return false;
    if (/[{};\\\/]/.test(s) || /url\(|expression|:has\(|-abp-/i.test(s)) return false;
    try { document.createDocumentFragment().querySelector(s); } catch (e) { return false; }
    return true;
  }

  // Ein <style> aus Gruppen zu 100 Selektoren: fällt einer durch, verliert die Seite nur seine Gruppe.
  function anwenden() {
    if (!an || !selektoren.length || !document.documentElement) return;
    var gut = [];
    for (var i = 0; i < selektoren.length && gut.length < 24000; i++) if (selektorOk(selektoren[i])) gut.push(selektoren[i]);
    var css = '';
    for (var k = 0; k < gut.length; k += 100) css += gut.slice(k, k + 100).join(',') + '{display:none!important;}\n';
    if (!style) {
      style = document.createElement('style');
      style.setAttribute('data-uzai', 'filter');
    }
    style.textContent = css;
    var ziel = document.head || document.documentElement;
    if (style.parentNode !== ziel) ziel.appendChild(style);
    // Zählen, was wirklich getroffen wird (nur für die Anzeige, höchstens 2000 Selektoren prüfen).
    var n = 0;
    try {
      for (var j = 0; j < gut.length && j < 2000; j++) n += document.querySelectorAll(gut[j]).length;
    } catch (e) { /* egal */ }
    versteckt = n;
    stand();
  }

  // --- Cookie-Banner: „Nur notwendige“ --------------------------------------------------------------------

  function sichtbar(el) {
    if (!el || !el.isConnected) return false;
    var r = el.getBoundingClientRect();
    if (r.width < 8 || r.height < 8) return false;
    var st = getComputedStyle(el);
    return st.visibility !== 'hidden' && st.display !== 'none' && Number(st.opacity) > 0.05;
  }

  function text(el) {
    return String(el.innerText || el.textContent || el.value || el.getAttribute('aria-label') || '').replace(/\s+/g, ' ').trim().toLowerCase();
  }

  function enthaelt(t, liste) {
    for (var i = 0; i < liste.length; i++) if (t.indexOf(String(liste[i]).toLowerCase()) >= 0) return true;
    return false;
  }

  // Der Text ohne die Ablehnen-Wörter (null, wenn keins drin war): So stört „zustimmen“ in „nicht zustimmen“ und
  // „agree“ in „disagree“ nicht, aber „ablehnen und alle akzeptieren“ fällt durch.
  function ohne(t, liste) {
    var traf = false;
    for (var i = 0; i < liste.length; i++) {
      var w = String(liste[i]).toLowerCase();
      if (!w) continue;
      var k = t.indexOf(w);
      while (k >= 0) { t = t.slice(0, k) + ' ' + t.slice(k + w.length); traf = true; k = t.indexOf(w); }
    }
    return traf ? t : null;
  }

  function knopfOk(el) {
    var t = text(el);
    if (!t || t.length > 60) return false;
    var rest = ohne(t, regeln.ablehnen);
    return rest !== null && !enthaelt(rest, regeln.nie);
  }

  // Für bekannte Dienste: der Selektor sagt, dass es der Ablehnen-Knopf ist – nur kein Akzeptieren-Wort darin.
  function nieDrin(el) {
    var t = text(el);
    var rest = ohne(t, regeln.ablehnen);
    return enthaelt(rest === null ? t : rest, regeln.nie);
  }

  function klick(el, wie) {
    try { el.click(); } catch (e) { return false; }
    geklickt = true;
    cookies = 'abgelehnt';
    stand();
    return true;
  }

  function bannerVersuch() {
    if (!an || geklickt || !document.body) return;
    versuche++;
    // 1. Bekannte Dienste: Erkennen-Selektor da → Ablehnen-Selektor drücken.
    var d = regeln.dienste || [];
    for (var i = 0; i < d.length && i < 200; i++) {
      var r = d[i];
      if (!r || !selektorOk(r.erkennen)) continue;
      var box = document.querySelector(r.erkennen);
      if (!box || !sichtbar(box)) continue;
      var liste = r.ablehnen || [];
      for (var k = 0; k < liste.length && k < 8; k++) {
        if (!selektorOk(liste[k])) continue;
        var el = document.querySelector(liste[k]);
        if (el && sichtbar(el) && !nieDrin(el) && klick(el, r.name)) return;
      }
    }
    // 2. Wortliste: ein fester/klebender Behälter mit Cookie-Text und einem Ablehnen-Knopf.
    var kandidaten = document.querySelectorAll('div, section, aside, dialog, form, footer');
    var vw = innerWidth, vh = innerHeight;
    for (var j = 0; j < kandidaten.length && j < 3000; j++) {
      var c = kandidaten[j];
      var st = getComputedStyle(c);
      if (st.position !== 'fixed' && st.position !== 'sticky' && !c.matches('dialog[open], [role="dialog"], [aria-modal="true"]')) continue;
      var rc = c.getBoundingClientRect();
      if (rc.width < vw * 0.3 || rc.height < 60 || !sichtbar(c)) continue;
      var tc = text(c).slice(0, 4000);
      if (!enthaelt(tc, regeln.banner || [])) continue;
      var knoepfe = c.querySelectorAll('button, a[role="button"], input[type="button"], input[type="submit"], [role="button"]');
      for (var n = 0; n < knoepfe.length && n < 40; n++) {
        if (sichtbar(knoepfe[n]) && knopfOk(knoepfe[n]) && klick(knoepfe[n], 'wort')) return;
      }
    }
    if (versuche < 12 && Date.now() - start < 12000) setTimeout(bannerVersuch, 1000);
  }

  // --- Befehle vom Kern (Werte, nie Code) -------------------------------------------------------------------

  function befehl(a) {
    if (!a || typeof a !== 'object' || a.t !== 'filter') return;
    an = a.an === true;
    selektoren = Array.isArray(a.selektoren) ? a.selektoren.slice(0, 24000) : [];
    if (!an) {
      if (style && style.parentNode) style.parentNode.removeChild(style);
      cookies = 'aus';
      versteckt = 0;
      stand();
      return;
    }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', function () { anwenden(); bannerVersuch(); }, { once: true });
    else { anwenden(); bannerVersuch(); }
  }

  Object.defineProperty(globalThis, '__uzaiFilter', { value: Object.freeze({ befehl: befehl }), writable: false, configurable: false });

  // Wird das <style> von der Seite entfernt, kommt es zurück (höchstens alle 400 ms).
  var plan = 0;
  new MutationObserver(function () {
    if (!an || !style || style.isConnected || plan) return;
    plan = setTimeout(function () { plan = 0; anwenden(); }, 400);
  }).observe(document.documentElement || document, { childList: true, subtree: true });
})();
