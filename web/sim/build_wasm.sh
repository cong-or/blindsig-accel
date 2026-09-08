#!/usr/bin/env bash
# build_wasm.sh — compile the REAL mulmod RTL to WebAssembly.
#
#   Verilator turns rtl/mulmod.v into a cycle-accurate C++ model; Emscripten
#   compiles that model + this harness to WASM. The browser then runs the exact
#   circuit as a cycle-accurate simulation — no re-implementation.
#
# Requires: verilator and em++ (an activated emsdk) on PATH.
# Output:   web/wasm/{mulmod.js, mulmod.wasm}
set -euo pipefail
cd "$(dirname "$0")"

RTL="../../blindsig-rtl/rtl/mulmod.v"
VINC="$(verilator --getenv VERILATOR_ROOT)/include"
OUT="../wasm"

rm -rf obj_dir "$OUT"
mkdir -p "$OUT"

# 1) Verilate to C++ (expose internals so the demo can read the live accumulator)
verilator --cc --public -Mdir obj_dir --top-module mulmod -Wno-fatal "$RTL"

# 2) Compile the model + harness to WASM (em++ for C++ linking)
em++ -O2 -DVL_NO_LEGACY -I obj_dir -I "$VINC" -I "$VINC/vltstd" \
  mulmod_sim.cpp stubs.c obj_dir/*.cpp "$VINC/verilated.cpp" "$VINC/verilated_threads.cpp" \
  -s EXPORTED_FUNCTIONS='["_sim_reset","_sim_load","_sim_step","_sim_result","_sim_cycles","_sim_busy","_sim_acc","_sim_bbit"]' \
  -s EXPORTED_RUNTIME_METHODS='["ccall","cwrap"]' \
  -s MODULARIZE=1 -s EXPORT_NAME=createMulmodSim \
  -o "$OUT/mulmod.js"

echo "built $OUT/mulmod.js + mulmod.wasm"
