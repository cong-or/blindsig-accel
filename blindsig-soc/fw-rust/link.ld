/* link.ld — Linker script for PicoRV32 SoC Rust firmware
 *
 * Single RAM region at 0x0000_0000, 16 KB.
 * Stack grows down from 0x4000 (set in startup assembly).
 */

MEMORY
{
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 16K
}

SECTIONS
{
    .text : {
        *(.text.start)    /* _start entry point first */
        *(.text .text.*)
    } > RAM

    .rodata : {
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
    } > RAM

    .data : {
        *(.data .data.*)
        *(.sdata .sdata.*)
    } > RAM

    .bss : {
        _bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        _bss_end = .;
    } > RAM

    /* Discard unwanted sections */
    /DISCARD/ : {
        *(.eh_frame)
        *(.comment)
        *(.note.*)
    }
}
