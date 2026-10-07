/* Linker script for QEMU virt machine */

OUTPUT_ARCH(riscv)

MEMORY
{
    ram         : ORIGIN = 0x80000000, LENGTH = 0x30000 /* 192 kB */
    stack       : ORIGIN = 0x80030000, LENGTH = 0x8000  /* 32 kB */
    memcrypt    : ORIGIN = 0x00140000, LENGTH = 0x400   /* 1 kB */
    prolead     : ORIGIN = 0x00150000, LENGTH = 0x400   /* 1 kB */
}

/* Stack information variables */
_min_stack      = 0x2000;   /* 8K - minimum stack space to reserve */
_stack_len     = LENGTH(stack);
_stack_start   = ORIGIN(stack) + LENGTH(stack);

ENTRY(reset_handler)

SECTIONS
{
    .vectors :
    {
        . = ALIGN(4);
        KEEP(*(.vectors))
        /* Ensure reset_handler is at the very beginning of the binary for QEMU */
        *(.text.reset_handler)
    } > ram

    .text : {
        . = ALIGN(4);
        *(.text)
        *(.text.*)
    }  > ram

    .rodata : {
        . = ALIGN(4);
        *(.srodata)
        *(.srodata.*)
        *(.rodata);
        *(.rodata.*)
    } > ram

    .data : {
        . = ALIGN(4);
        *(.sdata)
        *(.sdata.*)
        *(.data);
        *(.data.*)
    } > ram

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

    .test_output :
    {
        . = ALIGN(4);
        *(.test_output)
    } > test_result_mem

    /* ensure there is enough room for stack */
    .stack (NOLOAD): {
        . = ALIGN(4);
        . = . + _min_stack ;
        . = ALIGN(4);
        stack = . ;
        _stack = . ;
    } > stack
}
