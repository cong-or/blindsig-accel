# Blind Signature Accelerator for RISC-V

[![Live demo](https://img.shields.io/badge/live%20demo-real%20mulmod.v%20in%20your%20browser-06b6d4?logo=webassembly&logoColor=white)](https://cong-or.github.io/blindsig-accel/)
[![Multiplier formally verified](https://img.shields.io/badge/multiplier%3A%20formally%20verified-SymbiYosys-22c55e)](blindsig-rtl#formal-verification)
[![ci](https://github.com/cong-or/blindsig-accel/actions/workflows/ci.yml/badge.svg)](https://github.com/cong-or/blindsig-accel/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-CERN--OHL--P%2C%20MIT%2FApache--2.0-blue)](#licensing)

**Open hardware for blind-signature operations — blind RSA and blind Schnorr — on RISC-V soft cores and
FPGA.** These operations rest on modular exponentiation over large integers; doing that arithmetic in a
dedicated, constant-time circuit closes the timing side channels a general-purpose CPU reintroduces no
matter how careful the software is.

The first building block is real and runnable today: **`mulmod.v`**, a constant-time modular multiplier,
formally verified with SymbiYosys, wired into an accelerator peripheral, a PicoRV32 SoC and a bare-metal
driver — with a live in-browser simulation of the actual Verilog. I hand-wrote the datapath RTL, the
SymbiYosys formal harness and the RISC-V SoC integration here; it is concrete evidence that the gateware
this proposal describes is within reach.

> **This is an early feasibility prototype, not the finished accelerator — and that is the point.** It
> de-risks the hardest questions before the grant begins: that the open simulate-prove-integrate flow
> runs end to end, that a RISC-V core and the accelerator integrate cleanly over MMIO, and that the
> arithmetic core is constant-time and formally verified. It completes **none** of the five funded
> milestones — Montgomery reduction, the blind-signature operations themselves, FPGA synthesis and
> RSA-scale widths are the funded build-out on these de-risked methods. See the [roadmap](ROADMAP.md).

Live demo, running the real `mulmod.v` compiled to WebAssembly: <https://cong-or.github.io/blindsig-accel/>.
Project site: <https://blindsig-hardware.org>.

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

Full milestone-by-milestone breakdown in [ROADMAP.md](ROADMAP.md).

## Reusable modules

This is not one monolith — it is independently reusable blocks, each buildable on its own:

- **`mulmod`** — the constant-time `(a·b) mod m` primitive under RSA, DH, ECC and ZK. It is the one block
  that ships with machine-checkable proofs: `make formal` re-runs the correctness and range proofs
  against an open prover on your machine.
- **`redmod`** — constant-time modular reduction (`x mod m`); verified today by simulation, not yet by
  formal proof.
- **the accelerator peripheral** — a five-register MMIO block (`operand² mod modulus`) any RISC-V SoC can
  memory-map; checked by the integration testbench.
- **the SoC reference and the `no_std` Rust/C driver** — a worked example of wiring an accelerator to a
  soft core and driving it from bare metal.

**Who reuses them.** Any RISC-V SoC needing asymmetric-crypto acceleration — the ratified RISC-V crypto
extensions cover AES/SHA but deliberately leave public-key operations to a coprocessor — and any design
that needs a verified constant-time modular multiplier (RSA, DH, ECC, ZK).

**How a consumer adopts one.** Clone the block, read its spec and register map, instantiate the RTL (or
drive the MMIO peripheral from the Rust/C driver), and — for `mulmod` today — re-run `make formal` to
re-establish its properties yourself, so it is reused without a hand audit. Extending that re-runnable
proof footing to the other blocks is the "verified-component catalogue" this project is a first instance
of (see [ROADMAP](ROADMAP.md#beyond-the-grant)).

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

Not just tested on a few inputs — key properties are *mathematically proven* by an automated prover, and
you can re-run the proofs yourself:

- **Correct** — the result equals `(a·b) mod m`, verified exhaustively by bounded model checking over the
  *entire* input space against an independent reference. Exhaustive search is only tractable at a reduced
  word width, so this proof runs there; the range invariant below is what holds at full 32-bit width.
- **In range** — the accumulator stays below `m` at every step, proven at full 32-bit width by
  k-induction — an *unbounded* technique that covers a computation of any length at once.
- **Constant-time** — every multiplication takes the same number of cycles regardless of the operands, so
  the datapath has no timing side channel by construction. This is asserted directly by the testbench
  (`tb/tb_mulmod.v`), which measures the cycle count for varied operands — from small values up to
  `(m-1)²` — and checks it is identical in every case.
- **Re-proved in CI** — every push and pull request re-runs the whole matrix in GitHub Actions: the
  constant-time unit test, the accelerator testbench, the SymbiYosys formal proofs, the full
  CPU→bus→accelerator SoC integration with *both* C and Rust firmware on a real RISC-V toolchain (xPack
  `riscv-none-elf-gcc`), and a rebuild of the in-browser demo from `mulmod.v` to WebAssembly.

You have to trust only the open checker (Yosys and its SAT/SMT solver) and the design source under
proof — not the author. Re-run the correctness and range proofs with `cd blindsig-rtl && make formal`;
re-run the constant-time assertion with `cd blindsig-rtl && make`.

## Layout

| Directory | What it is |
|---|---|
| [`blindsig-rtl/`](blindsig-rtl/) | Constant-time modular multiplier and reducer, plus the accelerator peripheral |
| [`blindsig-soc/`](blindsig-soc/) | PicoRV32 SoC integrating CPU and accelerator, with C and Rust firmware |
| [`blindsig-fw/`](blindsig-fw/) | Bare-metal Rust (`no_std`) MMIO driver |

The accelerator is a five-register peripheral at `0x2000_0000` (CTRL, STATUS, OPERAND, RESULT,
MODULUS); the register map and driver sequence are documented in [`blindsig-rtl/`](blindsig-rtl/).
Each sub-directory has its own README with standalone build instructions — `make` in `blindsig-rtl/`
and `blindsig-soc/`, `cargo build` in `blindsig-fw/`.

## Why it matters

**Verification is the scarce part.** AI makes writing RTL cheap; it does not make *trusting* RTL cheap.
As more RTL is produced by tools, the bottleneck shifts from writing a design to trusting one you did not
write. Every block here ships with re-runnable, machine-checked evidence — SymbiYosys proofs of what it
computes and that its accumulator stays in range (`make formal`), plus a cycle-count constant-time check
in simulation (`make`) — so it can be reused without a hand audit, regardless of who or what wrote a
line. Without that evidence, reuse means taking the design on trust.

**Timing side channels are the target.** On a general-purpose CPU, blind-signature crypto can leak
secrets through execution time: the compiler and microarchitecture reintroduce data-dependent timing no
matter how careful the software is. A fixed-function, constant-time datapath removes the timing channel by
construction. Power and electromagnetic side channels are the next frontier: leakage assessment (TVLA)
and formal masking verification build directly on this constant-time foundation, and because they need
lab power measurement they extend just beyond this simulation-focused grant — the trajectory is in the
[roadmap](ROADMAP.md#beyond-the-grant).

**A repeatable pipeline, reusable across primitives.** The lasting output is not one accelerator but the
pipeline that produced it: constant-time RTL, formal proofs with an open prover, a cross-check against a
software reference, and CI that re-runs both. Blind signatures are the first primitive built this way; the
same pipeline is intended to apply to other modular-arithmetic, elliptic-curve, hashing, and post-quantum
cores — those are future work, not yet built.

## Licensing

- **Hardware** — Verilog RTL, under [CERN-OHL-P-2.0](blindsig-rtl/LICENSE).
- **Software** — the Rust driver, C firmware, and tooling, under [MIT](LICENSE-MIT) or
  [Apache-2.0](LICENSE-APACHE), at your option.

`blindsig-soc/rtl/picorv32.v` is the third-party [PicoRV32](https://github.com/YosysHQ/picorv32) core
by Claire Xenia Wolf, vendored unmodified under its original ISC license. All other work is original.

<details>
<summary><sub><b>Development and AI use</b></sub></summary>

<sub>AI coding assistants (Claude) were used for the documentation and the in-browser demo; the RTL, the SoC integration and the formal-verification harness are hand-written, and I take responsibility for all delivered code. Correctness does not depend on who wrote a line — every result is cross-checked against an independent software reference and machine-checked with SymbiYosys.</sub>

</details>
