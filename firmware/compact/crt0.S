# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
# Modified 2026 by Niels Wieser, TU Darmstadt:
# adapted for the micro-architecturally protected Ibex system.

.section .text

/* Exception handlers - we will just loop for now if they happen */
.global simple_exc_handler
simple_exc_handler:
  j simple_exc_handler

.global simple_timer_handler
simple_timer_handler:
  j simple_timer_handler

default_exc_handler:
  jal x0, simple_exc_handler

timer_handler:
  jal x0, simple_timer_handler

reset_handler:
  /* set all registers to zero */
  mv  x1, x0
  mv  x2, x1
  mv  x3, x1
  mv  x4, x1
  mv  x5, x1
  mv  x6, x1
  mv  x7, x1
  mv  x8, x1
  mv  x9, x1
  mv x10, x1
  mv x11, x1
  mv x12, x1
  mv x13, x1
  mv x14, x1
  mv x15, x1
  mv x16, x1
  mv x17, x1
  mv x18, x1
  mv x19, x1
  mv x20, x1
  mv x21, x1
  mv x22, x1
  mv x23, x1
  mv x24, x1
  mv x25, x1
  mv x26, x1
  mv x27, x1
  mv x28, x1
  mv x29, x1
  mv x30, x1
  mv x31, x1

  /* stack initilization */
  la   x2, _stack_start

  /* Initialize memcrypt key and rounds before data copy */
  li x26, 0x00140000         /* memcrypt base */
  li x27, 0x01245
  sw x27, 0(x26)             /* key_low (master_key_0) */
  
  li x28, 0x00150014         /* prolead_regs.fresh address */
  lw x27, 0(x28)
  sw x27, 4(x26)             /* key_high (master_key_1) */

  sw x0, 12(x26)             /* master_key_2 */
  sw x0, 16(x26)             /* master_key_3 */
  
  li x27, 1
  sw x27, 8(x26)             /* additional_rounds */

_start:
  .global _start

  /* copy data section from ROM to RAM */
  la x26, _data_load
  la x27, _data_start
  la x28, _data_end
  bge x27, x28, copy_data_end

copy_data_loop:
  lw x29, 0(x26)
  sw x29, 0(x27)
  addi x26, x26, 4
  addi x27, x27, 4
  blt x27, x28, copy_data_loop
  
copy_data_end:
  /* clear BSS */
  la x26, _bss_start
  la x27, _bss_end

  bge x26, x27, zero_loop_end

zero_loop:
  sw x0, 0(x26)
  addi x26, x26, 4
  ble x26, x27, zero_loop
zero_loop_end:


main_entry:
  /* jump to main program entry point (argc = argv = 0) */
  addi x10, x0, 0
  addi x11, x0, 0
  jal x1, main

  /* If execution ends up here just put the core to sleep */
sleep_loop:
  wfi
  j sleep_loop

/* =================================================== [ exceptions ] === */
/* This section has to be down here, since we have to disable rvc for it  */

  .section .vectors, "ax"
  .option norvc;

  // All unimplemented interrupts/exceptions go to the default_exc_handler.
  .org 0x00
  .rept 7
  jal x0, default_exc_handler
  .endr
  jal x0, timer_handler
  .rept 23
  jal x0, default_exc_handler
  .endr

  // reset vector
  .org 0x80
  jal x0, reset_handler