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
    volatile uint32_t plaintext_0;
    volatile uint32_t plaintext_1;
    volatile uint32_t key_s0;
    volatile uint32_t key_s1;
    volatile uint32_t fresh;
    volatile uint32_t ciphertext_s0;
    volatile uint32_t ciphertext_s1;
    volatile uint32_t done;
    volatile uint32_t reached_main;
} prolead_regs_t;
volatile prolead_regs_t prolead_regs __attribute__((section(".prolead")));

void set_memcrypt_key(uint64_t key) {
    memcrypt_regs.key_high = (uint32_t)key;
    memcrypt_regs.key_low = (uint32_t) (key >> 32);
}

void set_memcrypt_rounds(uint32_t rounds) {
    memcrypt_regs.additional_rounds = rounds;
}

// Simple memcpy implementation for bare metal
void *memcpy(void *dest, const void *src, size_t n) {
    uint8_t *d = (uint8_t *)dest;
    const uint8_t *s = (const uint8_t *)src;
    while (n--) *d++ = *s++;
    return dest;
}

// Helper struct for accessing 64-bit integers as 32-bit parts
// RISC-V is Little Endian
typedef struct {
    uint32_t lo;
    uint32_t hi;
} uint64_parts;

// 64-bit Arithmetic Shift Left
// Called implicitly by gcc for uint64_t <<
unsigned long long __ashldi3(unsigned long long u, int b) {
    if (b == 0) return u;
    
    uint64_parts *p = (uint64_parts*)&u;
    uint32_t lo = p->lo;
    uint32_t hi = p->hi;
    
    uint32_t r_lo, r_hi;
    
    if (b < 32) {
        r_lo = lo << b;
        r_hi = (hi << b) | (lo >> (32 - b));
    } else if (b < 64) {
        r_lo = 0;
        r_hi = lo << (b - 32);
    } else {
        r_lo = 0;
        r_hi = 0;
    }
    
    unsigned long long result;
    uint64_parts *pr = (uint64_parts*)&result;
    pr->lo = r_lo;
    pr->hi = r_hi;
    return result;
}

// 64-bit Logical Shift Right
// Called implicitly by gcc for uint64_t >>
unsigned long long __lshrdi3(unsigned long long u, int b) {
    if (b == 0) return u;

    uint64_parts *p = (uint64_parts*)&u;
    uint32_t lo = p->lo;
    uint32_t hi = p->hi;
    
    uint32_t r_lo, r_hi;
    
    if (b < 32) {
        r_hi = hi >> b;
        r_lo = (lo >> b) | (hi << (32 - b));
    } else if (b < 64) {
        r_hi = 0;
        r_lo = hi >> (b - 32);
    } else {
        r_hi = 0;
        r_lo = 0;
    }
    
    unsigned long long result;
    uint64_parts *pr = (uint64_parts*)&result;
    pr->lo = r_lo;
    pr->hi = r_hi;
    return result;
}


#define NUM_SHARES 2

/****************************************************************************************************
*       Declares the internal randomness source of the emulator                                     *
*       (only if required, otherwise comment out)                                                   *
*       ! make sure that the linker file contains a .randomness section if you want to use it !     *
*****************************************************************************************************/



void __attribute__((optimize("O0"))) generate_shares(uint32_t* output_array) {
  output_array[0] = prolead_regs.fresh;
  output_array[1] = output_array[0] ^ prolead_regs.plaintext_0;
}

