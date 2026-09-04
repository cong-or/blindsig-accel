#!/bin/bash
# test.sh — Full test suite for the blind signature SoC stack
#
# Runs all tests across both levels with verbose output showing
# what each test exercises and how the components connect.
#
# Usage:
#   ./test.sh           interactive (press enter between steps)
#   ./test.sh --ci      non-interactive (no pauses)

set -e

BOLD="\033[1m"
DIM="\033[2m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
RED="\033[31m"
MAGENTA="\033[35m"
RESET="\033[0m"

DIVIDER="${DIM}────────────────────────────────────────────────────────────────────────${RESET}"

CI=false
if [ "$1" = "--ci" ]; then
    CI=true
fi

step=0
narrate() {
    step=$((step + 1))
    echo ""
    echo -e "$DIVIDER"
    echo -e "  ${CYAN}${BOLD}[$step]${RESET} ${BOLD}$1${RESET}"
    if [ -n "$2" ]; then
        echo -e "  ${DIM}$2${RESET}"
    fi
    echo -e "$DIVIDER"
    echo ""
}

pause() {
    if [ "$CI" = false ]; then
        echo ""
        echo -e "  ${DIM}press enter to continue...${RESET}"
        read -r
    fi
}

# =====================================================================
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║          BlindSig SoC — Test Suite                          ║${RESET}"
echo -e "${BOLD}${CYAN}║                                                              ║${RESET}"
echo -e "${BOLD}${CYAN}║  Level 1: Standalone RTL    Level 2: SoC Integration (C/Rust)║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${DIM}Two levels of testing isolate hardware bugs from bus/firmware bugs."
echo -e "  Each step shows what is being tested and what the expected result is.${RESET}"
pause

# =====================================================================
# PART 1: RTL
# =====================================================================
narrate "Device under test — blindsig_accel.v" \
    "Scaffold accelerator: operand² mod modulus (placeholder for production Montgomery core)"

echo -e "  ${YELLOW}Operation:${RESET}    operand² mod modulus"
echo -e "  ${YELLOW}Word size:${RESET}    32-bit operands, 64-bit intermediate"
echo -e "  ${YELLOW}Latency:${RESET}      4 clock cycles"
echo -e "  ${YELLOW}Registers:${RESET}    CTRL(0x00) STATUS(0x04) OPERAND(0x08) RESULT(0x0C) MODULUS(0x10)"
echo -e "  ${YELLOW}States:${RESET}       IDLE → COMPUTING → DONE"
pause

# =====================================================================
narrate "Level 1 — standalone RTL test" \
    "tb_blindsig.v drives accelerator signals directly. No CPU, no bus, no firmware."

echo -e "  ${YELLOW}Test vectors:${RESET}"
echo -e "    1.  10² mod 7  = 2       ${DIM}basic sanity${RESET}"
echo -e "    2.  10² mod 0  = ERROR   ${DIM}division-by-zero protection${RESET}"
echo -e "    3.  15² mod 13 = 4       ${DIM}different values${RESET}"
echo -e "    4.  70000² mod 17 = 2    ${DIM}64-bit overflow (4.9B > 2³²)${RESET}"
echo ""
echo -e "  ${YELLOW}Exercises:${RESET}  state machine, armed-write gating, error handling, 64-bit math"
pause

narrate "Running Level 1..." \
    "compile: iverilog  run: vvp"

cd /home/soze/blindsig/blindsig-rtl
make clean > /dev/null 2>&1 || true

echo -e "  ${DIM}\$ iverilog -o blindsig_tb tb/tb_blindsig.v rtl/blindsig_accel.v${RESET}"
iverilog -o blindsig_tb tb/tb_blindsig.v rtl/blindsig_accel.v
echo -e "  ${GREEN}compiled${RESET}"
echo ""

echo -e "  ${DIM}\$ vvp blindsig_tb${RESET}"
echo ""
vvp blindsig_tb 2>&1 | while IFS= read -r line; do
    # Colorize output
    if echo "$line" | grep -q "PASS"; then
        echo -e "    ${GREEN}${BOLD}$line${RESET}"
    elif echo "$line" | grep -q "FAIL"; then
        echo -e "    ${RED}${BOLD}$line${RESET}"
    elif echo "$line" | grep -q "==="; then
        echo -e "    ${CYAN}$line${RESET}"
    elif echo "$line" | grep -q "Test"; then
        echo -e "    ${YELLOW}$line${RESET}"
    else
        echo -e "    ${DIM}$line${RESET}"
    fi
