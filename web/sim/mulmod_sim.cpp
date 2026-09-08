// mulmod_sim.cpp — a thin harness around the REAL mulmod.v, compiled by Verilator.
//
// The same C++ is used two ways:
//   * native build  → runs a self-test (verifies the harness against (a*b)%m)
//   * Emscripten    → exports sim_* to JavaScript so the browser runs the real
//                     circuit as a cycle-accurate simulation, bit-for-bit.
//
// This is not a re-implementation of the algorithm: Verilator turns the actual
// Verilog into a cycle-accurate model, and this file only drives its clock and
// reads its ports/registers.

#include "Vmulmod.h"
#include "Vmulmod___024root.h"   // internal signal access (the accumulator)
#include "verilated.h"
#include <cstdint>
#include <cstdio>

namespace {
Vmulmod* g_top = nullptr;
uint32_t g_cycles = 0;
bool     g_latched = false;

void tick() {          // one full clock: negedge then posedge
    g_top->clk = 0; g_top->eval();
    g_top->clk = 1; g_top->eval();
}
}

extern "C" {

// Create/reset the model. Call once before each computation.
void sim_reset() {
    if (!g_top) g_top = new Vmulmod;
    g_top->clk = 0;
    g_top->rst_n = 0;
    g_top->start = 0;
    g_top->a = 0; g_top->b = 0; g_top->m = 0;
    g_top->eval();
    tick(); tick();          // hold reset
    g_top->rst_n = 1;
    g_top->eval();
    g_cycles = 0;
    g_latched = false;
}

// Present operands and assert start (combinational; the first sim_step latches them).
void sim_load(uint32_t a, uint32_t b, uint32_t m) {
    g_top->a = a; g_top->b = b; g_top->m = m;
    g_top->start = 1;
    g_top->eval();
    g_cycles = 0;
    g_latched = false;
}

// Advance exactly one clock. Returns 1 on the cycle `done` pulses.
int sim_step() {
    tick();
    if (!g_latched) { g_top->start = 0; g_top->eval(); g_latched = true; }
    g_cycles++;
    return g_top->done ? 1 : 0;
}

uint32_t sim_result() { return g_top->result; }
uint32_t sim_cycles() { return g_cycles; }
int      sim_busy()   { return g_top->busy ? 1 : 0; }

// The live accumulator inside the real datapath (acc is 33 bits; acc < m fits 32).
uint32_t sim_acc() { return (uint32_t)g_top->rootp->mulmod__DOT__acc; }

// The active b bit inside the real datapath: b_reg shifts left each cycle and its
// MSB is what selects the add path (step = b_reg[WIDTH-1] ? red2 : red1). Reading
// this drives the animation from the circuit itself, not from a JS re-derivation.
int sim_bbit() { return (int)((g_top->rootp->mulmod__DOT__b_reg >> 31) & 1u); }

}  // extern "C"

#ifndef __EMSCRIPTEN__
// ---- native self-test: prove the harness drives the real RTL correctly ----
static bool run_one(uint32_t a, uint32_t b, uint32_t m, uint32_t& cycles_out) {
    sim_reset();
    sim_load(a, b, m);
    int guard = 0;
    while (!sim_step() && guard++ < 1000) {}
    cycles_out = sim_cycles();
    uint64_t expect = ((uint64_t)a * (uint64_t)b) % (uint64_t)m;
    uint32_t got = sim_result();
    bool ok = (got == (uint32_t)expect);
    printf("  %10u * %10u mod %10u = %10u  (expect %10u) %2u cycles  %s\n",
           a, b, m, got, (uint32_t)expect, cycles_out, ok ? "OK" : "FAIL");
    return ok;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    printf("=== native Verilator self-test of mulmod.v ===\n");
    struct V { uint32_t a, b, m; } vecs[] = {
        {3,3,7}, {6,6,7}, {123,456,789}, {65535,65534,65537},
        {0xFFFFFFFEu,0xFFFFFFFEu,0xFFFFFFFFu}, {0x7FFFFFFFu,0x7FFFFFFEu,0x80000000u},
    };
    bool all_ok = true;
    uint32_t ref_cycles = 0;
    bool ct_ok = true;
    for (size_t i = 0; i < sizeof(vecs)/sizeof(vecs[0]); i++) {
        uint32_t c;
        all_ok &= run_one(vecs[i].a, vecs[i].b, vecs[i].m, c);
        if (i == 0) ref_cycles = c; else if (c != ref_cycles) ct_ok = false;
    }
    printf("result: %s ; constant-time: %s (%u cycles each)\n",
           all_ok ? "ALL CORRECT" : "MISMATCH",
           ct_ok ? "YES" : "NO", ref_cycles);
    return (all_ok && ct_ok) ? 0 : 1;
}
#endif
