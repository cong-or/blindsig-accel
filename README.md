# Blind Signature Accelerator — RISC-V Integration Prototype

[![Live demo](https://img.shields.io/badge/live%20demo-real%20mulmod.v%20in%20your%20browser-06b6d4?logo=webassembly&logoColor=white)](https://cong-or.github.io/blindsig-accel/)
[![Multiplier formally verified](https://img.shields.io/badge/multiplier%3A%20formally%20verified-SymbiYosys-22c55e)](blindsig-rtl#formal-verification)
[![ci](https://github.com/cong-or/blindsig-accel/actions/workflows/ci.yml/badge.svg)](https://github.com/cong-or/blindsig-accel/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-CERN--OHL--P%2C%20MIT%2FApache--2.0-blue)](#licensing)

An open, formally-verified, constant-time modular multiplier for RISC-V — `mulmod.v` — wired into an
accelerator peripheral, a PicoRV32 SoC, and a bare-metal driver, with a live in-browser simulation of
the real RTL. It is the integration proof-of-concept for a larger project: open hardware for blind
signature operations (blind RSA and blind Schnorr) on RISC-V soft cores and FPGA.

> **This is an early feasibility prototype — not the finished accelerator.** It proves the open
> toolchain and the CPU–accelerator integration with a formally-verified, constant-time core, but the
> blind-signature operations themselves are **not built yet**. It completes **none** of the five funded
> milestones; the bulk of the work is what the grant funds. See the [roadmap](ROADMAP.md).

Live demo, running the real `mulmod.v` compiled to WebAssembly:
<https://cong-or.github.io/blindsig-accel/>. Project site: <https://blindsig-hardware.org>.

## Status

What runs today proves the open toolchain and the CPU–accelerator integration end to end; the
cryptographic work itself is still ahead. The arithmetic is real, constant-time, and single-word
(32-bit) today — no behavioural `*` or `%` in the datapath. The `mulmod` core is the general
`(a·b) mod m` primitive; the packaged accelerator currently wires it to a single modular squaring
(`operand²`) — the inner step of the exponentiation pipeline the grant funds.

Three parts are deliberate stand-ins for the funded design, each a swap within the proven structure:

- **Reducer** — conditional subtraction today; Montgomery reduction under the grant.
- **Host core** — PicoRV32 today; VexRiscv is the funded target, with the same MMIO interface.
- **Simulation and proof** — Icarus and SymbiYosys today; Verilator co-simulation is added under the grant.

The prototype completes none of the five funded milestones; it de-risks the methods behind them. Full
breakdown in [ROADMAP.md](ROADMAP.md).

## Quick start

Requires [Icarus Verilog](https://steveicarus.github.io/iverilog/). Re-running the proofs (`make formal`)
additionally needs [SymbiYosys](https://github.com/YosysHQ/sby) with Yosys and a SAT/SMT solver; the SoC
integration test needs a bare-metal RISC-V C toolchain (`riscv-none-elf-gcc`) on `PATH`.

```sh
git clone https://github.com/cong-or/blindsig-accel && cd blindsig-accel
make -C blindsig-rtl           # simulate: unit test + accelerator
make -C blindsig-rtl formal    # prove:    k-induction + equivalence (SymbiYosys)
make -C blindsig-soc           # full CPU -> accelerator integration test
./test.sh --ci                 # all of the above, with narration
```

## What's proven

The proofs are re-runnable objects, not claims:

- **Correct** — the result equals `(a·b) mod m`, by exhaustive bounded model checking against an
  independent reference.
- **In range** — the accumulator stays below `m` at every step, by unbounded k-induction at full
  32-bit width.
- **Constant-time** — every multiplication takes the same number of cycles regardless of the operands, so the datapath has no timing side channel by construction. This is asserted directly by the testbench (`tb/tb_mulmod.v`), which measures the cycle count for varied operands — from small values up to `(m-1)²` — and checks it is identical in every case.

You have to trust only the open checker (Yosys and its SAT/SMT solver) and the design source under
proof — not the author. Re-run the correctness and range proofs with `cd blindsig-rtl && make formal`;
re-run the constant-time assertion with `cd blindsig-rtl && make`.

## Layout

| Directory | What it is | Reusable as |
|---|---|---|
| [`blindsig-rtl/`](blindsig-rtl/) | Constant-time modular multiplier and reducer, plus the accelerator peripheral | `mulmod` — the arithmetic primitive under RSA, DH, ECC and ZK, at 32-bit width today |
| [`blindsig-soc/`](blindsig-soc/) | PicoRV32 SoC integrating CPU and accelerator, with C and Rust firmware | A reference for wiring an accelerator to a RISC-V core |
| [`blindsig-fw/`](blindsig-fw/) | Bare-metal Rust (`no_std`) MMIO driver | A firmware driver for constrained devices |

The accelerator is a five-register peripheral at `0x2000_0000` (CTRL, STATUS, OPERAND, RESULT,
MODULUS); the register map and driver sequence are documented in [`blindsig-rtl/`](blindsig-rtl/).
Each sub-directory has its own README with standalone build instructions — `make` in `blindsig-rtl/`
and `blindsig-soc/`, `cargo build` in `blindsig-fw/`.

## Why it matters

**Side channels are the real threat — and they are designed out here.** On a general-purpose CPU,
blind-signature crypto leaks secrets through *timing*: the compiler and microarchitecture reintroduce
data-dependent timing no matter how careful the software is. A fixed-function, constant-time datapath
removes that whole class of attack by construction, and the funded work extends the same discipline to
power and EM side channels (leakage assessment and formal masking).

**A catalogue of trustworthy building blocks — the method is the deliverable.** The lasting output of
this work is not one accelerator; it is a repeatable pipeline for shipping hardware whose correctness you
don't have to take on trust: constant-time-by-construction RTL, formally verified with an open prover,
cross-checked against a software reference, synthesised with a fully open flow, and re-verified in CI —
so each block's security properties travel with it as proofs anyone can re-run. Blind signatures are
simply the first primitive built this way; the same pipeline produces the modular-arithmetic,
elliptic-curve, hashing, and post-quantum cores the ecosystem needs, each permissively licensed and
ready to drop into someone else's chip.

The reason this matters is a shift in where the hard part lives. Producing a design is becoming cheap;
the difficulty is trusting one you didn't write — and, increasingly, one no human wrote at all. A block
that arrives with machine-checkable proofs of what it computes and what it doesn't leak can be composed
without re-auditing it by hand; one that arrives as "trust me" cannot. As more RTL is generated by tools
and agents, that gap only widens — so "the proof travels with the part" becomes the practical
basis for trust at scale. This project is a concrete, end-to-end instance of that model for open
cryptographic hardware.

## Licensing

- **Hardware** — Verilog RTL, under [CERN-OHL-P-2.0](blindsig-rtl/LICENSE).
- **Software** — the Rust driver, C firmware, and tooling, under [MIT](LICENSE-MIT) or
  [Apache-2.0](LICENSE-APACHE), at your option.

`blindsig-soc/rtl/picorv32.v` is the third-party [PicoRV32](https://github.com/YosysHQ/picorv32) core
by Claire Xenia Wolf, vendored unmodified under its original ISC license. All other work is original.
