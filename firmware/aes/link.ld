/* Copyright lowRISC contributors.
   Licensed under the Apache License, Version 2.0, see LICENSE for details.
   SPDX-License-Identifier: Apache-2.0
   Modified 2026 by Niels Wieser, TU Darmstadt:
   adapted for the micro-architecturally protected Ibex system. */

OUTPUT_ARCH(riscv)

MEMORY
{
    instr (rx)      : ORIGIN = 0x00100000, LENGTH = 0x4000   /* 16 kB */
    rom   (r)       : ORIGIN = 0x00110000, LENGTH = 0x4000   /* 16 kB */
    ram   (rwx)     : ORIGIN = 0x00120000, LENGTH = 0x1800   /*  6 kB */
    memcrypt        : ORIGIN = 0x00140000, LENGTH = 0x400    /*  1 kB */
    prolead         : ORIGIN = 0x00150000, LENGTH = 0x400    /*  1 kB */
}

/* Stack information variables */
_min_stack      = 0x400;
_stack_start    = ORIGIN(ram) + LENGTH(ram);

_entry_point = _vectors_start + 0x80;
ENTRY(_entry_point)

/* Spike-compatible tohost/fromhost */
tohost   = 0x20008;
fromhost = _stack_start + 0x10;

SECTIONS
{
    .vectors :
    {
        . = ALIGN(4);
        _vectors_start = .;
        KEEP(*(.vectors))
        _vectors_end = .;
    } > instr

    .text : {
        . = ALIGN(4);
        *(.text)
        *(.text.*)
    } > instr

    .rodata : {
        . = ALIGN(4);
        *(.srodata)
        *(.srodata.*)
        *(.rodata);
        *(.rodata.*)
    } > rom


    _data_load = LOADADDR(.data);
    .data : {
        . = ALIGN(4);
        _data_start = .;
        *(.sdata)
        *(.sdata.*)
        *(.data);
        *(.data.*)
        _data_end = .;
    } > ram AT > rom

    /* _data_load = LOADADDR(.data);
    .data(NOLOAD) : {
        . = ALIGN(4);
        *(.sdata)
        *(.sdata.*)
        *(.data);
        _data_start = .;
        *(.data.*)
        _data_end = .;
    } > ram */

    .bss :
    {
        . = ALIGN(4);
        _bss_start = .;
        *(.sbss)
        *(.sbss.*)
        *(.bss)
        *(.bss.*)
        *(COMMON)
        _bss_end = .;
    } > ram

    /* Stack grows downwards from the top of ram */
    .stack (NOLOAD): {
        . = ALIGN(4);
        . = . + _min_stack ;
        . = ALIGN(4);
        stack = . ;
        _stack = . ;
    } > ram

    .memcrypt :
    {
        . = ALIGN(4);
        *(.memcrypt)
    } > memcrypt

    .prolead :
    {
        . = ALIGN(4);
        *(.prolead)
    } > prolead

    /DISCARD/ :
    {
        *(.riscv.attributes)
        *(.comment)
    }
}
