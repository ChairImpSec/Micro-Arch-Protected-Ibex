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
    volatile uint32_t plaintext_0;
    volatile uint32_t plaintext_1;
    volatile uint32_t key_s0;
    volatile uint32_t key_s1;
    volatile uint32_t fresh;
    volatile uint32_t ciphertext_s0;
    volatile uint32_t ciphertext_s1;
    volatile uint32_t done;
} prolead_regs_t;
volatile prolead_regs_t prolead_regs __attribute__((section(".prolead")));

// Global signature to accumulate test results
volatile uint32_t signature = 0;

#ifdef QEMU_MODE
// QEMU virt machine UART (NS16550A)
#define UART_BASE 0x10000000
#define UART_DATA (*(volatile uint8_t *)(UART_BASE + 0x0))
#define UART_LSR  (*(volatile uint8_t *)(UART_BASE + 0x5))
#define UART_LSR_THRE 0x20

void uart_putc(char c) {
    while ((UART_LSR & UART_LSR_THRE) == 0);
    UART_DATA = c;
}

void print(const char *str) {
    while (*str) {
        uart_putc(*str++);
    }
}

void print_hex(uint32_t val) {
    for (int i = 7; i >= 0; i--) {
        uint32_t digit = (val >> (i * 4)) & 0xF;
        if (digit < 10) uart_putc('0' + digit);
        else uart_putc('A' + (digit - 10));
    }
}
#endif



void set_memcrypt_key(uint64_t key) {
    memcrypt_regs.key_high = (uint32_t)key;
    memcrypt_regs.key_low = (uint32_t) (key >> 32);
}

void set_memcrypt_rounds(uint32_t rounds) {
    memcrypt_regs.additional_rounds = rounds;
}



// Helper to update signature
static inline void update_sig(uint32_t val) {
    signature ^= val;
    signature = (signature << 1) | (signature >> 31);
#ifdef QEMU_MODE
    print("Updated sig to: 0x");
    print_hex(signature);
    print("\r\n");
#endif
}

void test_rv32i_arithmetic() {
    uint32_t a = 0x12345678;
    uint32_t b = 0x87654321;
    uint32_t res;

    // ADD
    asm volatile ("add %0, %1, %2" : "=r"(res) : "r"(a), "r"(b));
    update_sig(res);

    // SUB
    asm volatile ("sub %0, %1, %2" : "=r"(res) : "r"(a), "r"(b));
    update_sig(res);

    // ADDI
    asm volatile ("addi %0, %1, 123" : "=r"(res) : "r"(a));
    update_sig(res);
}

void test_rv32i_logical() {
    uint32_t a = 0xAAAAAAAA;
    uint32_t b = 0x55555555;
    uint32_t res;

    // XOR
    asm volatile ("xor %0, %1, %2" : "=r"(res) : "r"(a), "r"(b));
    update_sig(res);

    // OR
    asm volatile ("or %0, %1, %2" : "=r"(res) : "r"(a), "r"(b));
    update_sig(res);

    // AND
    asm volatile ("and %0, %1, %2" : "=r"(res) : "r"(a), "r"(b));
    update_sig(res);

    // XORI, ORI, ANDI
    asm volatile ("xori %0, %1, 0x3FF" : "=r"(res) : "r"(a));
    update_sig(res);
    asm volatile ("ori %0, %1, 0x3FF" : "=r"(res) : "r"(a));
    update_sig(res);
    asm volatile ("andi %0, %1, 0x3FF" : "=r"(res) : "r"(a));
    update_sig(res);
}

void test_rv32i_shifts() {
    uint32_t a = 0x12345678;
    uint32_t b = 5;
    uint32_t res;

    // SLL, SRL, SRA
    asm volatile ("sll %0, %1, %2" : "=r"(res) : "r"(a), "r"(b));
    update_sig(res);
    asm volatile ("srl %0, %1, %2" : "=r"(res) : "r"(a), "r"(b));
    update_sig(res);
    asm volatile ("sra %0, %1, %2" : "=r"(res) : "r"(a), "r"(b));
    update_sig(res);

    // SLLI, SRLI, SRAI
    asm volatile ("slli %0, %1, 3" : "=r"(res) : "r"(a));
    update_sig(res);
    asm volatile ("srli %0, %1, 3" : "=r"(res) : "r"(a));
    update_sig(res);
    asm volatile ("srai %0, %1, 3" : "=r"(res) : "r"(a));
    update_sig(res);
}

