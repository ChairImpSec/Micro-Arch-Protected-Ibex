# Copyright (c) 2026 Niels Wieser, TU Darmstadt
# SPDX-License-Identifier: MIT

{
  description = "Ibex Firmware Development Environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        # Cross-compiler for bare-metal RISC-V 32-bit
        pkgsRV32 = import nixpkgs {
          inherit system;
          crossSystem = {
            config = "riscv32-none-elf";
          };
        };
      in
      {
        devShells.default = pkgs.mkShell {
          name = "ibex-firmware-shell";
          
          # Native tools (run on the host)
          nativeBuildInputs = [
            pkgs.gnumake
            pkgsRV32.stdenv.cc
            pkgs.srecord    # For advanced VMEM generation if needed
            pkgs.hexdump    # Used in the current Makefile
          ];

          shellHook = ''
            echo "Ibex Firmware Dev Shell"
            echo "Compiler: $(riscv32-none-elf-gcc --version | head -n 1)"
          '';
        };
      }
    );
}