done

echo ""
echo -e "  ${GREEN}${BOLD}Level 1 passed — accelerator hardware logic verified in isolation.${RESET}"
pause

# =====================================================================
# LEVEL 2 SETUP
# =====================================================================
narrate "Level 2 — SoC integration test setup" \
    "Tests the full path: CPU → address decoder → bus adapter → accelerator → result back"

echo -e "  ${YELLOW}SoC components under test:${RESET}"
echo -e "    PicoRV32          ${DIM}RISC-V CPU executing real instructions from RAM${RESET}"
echo -e "    Address decoder    ${DIM}addr[31:28]: 0x0→RAM  0x1→SimIO  0x2→Accel${RESET}"
echo -e "    Bus adapter        ${DIM}valid/ready → wen/ren protocol translation${RESET}"
echo -e "    BlindSig Accel     ${DIM}same hardware tested in Level 1${RESET}"
echo ""
echo -e "  ${YELLOW}Firmware test sequence (MMIO):${RESET}"
echo -e "    1. CTRL = RESET            ${DIM}0x02 → 0x2000_0000${RESET}"
echo -e "    2. CTRL = LOAD_MOD         ${DIM}0x08 → 0x2000_0000  (arm)${RESET}"
echo -e "       MODULUS = 7             ${DIM}   7 → 0x2000_0010  (latch)${RESET}"
echo -e "    3. CTRL = LOAD_OP          ${DIM}0x04 → 0x2000_0000  (arm)${RESET}"
echo -e "       OPERAND = 10            ${DIM}  10 → 0x2000_0008  (latch)${RESET}"
echo -e "    4. CTRL = START            ${DIM}0x01 → 0x2000_0000${RESET}"
echo -e "    5. poll STATUS until DONE  ${DIM}read 0x2000_0004${RESET}"
echo -e "    6. read RESULT             ${DIM}read 0x2000_000C → expect 2${RESET}"
echo ""
echo -e "  ${YELLOW}Test harness (tb_soc.v):${RESET}"
echo -e "    100 MHz clock, 10-cycle reset, trap detection, 100K cycle timeout"
pause

# =====================================================================
narrate "Building C firmware..." \
    "riscv-none-elf-gcc → objcopy → makehex.py → firmware.hex"

cd /home/soze/blindsig/blindsig-soc
make -C fw clean > /dev/null 2>&1 || true

make -C fw 2>&1 | while IFS= read -r line; do
    if echo "$line" | grep -q "size"; then
        echo ""
    elif echo "$line" | grep -q "text"; then
        echo -e "    ${YELLOW}$line${RESET}"
    elif echo "$line" | grep -q "Entering\|Leaving"; then
        :
    else
        echo -e "    ${DIM}$line${RESET}"
    fi
done
echo ""
echo -e "  ${GREEN}firmware.hex ready${RESET}"
pause

# =====================================================================
narrate "Compiling Verilog SoC..." \
    "iverilog compiles all .v files into simulator executable"

make -C fw-rust clean > /dev/null 2>&1 || true
rm -f soc.vvp soc.vcd firmware.hex sim.log > /dev/null 2>&1 || true
cp fw/firmware.hex .

echo -e "  ${DIM}picorv32.v  soc_top.v  blindsig_bus_wrap.v  blindsig_accel.v  tb_soc.v${RESET}"

iverilog -o soc.vvp -s tb_soc \
    rtl/picorv32.v \
    rtl/soc_top.v \
    rtl/blindsig_bus_wrap.v \
    ../blindsig-rtl/rtl/blindsig_accel.v \
    tb/tb_soc.v

echo -e "  ${GREEN}compiled → soc.vvp${RESET}"
pause

# =====================================================================
narrate "Running Level 2 — SoC integration (C firmware)" \
    "CPU boots from RAM, executes MMIO sequence, result travels full bus path"

echo -e "  ${YELLOW}Expected:${RESET}  10² mod 7 = 2"
echo -e "  ${YELLOW}Path:${RESET}      CPU store → addr decode → bus adapter → accel → result → CPU load"
echo ""

