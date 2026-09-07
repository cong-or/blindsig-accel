# Blind Signature Accelerator — RISC-V Integration Prototype

[![Live demo](https://img.shields.io/badge/live%20demo-real%20RTL%20in%20your%20browser-06b6d4?logo=webassembly&logoColor=white)](https://cong-or.github.io/blindsig-accel/)
[![Formally verified](https://img.shields.io/badge/formally%20verified-SymbiYosys-22c55e)](blindsig-rtl#formal-verification)
[![ci](https://github.com/cong-or/blindsig-accel/actions/workflows/ci.yml/badge.svg)](https://github.com/cong-or/blindsig-accel/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-CERN--OHL--P%2C%20MIT%2FApache--2.0-blue)](#licensing)

An open-source hardware accelerator for a RISC-V SoC, with the firmware that drives it. It is the
integration proof-of-concept for a larger project: open hardware for blind signature operations
(blind RSA and blind Schnorr) on RISC-V soft cores and FPGA.

Live demo, running the real `mulmod.v` compiled to WebAssembly:
<https://cong-or.github.io/blindsig-accel/>. Project site: <https://blindsig-hardware.org>.

## Status

A feasibility prototype, not the finished accelerator. It proves the open toolchain and the
CPU–accelerator integration end to end, on a de-risked foundation. The arithmetic is real and
constant-time — no behavioural `*` or `%` in the datapath — on a single 32-bit word today.

Three parts are deliberate stand-ins for the funded design, each a swap within the proven structure:

- **Reducer** — conditional subtraction today; Montgomery reduction under the grant.
- **Host core** — PicoRV32 today; VexRiscv is the funded target, with the same MMIO interface.
- **Simulation and proof** — Icarus and SymbiYosys today; Verilator co-simulation is added under the grant.

The prototype completes none of the five funded milestones; it de-risks the methods behind them. Full
breakdown in [ROADMAP.md](ROADMAP.md).

## Quick start

Requires [Icarus Verilog](https://steveicarus.github.io/iverilog/). The SoC test also needs a
bare-metal RISC-V C toolchain (`riscv-none-elf-gcc`) on `PATH`.

```sh
cd blindsig-rtl && make        # simulate: unit test + accelerator
cd blindsig-rtl && make formal # prove:    k-induction + equivalence (SymbiYosys)
cd blindsig-soc && make        # full CPU -> accelerator integration test
./test.sh --ci                 # all of the above, with narration
```

## What's proven

The proofs are re-runnable objects, not claims:

- **Correct** — the result equals `(a·b) mod m`, by exhaustive bounded model checking against an
  independent reference.
- **In range** — the accumulator stays below `m` at every step, by unbounded k-induction at full
  32-bit width.
- **Constant-time** — every multiplication takes the same number of cycles regardless of the operands.

You have to trust only the open checker (Yosys and its SAT/SMT solver) and the Verilog — not the
author. Re-check it yourself: `cd blindsig-rtl && make formal`.

## Layout

| Directory | What it is | Reusable as |
|---|---|---|
| [`blindsig-rtl/`](blindsig-rtl/) | Constant-time modular multiplier and reducer, plus the accelerator peripheral | `mulmod` for any modular arithmetic (RSA, DH, ECC, ZK) |
| [`blindsig-soc/`](blindsig-soc/) | PicoRV32 SoC integrating CPU and accelerator, with C and Rust firmware | A reference for wiring an accelerator to a RISC-V core |
| [`blindsig-fw/`](blindsig-fw/) | Bare-metal Rust (`no_std`) MMIO driver | A firmware driver for constrained devices |

The accelerator is a five-register peripheral at `0x2000_0000` (CTRL, STATUS, OPERAND, RESULT,
MODULUS); the register map and driver sequence are documented in [`blindsig-rtl/`](blindsig-rtl/).

## Why it matters

Using a crypto accelerator today usually means trusting closed IP built by a closed toolchain. This
project is a reproducible pipeline instead: constant-time RTL, formally verified with an open prover,
cross-checked against a software reference, synthesised with a fully open flow, and re-verified in CI.
The security properties travel with the code as proofs anyone can re-run. Blind signatures are the
first primitive built this way; the same method generalises to elliptic-curve, hashing, and
post-quantum primitives.

## Licensing

- **Hardware** — Verilog RTL, under [CERN-OHL-P-2.0](blindsig-rtl/LICENSE).
- **Software** — the Rust driver, C firmware, and tooling, under [MIT](LICENSE-MIT) or
  [Apache-2.0](LICENSE-APACHE), at your option.

`blindsig-soc/rtl/picorv32.v` is the third-party [PicoRV32](https://github.com/YosysHQ/picorv32) core
by Claire Xenia Wolf, vendored unmodified under its original ISC license. All other work is original.
