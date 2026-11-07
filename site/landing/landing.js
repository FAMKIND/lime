/* limemessenger.com, the public landing (LIME-289). No cookies, no analytics, nothing about the visitor is kept. */
var reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

/* ONE SWITCH for launch (the same as the full site's, and the same two links as the full site's script and /get/): while both are empty, the card says "Notify me" and there is no
   download card. Put the App Store (and, once it exists, Google Play) links here and "Notify me" becomes "Download" (iPhone and iPad go to the App Store, Android to Google Play,
   a desktop opens the download card with its QR code), the email form goes, and the store badges show. Preview it locally with ?launched=1 (localhost only). */
window.LIME_LAUNCH = { appStore: "", googlePlay: "" };
var MSG_OK = "Check your email to confirm. We'll email you once, when lime is ready.";
(function () {
  var L = window.LIME_LAUNCH, local = /^(localhost|127\.0\.0\.1)$/.test(location.hostname);
  if (local && /[?&]launched=(1|ios)/.test(location.search)) L = window.LIME_LAUNCH = { appStore: "https://apps.apple.com/app/lime", googlePlay: /launched=ios/.test(location.search) ? "" : "https://play.google.com/store/apps/details?id=com.limemessenger.lime" };
  var launched = !!(L.appStore || L.googlePlay);
  document.documentElement.classList.toggle("launched", launched);
  document.querySelectorAll("[data-store]").forEach(function (a) { var u = L[a.dataset.store]; if (u) a.href = u; else a.hidden = true; });
  document.querySelector(".stores").hidden = !launched;
  if (!launched) return;
  var ua = navigator.userAgent, ios = /iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1), android = /Android/.test(ua);
  var store = ios ? L.appStore : android ? L.googlePlay : "";
  document.querySelectorAll("form[data-android]").forEach(function (f) { f.hidden = !(android && !L.googlePlay); });   /* Android visitors, before Google Play */
  if (android && !L.googlePlay) document.querySelector(".stores").hidden = true;
  var card = null;
  function openCard() { if (card) { card.hidden = false; card.classList.add("show"); } }
  document.querySelectorAll("form[data-subscribe]:not([data-android])").forEach(function (f) {
    var a = document.createElement("a"); a.className = "btn dl-cta"; a.textContent = "Download"; a.setAttribute("aria-label", "Download the lime app"); a.setAttribute("data-dl", ""); a.href = store || "#";
    f.replaceWith(a);
  });
  document.querySelectorAll("[data-fine]").forEach(function (p) { p.remove(); });
  var t = document.getElementById("dl-card"); card = t.content.firstElementChild.cloneNode(true); document.body.appendChild(card);
  card.querySelector("a.get").href = L.appStore || L.googlePlay || "#";
  card.querySelector(".x").addEventListener("click", function () { card.classList.remove("show"); card.hidden = true; });
  card.hidden = true;
  document.querySelectorAll("a[data-dl]").forEach(function (a) { if (!store) a.addEventListener("click", function (e) { e.preventDefault(); openCard(); }); });
})();

/* The launch list (284c2): the form posts to waitlist-join (a plain HTML post works without this script); here the answer shows in place. */
document.querySelectorAll("[data-subscribe]").forEach(function (f) {
  var out = f.querySelector("output"), btn = f.querySelector("button[type=submit]");
  f.addEventListener("submit", function (e) {
    if (!window.fetch || !window.URLSearchParams || !window.FormData) return;   /* an old browser sends the plain form */
    e.preventDefault();
    var android = f.hasAttribute("data-android"); btn.disabled = true; out.textContent = "";
    fetch(f.action, { method: "POST", headers: { "Accept": "application/json", "Content-Type": "application/x-www-form-urlencoded" }, body: new URLSearchParams(new FormData(f)).toString() })
      .then(function (r) { return r.json().catch(function () { return {}; }).then(function (b) { return { ok: r.ok, status: r.status, body: b }; }); })
      .then(function (r) {
        if (r.ok) {
          out.textContent = android ? "Check your email to confirm. We'll email you once, when lime is on Android." : MSG_OK;
          f.querySelectorAll("input[type=email]").forEach(function (i) { i.value = ""; });
          return;
        }
        btn.disabled = false;
        out.textContent = r.status === 429 ? "Too many tries. Please wait a few minutes." : r.status === 400 ? "That doesn't look like an email address." : "We couldn't add that just now. Please try again.";
      })
      .catch(function () { btn.disabled = false; out.textContent = "We couldn't reach the list. Please try again."; });
  });
});

/* The background: three videos, a plain crossfade every 6 s. Only the visible video plays; the next one starts 2 s before it fades in. The pause button stops the
   change and the video (and a tab that is hidden does the same). Reduce Motion: the first poster, still, no video is ever loaded. */
(function () {
  var bg = document.querySelector(".bg"), slides = [].slice.call(bg.querySelectorAll(".slide")), pp = document.querySelector(".pp");
  var N = slides.length, SECONDS = 6000, cur = 0, paused = false, timer = 0, early = 0;
  if (reduce || N < 2) { if (pp) pp.hidden = true; return; }
  var portrait = window.matchMedia("(max-aspect-ratio: 1/1)").matches;
  function vid(i) { return slides[i].querySelector("video"); }
  function prep(i) {
    var v = vid(i); if (v.dataset.ready) return v; v.dataset.ready = 1; v.preload = "auto";
    var base = portrait ? slides[i].dataset.tall : slides[i].dataset.wide;
    [["-av1.mp4", 'video/mp4; codecs="av01.0.05M.08"'], [".mp4", 'video/mp4; codecs="avc1.640028"']].forEach(function (t) { var e = document.createElement("source"); e.src = base + t[0]; e.type = t[1]; v.appendChild(e); });
    v.load(); return v;
  }
  function play(i) { var v = prep(i); v.play().then(function () { v.classList.add("go"); }).catch(function () {}); }
  function running() { return !paused && !document.hidden; }
  function schedule() {
    clearTimeout(timer); clearTimeout(early); if (!running()) return;
    early = setTimeout(function () { play((cur + 1) % N); }, SECONDS - 2000);
    timer = setTimeout(function () {
      var next = (cur + 1) % N;
      play(next); slides[cur].classList.remove("on"); slides[next].classList.add("on");
      var old = cur; cur = next;
      setTimeout(function () { if (old !== cur) { var v = vid(old); v.pause(); v.classList.remove("go"); } }, 1400);   /* after the fade, the old one stops */
      schedule();
    }, SECONDS);
  }
  function sync() {
    if (running()) { play(cur); schedule(); }
    else { clearTimeout(timer); clearTimeout(early); slides.forEach(function (s, i) { vid(i).pause(); }); }
  }
  pp.addEventListener("click", function () {
    paused = !paused; pp.classList.toggle("paused", paused);
    pp.setAttribute("aria-label", paused ? "Play the background video" : "Pause the background video");
    sync();
  });
  document.addEventListener("visibilitychange", sync);
  sync();
})();
