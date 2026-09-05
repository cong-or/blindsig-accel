# blindsig-rtl

The blind signature accelerator peripheral in Verilog, built from constant-time
modular-arithmetic datapaths, with testbenches.

The accelerator computes `operand² mod modulus` (a modular squaring — the inner step of
square-and-multiply modular exponentiation) over a memory-mapped register interface. The
arithmetic is done by two bit-serial datapaths — **not** by Verilog's behavioural `*`/`%`
operators — so the peripheral is constant-time end to end. This is single-word (32-bit)
today and reduces by conditional subtraction; the funded work keeps this constant-time,
formally-verified structure but swaps in **Montgomery reduction**, scales to full
RSA-2048/3072 widths, and chains it into a modular-exponentiation pipeline (see the
[top-level README](../README.md)).

## Modules

| File | What | Notes |
|---|---|---|
| `rtl/mulmod.v` | **Constant-time modular multiplier** `(a·b) mod m` | Bit-serial, MSB-first, WIDTH-cycle. Every step does identical work; the "reduce" and "add" choices are muxes, not branches. Reusable for any modular arithmetic. |
| `rtl/redmod.v` | Constant-time modular reduction `x mod m` | Brings an operand into range (`< m`) before multiplication. |
| `rtl/blindsig_accel.v` | MMIO peripheral: `operand² mod modulus` | Wraps `redmod → mulmod` behind the register interface. |

**Constant-time** here means: fixed cycle count independent of the operand values,
no early exit, no data-dependent branching in the datapath. `tb/tb_mulmod.v`
checks this directly — it asserts every multiplication, from `0` to `(m-1)²`,
takes the *same* number of cycles.

## Formal verification

`mulmod.v` carries a SymbiYosys harness (`formal/mulmod.sby`, run with `make formal`),
with two proofs:

- **`invariant`** — an *unbounded* proof by k-induction, at the full 32-bit width, that
  the accumulator stays reduced (`acc < m`) throughout the computation. This is the
  modular-arithmetic invariant that underwrites correctness.
- **`equiv`** — an exhaustive BMC proof, at a reduced width, that `result == (a·b) mod m`
  against an independent reference over the entire input space.

Both currently pass. The harness lives behind `` `ifdef FORMAL `` and is inert for
synthesis and simulation.

## Register interface

Base `0x2000_0000` — CTRL `0x00` (START/RESET/LOAD_OP/LOAD_MOD), STATUS `0x04`
(BUSY/DONE/ERROR), OPERAND `0x08`, RESULT `0x0C`, MODULUS `0x10`.
Sequence: `reset → load_mod → load_op → start → wait(DONE) → read`.

## Build

```sh
make          # runs both testbenches:
              #   mulmod unit test  → "ALL MULMOD TESTS PASSED (constant N-cycle latency)"
              #   accelerator test  → "ALL TESTS PASSED" (4/4)
make mulmod   # just the modular-multiplier unit test
make sim      # just the end-to-end accelerator test
make waves    # open the accelerator VCD in GTKWave
```

The accelerator tests cover `10² mod 7 = 2`, the divide-by-zero error flag,
`15² mod 13 = 4`, and a large operand exercising reduction. The mulmod test
covers small values, zeros, near-16-bit primes, and full 32-bit stress cases
(e.g. `(m-1)² mod m = 1`).

## License

[CERN-OHL-P-2.0](LICENSE) (permissive open hardware).
