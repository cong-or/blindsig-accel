    .section .text.start
    .global _start
_start:
    /* Set stack pointer to top of RAM (16 KB) */
    li sp, 0x4000

    /* Clear .bss section */
    la a0, _bss_start
    la a1, _bss_end
bss_loop:
    bge a0, a1, bss_done
    sw zero, 0(a0)
    addi a0, a0, 4
    j bss_loop
bss_done:

    /* Call main */
    jal ra, main

    /* Halt: write 0xFF to sim I/O */
    li a0, 0x10000000
    li a1, 0xFF
    sw a1, 0(a0)

    /* Infinite loop (should not reach here) */
hang:
    j hang
