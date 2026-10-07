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
	 -Wall -g -Os -fvisibility=hidden -nostdlib -nostartfiles -ffreestanding

LDFLAGS = -T link.ld -nostdlib -Wl,--no-warn-rwx-segments -Wl,-Map=$(PROG).map

all: $(PROG).elf $(PROG).bin $(PROG).vmem $(PROG).mem $(PROG).s

$(PROG).elf: $(OBJS) link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) $(OBJS) -o $@

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

%.o: %.S
	$(CC) $(CFLAGS) -c $< -o $@

%.bin: %.elf
	$(OBJCOPY) -O binary $< $@

%.vmem: %.elf
	# 1. Use -R to prevent the physical aliasing of memcrypt/prolead from overwriting .vectors
	$(OBJCOPY) -O verilog -R .memcrypt -R .prolead $< $@.tmp
	# 2. Exact hardware mapping: word_index = {addr[16], addr[13:2]}
	python3 -c "import sys; [sys.stdout.write(f'@{(((int(l[1:], 16) >> 16) & 1) << 12) | ((int(l[1:], 16) >> 2) & 0xFFF):04x}\\n') if l.startswith('@') else sys.stdout.write(l) for l in open('$@.tmp')]" > $@
	rm $@.tmp

%.mem: %.vmem
	# 3. Flatten into 16384 words. We multiply the word address marker by 4 (* 4) 
	# to place it correctly into the 65536-byte array before chunking it back out.
	python3 -c "import sys; m=['00']*65536; a=[0]; [((a.__setitem__(0, int(p[0][1:], 16) * 4), [(m.__setitem__(a[0], b), a.__setitem__(0, a[0]+1)) for b in p[1:] if a[0]<65536]) if p[0].startswith('@') else [(m.__setitem__(a[0], b), a.__setitem__(0, a[0]+1)) for b in p if a[0]<65536]) for p in [l.split() for l in open('$<') if l.strip()]]; sys.stdout.write('\n'.join([''.join(m[i:i+4][::-1]) for i in range(0, 65536, 4)]) + '\n')" > $@

%.s:	%.elf
	$(OBJDUMP) -dS $< > $@


clean:
	rm -f $(OBJS) $(PROG).elf $(PROG).bin $(PROG).vmem $(PROG).map $(PROG).s

.PHONY: all clean