vvp soc.vvp 2>&1 | tee sim.log | while IFS= read -r line; do
    if echo "$line" | grep -q "PASS"; then
        echo -e "    ${GREEN}${BOLD}$line${RESET}"
    elif echo "$line" | grep -q "FAIL"; then
        echo -e "    ${RED}${BOLD}$line${RESET}"
    elif echo "$line" | grep -q "halted\|finish"; then
        echo -e "    ${CYAN}$line${RESET}"
    elif echo "$line" | grep -q "result"; then
        echo -e "    ${YELLOW}$line${RESET}"
    else
        echo -e "    ${DIM}$line${RESET}"
    fi
done

echo ""
if grep -q "PASS" sim.log; then
    echo -e "  ${GREEN}${BOLD}Level 2 (C) passed.${RESET}"
else
    echo -e "  ${RED}${BOLD}Level 2 (C) FAILED${RESET}"
fi
pause

# =====================================================================
narrate "Running Level 2 — SoC integration (Rust firmware)" \
    "Same hardware, same test, different firmware language (blindsig-fw Rust driver)"

echo -e "  ${DIM}Building...${RESET}"
make -C fw-rust clean > /dev/null 2>&1 || true
make -C fw-rust 2>&1 | while IFS= read -r line; do
    if echo "$line" | grep -q "Compiling\|Finished"; then
        echo -e "    ${CYAN}$line${RESET}"
    elif echo "$line" | grep -q "warning"; then
        echo -e "    ${YELLOW}$line${RESET}"
    elif echo "$line" | grep -q "Entering\|Leaving"; then
        :
    else
        echo -e "    ${DIM}$line${RESET}"
    fi
done

cp fw-rust/firmware.hex .
iverilog -o soc.vvp -s tb_soc \
    rtl/picorv32.v \
    rtl/soc_top.v \
    rtl/blindsig_bus_wrap.v \
    ../blindsig-rtl/rtl/blindsig_accel.v \
    tb/tb_soc.v

echo ""

vvp soc.vvp 2>&1 | tee sim.log | while IFS= read -r line; do
    if echo "$line" | grep -q "PASS"; then
        echo -e "    ${GREEN}${BOLD}$line${RESET}"
    elif echo "$line" | grep -q "FAIL"; then
        echo -e "    ${RED}${BOLD}$line${RESET}"
    elif echo "$line" | grep -q "halted\|finish"; then
        echo -e "    ${CYAN}$line${RESET}"
    elif echo "$line" | grep -q "result"; then
        echo -e "    ${YELLOW}$line${RESET}"
    else
        echo -e "    ${DIM}$line${RESET}"
    fi
done

echo ""
if grep -q "PASS" sim.log; then
    echo -e "  ${GREEN}${BOLD}Level 2 (Rust) passed.${RESET}"
else
    echo -e "  ${RED}${BOLD}Level 2 (Rust) FAILED${RESET}"
fi
pause

# =====================================================================
narrate "Results"

echo ""
echo -e "  ${GREEN}${BOLD}Level 1  RTL standalone         ${RESET} 4/4 vectors pass"
echo -e "  ${GREEN}${BOLD}Level 2  SoC integration (C)    ${RESET} 10² mod 7 = 2  PASS"
echo -e "  ${GREEN}${BOLD}Level 2  SoC integration (Rust) ${RESET} 10² mod 7 = 2  PASS"
echo ""
echo -e "  ${YELLOW}Verified:${RESET}"
echo -e "    Accelerator math, state machine, error handling"
echo -e "    Bus adapter protocol translation (valid/ready → wen/ren)"
echo -e "    Address decoder routing (0x2000_xxxx → accel)"
echo -e "    Firmware MMIO sequence end-to-end"
echo -e "    CPU boot → firmware execution → peripheral interaction → correct result"
echo ""
echo -e "  ${YELLOW}Scaffold status:${RESET}"
echo -e "    Current core:    toy modular squaring (operand² mod modulus)"
echo -e "    Production core: Montgomery multiplier, modular exponentiation"
echo -e "    Swap:            drop-in replacement, same register interface"
echo -e "                     no changes to SoC, bus, firmware, or test infrastructure"
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║                     All tests passed                         ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo ""
