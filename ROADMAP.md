# Roadmap

The funded work is five milestones, from the grant proposal. The prototype in this repository is a
feasibility spike: it de-risks the methods behind several of them but completes none. Where each
stands today:

| Milestone | Deliverable | Status |
|---|---|---|
| M1 | Montgomery modular multiplier and property verification | Partial. A constant-time multiplier exists and is formally verified, but reduces by conditional subtraction; Montgomery is not yet built. |
| M2 | Modular-exponentiation pipeline and blind RSA | Not started. The core computes a single `operand²` squaring, not the square-and-multiply pipeline. |
| M3 | Blind Schnorr and SymbiYosys formal verification | Partial. The formal method is proven out — the range invariant at full 32-bit width, end-to-end correctness exhaustively at a reduced width; blind Schnorr is not built. |
| M4 | VexRiscv integration, Rust firmware, co-simulation | Partial. Integrated on PicoRV32 with C and Rust firmware; the VexRiscv port and Verilator co-simulation are not done. |
| M5 | ECP5 synthesis, docs, reproducible build | Not started. Simulation only; not yet synthesised to FPGA fabric. |

The register interface, the `mulmod` and `redmod` primitives, the formal harness, and the SoC
integration all carry over directly — the funded work builds on this foundation rather than restarting.

## Beyond the grant

The same pipeline extends to:

- **Side-channel hardening** — timing leakage is designed out today; the next stage adds power and EM
  leakage assessment (TVLA) and formal masking verification. Physical power analysis needs lab
  measurement, so it sits just outside this simulation-focused grant.
- **Supply-chain integrity** — a fully reproducible source-to-bitstream build, so a component can be
  rebuilt and audited rather than trusted.
- **Audit by parts, not by reputation** — the same method applied to more primitives (modular
  arithmetic, elliptic-curve, hashing, post-quantum), each permissively licensed and shipped with its
  proofs, is a means to an end: a hardware analogue of what the software supply chain already built. A
  bill of materials (CycloneDX, SPDX) records what a design is made of; reproducible builds let anyone
  rebuild it bit-for-bit; in-toto records how each build step was carried out, and Sigstore signs those
  steps to a verifiable identity. Those establish *what a part is, that it matches its source, and who
  built it* — but not *what the part computes and what it does not leak*. That last piece is the one
  missing for hardware, and it is what this project supplies first: `mulmod.v` is published not as
  "trust the author" but with re-runnable proofs of correctness, range, and constant-time behaviour,
  checkable against an open prover on someone else's machine.

  The longer-term goal, well beyond this grant, is a public library of open-hardware blocks assembled the
  same way: each linking its source, a reproducible build recipe, provenance, and proof scripts, so a
  downstream user can re-derive the properties themselves. A large design could then be audited by its
  parts rather than as a monolith. Today the only such block is the verified `mulmod.v` in this
  repository; the reusable output is the method that lets a second and third be added on the same footing.
