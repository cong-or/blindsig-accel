# blindsig-rtl

The blind signature accelerator peripheral in Verilog, with a self-checking testbench.

Computes `operand² mod modulus` (single word, 64-bit intermediate) behind a memory-mapped
register interface. This is a **placeholder arithmetic core**: it proves the register
interface and a fixed-cycle datapath, and stands in for the constant-time Montgomery
modular multiplier and modular-exponentiation pipeline that are the funded work ahead.
See the [top-level README](../README.md) for the full picture.

## Register interface

Base `0x2000_0000` — CTRL `0x00` (START/RESET/LOAD_OP/LOAD_MOD), STATUS `0x04`
(BUSY/DONE/ERROR), OPERAND `0x08`, RESULT `0x0C`, MODULUS `0x10`.
Sequence: `reset → load_mod → load_op → start → wait(DONE) → read`.

## Build

```sh
make        # iverilog + vvp; prints "ALL TESTS PASSED" (4/4)
make waves  # open the VCD in GTKWave
```

Tests cover the happy path (`10² mod 7 = 2`), the divide-by-zero error flag,
a second modulus (`15² mod 13 = 4`), and 64-bit intermediate overflow.

## License

[CERN-OHL-P-2.0](LICENSE) (permissive open hardware).
