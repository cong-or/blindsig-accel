// app.js — drive the datapath SVG from the REAL mulmod RTL (Verilator → WASM).
// Nothing here reimplements the algorithm: we only step the compiled circuit's
// clock and read its registers. The panel is an annunciator over that live state.

(function () {
  "use strict";
  const $ = (id) => document.getElementById(id);
  const STEP_MS = 70;

  let sim = null;
  let timer = null;
  let inA = 0, inB = 0, inM = 7;

  const stages = ["s_dbl", "s_red1", "s_add", "s_red2", "s_mux"];

  function setActive(ids) {
    stages.forEach((s) => {
      const g = $(s); if (!g) return;
      const box = g.querySelector("rect");
      if (!box) return;
      if (ids.includes(s)) { box.setAttribute("stroke", "#81e6d9"); box.setAttribute("filter", "url(#glowA)"); }
      else { box.removeAttribute("filter"); box.setAttribute("stroke", s === "s_mux" ? "#2c7a7b" : "#2a3540"); }
    });
  }
  function pulseAcc() {
    const g = $("s_acc"); if (!g) return;
    const box = g.querySelector("rect");
    box.setAttribute("stroke", "#81e6d9");
    setTimeout(() => box.setAttribute("stroke", "#4fd1c5"), STEP_MS * 0.7);
  }
  // dark-cockpit annunciation: dim at rest, the b-bit lights the live path
  function showActive(cyc, bit) {
    if (cyc < 2) setActive([]);
    else if (bit) setActive(["s_dbl", "s_red1", "s_add", "s_red2", "s_mux"]);
    else setActive(["s_dbl", "s_red1", "s_mux"]);
  }

  // ---- panel annunciator (state word + bounded sequence gauge) ----
  function setState(word, cls) { const e = $("state"); if (e) { e.textContent = word; e.className = "ind-state " + cls; } }
  function setProg(cyc) { const e = $("prog"); if (e) e.style.width = (Math.min(cyc, 33) / 33 * 100) + "%"; }
  function setRes(text, fault) { const e = $("res2"); if (e) { e.textContent = text; e.className = fault ? "ind-res fault" : "ind-res"; } }

  function u32(x) { return (x >>> 0); }
  function bigMulMod(a, b, m) { return Number((BigInt(u32(a)) * BigInt(u32(b))) % BigInt(u32(m))); }

  function readInputs() {
    const pa = u32(parseInt($("in_a").value || "0", 10));
    const pb = u32(parseInt($("in_b").value || "0", 10));
    let pm = u32(parseInt($("in_m").value || "0", 10));
    if (pm < 2) pm = 2;
    // mulmod's contract is a < m; reduce a so the demo always matches (a·b) mod m.
    return { a: pa % pm, b: pb, m: pm };
  }

  function stop() { if (timer) { clearInterval(timer); timer = null; } }

  function arm() {
    $("resv").textContent = "…";
    $("cyc").textContent = "00 / 33";
    setRes("…", false);
    setProg(0);
    setState("RUN", "run");
  }

  function finish(a, b, m, cycles) {
    const res = u32(sim.result());
    const exp = bigMulMod(a, b, m);
    const ok = res === exp;
    $("resv").textContent = String(res);
    setActive([]);
    setProg(cycles);
    setState(ok ? "DONE" : "FAULT", ok ? "done" : "fault");
    setRes(ok ? String(res) : "ERR", !ok);
    $("status").innerHTML = ok
      ? `VERIFIED · result matches (a·b) mod m · ${cycles} cycles`
      : `<span class="fault">FAULT · got ${res}, expected ${exp}</span>`;
    // constant-time evidence
    const log = $("ctlog");
    const chip = document.createElement("span");
    chip.className = "chip";
    chip.innerHTML = `${u32(a)}·${u32(b)} mod ${u32(m)} = ${res} · <b>${cycles} cyc</b>`;
    log.prepend(chip);
    while (log.children.length > 6) log.removeChild(log.lastChild);
    setRunning(false);
  }

  function run() {
    if (!sim) return;
    stop();
    const { a, b, m } = readInputs();
    inA = a; inB = b; inM = m;
    sim.reset(); sim.load(a, b, m);
    arm();
    setRunning(true);
    timer = setInterval(() => {
      const bit = sim.bbit();
      const done = sim.step();
      const cyc = sim.cycles();
      $("cyc").textContent = String(cyc).padStart(2, "0") + " / 33";
      $("accv").textContent = String(u32(sim.acc()));
      setProg(cyc);
      showActive(cyc, bit);
      pulseAcc();
      if (done) { stop(); finish(a, b, m, cyc); }
    }, STEP_MS);
  }

  function stepOne() {
    if (!sim) return;
    if (!timer && (sim.cycles() === 0 || sim.cycles() >= 33)) {
      const { a, b, m } = readInputs(); inA = a; inB = b; inM = m;
      sim.reset(); sim.load(a, b, m); arm(); setRunning(true, true);
    }
    const bit = sim.bbit();
    const done = sim.step();
    const cyc = sim.cycles();
    $("cyc").textContent = String(cyc).padStart(2, "0") + " / 33";
    $("accv").textContent = String(u32(sim.acc()));
    setProg(cyc);
    showActive(cyc, bit);
    pulseAcc();
    if (done) finish(inA, inB, inM, cyc);
  }

  function setRunning(on, keepEnable) {
    $("btn_run").disabled = on && !keepEnable;
    ["in_a", "in_b", "in_m"].forEach((id) => { if (!keepEnable) $(id).disabled = on; });
  }

  function boot(Module) {
    sim = {
      reset:  Module.cwrap("sim_reset", null, []),
      load:   Module.cwrap("sim_load", null, ["number", "number", "number"]),
      step:   Module.cwrap("sim_step", "number", []),
      result: Module.cwrap("sim_result", "number", []),
      cycles: Module.cwrap("sim_cycles", "number", []),
      acc:    Module.cwrap("sim_acc", "number", []),
      bbit:   Module.cwrap("sim_bbit", "number", []),
    };
    $("btn_run").addEventListener("click", run);
    $("btn_step").addEventListener("click", stepOne);
    ["in_a", "in_b", "in_m"].forEach((id) =>
      $(id).addEventListener("keydown", (e) => { if (e.key === "Enter") run(); }));
    $("status").innerHTML = 'ready · the real <span class="mono">mulmod.v</span> is loaded';
    setState("READY", "stby");
    run(); // show it working immediately
  }

  window.addEventListener("DOMContentLoaded", () => {
    if (typeof createMulmodSim !== "function") {
      setState("FAULT", "fault");
      $("status").innerHTML = '<span class="fault">WASM module failed to load</span>';
      return;
    }
    createMulmodSim().then(boot).catch((e) => {
      setState("FAULT", "fault");
      $("status").innerHTML = '<span class="fault">init error: ' + e + "</span>";
    });
  });

  // copy buttons (unused on the current page, kept for reuse)
  window.copyCode = function (id, btn) {
    const el = $(id); if (!el) return;
    navigator.clipboard.writeText(el.innerText).then(() => {
      const t = btn.textContent; btn.textContent = "copied ✓";
      setTimeout(() => (btn.textContent = t), 1200);
    });
  };
})();
