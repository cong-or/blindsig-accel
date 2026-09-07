// app.js — drive the datapath SVG from the REAL mulmod RTL (Verilator → WASM).
// Nothing here reimplements the algorithm: we only step the compiled circuit's
// clock and read its registers.

(function () {
  "use strict";
  const $ = (id) => document.getElementById(id);
  const STEP_MS = 70;

  let sim = null;        // wrapped WASM entry points
  let timer = null;
  let inA = 0, inB = 0, inM = 7;

  const stages = ["s_dbl", "s_red1", "s_add", "s_red2", "s_mux"];

  function setActive(ids) {
    stages.forEach((s) => {
      const g = $(s); if (!g) return;
      const box = g.querySelector("rect");
      if (!box) return;
      if (ids.includes(s)) { box.setAttribute("stroke", "#ffce7a"); box.setAttribute("filter", "url(#glowA)"); }
      else { box.removeAttribute("filter"); box.setAttribute("stroke", s === "s_mux" ? "#c8912f" : "#31507d"); }
    });
  }
  function pulseAcc() {
    const g = $("s_acc"); if (!g) return;
    const box = g.querySelector("rect");
    box.setAttribute("stroke", "#7fe9e2");
    setTimeout(() => box.setAttribute("stroke", "#37d6cf"), STEP_MS * 0.7);
  }
  // Highlight the stages the circuit exercises this cycle, from the real b bit:
  // b-bit set => the add path (`+ a` / red2) is live; clear => just double-and-
  // reduce. cyc < 2 is the load cycle, before any compute has happened.
  function showActive(cyc, bit) {
    if (cyc < 2) setActive([]);
    else if (bit) setActive(["s_dbl", "s_red1", "s_add", "s_red2", "s_mux"]);
    else setActive(["s_dbl", "s_red1", "s_mux"]);
  }

  function u32(x) { return (x >>> 0); }
  function bigMulMod(a, b, m) { return Number((BigInt(u32(a)) * BigInt(u32(b))) % BigInt(u32(m))); }

  function readInputs() {
    const pa = u32(parseInt($("in_a").value || "0", 10));
    const pb = u32(parseInt($("in_b").value || "0", 10));
    let pm = u32(parseInt($("in_m").value || "0", 10));
    if (pm < 2) pm = 2;
    // mulmod's contract is a < m; reduce a so the demo always matches (a·b) mod m.
    return { a: pa % pm, b: pb, m: pm, rawa: pa };
  }

  function stop() { if (timer) { clearInterval(timer); timer = null; } }

  function finish(a, b, m, cycles) {
    const res = u32(sim.result());
    const exp = bigMulMod(a, b, m);
    $("resv").textContent = String(res);
    setActive([]);
    const ok = res === exp;
    $("status").innerHTML = ok
      ? `done · <b>result ${res}</b> = ${u32(a)}·${u32(b)} mod ${u32(m)} · <span class="mono">${cycles} cycles</span> · verified against (a·b) mod m ✓`
      : `<span style="color:#ff8f8f">mismatch: got ${res}, expected ${exp}</span>`;
    // constant-time evidence log
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
    $("resv").textContent = "…";
    setRunning(true);
    timer = setInterval(() => {
      const bit = sim.bbit();          // real b_reg MSB — the bit this step consumes
      const done = sim.step();
      const cyc = sim.cycles();
      $("cyc").textContent = String(cyc).padStart(2, "0") + " / 33";
      $("accv").textContent = String(u32(sim.acc()));
      showActive(cyc, bit);
      pulseAcc();
      if (done) { stop(); finish(a, b, m, cyc); }
    }, STEP_MS);
  }

  function stepOne() {
    if (!sim) return;
    if (!timer && (sim.cycles() === 0 || sim.cycles() >= 33)) {
      const { a, b, m } = readInputs(); inA = a; inB = b; inM = m;
      sim.reset(); sim.load(a, b, m); $("resv").textContent = "…"; setRunning(true, true);
    }
    const bit = sim.bbit();          // real b_reg MSB — the bit this step consumes
    const done = sim.step();
    const cyc = sim.cycles();
    $("cyc").textContent = String(cyc).padStart(2, "0") + " / 33";
    $("accv").textContent = String(u32(sim.acc()));
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
    $("status").innerHTML = 'ready · the real <span class="mono">mulmod.v</span> is loaded — press Run';
    run(); // show it working immediately
  }

  window.addEventListener("DOMContentLoaded", () => {
    if (typeof createMulmodSim !== "function") {
      $("status").innerHTML = '<span style="color:#ff8f8f">WASM module failed to load</span>';
      return;
    }
    createMulmodSim().then(boot).catch((e) => {
      $("status").innerHTML = '<span style="color:#ff8f8f">init error: ' + e + "</span>";
    });
  });

  // copy buttons
  window.copyCode = function (id, btn) {
    const el = $(id); if (!el) return;
    navigator.clipboard.writeText(el.innerText).then(() => {
      const t = btn.textContent; btn.textContent = "copied ✓";
      setTimeout(() => (btn.textContent = t), 1200);
    });
  };
})();
