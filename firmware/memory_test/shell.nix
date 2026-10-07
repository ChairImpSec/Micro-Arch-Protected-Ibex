# Copyright (c) 2026 Niels Wieser, TU Darmstadt
# SPDX-License-Identifier: MIT

{ pkgs ? import <nixpkgs> {} }:
let
  pkgsRV32 = import <nixpkgs> {
    crossSystem = {
      config = "riscv32-none-elf";
    };
  };
in
pkgs.mkShell {
  buildInputs = [
    pkgs.gnumake
    pkgsRV32.stdenv.cc
    pkgs.python3
    pkgs.srecord
    pkgs.hexdump
  ];
}
