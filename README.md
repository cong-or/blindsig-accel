# Blind Signature Accelerator — RISC-V Integration Prototype

[![Live demo](https://img.shields.io/badge/live%20demo-real%20RTL%20in%20your%20browser-06b6d4?logo=webassembly&logoColor=white)](https://cong-or.github.io/blindsig-accel/)
[![Formally verified](https://img.shields.io/badge/formally%20verified-SymbiYosys-22c55e)](blindsig-rtl#formal-verification)
[![ci](https://github.com/cong-or/blindsig-accel/actions/workflows/ci.yml/badge.svg)](https://github.com/cong-or/blindsig-accel/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-CERN--OHL--P%2C%20MIT%2FApache--2.0-blue)](#licensing)

An open-source hardware accelerator peripheral for a RISC-V SoC, together with the
firmware that drives it. This repository is the **integration proof-of-concept** for a
larger project: an open hardware accelerator for blind signature operations (blind RSA
and blind Schnorr) targeting RISC-V soft cores on FPGA.

**[▶ Try the live demo](https://cong-or.github.io/blindsig-accel/)** — the real `mulmod.v`,
compiled to WebAssembly, animating the datapath one cycle at a time in your browser.
Project site: <https://blindsig-hardware.org>

![Composable open hardware — your project contains the SoC, which contains the accelerator, which contains the reusable modular-multiplier core](doc/composability.png)

Each layer is independently reusable: the `mulmod` core drops into any modular-arithmetic
design, the accelerator into any RISC-V SoC, the SoC into your product.

## Status — read this first

This is a **feasibility prototype**, not the finished accelerator. Its job is to prove the
open toolchain and the CPU↔accelerator integration end-to-end, so the hard cryptographic
work is built on a de-risked foundation. The arithmetic is real and constant-time — there
is **no behavioural `*`/`%` anywhere in the datapath** — but it operates on a single 32-bit
word today, reducing by conditional subtraction. Exactly what's done versus what the grant
builds is in the [roadmap](#roadmap).

**Three things you see here are deliberate stand-ins for the funded design** — each a swap
*within* the proven structure, not a redesign:

- **Reducer:** conditional subtraction → **Montgomery reduction** (same constant-time, bit-serial structure)
- **Host core:** **PicoRV32** → **VexRiscv** (identical MMIO pattern — a bus-adapter change)
- **Sim / verify:** **Icarus** testbenches + SymbiYosys proofs → adds **Verilator** co-simulation against the `blind-rsa` reference

The register interface, the `mulmod`/`redmod` primitives, the formal harness, and the SoC
integration all carry over directly — the funded work builds on this foundation.

## Why this matters

Using a crypto accelerator today usually means trusting a vendor's closed IP, compiled by a
closed toolchain — you take the security on faith. The lasting output of this project is not
one accelerator but a **reproducible pipeline for trustworthy crypto hardware**:
constant-time-by-construction RTL, formally verified with an open prover, cross-checked
against a software reference, synthesised end-to-end with a fully open flow, and re-verified
in CI — so the security properties travel with the code as machine-checked proofs anyone can
re-run. Blind signatures are the first primitive built this way; the same pipeline
generalises to the modular-arithmetic, elliptic-curve, and post-quantum primitives the
ecosystem needs next. And because the whole path from source to bitstream is open and
reproducible, the components are auditable — the openness that enables the verification is
also the supply-chain-integrity story, with no proprietary black box between design and gate.

And as generation — of code, of RTL, even of proofs — automates, the scarce part is the *claim* a
human can still read and re-check: a machine can search for a proof, but only a person can be
accountable for what it proves. (What's proven here, and how to re-check it, is spelled out below.)

## Roadmap

The funded work is organised as five milestones (from the grant proposal). The prototype in
this repository is a **feasibility spike**: it de-risks the *methods* behind several of them,
but completes **none** — here is exactly where each stands.

| Milestone | Deliverable | Status in this repo |
|---|---|---|
| **M1** | Montgomery modular multiplier + property verification | 🟡 **Partial** — a constant-time modular multiplier exists and is formally verified, but it reduces by **conditional subtraction**; Montgomery reduction is not yet built |
| **M2** | Modular-exponentiation pipeline + blind RSA | 🔴 **Not started** — the accelerator does a single `operand²` squaring, not the square-and-multiply pipeline, and no blind-RSA operation exists yet |
| **M3** | Blind Schnorr + SymbiYosys formal verification | 🟡 **Partial** — the formal method is proven out (k-induction + BMC) at 32-bit / reduced width; **blind Schnorr is not built** |
| **M4** | VexRiscv MMIO integration + Rust firmware + co-sim | 🟡 **Partial** — integrated end-to-end on **PicoRV32** with C and Rust firmware; the **VexRiscv** port and **Verilator** co-simulation are not done |
| **M5** | ECP5 synthesis + docs + reproducible build | 🔴 **Not started** — simulation only; the design has **never been synthesised to FPGA fabric** (no timing, no fit) |

In short: what runs today is a formally-verified, constant-time modular *squaring* on a 32-bit
word, integrated into a RISC-V SoC in simulation. The blind-signature operations themselves —
the point of the project — are still ahead.

**Beyond the grant — where the pipeline goes:**

- **Side-channel hardening.** Timing leakage is designed out today; the next stage adds power/EM
  leakage assessment (TVLA) and formal masking verification as an extra verification pass.
  Physical power analysis needs lab measurement, so it sits just outside this simulation-focused
  grant — it is the natural follow-on.
- **Supply-chain integrity.** A fully reproducible *source → RTL → bitstream* build, so a component
  can be rebuilt and audited rather than trusted — provenance by reproducibility, not by an
  attestation you cannot check.
- **A catalogue for builders.** The same pipeline applied to more primitives — modular arithmetic,
  elliptic-curve, hashing, post-quantum — each permissively licensed and shipped *with its proofs*,
  so a builder can pull a verified component off the shelf and re-check its guarantees in CI.
  Making secure open-hardware building blocks this accessible is the point.

## Layout

The three components are independently useful and each has its own README:

| Directory | What | Reusable as |
|---|---|---|
| [`blindsig-rtl/`](blindsig-rtl/) | Constant-time modular multiplier + reducer + the accelerator peripheral, with testbenches | `mulmod` is reusable for any modular arithmetic (RSA/DH/ECC/ZK) |
| [`blindsig-soc/`](blindsig-soc/) | PicoRV32 SoC integrating CPU + accelerator, with C and Rust firmware | An integration reference for wiring an accelerator to a RISC-V core |
| [`blindsig-fw/`](blindsig-fw/) | Bare-metal Rust (`no_std`) MMIO driver | A firmware driver library for constrained devices |

```
blindsig-rtl  ──(accelerator RTL)──┐
                                    ├─►  blindsig-soc  (PicoRV32 + accel + firmware)
blindsig-fw   ──(driver API)────────┘     proves the full stack in simulation
   register map & sequence mirrored in the SoC's C firmware
```

## Register interface

Base address `0x2000_0000`:

| Offset | Register | Notes |
|---|---|---|
| `0x00` | CTRL    | bit0 START, bit1 RESET, bit2 LOAD_OP, bit3 LOAD_MOD |
| `0x04` | STATUS  | bit0 BUSY, bit1 DONE, bit2 ERROR |
| `0x08` | OPERAND | operand input |
| `0x0C` | RESULT  | result output |
| `0x10` | MODULUS | modulus input |

Sequence: `reset → load_mod → load_op → start → wait(DONE) → read`.

## Building and testing

Requires [Icarus Verilog](https://steveicarus.github.io/iverilog/) (`iverilog`/`vvp`).
The SoC firmware additionally needs a bare-metal RISC-V C toolchain
(`riscv-none-elf-gcc`, e.g. the [xPack](https://xpack.github.io/) build) on `PATH`.

```sh
# Accelerator RTL testbench (no C toolchain needed)
cd blindsig-rtl && make          # → "ALL TESTS PASSED" (4/4)

# Full SoC integration test (needs riscv-none-elf-gcc)
cd blindsig-soc && make          # → "PASS: Integration test succeeded"

# Everything, with narration
./test.sh --ci
```

## What's guaranteed — and how you check it

You don't have to take any of this on trust — the proofs are re-runnable objects, not claims. Here is
exactly what is proven, what you must trust, and how to confirm it yourself.

**The claims, in plain terms:**

1. **Correct** — the result equals `(a·b) mod m`, proven exhaustively by BMC at a reduced width
   against an independent reference.
2. **Reduced throughout** — the accumulator stays `< m` at every step (the modular-arithmetic
   invariant), proven unbounded by k-induction at the full 32-bit width.
3. **Constant-time** — every multiplication takes the same fixed cycle count regardless of the
   operands, asserted by the testbench across the range `0` to `(m-1)²`.

**What you actually have to trust:** not the author, and not any tool that helped write the RTL — only
the open checker itself (Yosys and its SAT/SMT solver) and the Verilog semantics. If you trust the
checker, you can ignore everything else and still know the claims hold.

**How to re-check:** `cd blindsig-rtl && make formal` re-runs the k-induction and BMC proofs from a
clean clone with open tools; `make` re-runs the constant-latency simulation. Nothing here depends on
who — or what — wrote the code.

## Licensing

- **Hardware** (Verilog RTL in `blindsig-rtl/` and the accelerator/bus RTL in
  `blindsig-soc/`): [CERN-OHL-P-2.0](blindsig-rtl/LICENSE) (permissive open hardware).
- **Software** (Rust driver, C firmware, tooling): dual-licensed
  [MIT](LICENSE-MIT) OR [Apache-2.0](LICENSE-APACHE), at your option.

`blindsig-soc/rtl/picorv32.v` is the third-party [PicoRV32](https://github.com/YosysHQ/picorv32)
core by Claire Xenia Wolf, vendored unmodified under its original ISC license (see the file
header). All other RTL, firmware, and tooling is original work.
