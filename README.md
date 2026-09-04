# Blind Signature Accelerator — RISC-V Integration Prototype

An open-source hardware accelerator peripheral for a RISC-V SoC, together with the
firmware that drives it. This repository is the **integration proof-of-concept** for a
larger project: an open hardware accelerator for blind signature operations (blind RSA
and blind Schnorr) targeting RISC-V soft cores on FPGA.

Project site: <https://blindsig-hardware.org>

## Status — read this first

This is a **feasibility prototype**, not the finished accelerator. Its job is to prove
the toolchain and the CPU↔accelerator integration end-to-end, so that the hard
cryptographic work can be built on a de-risked foundation.

**What works today (and is tested in simulation):**

- A memory-mapped accelerator peripheral in Verilog with a clean register interface.
- A PicoRV32 RISC-V SoC that integrates the accelerator on a memory-mapped bus.
- C firmware and a bare-metal Rust (`no_std`) driver that drive the accelerator and read
  results back — the full `CPU → bus → accelerator → result` path runs end-to-end.

**What is deliberately a placeholder:** the arithmetic core currently computes
`operand² mod modulus` on a single machine word (test vector `10² mod 7 = 2`). This
exercises the register interface, the bus integration, and a **fixed-cycle datapath**,
but it is *not* the cryptographic core. The real work — a constant-time Montgomery
modular multiplier for RSA-2048/3072, a modular-exponentiation pipeline, blind Schnorr
support, SymbiYosys formal verification, and Lattice ECP5 synthesis via the open
Yosys/nextpnr/Trellis toolchain — is the funded scope ahead.

The current core also runs on **PicoRV32**; the proposed target core is **VexRiscv**.
The MMIO integration pattern is identical, so the port is a bus-adapter change.

## Layout

The three components are independently useful and each has its own README:

| Directory | What | Reusable as |
|---|---|---|
| [`blindsig-rtl/`](blindsig-rtl/) | The accelerator peripheral in Verilog + standalone testbench | A fixed-function MMIO arithmetic peripheral for any SoC |
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

## Licensing

- **Hardware** (Verilog RTL in `blindsig-rtl/` and the accelerator/bus RTL in
  `blindsig-soc/`): [CERN-OHL-P-2.0](blindsig-rtl/LICENSE) (permissive open hardware).
- **Software** (Rust driver, C firmware, tooling): dual-licensed
  [MIT](LICENSE-MIT) OR [Apache-2.0](LICENSE-APACHE), at your option.

`blindsig-soc/rtl/picorv32.v` is the third-party [PicoRV32](https://github.com/YosysHQ/picorv32)
core by Claire Xenia Wolf, vendored unmodified under its original ISC license (see the file
header). All other RTL, firmware, and tooling is original work.