void test_rv32i_compare() {
    int32_t a = -100;
    int32_t b = 100;
    uint32_t res;

    // SLT
    asm volatile ("slt %0, %1, %2" : "=r"(res) : "r"(a), "r"(b));
    update_sig(res);
    // SLTU
    asm volatile ("sltu %0, %1, %2" : "=r"(res) : "r"((uint32_t)a), "r"((uint32_t)b));
    update_sig(res);
    // SLTI
    asm volatile ("slti %0, %1, -50" : "=r"(res) : "r"(a));
    update_sig(res);
    // SLTIU
    asm volatile ("sltiu %0, %1, 50" : "=r"(res) : "r"((uint32_t)a));
    update_sig(res);
}

void test_rv32i_lui_auipc() {
    uint32_t res, pc;
    asm volatile ("lui %0, 0x12345" : "=r"(res));
    update_sig(res);
    
    // Make AUIPC test address-independent by calculating the difference
    asm volatile ("auipc %0, 0" : "=r"(pc));
    asm volatile ("auipc %0, 0x1" : "=r"(res));
    update_sig(res - pc);
}

void test_rv32i_memory() {
    volatile uint32_t mem_space[2] = {0x11223344, 0x55667788};
    uint32_t res;

    // LW
    asm volatile ("lw %0, 0(%1)" : "=r"(res) : "r"(&mem_space[0]));
    update_sig(res);

    // LH, LHU
    asm volatile ("lh %0, 0(%1)" : "=r"(res) : "r"(&mem_space[0]));
    update_sig(res);
    asm volatile ("lhu %0, 2(%1)" : "=r"(res) : "r"(&mem_space[0]));
    update_sig(res);

    // LB, LBU
    asm volatile ("lb %0, 0(%1)" : "=r"(res) : "r"(&mem_space[0]));
    update_sig(res);
    asm volatile ("lbu %0, 1(%1)" : "=r"(res) : "r"(&mem_space[0]));
    update_sig(res);

    // SW, SH, SB
    uint32_t test_val = 0xAABBCCDD;
    asm volatile ("sw %1, 4(%0)" :: "r"(&mem_space[0]), "r"(test_val));
    update_sig(mem_space[1]);
    
    asm volatile ("sh %1, 0(%0)" :: "r"(&mem_space[0]), "r"(test_val));
    update_sig(mem_space[0]);

    asm volatile ("sb %1, 3(%0)" :: "r"(&mem_space[0]), "r"(test_val));
    update_sig(mem_space[0]);
}

void test_rv32i_branches() {
    uint32_t a = 10, b = 20;
    uint32_t res = 0;

    // BEQ (Not taken)
    asm volatile (
        "beq %1, %2, 1f\n"
        "addi %0, %0, 1\n" // Executed
        ".balign 4\n"
        "1:"
        : "+r"(res) : "r"(a), "r"(b)
    );
    update_sig(res);

    // BEQ (Taken)
    asm volatile (
        "beq %1, %1, 1f\n"
        "addi %0, %0, 10\n" // Skipped
        ".balign 4\n"
        "1:"
        "addi %0, %0, 1\n"
        : "+r"(res) : "r"(a)
    );
    update_sig(res);

    // BNE (Taken)
    asm volatile (
        "bne %1, %2, 1f\n"
        "addi %0, %0, 10\n" // Skipped
        ".balign 4\n"
        "1:"
        "addi %0, %0, 1\n"
        : "+r"(res) : "r"(a), "r"(b)
    );
    update_sig(res);

    // BLT (Taken: 10 < 20)
    asm volatile (
        "blt %1, %2, 1f\n"
        "addi %0, %0, 10\n" // Skipped
        ".balign 4\n"
        "1:"
        "addi %0, %0, 1\n"
        : "+r"(res) : "r"(a), "r"(b)
    );
    update_sig(res);

    // BGE (Not taken: 10 >= 20)
    asm volatile (
        "bge %1, %2, 1f\n"
        "addi %0, %0, 1\n" // Executed
        ".balign 4\n"
        "1:"
        : "+r"(res) : "r"(a), "r"(b)
    );
    update_sig(res);

    // BGE (Taken: 20 >= 10)
    asm volatile (
        "bge %2, %1, 1f\n"
        "addi %0, %0, 10\n" // Skipped
        ".balign 4\n"
        "1:"
        "addi %0, %0, 1\n"
        : "+r"(res) : "r"(a), "r"(b)
    );
    update_sig(res);

    // BLTU (Taken: 10 < 20 unsigned)
    asm volatile (
        "bltu %1, %2, 1f\n"
        "addi %0, %0, 10\n" // Skipped
        ".balign 4\n"
        "1:"
        "addi %0, %0, 1\n"
        : "+r"(res) : "r"(a), "r"(b)
    );
    update_sig(res);

    // BGEU (Taken: 20 >= 10 unsigned)
    asm volatile (
        "bgeu %2, %1, 1f\n"
        "addi %0, %0, 10\n" // Skipped
        ".balign 4\n"
        "1:"
        "addi %0, %0, 1\n"
        : "+r"(res) : "r"(a), "r"(b)
    );
    update_sig(res);
}