void __attribute__((optimize("O0"))) cipher(uint32_t* shares) {
    // Preamble: Load constants and shares using C
    register uint32_t const_a asm("t0") = 0xAAAAAAAA;
    register uint32_t const_h asm("t1") = 0xFFFF0000;
    register uint32_t const_l asm("t2") = 0x0000FFFF;


    register uint32_t s0 asm("a0");
    register uint32_t s1 asm("a1");

    // Temporary results mapped to registers to control allocation
    register uint32_t res1 asm("a2");
    register uint32_t res2 asm("a3");
    register uint32_t temp asm("t3") = (uint32_t)shares;
    
    // Diagnostic registers to test RF address/bitline leakage
    register uint32_t s0_alt asm("t4");
    register uint32_t s1_alt asm("t5");

    volatile uint32_t arr[2];

    asm volatile (
        // --- 0. Load Shares ----
        "lw %[s0], 0(%[temp])\n\t"     // Load shares[0] into s0 (a0)
        "lw %[s1], 4(%[temp])\n\t"     // Load shares[1] into s1 (a1)
        "mv %[s0_alt], %[s0]\n\t"      // Copy for alternative register tests
        "mv %[s1_alt], %[s1]\n\t"      

        // --- 1. Baseline & Symmetry Test ---
        "xor %[res1], %[s0], %[const_a]\n\t"   // Case 1: s0 ^ const_a (rs1=s0, rs2=const)
        "xor %[res1], %[const_a], %[s1]\n\t"   // Case 2: Swap operands (rs1=const, rs2=s0). Checks Port A vs B.

        // --- 2. Functional Unit vs. Data Path ---
        "add %[res1], %[s0], %[const_a]\n\t"   // Case 3: Does the Adder leak similarly?
        "and %[res1], %[s1], %[const_a]\n\t"   // Case 4: Does the AND gate leak?

        // --- 3. Register Index Dependency ---
        "xor %[res1], %[s0_alt], %[const_a]\n\t"   // Case 5: Use t4 instead of a0. Checks RF decoder/bitline leakage.

        // --- 4. Immediate Port (Bypass RF Port B) ---
        "xori %[res1], %[s0], 0x5AA\n\t" // Case 6: No RF Port B read.

        // --- 5. NOP-Isolated Control (Isolate Pipeline Transitions) ---
        "nop\n\t"
        "nop\n\t"
        "xor %[res1], %[s0], %[const_a]\n\t"   // Case 7: NOP-isolated XOR.
        "nop\n\t"
        "nop\n\t"

        // --- 6. RF Read to Zero (Control for Port Reads) ---
        "add x0, %[s0], x0\n\t"   // Case 10: Read s0 to x0.
        "add x0, %[s1], x0\n\t"   // Case 11: Read s1 to x0.

        // --- 7. Memory / LSU Transitions ---
        "sw %[s0], -4(sp)\n\t"    // Case 12: Store s0 to addr A
        "sw %[s1], -4(sp)\n\t"    // Case 13: Store s1 to addr A (Data transition, same tweak)
        "sw %[s0], -4(sp)\n\t"    // Reset addr A with s0
        "sw %[s1], -8(sp)\n\t"    // Case 14: Store s1 to addr B (Data transition, different tweak)
        "sw %[const_a], -12(sp)\n\t"   // Case 15: Store public constant to addr C

        // --- Original logic preserved for functional results ---
        "and %[res1], %[const_h], %[s0]\n\t"   // res1 = const_h & s0
        "and %[temp], %[const_l], %[s1]\n\t"   // temp = const_l & s1
        "or %[res1], %[res1], %[temp]\n\t"     // res1 = res1 | temp
        
        "and %[res2], %[const_l], %[s0]\n\t"   // res2 = const_l & s0
        "and %[temp], %[const_h], %[s1]\n\t"   // temp = const_h & s1
        "or %[res2], %[res2], %[temp]\n\t"    // res2 = res2 | temp
        
        // Transitional leakage when overwriting the same register
        "xor %[temp], %[res1], %[const_a]\n\t"   
        "xor %[temp], %[res2], %[const_a]\n\t"   

        // --- 9. Bitslicing Test (Interleaving & Permutation) ---
        // Goal: Test if bitsliced representation or the transformation leaks.
        "and %[res1], %[s0], %[const_h]\n\t"   // res1 = {share1[31:16], 0}
        "and %[temp], %[s1], %[const_l]\n\t"   // temp = {0, share2[15:0]}
        "or  %[res1], %[res1], %[temp]\n\t"    // res1 = {share1[31:16], share2[15:0]}

        "and %[res2], %[s1], %[const_h]\n\t"   // res2 = {share2[31:16], 0}
        "and %[temp], %[s0], %[const_l]\n\t"   // temp = {0, share1[15:0]}
        "or  %[res2], %[res2], %[temp]\n\t"    // res2 = {share2[31:16], share1[15:0]}

        "li  %[temp], 7\n\t"                   // Use register for shift amount N
        "sll %[res1], %[res1], %[temp]\n\t"    // {share1[31:16], share2[15:0]} << N (Register SLL)
        "srl %[res2], %[res2], %[temp]\n\t"    // {share2[31:16], share1[15:0]} >> N (Register SRL)

        // Parallel computation on shifted registers
        "xor  %[res1], %[res1], %[const_a]\n\t"
        "xor  %[res2], %[res2], %[const_a]\n\t"


        // --- 8. Final consecutive stores ---
        // "sw %[s0], 0(%[ptr_arr])\n\t"
        "sb %[s0], 0(%[ptr_arr])\n\t"
        "lw %[s0_alt], 0(%[ptr_arr])\n\t"
        "srli t0, %[s0], 8\n\t"
        "sb t0, 1(%[ptr_arr])\n\t"
        "lw %[s0_alt], 0(%[ptr_arr])\n\t"
        "srli t0, %[s0], 16\n\t"
        "sb t0, 2(%[ptr_arr])\n\t"
        "lw %[s0_alt], 0(%[ptr_arr])\n\t"
        "srli t0, %[s0], 24\n\t"
        "sb t0, 3(%[ptr_arr])\n\t"
        "lw %[s0_alt], 0(%[ptr_arr])\n\t"
        // "sw %[s1], 4(%[ptr_arr])\n\t"
        "sb %[s1], 0(%[ptr_arr])\n\t"
        "lw %[s1_alt], 0(%[ptr_arr])\n\t"
        "srli t0, %[s1], 8\n\t"
        "sb t0, 1(%[ptr_arr])\n\t"
        "lw %[s1_alt], 0(%[ptr_arr])\n\t"
        "srli t0, %[s1], 16\n\t"
        "sb t0, 2(%[ptr_arr])\n\t"
        "lw %[s1_alt], 0(%[ptr_arr])\n\t"
        "srli t0, %[s1], 24\n\t"
        "sb t0, 3(%[ptr_arr])\n\t"
        "lw %[s1_alt], 0(%[ptr_arr])\n\t"

        : [res1] "=&r" (res1), [res2] "=&r" (res2), [temp] "=&r" (temp),
          [s0] "+r" (s0), [s1] "+r" (s1), [s0_alt] "+r" (s0_alt), [s1_alt] "+r" (s1_alt)
        : [const_a] "r" (const_a), [const_h] "r" (const_h), [const_l] "r" (const_l),
          [ptr_arr] "r" (arr)
    );
}

uint32_t __attribute__((optimize("O0")))  recombine_shares(uint32_t* shares) {
  uint32_t result = 0;
  for (uint32_t share_index = 0; share_index < NUM_SHARES ; ++share_index) {
    result ^= shares[share_index];
  }
  return result;
}

void main() {
    prolead_regs.reached_main = 1;
    // Generate shares
    uint32_t shares[2];
    // generate_shares(shares);
    shares[0] = prolead_regs.plaintext_0;
    shares[1] = prolead_regs.plaintext_1;
    // Execute cipher
    cipher(shares);
    // Execute again, to see, if the peaks are identical
    cipher(shares);
    // Check result
    prolead_regs.ciphertext_s0 = shares[1];
    prolead_regs.ciphertext_s1 = shares[0];
    prolead_regs.done = 1;
    prolead_regs.reached_main = 0;
    // Loop forever
    while(1);
}