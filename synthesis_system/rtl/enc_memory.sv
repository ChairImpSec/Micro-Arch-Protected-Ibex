// Copyright (c) 2026 Niels Wieser, TU Darmstadt
// SPDX-License-Identifier: MIT

`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: enc_memory
// Description: Encrypted RAM. Drop-in replacement for a `memory` RAM instance:
//   it exposes the same dual-port data interface (port A read-only, port B
//   read/write) plus a cipher-config MMIO interface, and internally wraps
//   mem_crypt (the on-the-fly memory encryption engine) around a plain `memory`
//   used as the ciphertext backing store (LUT distributed RAM by default).
//
//   Data path:
//     port B  <->  mem_crypt CPU interface  <->  mem_crypt RAM interface
//                                                       |
//                                                 internal `memory` (MEM_STYLE)
//
//   mem_crypt is multi-cycle (loads take 2 cycles, stores/RMW more); the Ibex
//   bus/core tolerate a delayed rvalid, so B_RVALID (= mem_crypt cpu_done) may
//   arrive several cycles after the request.
//
//   Port A is not used by the encrypted RAM (the RAM is only reached over the
//   data bus) and is tied off.
//////////////////////////////////////////////////////////////////////////////////

module enc_memory #(
    // Encryption backend: "CRYPT" (mem_crypt block cipher) or "PRNG"
    parameter     ENGINE    = "CRYPT",
    // Implementation style of the internal ciphertext RAM ("BRAM"|"LUT"|"FF").
    parameter     MEM_STYLE = "LUT",
    parameter int DEPTH     = 1024,
    parameter int ADDR_W    = $clog2(DEPTH)
)(
    input  logic        CLK,
    input  logic        RST_N,
    output logic        BUSY,

    // Fresh randomness for the PRNG (secret-sharing) module. Sampled from
    // Fresh[31:0] in the wrapper; used as the one-time mask on stores. Ignored
    // by the CRYPT engine.
    input  logic [31:0] RND,

    // Port A (read only, unused)
    input  logic [31:0] A_ADDR,
    input  logic [ 3:0] A_WE,
    input  logic [31:0] A_WDATA,
    input  logic        A_RE,
    output logic [31:0] A_RDATA,
    output logic        A_RVALID,

    // Port B (data, encrypted). Byte address (not word index) so the cipher can
    // use the full address as its tweak.
    input  logic [31:0] B_ADDR,
    input  logic [ 3:0] B_WE,
    input  logic [31:0] B_WDATA,
    input  logic        B_RE,
    output logic [31:0] B_RDATA,
    output logic        B_RVALID,

    // Cipher configuration (MMIO): key / additional rounds
    input  logic [31:0] cfg_addr_i,
    input  logic        cfg_req_i,
    input  logic        cfg_wr_en_i,
    input  logic [31:0] cfg_wdata_i,
    output logic [31:0] cfg_rdata_o,
    output logic        cfg_rvalid_o
);

  // Internal (ciphertext) RAM interface between mem_crypt and the backing store.
  logic [31:0] ram_addr;
  logic [31:0] ram_wdata;
  logic [ 3:0] ram_be;
  logic        ram_we;
  logic        ram_re;
  logic [31:0] ram_rdata;
  logic        ram_rvalid;

  // Second RAM (mask / share1) interface, used only by the PRNG module.
  logic [31:0] ram2_wdata;
  logic [31:0] ram2_rdata;

  // --- Memory encryption (block cipher or PRNG one-time pad) ---
  // Both backends share the exact same interface.
  generate
    if (ENGINE == "PRNG") begin : g_prng
      mem_prng u_engine (
        .clk_i        (CLK),
        .rst_ni       (RST_N),
        // Config (MMIO)
        .cfg_addr_i   (cfg_addr_i),
        .cfg_req_i    (cfg_req_i),
        .cfg_wr_en_i  (cfg_wr_en_i),
        .cfg_wdata_i  (cfg_wdata_i),
        .cfg_rdata_o  (cfg_rdata_o),
        .cfg_rvalid_o (cfg_rvalid_o),
        // CPU interface (mapped from the port-B data interface)
        .cpu_addr_i   (B_ADDR),
        .cpu_wdata_i  (B_WDATA),
        .cpu_be_i     (B_WE),
        .cpu_we_i     (|B_WE),
        .cpu_req_i    (B_RE | (|B_WE)),
        .cpu_rdata_o  (B_RDATA),
        .cpu_done_o   (B_RVALID),
        // Fresh randomness (one-time mask)
        .rnd_i        (RND),
        // Ciphertext (share0) RAM interface
        .ram_addr_o   (ram_addr),
        .ram_wdata_o  (ram_wdata),
        .ram_be_o     (ram_be),
        .ram_we_o     (ram_we),
        .ram_re_o     (ram_re),
        .ram_rdata_i  (ram_rdata),
        .ram_rvalid_i (ram_rvalid),
        // Second (mask / share1) RAM interface
        .ram2_wdata_o (ram2_wdata),
        .ram2_rdata_i (ram2_rdata)
      );

      // --- Second ciphertext RAM (mask / share1 store) ---
      // Identical size and timing to the main RAM; shares the address, byte
      // enables, write- and read-enable, so a load reads both shares in lockstep.
      memory #(
        .MEM_STYLE     (MEM_STYLE),
        .DEPTH         (DEPTH),
        .CLEAR_ON_RESET(1),
        .RESET_START   (0),
        .RESET_DEPTH   (DEPTH),
        .INIT_FILE     ("")
      ) u_ram2 (
        .CLK   (CLK),
        .RST_N (RST_N),
        .BUSY  (),

        // Port A: unused
        .A_ADDR  (32'b0),
        .A_WE    (4'b0),
        .A_WDATA (32'b0),
        .A_RE    (1'b0),
        .A_RDATA (),
        .A_RVALID(),

        // Port B: mask store (same decode/control as the main RAM)
        .B_ADDR  ({2'b0, ram_addr[31:2]}),
        .B_WE    (ram_we ? ram_be : 4'b0),
        .B_WDATA (ram2_wdata),
        .B_RE    (ram_re),
        .B_RDATA (ram2_rdata),
        .B_RVALID()
      );
    end else begin : g_crypt
      // CRYPT engine does not use the second (mask) RAM.
      assign ram2_wdata = 32'b0;
      assign ram2_rdata = 32'b0;
      mem_crypt u_engine (
        .clk_i        (CLK),
        .rst_ni       (RST_N),
        // Config (MMIO)
        .cfg_addr_i   (cfg_addr_i),
        .cfg_req_i    (cfg_req_i),
        .cfg_wr_en_i  (cfg_wr_en_i),
        .cfg_wdata_i  (cfg_wdata_i),
        .cfg_rdata_o  (cfg_rdata_o),
        .cfg_rvalid_o (cfg_rvalid_o),
        // CPU interface (mapped from the port-B data interface)
        .cpu_addr_i   (B_ADDR),
        .cpu_wdata_i  (B_WDATA),
        .cpu_be_i     (B_WE),
        .cpu_we_i     (|B_WE),
        .cpu_req_i    (B_RE | (|B_WE)),
        .cpu_rdata_o  (B_RDATA),
        .cpu_done_o   (B_RVALID),
        // Ciphertext RAM interface
        .ram_addr_o   (ram_addr),
        .ram_wdata_o  (ram_wdata),
        .ram_be_o     (ram_be),
        .ram_we_o     (ram_we),
        .ram_re_o     (ram_re),
        .ram_rdata_i  (ram_rdata),
        .ram_rvalid_i (ram_rvalid)
      );
    end
  endgenerate

  // --- Internal ciphertext RAM ---
  // mem_crypt drives a byte address on ram_addr; convert it to the word index
  // the `memory` port expects (memory uses B_ADDR[ADDR_W-1:0]).
  memory #(
    .MEM_STYLE     (MEM_STYLE),
    .DEPTH         (DEPTH),
    .CLEAR_ON_RESET(1),
    .RESET_START   (0),
    .RESET_DEPTH   (DEPTH),
    .INIT_FILE     ("")
  ) u_ram (
    .CLK   (CLK),
    .RST_N (RST_N),
    .BUSY  (BUSY),

    // Port A: unused
    .A_ADDR  (32'b0),
    .A_WE    (4'b0),
    .A_WDATA (32'b0),
    .A_RE    (1'b0),
    .A_RDATA (),
    .A_RVALID(),

    // Port B: ciphertext store
    .B_ADDR  ({2'b0, ram_addr[31:2]}),
    .B_WE    (ram_we ? ram_be : 4'b0),
    .B_WDATA (ram_wdata),
    .B_RE    (ram_re),
    .B_RDATA (ram_rdata),
    .B_RVALID(ram_rvalid)
  );

  // Port A of the encrypted RAM is unused.
  assign A_RDATA  = 32'b0;
  assign A_RVALID = 1'b0;

endmodule