void test_rv32i_jumps() {
    uint32_t res = 0;
    uint32_t link = 0;
    uint32_t target_addr;

    // JAL
    // link should be (Target - 4) because we skip one 4-byte instruction
    asm volatile (
        ".option push\n"
        ".option norvc\n"
        "la %2, 1f\n"
        "jal %0, 1f\n"
        "addi %1, %1, 100\n" // Skipped
        "1:\n"
        "addi %1, %1, 1\n"
        ".option pop"
        : "=&r"(link), "+r"(res), "=&r"(target_addr)
    );
    update_sig(res);
    update_sig(target_addr - link); // Should be 4

    // JALR
    res = 0;
    // link should be (Target - 4)
    asm volatile (
        ".option push\n"
        ".option norvc\n"
        "la %0, 2f\n"
        "jalr %1, %0, 0\n"
        "addi %2, %2, 100\n" // Skipped
        "2:\n"
        "addi %2, %2, 1\n"
        ".option pop"
        : "=&r"(target_addr), "=&r"(link), "+r"(res)
    );
    update_sig(res);
    update_sig(target_addr - link); // Should be 4
}

void test_rv32m() {
    uint32_t a = 0x1234, b = 0x5678;
    int32_t sa = -0x1234, sb = 0x5678;
    uint32_t res;

    // MUL
    asm volatile ("mul %0, %1, %2" : "=r"(res) : "r"(a), "r"(b));
    update_sig(res);

    // MULH, MULHU, MULHSU
    asm volatile ("mulh %0, %1, %2" : "=r"(res) : "r"(sa), "r"(sb));
    update_sig(res);
    asm volatile ("mulhu %0, %1, %2" : "=r"(res) : "r"(a), "r"(b));
    update_sig(res);
    asm volatile ("mulhsu %0, %1, %2" : "=r"(res) : "r"(sa), "r"(b));
    update_sig(res);

    // DIV, DIVU, REM, REMU
    asm volatile ("div %0, %1, %2" : "=r"(res) : "r"(sa), "r"(sb));
    update_sig(res);
    asm volatile ("divu %0, %1, %2" : "=r"(res) : "r"(a), "r"(b));
    update_sig(res);
    asm volatile ("rem %0, %1, %2" : "=r"(res) : "r"(sa), "r"(sb));
    update_sig(res);
    asm volatile ("remu %0, %1, %2" : "=r"(res) : "r"(a), "r"(b));
    update_sig(res);
}

void main() {
#ifdef QEMU_MODE
    print("Starting instruction tests in QEMU...\r\n");
#else
    set_memcrypt_rounds(1);
    set_memcrypt_key(0x0123456789ABCDEF);
#endif

    signature = 0;

    test_rv32i_arithmetic();
#ifdef QEMU_MODE
    print("Arithmetic tests done.\r\n");
#endif

    test_rv32i_logical();
#ifdef QEMU_MODE
    print("Logical tests done.\r\n");
#endif

    test_rv32i_shifts();
#ifdef QEMU_MODE
    print("Shift tests done.\r\n");
#endif

    test_rv32i_compare();
#ifdef QEMU_MODE
    print("Comparison tests done.\r\n");
#endif

    test_rv32i_lui_auipc();
#ifdef QEMU_MODE
    print("LUI/AUIPC tests done.\r\n");
#endif

    test_rv32i_memory();
#ifdef QEMU_MODE
    print("Memory tests done.\r\n");
#endif

    test_rv32i_branches();
#ifdef QEMU_MODE
    print("Branch tests done.\r\n");
#endif

    test_rv32i_jumps();
#ifdef QEMU_MODE
    print("Jump tests done.\r\n");
#endif

    test_rv32m();
#ifdef QEMU_MODE
    print("RV32M tests done.\r\n");
#endif

    // Write final result to the designated memory location
    prolead_regs.ciphertext_s0 = signature;
    prolead_regs.done = 1;

#ifdef QEMU_MODE
    print("Final Golden Signature: 0x");
    print_hex(signature);
    print("\r\n");
#endif

    while(1);
}
