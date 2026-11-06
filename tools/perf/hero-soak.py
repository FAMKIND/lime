#!/usr/bin/env python3
"""LIME-284e13: run the marketing page's hero for N minutes and sample it about every 5 s.

    python3 tools/perf/hero-soak.py URL MINUTES OUT.json [--dpr 2]

Per sample: frames per second the page managed (a requestAnimationFrame counter), long tasks (>50 ms) and their total,
the share of one CPU core the page's main thread used (CDP Performance TaskDuration), script/layout/style-recalc counts
in that interval, the JS heap, DOM nodes, event listeners, how many <video> elements are playing and their decoded
and dropped frames, and the canvas size. The pointer moves a little every 5 s, as a visitor's would. Playwright's headless
Chromium uses software rendering, so read the trend, not the absolute numbers."""
import json, sys, time
from playwright.sync_api import sync_playwright

url, minutes, out = sys.argv[1], float(sys.argv[2]), sys.argv[3]
dpr = float(sys.argv[sys.argv.index("--dpr") + 1]) if "--dpr" in sys.argv else 2
INIT = """
window.__f = 0; (function r(){ window.__f++; requestAnimationFrame(r); })();
window.__lt = {n:0, ms:0};
try { new PerformanceObserver(l => l.getEntries().forEach(e => { window.__lt.n++; window.__lt.ms += e.duration; })).observe({entryTypes:['longtask']}); } catch (e) {}
"""
SNAP = """() => {
  const v = [...document.querySelectorAll('video')];
  const q = v.map(e => e.getVideoPlaybackQuality ? e.getVideoPlaybackQuality() : {totalVideoFrames:0, droppedVideoFrames:0});
  const cv = document.querySelector('canvas.bloom');
  return { f: window.__f, lt: window.__lt, heap: performance.memory ? performance.memory.usedJSHeapSize : 0,
    playing: v.filter(e => !e.paused && !e.ended).length, videos: v.length,
    decoded: q.reduce((a,b)=>a+b.totalVideoFrames,0), dropped: q.reduce((a,b)=>a+b.droppedVideoFrames,0),
    canvas: cv ? cv.width + 'x' + cv.height : '-', slide: [...document.querySelectorAll('.slide')].findIndex(s => s.classList.contains('on')) };
}"""
rows = []
with sync_playwright() as p:
    b = p.chromium.launch(args=["--enable-precise-memory-info"])
    ctx = b.new_context(viewport={"width": 1440, "height": 900}, device_scale_factor=dpr)
    pg = ctx.new_page(); pg.add_init_script(INIT)
    cdp = ctx.new_cdp_session(pg); cdp.send("Performance.enable")
    def metrics():
        m = {x["name"]: x["value"] for x in cdp.send("Performance.getMetrics")["metrics"]}
        c = cdp.send("Memory.getDOMCounters")
        return m, c
    pg.goto(url, wait_until="load"); pg.wait_for_timeout(3000)
    m0, _ = metrics(); s0 = pg.evaluate(SNAP); t0 = time.time(); prev_t = t0
    x, y, n = 700, 420, 0
    while time.time() - t0 < minutes * 60:
        for _ in range(2):
            n += 1; x = 700 + (n % 7) * 40; y = 380 + (n % 5) * 30; pg.mouse.move(x, y, steps=6); pg.wait_for_timeout(2300)
        m1, c1 = metrics(); s1 = pg.evaluate(SNAP); now = time.time(); dt = now - prev_t
        rows.append({
            "t": round(now - t0), "fps": round((s1["f"] - s0["f"]) / dt, 1), "longtasks": s1["lt"]["n"] - s0["lt"]["n"], "longtask_ms": round(s1["lt"]["ms"] - s0["lt"]["ms"]),
            "main_thread_cpu_pct": round(100 * (m1["TaskDuration"] - m0["TaskDuration"]) / dt, 1), "script_pct": round(100 * (m1["ScriptDuration"] - m0["ScriptDuration"]) / dt, 1),
            "layouts": int(m1["LayoutCount"] - m0["LayoutCount"]), "recalcs": int(m1["RecalcStyleCount"] - m0["RecalcStyleCount"]),
            "heap_mb": round(s1["heap"] / 1048576, 1), "nodes": c1["nodes"], "listeners": c1["jsEventListeners"],
            "videos_playing": s1["playing"], "video_elements": s1["videos"], "decoded_fps": round((s1["decoded"] - s0["decoded"]) / dt, 1), "dropped": s1["dropped"] - s0["dropped"],
            "canvas": s1["canvas"], "slide": s1["slide"]})
        m0, s0, prev_t = m1, s1, now
        print(json.dumps(rows[-1]), flush=True)
        json.dump(rows, open(out, "w"), indent=1)
    b.close()
