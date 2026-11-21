(function () {
  'use strict';
  var pending = false, committing = false;
  var clean = function (n) { return (n && n.textContent || '').replace(/\s+/g, ' ').trim(); };
  function parts() {
    var headings = Array.from(document.querySelectorAll('h3'));
    var rent = headings.find(function (n) { return /^Thuê lẻ từng tập phim$/i.test(clean(n)); });
    var month = headings.find(function (n) { return /^Trọn gói$/i.test(clean(n)); });
    if (!rent || !month) return null;
    var card = rent.parentElement, monthly = month.parentElement;
    return {card: card, monthly: monthly, button: card.querySelector('button'), root: card.parentElement};
  }
  function offer() {
    var p = parts();
    if (!p || !p.button || p.button.disabled || pending || !/^\/watch\/[^/]+$/.test(location.pathname)) return null;
    var price = clean(p.card.querySelector('h2')), term = clean(p.card.querySelector('li'));
    var title = clean(document.querySelector('main h1')) || clean(document.querySelector('h1')) || document.title;
    if (!price || !title) return null;
    return {title: title, price: price, term: term, page: location.href,
      fingerprint: JSON.stringify([location.pathname, title, price, term])};
  }
  function prepare() {
    var p = parts();
    if (p) { p.monthly.style.display = 'none'; return 'open'; }
    var button = Array.from(document.querySelectorAll('button')).find(function (n) { return /^Kích hoạt VIP mod(?:e)?$/i.test(clean(n)); });
    if (!button || button.disabled) return 'waiting';
    button.click(); p = parts(); if (p) p.monthly.style.display = 'none';
    return p ? 'open' : 'waiting';
  }
  function commit(fingerprint) {
    var current = offer();
    if (!current || current.fingerprint !== fingerprint) return false;
    var p = parts(); pending = true; committing = true;
    try { p.button.click(); } finally { committing = false; }
    return true;
  }
  document.addEventListener('submit', function (e) {
    var p = parts(); if (p && p.monthly.contains(e.target)) { e.preventDefault(); e.stopImmediatePropagation(); }
  }, true);
  document.addEventListener('click', function (e) {
    var p = parts(); if (!p) return;
    if (p.monthly.contains(e.target)) { e.preventDefault(); e.stopImmediatePropagation(); return; }
    var b = e.target.closest && e.target.closest('button');
    if (b !== p.button || committing) return;
    e.preventDefault(); e.stopImmediatePropagation();
    var value = offer(); if (value && window.webkit && window.webkit.messageHandlers.rental) {
      window.webkit.messageHandlers.rental.postMessage(value);
    }
  }, true);
  function snapshot() {
    var v = document.querySelector('video'), player = v && v.player;
    if (!player) { var el = document.querySelector('.video-js'); player = el && el.player; }
    var urls = [], add = function (value) { if (typeof value === 'string' && /^https:\/\//.test(value) && urls.indexOf(value) < 0) urls.push(value); };
    try { if (player && player.currentSource) add(player.currentSource().src); } catch (_) {}
    try { if (player && player.currentSources) player.currentSources().forEach(function (s) { add(s.src); }); } catch (_) {}
    document.querySelectorAll('video,video source').forEach(function (e) { add(e.currentSrc || e.src); });
    var tracks = (player && player.textTracks && player.textTracks()) || (v && v.textTracks) || [], subs = [], total = 0;
    for (var i = 0; i < tracks.length && subs.length < 4; i++) {
      var t = tracks[i]; if (!/^(subtitles|captions)$/.test(t.kind) || !t.cues || !t.cues.length || /^__/.test(t.language || '')) continue;
      var cues = [];
      for (var k = 0; k < t.cues.length && k < 5000; k++) {
        var c = t.cues[k], text = String(c.text || '').slice(0, 2000);
        if (!Number.isFinite(c.startTime) || !Number.isFinite(c.endTime) || c.endTime <= c.startTime || !text) continue;
        total += text.length; if (total > 350000) break;
        cues.push({start: c.startTime, end: c.endTime, text: text});
      }
      if (cues.length) subs.push({language: t.language || 'vi', label: t.label || t.language || 'Phụ đề', cues: cues});
    }
    if (v) v.pause();
    return {urls: urls, page: location.href, time: v && Number.isFinite(v.currentTime) ? v.currentTime : 0, subtitles: subs, ua: navigator.userAgent};
  }
  window.XemRental = {prepare: prepare, offer: offer, commit: commit, snapshot: snapshot};
})();
