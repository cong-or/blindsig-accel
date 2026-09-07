# Blind Signature Accelerator — RISC-V Integration Prototype

[![Live demo](https://img.shields.io/badge/live%20demo-real%20RTL%20in%20your%20browser-06b6d4?logo=webassembly&logoColor=white)](https://cong-or.github.io/blindsig-accel/)
[![Formally verified](https://img.shields.io/badge/formally%20verified-SymbiYosys-22c55e)](blindsig-rtl#formal-verification)
[![ci](https://github.com/cong-or/blindsig-accel/actions/workflows/ci.yml/badge.svg)](https://github.com/cong-or/blindsig-accel/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-CERN--OHL--P%2C%20MIT%2FApache--2.0-blue)](#licensing)

An open-source hardware accelerator for a RISC-V SoC, with the firmware that drives it. It is the
integration proof-of-concept for a larger project: open hardware for blind signature operations
(blind RSA and blind Schnorr) on RISC-V soft cores and FPGA.

Live demo: the real `mulmod.v`, compiled to WebAssembly, animating the datapath one clock at a time —
<https://cong-or.github.io/blindsig-accel/>. Project site: <https://blindsig-hardware.org>.

![Composable open hardware — your project contains the SoC, which contains the accelerator, which contains the reusable modular-multiplier core](doc/composability.png)

Each layer is independently reusable: the `mulmod` core drops into any modular-arithmetic design, the
accelerator into any RISC-V SoC, the SoC into your product.

## Status

This is a feasibility prototype, not the finished accelerator. Its job is to prove the open toolchain
and the CPU–accelerator integration end to end, so the hard cryptographic work starts from a de-risked
foundation. The arithmetic is real and constant-time — no behavioural `*` or `%` anywhere in the
datapath — but it operates on a single 32-bit word today, reducing by conditional subtraction. What is
done, and what the grant builds, is in the [roadmap](#roadmap).

Three parts of what you see are deliberate stand-ins for the funded design, each a swap within the
proven structure rather than a redesign:

- **Reducer** — conditional subtraction today; Montgomery reduction under the grant, keeping the same
  constant-time, bit-serial structure.
- **Host core** — PicoRV32 today; VexRiscv is the funded target. The MMIO pattern is identical, so the
  port is a bus-adapter change.
- **Simulation and proof** — Icarus testbenches and SymbiYosys today; Verilator co-simulation against
  the `blind-rsa` reference is added under the grant.

The register interface, the `mulmod` and `redmod` primitives, the formal harness, and the SoC
integration all carry over directly.

## Roadmap

The funded work is five milestones, from the grant proposal. The prototype here is a feasibility
spike: it de-risks the methods behind several of them but completes none. Where each stands today:

| Milestone | Deliverable | Status |
|---|---|---|
| M1 | Montgomery modular multiplier and property verification | Partial. A constant-time multiplier exists and is formally verified, but reduces by conditional subtraction; Montgomery is not yet built. |
| M2 | Modular-exponentiation pipeline and blind RSA | Not started. The core computes a single `operand²` squaring, not the square-and-multiply pipeline. |
| M3 | Blind Schnorr and SymbiYosys formal verification | Partial. The formal method is proven out at 32-bit width; blind Schnorr is not built. |
| M4 | VexRiscv integration, Rust firmware, co-simulation | Partial. Integrated on PicoRV32 with C and Rust firmware; the VexRiscv port and Verilator co-simulation are not done. |
| M5 | ECP5 synthesis, docs, reproducible build | Not started. Simulation only; not yet synthesised to FPGA fabric. |

In short: what runs today is a formally-verified, constant-time modular squaring on a 32-bit word,
integrated into a RISC-V SoC in simulation. The blind-signature operations themselves are still ahead.

Beyond the grant, the same pipeline extends to:

- **Side-channel hardening** — timing leakage is designed out today; the next stage adds power and EM
  leakage assessment (TVLA) and formal masking verification. Physical power analysis needs lab
  measurement, so it sits just outside this simulation-focused grant.
- **Supply-chain integrity** — a fully reproducible source-to-bitstream build, so a component can be
  rebuilt and audited rather than trusted.
- **A catalogue for builders** — the same method applied to more primitives (modular arithmetic,
  elliptic-curve, hashing, post-quantum), each permissively licensed and shipped with its proofs.

## Layout

Three components, each independently useful, each with its own README:

| Directory | What it is | Reusable as |
|---|---|---|
| [`blindsig-rtl/`](blindsig-rtl/) | Constant-time modular multiplier and reducer, plus the accelerator peripheral, with testbenches | `mulmod` for any modular arithmetic (RSA, DH, ECC, ZK) |
| [`blindsig-soc/`](blindsig-soc/) | PicoRV32 SoC integrating CPU and accelerator, with C and Rust firmware | A reference for wiring an accelerator to a RISC-V core |
| [`blindsig-fw/`](blindsig-fw/) | Bare-metal Rust (`no_std`) MMIO driver | A firmware driver library for constrained devices |

```
blindsig-rtl  ──(accelerator RTL)──┐
                                    ├─►  blindsig-soc  (PicoRV32 + accel + firmware)
blindsig-fw   ──(driver API)────────┘     proves the full stack in simulation
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

Sequence: reset, load modulus, load operand, start, wait for DONE, read.

## Building and testing

Requires [Icarus Verilog](https://steveicarus.github.io/iverilog/). The SoC firmware also needs a
bare-metal RISC-V C toolchain (`riscv-none-elf-gcc`, e.g. the [xPack](https://xpack.github.io/) build)
on `PATH`.

```sh
cd blindsig-rtl && make     # accelerator RTL testbench (no C toolchain needed)
cd blindsig-soc && make     # full SoC integration test (needs riscv-none-elf-gcc)
./test.sh --ci              # everything, with narration
```

## What's guaranteed — and how you check it

The proofs are re-runnable objects, not claims. What is proven, what you have to trust, and how to
confirm it:

1. **Correct** — the result equals `(a·b) mod m`, proven exhaustively by bounded model checking at a
   reduced width against an independent reference.
2. **Reduced throughout** — the accumulator stays below `m` at every step, proven unbounded by
   k-induction at the full 32-bit width.
3. **Constant-time** — every multiplication takes the same number of cycles regardless of the
   operands, asserted by the testbench across the full input range.

What you have to trust: only the open checker (Yosys and its SAT/SMT solver) and the Verilog
semantics — not the author, and not any tool that helped write the RTL.

How to re-check: `cd blindsig-rtl && make formal` re-runs the k-induction and equivalence proofs from
a clean clone; `make` re-runs the constant-latency simulation.

## Why this matters

Using a crypto accelerator today usually means trusting a vendor's closed IP, compiled by a closed
toolchain. The lasting output of this project is not one accelerator but a reproducible pipeline for
trustworthy crypto hardware: constant-time-by-construction RTL, formally verified with an open prover,
cross-checked against a software reference, synthesised with a fully open flow, and re-verified in CI.
The security properties travel with the code as machine-checked proofs anyone can re-run. Blind
signatures are the first primitive built this way; the same pipeline generalises to the
modular-arithmetic, elliptic-curve, and post-quantum primitives the ecosystem needs next.

As generation — of code, of RTL, even of proofs — automates, the scarce part is the claim a human can
still read and re-check: a machine can search for a proof, but only a person can be accountable for
what it proves. The properties above are stated plainly for exactly that reason.

## Licensing

- **Hardware** — Verilog RTL in `blindsig-rtl/` and the accelerator and bus RTL in `blindsig-soc/`,
  under [CERN-OHL-P-2.0](blindsig-rtl/LICENSE).
- **Software** — the Rust driver, C firmware, and tooling, under [MIT](LICENSE-MIT) or
  [Apache-2.0](LICENSE-APACHE), at your option.

`blindsig-soc/rtl/picorv32.v` is the third-party [PicoRV32](https://github.com/YosysHQ/picorv32) core
by Claire Xenia Wolf, vendored unmodified under its original ISC license. All other RTL, firmware, and
tooling is original work.
