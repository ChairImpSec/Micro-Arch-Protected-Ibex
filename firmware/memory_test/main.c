// Copyright (c) 2026 Niels Wieser, TU Darmstadt
// SPDX-License-Identifier: MIT

#include <stdint.h>
#include <stddef.h>

// MemCrypt registers
typedef struct {
    volatile uint32_t key_low;
    volatile uint32_t key_high;
    volatile uint32_t additional_rounds;
} memcrypt_regs_t;
volatile memcrypt_regs_t memcrypt_regs __attribute__((section(".memcrypt")));


typedef struct {
    volatile uint32_t reserved;
    volatile uint32_t plaintext_0[4];
    volatile uint32_t plaintext_1[4];
    volatile uint32_t key_s0[4];
    volatile uint32_t key_s1[4];
    volatile uint32_t fresh;
    volatile uint32_t ciphertext_s0[4];
    volatile uint32_t ciphertext_s1[4];
    volatile uint32_t done;
    volatile uint32_t reached_main;
} prolead_regs_t;
volatile prolead_regs_t prolead_regs __attribute__((section(".prolead")));






/*******************************************************************************************************
*       Memory access-pattern leakage test                                                            *
********************************************************************************************************/

// Global test buffers in BRAM (RAM)
volatile uint8_t test_ram_table[256] __attribute__((aligned(256)));
volatile uint32_t test_ram_word_table[256] __attribute__((aligned(1024)));

// Constant-data table: filled with a fixed value so that indexing by the
// shares moves the secret on the *address* only, not on the returned data.
volatile uint8_t const_ram_table[256] __attribute__((aligned(256)));
// Small aligned buffer to force two shares into the same 32-bit word.
volatile uint8_t pair_ram_table[4] __attribute__((aligned(4)));

// Signature marker macro to delimit test cases in side-channel traces
#define INSERT_MARKER(id) \
    do { \
        (void)test_ram_table[0xAA]; \
        asm volatile("nop; nop; nop; nop; nop;"); \
        (void)test_ram_table[id]; \
        asm volatile("nop; nop; nop; nop; nop;"); \
        (void)test_ram_table[0x55]; \
        asm volatile("nop; nop; nop; nop; nop;"); \
        asm volatile("" : : : "memory"); \
    } while(0)



