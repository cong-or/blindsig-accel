# blindsig-soc

A PicoRV32 RISC-V SoC that integrates the [blindsig-rtl](../blindsig-rtl/) accelerator on
a memory-mapped bus, with firmware that drives it. This is the **integration point**: a
RISC-V CPU executing firmware that talks to the accelerator over MMIO, proving the full
`CPU → bus → accelerator → result` stack in simulation.

**The three parts of this repo:** the hardware ([`blindsig-rtl/`](../blindsig-rtl/)), the RISC-V SoC
that runs it (this directory, `blindsig-soc/`), and the bare-metal Rust driver
([`blindsig-fw/`](../blindsig-fw/)).

## Contents

- `rtl/soc_top.v` — top-level SoC (CPU + memory + accelerator wrapper)
- `rtl/blindsig_bus_wrap.v` — bus adapter exposing the accelerator as an MMIO peripheral
- `rtl/picorv32.v` — vendored [PicoRV32](https://github.com/YosysHQ/picorv32) core
  (Claire Xenia Wolf, ISC — unmodified)
- `fw/` — C firmware (`test_accel.c`, `start.S`) driving the accelerator
- `fw-rust/` — the same in bare-metal Rust (`no_std`)
- `tb/tb_soc.v` — testbench that boots the SoC and checks the result

## Build

```sh
make        # builds firmware, runs the SoC sim; prints "PASS: Integration test succeeded"
```

Needs `iverilog` and a bare-metal RISC-V C toolchain (`riscv-none-elf-gcc`) on `PATH`.
The accelerator RTL is pulled in from `../blindsig-rtl/` — keep the two directories as
siblings.

## License

RTL under [CERN-OHL-P-2.0](LICENSE-HARDWARE); firmware under MIT OR Apache-2.0
(see the [top-level README](../README.md)). `picorv32.v` retains its original ISC license.
