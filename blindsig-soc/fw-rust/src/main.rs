#![no_std]
#![no_main]

use blindsig_fw::BlindSigAccel;
use core::ptr;

// ---------------------------------------------------------------------------
// Startup assembly (replicates start.S)
// ---------------------------------------------------------------------------
core::arch::global_asm!(
    r#"
    .section .text.start
    .global _start
_start:
    /* Set stack pointer to top of RAM (16 KB) */
    li sp, 0x4000

    /* Clear .bss section */
    la a0, _bss_start
    la a1, _bss_end
1:
    bge a0, a1, 2f
    sw zero, 0(a0)
    addi a0, a0, 4
    j 1b
2:
    /* Call main */
    jal ra, main

    /* Halt: write 0xFF to sim I/O */
    li a0, 0x10000000
    li a1, 0xFF
    sw a1, 0(a0)

    /* Infinite loop (should not reach here) */
3:
    j 3b
"#
);

// ---------------------------------------------------------------------------
// Sim I/O helpers
// ---------------------------------------------------------------------------
const SIMIO: *mut u32 = 0x1000_0000 as *mut u32;

fn sim_putc(c: u8) {
    unsafe { ptr::write_volatile(SIMIO, c as u32) };
}

fn sim_print_str(s: &str) {
    for b in s.bytes() {
        sim_putc(b);
    }
}

fn sim_print_hex(val: u32) {
    sim_print_str("0x");
    for i in (0..8).rev() {
        let nibble = (val >> (i * 4)) & 0xF;
        let c = if nibble < 10 {
            b'0' + nibble as u8
        } else {
            b'a' + (nibble as u8 - 10)
        };
        sim_putc(c);
    }
}

fn sim_halt() -> ! {
    unsafe { ptr::write_volatile(SIMIO, 0xFF) };
    loop {}
}

// ---------------------------------------------------------------------------
// Panic handler
// ---------------------------------------------------------------------------
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    sim_print_str("PANIC\n");
    sim_halt()
}

// ---------------------------------------------------------------------------
// Main — integration test
// ---------------------------------------------------------------------------
#[no_mangle]
pub extern "C" fn main() {
    sim_print_str("blindsig-soc: rust integration test\n");

    let accel = BlindSigAccel::new(0x2000_0000);

    match accel.compute(&[7], &[10]) {
        Ok(result) => {
            sim_print_str("result = ");
            sim_print_hex(result);
            sim_print_str("\n");

            if result == 2 {
                sim_print_str("PASS\n");
            } else {
                sim_print_str("FAIL: expected 2, got ");
                sim_print_hex(result);
                sim_print_str("\n");
            }
        }
        Err(()) => {
            sim_print_str("FAIL: accelerator reported error\n");
        }
    }
}
