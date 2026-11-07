/* LIME-286a: the interactive lime phone, engine and the "link" screens. Vanilla JS, no framework.
   Screens are plain HTML at the app's size (390 x 848) inside .lpwrap, scaled to the frame; people, chats, messages and the auto-play script
   come from media/demo/demo.json (swap the manifest and pictures to change the cast). Icons: Lucide (ISC licence), inlined.
   The script player auto-plays while the phone is on screen, pauses the moment a visitor touches, hovers or focuses it, resumes after ~10 s
   of quiet from where it was, and never moves focus. Reduced motion: no auto-play; the phone is still interactive. */
(function () {
  "use strict";
  var reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var P = {
    back: '<path d="m15 18-6-6 6-6"/>', search: '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>', video: '<path d="m16 13 5.223 3.482a.5.5 0 0 0 .777-.416V7.87a.5.5 0 0 0-.752-.432L16 10.5"/><rect x="2" y="6" width="14" height="12" rx="2"/>',
    plus: '<path d="M5 12h14"/><path d="M12 5v14"/>', up: '<path d="m5 12 7-7 7 7"/><path d="M12 19V5"/>', mic: '<path d="M12 19v3"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><rect x="9" y="2" width="6" height="13" rx="3"/>',
    smile: '<circle cx="12" cy="12" r="10"/><path d="M8 14s1.5 2 4 2 4-2 4-2"/><line x1="9" x2="9.01" y1="9" y2="9"/><line x1="15" x2="15.01" y1="9" y2="9"/>',
    pin: '<path d="M12 17v5"/><path d="M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 1 0 0 1 1 1z"/>',
    play: '<polygon points="6 3 20 12 6 21 6 3"/>', phone: '<path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z"/>',
    chat: '<path d="M7.9 20A9 9 0 1 0 4 16.1L2 22Z"/>', link: '<path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>', inbox: '<polyline points="22 12 16 12 14 15 10 15 8 12 2 12"/><path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/>'
  };
  function ic(n) { return '<svg class="ic" viewBox="0 0 24 24" aria-hidden="true">' + P[n] + '</svg>'; }
  function h(tag, cls, html) { var e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; }
  function esc(s) { return String(s).replace(/[&<>"]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]; }); }
  var SYS = '<span class="sys"><svg viewBox="0 0 20 12" aria-hidden="true"><path d="M1 8h3v3H1zM6 6h3v5H6zM11 4h3v7h-3zM16 1h3v10h-3z"/></svg><svg viewBox="0 0 18 12" aria-hidden="true"><path d="M9 11.5 6.6 9a3.4 3.4 0 0 1 4.8 0zM9 6a6 6 0 0 1 4.2 1.7l-1.2 1.3a4.3 4.3 0 0 0-6 0L4.8 7.7A6 6 0 0 1 9 6zM9 2.2a9.7 9.7 0 0 1 6.8 2.8l-1.2 1.3a8 8 0 0 0-11.2 0L2.2 5A9.7 9.7 0 0 1 9 2.2z"/></svg><svg viewBox="0 0 28 12" aria-hidden="true"><rect x="0.5" y="0.5" width="23" height="11" rx="3.2" fill="none" stroke="#131b17" opacity=".4"/><rect x="2" y="2" width="20" height="8" rx="2" fill="#34c759"/><path d="M25 4v4c.8-.3 1.5-1.1 1.5-2S25.8 4.3 25 4z" opacity=".4"/></svg></span>';
  function status() { return h("div", "status", "<span>9:41</span>" + SYS); }

  var demo = null, queue = [], phones = [];
  function load(cb) { if (demo) return cb(); queue.push(cb); if (load.busy) return; load.busy = 1; fetch("media/demo/demo.json").then(function (r) { return r.json(); }).then(function (d) { demo = d; queue.splice(0).forEach(function (f) { f(); }); }); }
  function colour(t) { return demo.accents[((t % 8) + 8) % 8]; }
  function initials(name) { return name.split(" ").map(function (w) { return w[0]; }).slice(0, 2).join(""); }
  function avatar(c, size) { var t = c.person ? demo.people[c.person] : c, name = t.name || t.title, a = h("span", "av"); a.style.setProperty("--c", colour(t.tone)); if (size) a.style.setProperty("--s", size + "px"); a.setAttribute("aria-hidden", "true"); a.textContent = c.emoji || (t.emoji) || initials(name); return a; }
  function title(c) { return c.person ? demo.people[c.person].name : c.title; }

  /* ---------- the link phone ---------- */
  function link(root) {
    var wrap = root, lp = h("div", "lp"), listScr = h("section", "scr"), chatScr = h("section", "scr right");
    var island = h("div", "island"); island.setAttribute("aria-hidden", "true");
    lp.appendChild(island); lp.appendChild(listScr); lp.appendChild(chatScr); wrap.appendChild(lp);
    chatScr.hidden = true;
    var state = { chat: null, msgs: {}, reacted: {} };
    var timers = [];
    function scale() { lp.style.setProperty("--k", (wrap.clientWidth / 390).toFixed(4)); }
    scale(); if ("ResizeObserver" in window) new ResizeObserver(scale).observe(wrap);

    /* the list */
    function buildList() {
      listScr.innerHTML = ""; listScr.appendChild(status());
      var top = h("div", "ltop");
      top.innerHTML = '<img class="brandmark" src="brand/lime-Logomark.svg" alt="">' + '<span style="display:flex;gap:10px"><button class="circ" type="button" aria-label="Search">' + ic("search") + "</button></span>";
      listScr.appendChild(top);
      listScr.appendChild(h("div", "banner", ic("inbox") + "<span>Requests: 1 person wants to message you</span><span class='num'>1</span>"));
      var rows = h("div", "rows"); rows.setAttribute("role", "list");
      demo.chats.forEach(function (c) {
        var b = h("button", "row"); b.type = "button"; b.setAttribute("role", "listitem"); b.dataset.chat = c.id;
        b.setAttribute("aria-label", title(c) + ": " + c.preview + (c.unread ? ", unread" : ""));
        b.appendChild(avatar(c));
        var tx = h("span", "tx", "<b>" + esc(title(c)) + "</b><span class='pv'>" + esc(c.preview) + "</span>"); b.appendChild(tx);
        b.appendChild(h("span", "meta", "<span>" + c.time + "</span>" + (c.unread ? "<i class='dot'></i>" : c.pinned ? ic("pin").replace('class="ic"', 'class="ic pin"') : "")));
        b.addEventListener("click", function () { openChat(c.id); });
        rows.appendChild(b);
      });
      listScr.appendChild(rows);
      listScr.appendChild(h("button", "fab", ic("plus"))); listScr.lastChild.setAttribute("aria-label", "New message"); listScr.lastChild.type = "button";
      var tabs = h("div", "tabs"); tabs.setAttribute("role", "navigation"); tabs.setAttribute("aria-label", "Tabs");
      tabs.innerHTML = '<button type="button" aria-current="page">' + ic("chat") + "link</button><button type='button'>" + ic("phone") + "call</button><button type='button'><span class='q' aria-hidden='true'>””</span>jam</button>";
      listScr.appendChild(tabs);
    }

    /* the conversation */
    function bubbleFor(c, m) {
      var row = h("div", "m" + (m.from === "me" ? " me" : "")), b = h("div", "b");
      if (m.from !== "me" && c.group) row.appendChild(avatar({ person: m.from }, 28));
      if (m.photo) { b.className += " ph"; b.innerHTML = '<img src="media/demo/' + m.photo + '.webp" width="236" height="156" alt="A desk seen from above: notepad, phone, pens">' + (m.text ? "<span>" + esc(m.text) + "</span>" : ""); }
      else if (m.voice) { b.className += " vn"; var w = ""; for (var i = 0; i < 26; i++) w += "<i style='height:" + (6 + Math.round(Math.abs(Math.sin(i * 1.7)) * 18)) + "px'></i>"; b.innerHTML = "<span class='pl'>" + ic("play") + "</span><span class='wave' aria-hidden='true'>" + w + "</span><span>" + m.voice + "</span>"; b.setAttribute("aria-label", "Voice message, " + m.voice); }
      else if (m.link) { b.className += " lk"; b.innerHTML = "<b>" + esc(m.link.title) + "</b><span>" + ic("link") + esc(m.link.host) + "</span>"; }
      else b.textContent = m.text;
      b.tabIndex = 0; b.setAttribute("role", "button"); if (!b.getAttribute("aria-label")) b.setAttribute("aria-label", (m.text || "Message") + ". Press to react");
      b.addEventListener("click", function (e) { e.stopPropagation(); showBar(row, m); });
      b.addEventListener("keydown", function (e) { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); showBar(row, m); } });
      row.appendChild(b); if (m.time) { var t = h("span", "t", m.time); if (m.from === "me") row.insertBefore(t, b); else row.appendChild(t); }
      row._m = m; if (m.react) addPill(row, m.react);
      return row;
    }
    function addPill(row, emoji) { var bub = row.querySelector(".b"), old = bub.querySelector(".react"); if (old) old.remove(); var p = h("span", "react", "<span aria-hidden='true'>" + emoji + "</span> 1"); p.setAttribute("aria-label", "Reaction " + emoji + ", 1 person"); bub.appendChild(p); row.classList.add("hasr"); row._m.react = emoji; }
    function showBar(row, m) {
      hideBar(); var bar = h("div", "bar"); bar.setAttribute("role", "toolbar"); bar.setAttribute("aria-label", "React");
      ["👍", "❤️", "😂", "😮", "😢", "🙏"].forEach(function (e) { var b = h("button", "", e); b.type = "button"; b.setAttribute("aria-label", "React with " + e); b.addEventListener("click", function (ev) { ev.stopPropagation(); addPill(row, e); hideBar(); }); bar.appendChild(b); });
      var pl = h("button", "plus", "+"); pl.type = "button"; pl.setAttribute("aria-label", "More emoji"); bar.appendChild(pl);
      chatScr.appendChild(bar); var r = row.querySelector(".b").getBoundingClientRect(), s = chatScr.getBoundingClientRect(), k = wrap.clientWidth / 390;
      var y = (r.top - s.top) / k - 58; bar.style.top = Math.max(60, y) + "px"; var x = (m.from === "me" ? (r.right - s.left) / k - 292 : (r.left - s.left) / k); bar.style.left = Math.max(8, Math.min(390 - 300, x)) + "px"; bar._row = row;
    }
    function hideBar() { var b = chatScr.querySelector(".bar"); if (b) b.remove(); }
    function openChat(id, silent) {
      var c = demo.chats.filter(function (x) { return x.id === id; })[0]; state.chat = id; chatScr.innerHTML = ""; chatScr.appendChild(status());
      var who = c.person ? demo.people[c.person] : null;
      var nav = h("div", "nav"); var back = h("button", "circ", ic("back")); back.type = "button"; back.setAttribute("aria-label", "Back to your chats"); back.addEventListener("click", function () { backToList(); }); nav.appendChild(back);
      nav.appendChild(avatar(c, 40)); nav.appendChild(h("div", "who", "<b>" + esc(title(c)) + "</b><span>" + esc(who ? who.status : "4 members") + "</span>"));
      var v = h("button", "circ", ic("video")); v.type = "button"; v.setAttribute("aria-label", "Video call"); nav.appendChild(v); chatScr.appendChild(nav);
      var msgs = h("div", "msgs"); msgs.setAttribute("role", "log"); msgs.setAttribute("aria-label", "Conversation with " + title(c));
      var list = state.msgs[id] || (state.msgs[id] = JSON.parse(JSON.stringify(demo.conversations[id] || [])));
      list.forEach(function (m) { if (m.day) msgs.appendChild(h("div", "day", m.day)); else if (m.call) { var cl = h("div", "call", ic("video") + esc(m.call)); msgs.appendChild(cl); } else msgs.appendChild(bubbleFor(c, m)); });
      chatScr.appendChild(msgs); msgs.addEventListener("click", hideBar);
      var comp = h("form", "composer"); comp.innerHTML = '<label class="sr" for="lp-in" style="position:absolute;left:-9999px">Message</label><input id="lp-in" type="text" placeholder="Send message…" autocomplete="off" enterkeyhint="send"><button class="go" type="submit" aria-label="Send" disabled>' + ic("up") + "</button>";
      var inp = comp.querySelector("input"), go = comp.querySelector(".go");
      inp.addEventListener("input", function () { go.disabled = !inp.value.trim(); });
      comp.addEventListener("submit", function (e) { e.preventDefault(); var t = inp.value.trim(); if (!t) return; inp.value = ""; go.disabled = true; sendMine(t); if (!running) timers.push(setTimeout(function () { reply(); }, 1100)); });
      chatScr.appendChild(comp);
      chatScr.hidden = false; if (silent) { chatScr.classList.remove("right"); listScr.classList.add("left"); msgs.scrollTop = msgs.scrollHeight; }
      else { void chatScr.offsetWidth; chatScr.classList.remove("right"); listScr.classList.add("left"); setTimeout(function () { msgs.scrollTop = msgs.scrollHeight; }, 30); }
      msgs.style.scrollBehavior = "auto"; msgs.scrollTop = msgs.scrollHeight; msgs.style.scrollBehavior = "";
    }
    function backToList() { hideBar(); state.chat = null; chatScr.classList.add("right"); listScr.classList.remove("left"); setTimeout(function () { if (!state.chat) chatScr.hidden = true; }, 340); }
    function msgsEl() { return chatScr.querySelector(".msgs"); }
    function push(m, fromName) {
      var c = demo.chats.filter(function (x) { return x.id === state.chat; })[0], list = state.msgs[state.chat]; list.push(m);
      var el = bubbleFor(c, m), box = msgsEl(), ty = box.querySelector(".typingrow"); if (ty) ty.remove(); box.appendChild(el); box.scrollTop = box.scrollHeight; return el;
    }
    function now() { var d = new Date(); return d.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }); }
    function sendMine(t) { if (!state.chat) return; push({ from: "me", text: t, time: now() }); }
    function reply(text) {
      if (!state.chat) return; var c = demo.chats.filter(function (x) { return x.id === state.chat; })[0], box = msgsEl(), id = state.chat;
      var ty = h("div", "m typingrow", ""); if (c.group) ty.appendChild(avatar({ person: "lee" }, 28)); ty.appendChild(h("div", "b typing", "<i></i><i></i><i></i>")); ty.setAttribute("aria-hidden", "true"); box.appendChild(ty); box.scrollTop = box.scrollHeight;
      timers.push(setTimeout(function () { if (state.chat !== id) return; var t = text || demo.replies[Math.floor(Math.random() * demo.replies.length)]; push({ from: c.person || "lee", text: t, time: now() }); }, 1100));
    }
    function clearTimers() { timers.splice(0).forEach(clearTimeout); }
    var running = false;

    /* the script's verbs */
    var actions = {
      tap: function (a, done) { if (state.chat) return done(); var b = listScr.querySelector('[data-chat="' + a.tap + '"]'); b.classList.add("press"); timers.push(setTimeout(function () { b.classList.remove("press"); openChat(a.tap); done(); }, 420)); },
      scroll: function (a, done) { var b = msgsEl(); if (!b) return done(); b.scrollTo ? b.scrollTo({ top: a.scroll === "up" ? 0 : b.scrollHeight, behavior: "smooth" }) : (b.scrollTop = a.scroll === "up" ? 0 : b.scrollHeight); done(); },
      type: function (a, done) { if (!state.chat) openChat("mei", true); var inp = chatScr.querySelector("input"), go = chatScr.querySelector(".go"), i = 0; (function next() { if (i > a.type.length) return done(); inp.value = a.type.slice(0, i++); go.disabled = !inp.value; timers.push(setTimeout(next, 45)); })(); },
      send: function (a, done) { var inp = chatScr && chatScr.querySelector("input"); if (!inp || !inp.value.trim()) return done(); var t = inp.value; inp.value = ""; chatScr.querySelector(".go").disabled = true; sendMine(t); done(); },
      reply: function (a, done) { reply(a.reply); done(); },
      react: function (a, done) { var rows = chatScr.querySelectorAll(".m:not(.me):not(.typingrow)"), row = rows[rows.length - 1]; if (!row) return done(); showBar(row, row._m); timers.push(setTimeout(function () { addPill(row, a.react); hideBar(); done(); }, 900)); },
      back: function (a, done) { if (state.chat) backToList(); done(); },
      reset: function (a, done) { state.msgs = {}; done(); }   /* the loop starts clean: nothing the script said piles up */
    };
    function step(a, done) { if (a.wait != null) { timers.push(setTimeout(done, a.wait)); return; } for (var k in actions) if (k in a) return actions[k](a, done); done(); }

    buildList();
    return { el: wrap, step: step, clear: clearTimers, setRunning: function (v) { running = v; }, state: state, openChat: openChat, back: backToList };
  }

  /* ---------- the script player: one for all phones ---------- */
  function mount(root, kind) {
    var inst = ({ link: link })[kind](root), i = 0, paused = true, visible = false, idle = null, tick = null;
    function runNext() {
      if (paused || !visible) return;
      var a = demo.script[i % demo.script.length]; i++;
      inst.setRunning(true); inst.step(a, function () { inst.setRunning(false); tick = setTimeout(runNext, 30); });
    }
    function pause() { paused = true; clearTimeout(tick); inst.clear(); inst.setRunning(false); }
    function play() { if (reduce || !visible || !paused) return; paused = false; runNext(); }
    function touched() { pause(); clearTimeout(idle); idle = setTimeout(play, 10000); }   /* back to the script after ~10 s of quiet, from where it was */
    ["pointerdown", "pointerenter", "focusin", "touchstart", "keydown"].forEach(function (e) { root.addEventListener(e, touched, { passive: true }); });
    root.addEventListener("pointerleave", function () { clearTimeout(idle); idle = setTimeout(play, 10000); });
    root.addEventListener("pointermove", function () { if (!paused) touched(); }, { passive: true });
    if ("IntersectionObserver" in window) new IntersectionObserver(function (es) { visible = es[0].isIntersecting; if (visible) { clearTimeout(idle); if (!reduce) { paused = true; setTimeout(play, 600); } } else { pause(); clearTimeout(idle); } }, { threshold: 0.4 }).observe(root);
    phones.push(inst); return inst;
  }
  window.LimePhone = { mount: function (root, kind) { load(function () { mount(root, kind); }); } };
  document.querySelectorAll("[data-demo]").forEach(function (r) { window.LimePhone.mount(r, r.dataset.demo); });
})();
