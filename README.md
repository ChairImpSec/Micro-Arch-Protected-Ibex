# Micro-Architecturally Protected Ibex

This repository contains a modified version of the [Ibex](https://github.com/lowRISC/ibex) RISC-V core
that implements countermeasures against micro-architectural leakage.
It is based on upstream Ibex commit
[`05ef0e67`](https://github.com/lowRISC/ibex/commit/05ef0e67eb5eb767a5091e6ff9c5e69afba28a9d).
All changes relative to upstream are shown in
[this diff](https://github.com/ChairImpSec/Micro-Arch-Protected-Ibex/compare/05ef0e67eb5eb767a5091e6ff9c5e69afba28a9d...main).

## Repository Structure

| Path | Description |
| ---- | ----------- |
| [`rtl/`](rtl) | Ibex core RTL, extended with the countermeasures |
| [`synthesis_system/`](synthesis_system) | System used for evaluation: core, memories, memory encryption (`mem_crypt`) and the FPGA wrapper |
| [`firmware/`](firmware) | Bare-metal test programs (see [Firmware](#firmware)) |
| [`generate_rtl.sh`](generate_rtl.sh) | Collects the RTL sources of the synthesis system for synthesis |

Everything else is inherited unchanged from upstream Ibex.
For general documentation of the core, refer to the [Ibex user manual](https://ibex-core.readthedocs.io/en/latest/).

## Prerequisites

* [FuseSoC](https://github.com/olofk/fusesoc) and [Verilator](https://www.veripool.org/verilator/)
* Python 3 (`pip3 install -r python-requirements.txt`)
* A `riscv32-none-elf` GCC toolchain for the firmware.
  Each firmware directory provides a Nix environment (`nix develop` or `nix-shell`) that supplies it.
* For the results in our work: Synopsys Design Compiler with the Nangate 45 nm library and Xilinx Vivado 2025.2 were used.

## Building

### Firmware

The synthesis system initializes its ROM from `firmware/aes/firmware.mem`, so build the firmware first:

```sh
cd firmware/aes
nix develop   # or provide riscv32-none-elf-gcc yourself
make
```

To use a different program, change `INIT_FILE` in
[`synthesis_system/rtl/vivado_wrapper.sv`](synthesis_system/rtl/vivado_wrapper.sv).

### ASIC Synthesis

The FuseSoC core `lowrisc:ibex:synthesis_system` describes the full system.
The results in our work were produced with Synopsys Design Compiler:

```sh
./generate_rtl.sh
```

This runs the FuseSoC lint target to resolve the source list and then writes `ibex_sources.tcl`,
which can be sourced in Design Compiler to read all RTL files, include directories and defines.

### FPGA

For FPGA targets, we first synthesized the CPU with Design Compiler.
We then imported the resulting netlist into Vivado 2025.2 and replaced the Nangate 45 cells
with FPGA equivalents ([`synthesis_system/rtl/*_gate.v`, `*_cell.v`](synthesis_system/rtl)).
The top level module for vivado is [`vivado_wrapper.sv`](synthesis_system/rtl/vivado_wrapper.sv), while the top level module for synopsys is [`vivado_cpu.sv`](synthesis_system/rtl/vivado_cpu.sv).

## Firmware

Each directory under [`firmware/`](firmware) is a self-contained program with its own `Makefile`, linker script and startup code.
Running `make` produces `firmware.elf`, `.bin`, `.vmem`, `.mem` (ROM image) and a disassembly listing `.s`.

| Directory | Description |
| --------- | ----------- |
| [`aes/`](firmware/aes) | First-order masked AES (Rivain–Prouff S-box), based on the [PROLEAD](https://github.com/ChairImpSec/PROLEAD) examples |
| [`compact/`](firmware/compact) | A compact test to test specific worst case scenarios |
| [`memory_test/`](firmware/memory_test) | Memory access-pattern leakage test |
| [`instr_test/`](firmware/instr_test) | Instruction functional test; `make qemu` runs it on QEMU |


## Publications

*Coming soon.*

## Contact and Support

If you have questions or comments, or if you find a bug, please contact
[Niels Wieser](https://github.com/Niels-ImpSec) ([niels.wieser@tu-darmstadt.de](mailto:niels.wieser@tu-darmstadt.de)).

## License

This repository combines code under several licenses.
Each file states its license in an `SPDX-License-Identifier` header, and the full texts are in [`LICENSES/`](LICENSES).

* **Upstream Ibex:** Apache License, Version 2.0 (see [LICENSE](LICENSE) and [NOTICE](NOTICE)).
  This applies to all files without a header of their own, and to files we modified from upstream.
  Those carry an additional "Modified by" note, including the protected core in [`rtl/`](rtl).
* **New contributions** of this work, such as the memory encryption system, cell models, firmware and scripts:
  [MIT](LICENSES/MIT.txt).
* **Third-party components**, included under their original licenses:

| Files | Origin | License |
| ----- | ------ | ------- |
| [`synthesis_system/rtl/cipher_beanie.sv`](synthesis_system/rtl/cipher_beanie.sv), [`synthesis_system/rtl/tweakey.sv`](synthesis_system/rtl/tweakey.sv) | [BEANIE reference hardware](https://github.com/NXP-Research/beanie_cipher), NXP | [CC-BY-SA-4.0](LICENSES/CC-BY-SA-4.0.txt) |
| [`firmware/aes/main.c`](firmware/aes/main.c) | [PROLEAD](https://github.com/ChairImpSec/PROLEAD) AES example (Rivain–Prouff masked AES) | [BSD-3-Clause](LICENSES/BSD-3-Clause.txt) |
| [`firmware/compact/aes_sbox.S`](firmware/compact/aes_sbox.S) | [coco-alma](https://github.com/IAIK/coco-alma), IAIK, Graz University of Technology | [Apache-2.0](LICENSE) |