void main() {
    prolead_regs.reached_main = 1;

    // Initialize test tables in BRAM
    for (int i = 0; i < 256; i++) {
        test_ram_table[i] = (uint8_t)i;
        test_ram_word_table[i] = (uint32_t)i;
        const_ram_table[i] = 0x00;   // constant data: isolates address-driven leakage
    }
    for (int i = 0; i < 4; i++) {
        pair_ram_table[i] = 0x00;
    }

    // Reconstruct input shares
    uint32_t shares[16][2];
    for (uint32_t i = 0; i < 16; i++) {
      shares[i][0] = ((prolead_regs.plaintext_0[i>>2] ^ prolead_regs.key_s0[i>>2]) >> (3 - i%4)*8) & 0xFF;
      shares[i][1] = ((prolead_regs.plaintext_1[i>>2] ^ prolead_regs.key_s1[i>>2]) >> (3 - i%4)*8) & 0xFF;
    }

    // Execute each memory access pattern 16 times (once per share byte)
    
    // Pattern 1: Direct Read Add
    INSERT_MARKER(1);
    for (int i = 0; i < 16; i++) {
        uint32_t s0 = shares[i][0];
        uint32_t s1 = shares[i][1];
        (void)test_ram_table[s0];
        (void)test_ram_table[s1];
        asm volatile("" : : : "memory");
    }

    // Pattern 2: Direct Read XOR
    INSERT_MARKER(2);
    for (int i = 0; i < 16; i++) {
        uint32_t s0 = shares[i][0];
        uint32_t s1 = shares[i][1];
        (void)*(volatile uint8_t *)((uintptr_t)test_ram_table ^ s0);
        (void)*(volatile uint8_t *)((uintptr_t)test_ram_table ^ s1);
        asm volatile("" : : : "memory");
    }

    // Pattern 3: Direct Read OR
    INSERT_MARKER(3);
    for (int i = 0; i < 16; i++) {
        uint32_t s0 = shares[i][0];
        uint32_t s1 = shares[i][1];
        (void)*(volatile uint8_t *)((uintptr_t)test_ram_table | s0);
        (void)*(volatile uint8_t *)((uintptr_t)test_ram_table | s1);
        asm volatile("" : : : "memory");
    }

    // Pattern 4: Read NOPs
    INSERT_MARKER(4);
    for (int i = 0; i < 16; i++) {
        uint32_t s0 = shares[i][0];
        uint32_t s1 = shares[i][1];
        (void)test_ram_table[s0];
        asm volatile("nop; nop; nop; nop; nop; nop; nop; nop;");
        (void)test_ram_table[s1];
        asm volatile("" : : : "memory");
    }

    // Pattern 5: Read Clear Zero
    INSERT_MARKER(5);
    for (int i = 0; i < 16; i++) {
        uint32_t s0 = shares[i][0];
        uint32_t s1 = shares[i][1];
        (void)test_ram_table[s0];
        (void)test_ram_table[0];
        (void)test_ram_table[s1];
        asm volatile("" : : : "memory");
    }

    // Pattern 6: Read Clear Fixed
    INSERT_MARKER(6);
    for (int i = 0; i < 16; i++) {
        uint32_t s0 = shares[i][0];
        uint32_t s1 = shares[i][1];
        (void)test_ram_table[s0];
        (void)test_ram_table[0xAA];
        (void)test_ram_table[s1];
        asm volatile("" : : : "memory");
    }

    // Pattern 7: Read Clear Random
    INSERT_MARKER(7);
    for (int i = 0; i < 16; i++) {
        uint32_t s0 = shares[i][0];
        uint32_t s1 = shares[i][1];
        uint32_t rnd = prolead_regs.fresh & 0xFF;
        (void)test_ram_table[s0];
        (void)test_ram_table[rnd];
        (void)test_ram_table[s1];
        asm volatile("" : : : "memory");
    }

    // Pattern 8: Read Precharged Random
    INSERT_MARKER(8);
    for (int i = 0; i < 16; i++) {
        uint32_t s0 = shares[i][0];
        uint32_t s1 = shares[i][1];
        uint32_t rnd0 = prolead_regs.fresh & 0xFF;
        uint32_t rnd1 = (prolead_regs.fresh >> 8) & 0xFF;
        (void)test_ram_table[rnd0];
        (void)test_ram_table[s0];
        (void)test_ram_table[rnd1];
        (void)test_ram_table[s1];
        asm volatile("" : : : "memory");
    }

    // Pattern 9: Direct Write Add
    INSERT_MARKER(9);
    for (int i = 0; i < 16; i++) {
        uint32_t s0 = shares[i][0];
        uint32_t s1 = shares[i][1];
        test_ram_table[s0] = 0x11;
        test_ram_table[s1] = 0x22;
        asm volatile("" : : : "memory");
    }

    // Pattern 10: Write Clear Zero
    INSERT_MARKER(10);
    for (int i = 0; i < 16; i++) {
        uint32_t s0 = shares[i][0];
        uint32_t s1 = shares[i][1];
        test_ram_table[s0] = 0x11;
        test_ram_table[0]  = 0x00;
        test_ram_table[s1] = 0x22;
        asm volatile("" : : : "memory");
    }

    // Pattern 11: Write Clear Random
    INSERT_MARKER(11);
    for (int i = 0; i < 16; i++) {
        uint32_t s0 = shares[i][0];
        uint32_t s1 = shares[i][1];
        uint32_t rnd = prolead_regs.fresh & 0xFF;
        test_ram_table[s0] = 0x11;
        test_ram_table[rnd] = 0x00;
        test_ram_table[s1] = 0x22;
        asm volatile("" : : : "memory");
    }

    // Pattern 12: Reshared Read
    INSERT_MARKER(12);
    for (int i = 0; i < 16; i++) {
        uint32_t s0 = shares[i][0];
        uint32_t s1 = shares[i][1];
        uint32_t r = prolead_regs.fresh & 0xFF;
        uint32_t s0_new = (s0 ^ r) & 0xFF;
        uint32_t s1_new = (s1 ^ r) & 0xFF;
        (void)test_ram_table[s0_new];
        (void)test_ram_table[s1_new];
        asm volatile("" : : : "memory");
    }

    // Pattern 13: Reshared Read Clear
    INSERT_MARKER(13);
    for (int i = 0; i < 16; i++) {
        uint32_t s0 = shares[i][0];
        uint32_t s1 = shares[i][1];
        uint32_t r = prolead_regs.fresh & 0xFF;
        uint32_t s0_new = (s0 ^ r) & 0xFF;
        uint32_t s1_new = (s1 ^ r) & 0xFF;
        (void)test_ram_table[s0_new];
        (void)test_ram_table[0];
        (void)test_ram_table[s1_new];
        asm volatile("" : : : "memory");
    }

    // Pattern 14: Reshared Read Independent Mask
    INSERT_MARKER(14);
    for (int i = 0; i < 16; i++) {
        uint32_t s0 = shares[i][0];
        uint32_t s1 = shares[i][1];
        uint32_t r0 = prolead_regs.fresh & 0xFF;
        uint32_t r1 = (prolead_regs.fresh >> 8) & 0xFF;
        uint32_t s0_new = (s0 ^ r0) & 0xFF;
        uint32_t s1_new = (s1 ^ r1) & 0xFF;
        (void)test_ram_table[s0_new];
        (void)test_ram_table[s1_new];
        asm volatile("" : : : "memory");
    }

    // Pattern 15: Interleaved Regs Read
    INSERT_MARKER(15);
    for (int i = 0; i < 16; i++) {
        uint32_t s0 = shares[i][0];
        uint32_t s1 = shares[i][1];
        uint32_t addr0 = (uintptr_t)test_ram_table + s0;
        uint32_t addr1 = (uintptr_t)test_ram_table + s1;
        uint32_t val0, val1;
        asm volatile(
            "lbu %0, 0(%2)\n\t"
            "lbu %1, 0(%3)\n\t"
            : "=r"(val0), "=r"(val1)
            : "r"(addr0), "r"(addr1)
        );
        (void)val0; (void)val1;
        asm volatile("" : : : "memory");
    }

    // Pattern 16: Direct Read Word
    INSERT_MARKER(16);
    for (int i = 0; i < 16; i++) {
        uint32_t s0 = shares[i][0];
        uint32_t s1 = shares[i][1];
        (void)test_ram_word_table[s0];
        (void)test_ram_word_table[s1];
        asm volatile("" : : : "memory");
    }

    // Pattern 17: Write Secret Data, Fixed Address
    INSERT_MARKER(17);
    for (int i = 0; i < 16; i++) {
        uint32_t s0 = shares[i][0];
        uint32_t s1 = shares[i][1];
        test_ram_table[0x40] = (uint8_t)s0;
        test_ram_table[0x40] = (uint8_t)s1;
        asm volatile("" : : : "memory");
    }

    // Pattern 18: Both Shares In One Word (full-word store)
    INSERT_MARKER(18);
    for (int i = 0; i < 16; i++) {
        uint32_t s0 = shares[i][0];
        uint32_t s1 = shares[i][1];
        test_ram_word_table[0x40] = (s0 & 0xFF) | ((s1 & 0xFF) << 8);
        asm volatile("" : : : "memory");
    }

    // Pattern 19: Both Shares In One Word (RMW merge)
    INSERT_MARKER(19);
    for (int i = 0; i < 16; i++) {
        uint32_t s0 = shares[i][0];
        uint32_t s1 = shares[i][1];
        pair_ram_table[0] = (uint8_t)s0;   // store
        pair_ram_table[1] = (uint8_t)s1;   // rmw: reads word w/ s0, merges s1
        asm volatile("" : : : "memory");
    }

    // Pattern 20: Write Secret Address + Secret Data
    INSERT_MARKER(20);
    for (int i = 0; i < 16; i++) {
        uint32_t s0 = shares[i][0];
        uint32_t s1 = shares[i][1];
        test_ram_table[s0] = (uint8_t)s0;
        test_ram_table[s1] = (uint8_t)s1;
        asm volatile("" : : : "memory");
    }

    // Pattern 21: Load then Store (cross-path transition)
    INSERT_MARKER(21);
    for (int i = 0; i < 16; i++) {
        uint32_t s0 = shares[i][0];
        uint32_t s1 = shares[i][1];
        (void)test_ram_table[s0];
        test_ram_table[0x40] = (uint8_t)s1;
        asm volatile("" : : : "memory");
    }

    // Pattern 22: Store then Load (cross-path transition)
    INSERT_MARKER(22);
    for (int i = 0; i < 16; i++) {
        uint32_t s0 = shares[i][0];
        uint32_t s1 = shares[i][1];
        test_ram_table[0x40] = (uint8_t)s0;
        (void)test_ram_table[s1];
        asm volatile("" : : : "memory");
    }

    // Pattern 23: Read Constant Data (isolate address / tweak / decoder)
    INSERT_MARKER(23);
    for (int i = 0; i < 16; i++) {
        uint32_t s0 = shares[i][0];
        uint32_t s1 = shares[i][1];
        (void)const_ram_table[s0];
        (void)const_ram_table[s1];
        asm volatile("" : : : "memory");
    }

    // Pattern 24: Store then Load, Same Address (round-trip through encrypted RAM)
    INSERT_MARKER(24);
    for (int i = 0; i < 16; i++) {
        uint32_t s0 = shares[i][0];
        uint32_t s1 = shares[i][1];
        test_ram_table[0x40] = (uint8_t)s0;
        (void)test_ram_table[0x40];
        test_ram_table[0x40] = (uint8_t)s1;
        (void)test_ram_table[0x40];
        asm volatile("" : : : "memory");
    }

    // Pattern 25: Accumulate Into One Register (regfile writeback path)
    INSERT_MARKER(25);
    for (int i = 0; i < 16; i++) {
        uint32_t s0 = shares[i][0];
        uint32_t s1 = shares[i][1];
        uint32_t acc = test_ram_table[s0];
        acc ^= test_ram_table[s1];
        (void)acc;
        asm volatile("" : : : "memory");
    }


    for (int i = 0; i < 4; i++) {
        prolead_regs.ciphertext_s0[i] = prolead_regs.plaintext_0[i];
        prolead_regs.ciphertext_s1[i] = prolead_regs.plaintext_1[i];
    }

    prolead_regs.done = 1;
    prolead_regs.reached_main = 0;
    while(1);
}

