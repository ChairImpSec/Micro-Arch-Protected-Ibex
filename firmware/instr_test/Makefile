# Copyright (c) 2026 Niels Wieser, TU Darmstadt
# SPDX-License-Identifier: MIT

# Makefile for Ibex Simple System Firmware

PROG = firmware
SRCS = main.c crt0.S
OBJS = $(SRCS:.c=.o)
OBJS := $(OBJS:.S=.o)

CC_PREFIX ?= riscv32-none-elf-
CC = $(CC_PREFIX)gcc
OBJCOPY = $(CC_PREFIX)objcopy
OBJDUMP = $(CC_PREFIX)objdump

CFLAGS = -march=rv32imc -mabi=ilp32 -static -mcmodel=medany \
	 -Wall -g -Os -fvisibility=hidden -nostdlib -nostartfiles -ffreestanding \
	 -I.

ifeq ($(QEMU), 1)
CFLAGS += -DQEMU_MODE
LDFLAGS = -T link_qemu.ld -nostdlib -Wl,--no-warn-rwx-segments -Wl,-Map=$(PROG).map
else
LDFLAGS = -T link.ld -nostdlib -Wl,--no-warn-rwx-segments -Wl,-Map=$(PROG).map
endif

all: $(PROG).elf $(PROG).bin $(PROG).vmem $(PROG).s

$(PROG).elf: $(OBJS) link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) $(OBJS) -o $@

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

%.o: %.S
	$(CC) $(CFLAGS) -c $< -o $@

%.bin: %.elf
	$(OBJCOPY) -O binary $< $@

%.vmem: %.bin
	# Simple vmem generation: words in hex, one per line (optional, for Verilog $readmemh)
	hexdump -v -e '1/4 "%08x" "\n"' $< > $@

%.s:	%.elf
	$(OBJDUMP) -d $< > $@

qemu:
	$(MAKE) clean
	$(MAKE) QEMU=1 all
	qemu-system-riscv32 -M virt -display none -serial stdio -bios none -kernel $(PROG).elf

clean:
	rm -f $(OBJS) $(PROG).elf $(PROG).bin $(PROG).vmem $(PROG).map $(PROG).s

.PHONY: all clean
