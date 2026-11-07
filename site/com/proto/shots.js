/* LIME-286r: a feature phone built from real screenshots of the app (the iOS simulator, the demo, the default look), so every icon, font and spacing is the app's own.
   media/demo/flows.json lists, for each feature, its workflows and their states: a screenshot, its alt text, how long it stays, the hot spots over its real buttons,
   and any overlay. The player auto-plays the workflows in turn while the phone is on screen; a touch, hover or focus pauses it and a visitor can tap the hot spots to
   go on by hand; after ~10 s of quiet it takes over again from where it was. The list beside the phone shows the workflow that is playing (a thin bar fills as it
   goes) and jumps to one when clicked. Reduced motion: no auto-play; the phone is still usable by hand. */
(function () {
  "use strict";
  var reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches, flows = null, waiting = [];
  function load(cb) { if (flows) return cb(); waiting.push(cb); if (load.busy) return; load.busy = 1; fetch("media/demo/flows.json").then(function (r) { return r.json(); }).then(function (d) { flows = d; waiting.splice(0).forEach(function (f) { f(); }); }); }
  function h(tag, cls, html) { var e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; }
  var URL = "media/demo/flow/";
  var MESH = '<svg viewBox="0 0 300 130" aria-hidden="true" focusable="false"><g stroke="#131b17" stroke-opacity=".4" stroke-width="2" stroke-linecap="round" stroke-dasharray="1 8" fill="none"><path d="M40 70 100 30M40 70 100 100M100 30 170 65M100 100 170 65M170 65 230 28M170 65 235 100"/><animate attributeName="stroke-dashoffset" values="0;-18" dur="2s" repeatCount="indefinite"/></g><g fill="#fff" stroke="#131b17" stroke-width="2"><rect x="26" y="46" width="28" height="48" rx="8" fill="#a3e18a"/><circle cx="40" cy="70" r="5" fill="#131b17" stroke="none"/><rect x="88" y="10" width="22" height="40" rx="6"/><rect x="88" y="82" width="22" height="40" rx="6"/><rect x="159" y="45" width="22" height="40" rx="6"/><rect x="219" y="8" width="22" height="40" rx="6"/><rect x="220" y="80" width="30" height="46" rx="8" fill="#e4f9be"/></g>'
    + '<g><path d="M0-9c5 0 9 3.6 9 8s-4 8-9 8c-1.3 0-2.5-.2-3.6-.7L-8 9l1.4-4C-8.5 3.7-9-.2-9-1c0-4.4 4-8 9-8z" fill="#a3e18a" stroke="#131b17" stroke-width="1.8"/><rect x="-3" y="-3" width="6" height="5" rx="1" fill="#131b17"/>'
    + '<animateTransform attributeName="transform" type="translate" calcMode="linear" values="40 70;40 70;100 30;170 65;235 100;235 100" keyTimes="0;.08;.36;.64;.9;1" dur="3.4s" repeatCount="indefinite"/><animate attributeName="opacity" values="0;1;1;0;0" keyTimes="0;.06;.9;.95;1" dur="3.4s" repeatCount="indefinite"/></g></svg>';

  function Flow(root, def, list) {
    var A = h("img", "sp on"), B = h("img", "sp"), ov = h("div", "sp-ov"), box = h("div", "sp-hs"), live = h("div", "sp-live"); live.setAttribute("aria-live", "polite");
    A.decoding = B.decoding = "async"; B.alt = ""; B.setAttribute("aria-hidden", "true"); live.style.cssText = "position:absolute;left:-9999px;width:1px;height:1px;overflow:hidden";
    root.appendChild(A); root.appendChild(B); root.appendChild(ov); root.appendChild(box); root.appendChild(live);
    var all = [], byId = {}; def.workflows.forEach(function (w, wi) { w.states.forEach(function (s, si) { s.w = wi; s.i = si; all.push(s); byId[s.id] = s; }); w.total = w.states.reduce(function (a, s) { return a + s.ms; }, 0); });
    var cur = null, front = A, back = B, timer = null, paused = true, visible = false, idle = null, manual = false, activeW = -1, items = [];
    if (list) {   /* five small dots under the phone, one per workflow: the playing one stretches and fills (a thin progress line); a click jumps to it */
      var nm = h("span", "sp-name"); nm.setAttribute("aria-hidden", "true");
      def.workflows.forEach(function (w, wi) {
        var b = h("button", "", "<i class='bar'></i>"); b.type = "button"; b.setAttribute("aria-label", w.title + ": " + w.line);
        b.addEventListener("click", function () { manual = false; go(w.states[0].id); paused = false; if (visible) schedule(); });
        list.appendChild(b); items.push(b);
      });
      list.appendChild(nm); list._nm = nm;
    }
    function mark(s) {
      if (s.w === activeW) return; activeW = s.w;
      if (list && list._nm) list._nm.textContent = def.workflows[s.w].title;
      items.forEach(function (b, i) { var on = i === s.w; b.classList.toggle("on", on); if (on) b.setAttribute("aria-current", "true"); else b.removeAttribute("aria-current"); var bar = b.querySelector(".bar"); bar.style.animation = "none"; if (on) { void bar.offsetWidth; bar.style.animation = "wffill " + def.workflows[s.w].total + "ms linear forwards"; bar.style.animationPlayState = paused ? "paused" : "running"; } });
    }
    function preload(s) { if (!s) return; var n = all[(all.indexOf(s) + 1) % all.length], i = new Image(); i.src = URL + n.img + ".webp"; }
    function overlays(s) {
      ov.innerHTML = "";
      if (s.nosignal) ov.appendChild(h("span", "nosig", "No service"));
      if (s.overlay === "mesh") { var c = h("div", "meshcard", MESH + "<p>No signal. Nearby phones pass it on, sealed.</p>"); ov.appendChild(c); }
      if (s.looks) {
        var row = h("div", "looks"); row.setAttribute("role", "group"); row.setAttribute("aria-label", "Looks");
        def.workflows[s.w].states.forEach(function (t) { var b = h("button", t === s ? "on" : "", t.alt.replace(/^A chat on an? /, "").replace(/ background with an? /, " · ").replace(/ accent$/, "")); b.type = "button"; b.addEventListener("click", function () { touched(); go(t.id, true); }); row.appendChild(b); });
        ov.appendChild(row);
      }
    }
    function hotspots(s) {
      box.innerHTML = ""; (s.hs || []).forEach(function (p) {
        var b = h("button", "hs"); b.type = "button"; b.setAttribute("aria-label", p.label); b.style.cssText = "left:" + p.x * 100 + "%;top:" + p.y * 100 + "%;width:" + p.w * 100 + "%;height:" + p.h * 100 + "%";
        b.addEventListener("click", function (e) { e.stopPropagation(); touched(); go(p.to, true); }); box.appendChild(b);
      });
    }
    function go(id, byHand) {
      var s = byId[id]; if (!s || s === cur) return; var first = !cur; cur = s; manual = !!byHand;
      back.alt = s.alt; back.removeAttribute("aria-hidden"); front.alt = ""; front.setAttribute("aria-hidden", "true");
      var fin = function () { back.classList.toggle("slide", !!s.slide && !first); back.classList.add("on"); front.classList.remove("on"); var t = front; front = back; back = t; };
      back.onload = fin; back.src = URL + s.img + ".webp"; if (back.complete && back.naturalWidth) { back.onload = null; fin(); }
      mark(s); overlays(s); hotspots(s); preload(s); if (byHand) live.textContent = s.alt;
    }
    function next() { var s = all[(all.indexOf(cur) + 1) % all.length]; go(s.id); schedule(); }
    function schedule() { clearTimeout(timer); if (paused || !visible || reduce) return; timer = setTimeout(next, cur.ms); }
    function setPaused(v) { paused = v; items.forEach(function (b) { var bar = b.querySelector(".bar"); if (bar) bar.style.animationPlayState = v ? "paused" : "running"; }); }
    function touched() { setPaused(true); clearTimeout(timer); clearTimeout(idle); idle = setTimeout(play, 10000); }   /* back to the script after ~10 s of quiet, from where it was */
    function play() { if (reduce || !visible || !paused) return; setPaused(false); schedule(); }
    ["pointerdown", "pointerenter", "focusin", "touchstart", "keydown"].forEach(function (e) { root.addEventListener(e, function () { if (!reduce) touched(); }, { passive: true }); });
    root.addEventListener("pointerleave", function () { clearTimeout(idle); if (!reduce) idle = setTimeout(play, 10000); });
    function scale() { root.style.setProperty("--k", (root.clientWidth / 390).toFixed(4)); } scale(); if ("ResizeObserver" in window) new ResizeObserver(scale).observe(root);
    if ("IntersectionObserver" in window) new IntersectionObserver(function (es) { visible = es[0].isIntersecting; if (visible) { clearTimeout(idle); if (!reduce && !manual) { setPaused(true); setTimeout(play, 500); } } else { setPaused(true); clearTimeout(timer); clearTimeout(idle); } }, { threshold: 0.4 }).observe(root);
    go(all[0].id); setPaused(true);
    if (list) list.hidden = false;
  }
  window.LimeShots = { mount: function (root) { var key = root.dataset.flow; load(function () { new Flow(root, flows[key], document.querySelector('[data-dots-for="' + key + '"]')); }); } };
  document.querySelectorAll("[data-flow]").forEach(function (r) { window.LimeShots.mount(r); });
})();
