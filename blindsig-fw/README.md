# blindsig-fw

A bare-metal Rust (`no_std`, no allocator) MMIO driver for the blind signature
accelerator. Provides a small, safe API over the memory-mapped register interface:
reset, load modulus/operand, start, poll status, read result — with volatile accesses
and explicit ordering.

The same register map and sequence are mirrored in the C firmware in
[blindsig-soc](../blindsig-soc/), so the driver and the SoC integration stay in step.

**The three parts of this repo:** the hardware ([`blindsig-rtl/`](../blindsig-rtl/)), the RISC-V SoC
that runs it ([`blindsig-soc/`](../blindsig-soc/)), and this bare-metal Rust driver.

## Register interface

Base `0x2000_0000` — CTRL `0x00` (START/RESET/LOAD_OP/LOAD_MOD), STATUS `0x04`
(BUSY/DONE/ERROR), OPERAND `0x08`, RESULT `0x0C`, MODULUS `0x10`.

## Build

```sh
cargo build          # host build of the driver library
```

Intended for RISC-V `no_std` targets; the driver itself is platform-agnostic MMIO.

## License

Dual-licensed MIT OR Apache-2.0, at your option (see the [top-level README](../README.md)).
