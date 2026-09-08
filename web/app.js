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
  let hasBreg = false;
  let bitCells = [];

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
  function popcount(x) { x >>>= 0; let c = 0; while (x) { c += x & 1; x >>>= 1; } return c; }
  function hex32(x) { return "0x" + u32(x).toString(16).padStart(8, "0").toUpperCase(); }

  // --- b shift register, drawn live from the circuit (not re-derived in JS) ---
  function buildBits() {
    const box = $("breg"); if (!box) return;
    box.innerHTML = ""; bitCells = [];
    for (let i = 0; i < 32; i++) {
      const s = document.createElement("span");
      s.className = "bit"; s.textContent = "0";
      box.appendChild(s); bitCells.push(s);
    }
  }
  function renderBits(v) {
    if (!bitCells.length) return;
    v >>>= 0;
    for (let i = 0; i < 32; i++) {
      const bit = (v >>> (31 - i)) & 1;   // i = 0 is the MSB — the active bit
      const c = bitCells[i];
      c.textContent = String(bit);
      c.className = "bit" + (bit ? " one" : "") + (i === 0 ? " act" : "");
    }
  }
  function updateAcc() {
    const e = $("acchex"); if (e && sim) e.textContent = hex32(sim.acc());
  }

  // --- schematic timing contrast (NOT a benchmark): a branch-per-bit software
  //     mod-mul does an add only on set bits, so its work tracks popcount(b);
  //     this fixed circuit does not. Illustrates the leak the datapath removes. ---
  function updateContrast(b) {
    const pc = popcount(b);
    const cpu = $("bar_cpu"), steps = $("cpu_steps"), hw = $("bar_hw");
    if (cpu) cpu.style.width = (pc / 32 * 100) + "%";
    if (steps) steps.textContent = pc + (pc === 1 ? " add" : " adds");
    if (hw) hw.style.width = "100%";
  }

  // --- constant-time proof: run four very different inputs to completion and
  //     show they all land on the same cycle. The real circuit runs each one. ---
  function prove() {
    if (!sim) return;
    stop();
    const m = readInputs().m;
    const a = u32(m - 1);                 // a < m — the multiplier's precondition
    const cases = [
      { lab: "b = 0 · no bits set",           b: 0 },
      { lab: "b = 0xFFFFFFFF · all bits set", b: 0xFFFFFFFF },
      { lab: "b = 0xDEADBEEF",                b: 0xDEADBEEF },
      { lab: "b = m − 1",                     b: u32(m - 1) },
    ];
    const box = $("prove"); if (!box) return;
    box.innerHTML = "";
    let refCyc = null, allSame = true, allOk = true;
    cases.forEach((c) => {
      sim.reset(); sim.load(a, c.b, m);
      let guard = 0; while (!sim.step() && guard++ < 100) {}
      const cyc = sim.cycles(), res = u32(sim.result());
      const ok = res === bigMulMod(a, c.b, m);
      if (refCyc === null) refCyc = cyc; else if (cyc !== refCyc) allSame = false;
      if (!ok) allOk = false;
      const row = document.createElement("div");
      row.className = "prow";
      row.innerHTML =
        '<span class="plab">' + c.lab + "</span>" +
        '<span class="pres">&rarr; ' + res + (ok ? "" : " ✗") + "</span>" +
        '<span class="pbar"><i style="width:' + (Math.min(cyc, 33) / 33 * 100) + '%"></i></span>' +
        '<span class="pcyc">' + cyc + " cyc</span>";
      box.appendChild(row);
    });
    const v = document.createElement("div");
    v.className = "prove-verdict" + (allOk && allSame ? "" : " bad");
    v.textContent = allOk
      ? (allSame
          ? "✓ all four finish on cycle " + refCyc + " — the timing is independent of the operands"
          : "⚠ timing differed across inputs — see cycle counts above")
      : "✗ a result disagreed with the reference";
    box.appendChild(v);
    // leave the live panel primed for a fresh Run
    const { a: la, b: lb, m: lm } = readInputs();
    inA = la; inB = lb; inM = lm;
    sim.reset(); sim.load(la, lb, lm);
    if (hasBreg) renderBits(lb);
    updateAcc(); updateContrast(lb);
    setState("READY", "stby");
  }

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
    updateContrast(b);
    if (hasBreg) renderBits(b);
    arm();
    setRunning(true);
    timer = setInterval(() => {
      const bit = sim.bbit();
      const done = sim.step();
      const cyc = sim.cycles();
      $("cyc").textContent = String(cyc).padStart(2, "0") + " / 33";
      $("accv").textContent = String(u32(sim.acc()));
      if (hasBreg) renderBits(sim.breg());
      updateAcc();
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
      sim.reset(); sim.load(a, b, m); updateContrast(b); if (hasBreg) renderBits(b); arm(); setRunning(true, true);
    }
    const bit = sim.bbit();
    const done = sim.step();
    const cyc = sim.cycles();
    $("cyc").textContent = String(cyc).padStart(2, "0") + " / 33";
    $("accv").textContent = String(u32(sim.acc()));
    if (hasBreg) renderBits(sim.breg());
    updateAcc();
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
    hasBreg = (typeof Module._sim_breg === "function");
    sim = {
      reset:  Module.cwrap("sim_reset", null, []),
      load:   Module.cwrap("sim_load", null, ["number", "number", "number"]),
      step:   Module.cwrap("sim_step", "number", []),
      result: Module.cwrap("sim_result", "number", []),
      cycles: Module.cwrap("sim_cycles", "number", []),
      acc:    Module.cwrap("sim_acc", "number", []),
      bbit:   Module.cwrap("sim_bbit", "number", []),
      breg:   hasBreg ? Module.cwrap("sim_breg", "number", []) : null,
    };
    if (hasBreg) buildBits();
    else { const el = document.querySelector(".internals"); if (el) el.style.display = "none"; }
    $("btn_run").addEventListener("click", run);
    $("btn_step").addEventListener("click", stepOne);
    const bp = $("btn_prove"); if (bp) bp.addEventListener("click", prove);
    ["in_a", "in_b", "in_m"].forEach((id) =>
      $(id).addEventListener("keydown", (e) => { if (e.key === "Enter") run(); }));
    updateContrast(u32(parseInt($("in_b").value || "0", 10)));
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
