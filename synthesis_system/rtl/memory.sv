// Copyright (c) 2026 Niels Wieser, TU Darmstadt
// SPDX-License-Identifier: MIT

`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: memory
// Description: Unified dual-port memory with a selectable FPGA implementation.
//
//   MEM_STYLE selects how the storage is built (FPGA / simulation):
//     "BRAM" : inferred block RAM        (ram_style = "block")
//     "LUT"  : inferred distributed RAM  (ram_style = "distributed")
//     "FF"   : register file from FDRE cells with byte-enabled, two-phase
//              (clear-then-write) stores and one-hot addressing.
//   TARGET_ASIC overrides all styles with a custom_sram blackbox.
//
//   Port A is read-only (e.g. instruction fetch); port B is read/write (e.g.
//   data). All three styles share this interface, so a single-port user just
//   drives port B and ties port A off.
//
//   BRAM/LUT: the array is initialised from INIT_FILE and can be zeroed by a
//   reset-clearing FSM (CLEAR_ON_RESET), which pulses BUSY while it runs.
//   FF: has no init file and clears itself through the FDRE reset in one cycle
//   (CLEAR_ON_RESET is ignored, BUSY stays low).
//////////////////////////////////////////////////////////////////////////////////

module memory #(
    parameter              MEM_STYLE      = "BRAM",
    parameter int          DEPTH          = 1024,
    parameter int          ADDR_W         = $clog2(DEPTH),
    parameter int          RESET_START    = 0,
    parameter int          RESET_DEPTH    = DEPTH,
    // BRAM/LUT only: run the reset-clearing FSM. FF self-clears and ignores it.
    parameter bit          CLEAR_ON_RESET = 1,
    // BRAM/LUT only: hex image loaded into the array at time 0.
    parameter              INIT_FILE      = "firmware/aes/firmware.mem"
)(
    input  logic        CLK,
    input  logic        RST_N,
    output logic        BUSY,

    // Port A (read only)
    input  logic [31:0] A_ADDR,
    input  logic [ 3:0] A_WE,
    input  logic [31:0] A_WDATA,
    input  logic        A_RE,
    output logic [31:0] A_RDATA,
    output logic        A_RVALID,

    // Port B (read / write)
    input  logic [31:0] B_ADDR,
    input  logic [ 3:0] B_WE,
    input  logic [31:0] B_WDATA,
    input  logic        B_RE,
    output logic [31:0] B_RDATA,
    output logic        B_RVALID
);

`ifdef TARGET_ASIC
    // ---------------------------------------------------------------------
    // ASIC: SRAM blackbox for all styles.
    // ---------------------------------------------------------------------
    assign BUSY = 1'b0;

    custom_sram #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .MEMSIZE(DEPTH)
    ) u_ram (
      .CLK    (CLK),
      // Port A
      .A1ADDR (A_ADDR), .A1EN (A_WE), .A1DATA (A_WDATA),
      .B1ADDR (A_ADDR), .B1EN (A_RE), .B1DATA (A_RDATA),
      // Port B
      .A2ADDR (B_ADDR), .A2EN (B_WE), .A2DATA (B_WDATA),
      .B2ADDR (B_ADDR), .B2EN (B_RE), .B2DATA (B_RDATA)
    );

    always_ff @(posedge CLK or negedge RST_N) begin
      if (!RST_N) begin
        A_RVALID <= 1'b0;
        B_RVALID <= 1'b0;
      end else begin
        A_RVALID <= A_RE;
        B_RVALID <= B_RE | (|B_WE);
      end
    end
`else
  generate
    if (MEM_STYLE == "FF") begin : g_ff
      // -----------------------------------------------------------------
      // FF: register file from FDRE cells.
      //
      // Port B writes are split across the two clock cycles of the Ibex
      // store handshake:
      //   * Phase 1 (request live): the addressed byte lanes are cleared to
      //     0 via the FDRE reset (R); address/byte-enables/data are latched.
      //   * Phase 2 (next cycle): the latched data is written via the FDRE
      //     clock-enable (CE).
      // Only byte lanes selected by B_WE are touched. The global RST_N clears
      // the whole array through the same FDRE R input, so no clearing FSM is
      // needed. Port A is read-only.
      // -----------------------------------------------------------------
      assign BUSY = 1'b0;

      logic [ADDR_W-1:0] a_idx, b_idx;
      assign a_idx = A_ADDR[ADDR_W-1:0];
      assign b_idx = B_ADDR[ADDR_W-1:0];

      logic any_web;
      assign any_web = |B_WE;

      // Phase-1 one-hot write decode (live). All-zero unless writing.
      logic [DEPTH-1:0] wr_sel_oh;
      always_comb begin
        wr_sel_oh = '0;
        if (any_web) wr_sel_oh[b_idx] = 1'b1;
      end

      // Phase-2 controls: latched one cycle after the request.
      logic [DEPTH-1:0] wr_sel_oh_q;
      logic [3:0]       wr_be_q;
      logic [31:0]      wr_data_q;
      always_ff @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
          wr_sel_oh_q <= '0;
          wr_be_q     <= '0;
          wr_data_q   <= '0;
        end else begin
          wr_sel_oh_q <= wr_sel_oh;
          wr_be_q     <= B_WE;
          wr_data_q   <= B_WDATA;
        end
      end

      // Storage: FDRE per bit, per-byte clear (phase 1) and write (phase 2).
      logic [31:0] mem_q [DEPTH];

      genvar w, b, bit_i;
      for (w = 0; w < DEPTH; w = w + 1) begin : gen_word
        for (b = 0; b < 4; b = b + 1) begin : gen_byte
          logic byte_clr, byte_wen, byte_rst;
          assign byte_clr = wr_sel_oh[w]   & B_WE[b];      // phase 1 (live)
          assign byte_wen = wr_sel_oh_q[w] & wr_be_q[b];   // phase 2 (latched)
          assign byte_rst = ~RST_N | byte_clr;             // global or pre-clear
          for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin : gen_bit
            FDRE #(.INIT(1'b0)) u_bit (
              .C  (CLK),
              .CE (byte_wen),
              .D  (wr_data_q[b*8 + bit_i]),
              .Q  (mem_q[w][b*8 + bit_i]),
              .R  (byte_rst)
            );
          end
        end
      end

      // Read ports: register the one-hot select, recombine with AND/OR.
      logic [DEPTH-1:0] rd_sel_a_q, rd_sel_b_q;
      always_ff @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
          rd_sel_a_q <= '0;
          rd_sel_b_q <= '0;
        end else begin
          rd_sel_a_q <= '0;
          rd_sel_b_q <= '0;
          if (A_RE) rd_sel_a_q[a_idx] <= 1'b1;
          if (B_RE) rd_sel_b_q[b_idx] <= 1'b1;
        end
      end

      logic [31:0] a_gated [DEPTH];
      logic [31:0] b_gated [DEPTH];
      for (w = 0; w < DEPTH; w = w + 1) begin : gen_rd_mux
        AND_gate #(.N(32)) u_a (.A1(mem_q[w]), .A2({32{rd_sel_a_q[w]}}), .ZN(a_gated[w]));
        AND_gate #(.N(32)) u_b (.A1(mem_q[w]), .A2({32{rd_sel_b_q[w]}}), .ZN(b_gated[w]));
      end

      integer i;
      always_comb begin
        A_RDATA = '0;
        B_RDATA = '0;
        for (i = 0; i < DEPTH; i = i + 1) begin
          A_RDATA = A_RDATA | a_gated[i];
          B_RDATA = B_RDATA | b_gated[i];
        end
      end

      // Bus response one cycle after any access (loads and stores).
      always_ff @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
          A_RVALID <= 1'b0;
          B_RVALID <= 1'b0;
        end else begin
          A_RVALID <= A_RE;
          B_RVALID <= B_RE | any_web;
        end
      end

    end else begin : g_infer
      // -----------------------------------------------------------------
      // BRAM / LUT: inferred RAM. The ram_style
      // attribute picks block vs distributed based on MEM_STYLE.
      // -----------------------------------------------------------------
      localparam RAM_STYLE_ATTR = (MEM_STYLE == "LUT") ? "distributed" : "block";

      (* ram_style = RAM_STYLE_ATTR *)
      logic [31:0] ram [DEPTH];

      initial begin
        if (INIT_FILE != "") $readmemh(INIT_FILE, ram);
      end

      // Reset controller signals
      logic [ADDR_W-1:0] rst_ptr;
      logic resetting;
      assign BUSY = resetting;

      // Internal port mux signals
      logic [ADDR_W-1:0] ram_addr_a, ram_addr_b;
      logic [31:0]       ram_wdata_a, ram_wdata_b;
      logic [3:0]        ram_we_a, ram_we_b;
      logic              ram_en_a, ram_en_b;

      if (CLEAR_ON_RESET) begin : g_clear
        // Dual-port accelerated reset: clear RESET_DEPTH words from RESET_START.
        always_ff @(posedge CLK) begin
          if (RST_N == 1'b0) begin
            resetting <= 1'b1;
            rst_ptr   <= '0;
          end else if (resetting) begin
            if (rst_ptr == (RESET_DEPTH/2) - 1) begin
              resetting <= 1'b0;
            end else begin
              rst_ptr <= rst_ptr + 1;
            end
          end
        end

        always_comb begin
          if (resetting) begin
            ram_addr_a  = RESET_START[ADDR_W-1:0] + rst_ptr;
            ram_wdata_a = 32'b0;
            ram_we_a    = 4'b1111;
            ram_en_a    = 1'b1;

            ram_addr_b  = RESET_START[ADDR_W-1:0] + (RESET_DEPTH/2) + rst_ptr;
            ram_wdata_b = 32'b0;
            ram_we_b    = 4'b1111;
            ram_en_b    = 1'b1;
          end else begin
            ram_addr_a  = A_ADDR[ADDR_W-1:0];
            ram_wdata_a = A_WDATA;
            ram_we_a    = A_WE;
            ram_en_a    = A_RE || (A_WE != 4'b0);

            ram_addr_b  = B_ADDR[ADDR_W-1:0];
            ram_wdata_b = B_WDATA;
            ram_we_b    = B_WE;
            ram_en_b    = B_RE || (B_WE != 4'b0);
          end
        end
      end else begin : g_noclear
        // Never clear (e.g. ROM); ports pass straight through, BUSY stays low.
        assign resetting = 1'b0;
        assign rst_ptr   = '0;

        always_comb begin
          ram_addr_a  = A_ADDR[ADDR_W-1:0];
          ram_wdata_a = A_WDATA;
          ram_we_a    = A_WE;
          ram_en_a    = A_RE || (A_WE != 4'b0);

          ram_addr_b  = B_ADDR[ADDR_W-1:0];
          ram_wdata_b = B_WDATA;
          ram_we_b    = B_WE;
          ram_en_b    = B_RE || (B_WE != 4'b0);
        end
      end

      // Port A access
      always_ff @(posedge CLK) begin
        if (ram_en_a) begin
          if (ram_we_a[0]) ram[ram_addr_a][ 7:0]  <= ram_wdata_a[ 7:0];
          if (ram_we_a[1]) ram[ram_addr_a][15:8]  <= ram_wdata_a[15:8];
          if (ram_we_a[2]) ram[ram_addr_a][23:16] <= ram_wdata_a[23:16];
          if (ram_we_a[3]) ram[ram_addr_a][31:24] <= ram_wdata_a[31:24];
          A_RDATA <= ram[ram_addr_a];
        end
      end

      // Port B access
      always_ff @(posedge CLK) begin
        if (ram_en_b) begin
          if (ram_we_b[0]) ram[ram_addr_b][ 7:0]  <= ram_wdata_b[ 7:0];
          if (ram_we_b[1]) ram[ram_addr_b][15:8]  <= ram_wdata_b[15:8];
          if (ram_we_b[2]) ram[ram_addr_b][23:16] <= ram_wdata_b[23:16];
          if (ram_we_b[3]) ram[ram_addr_b][31:24] <= ram_wdata_b[31:24];
          B_RDATA <= ram[ram_addr_b];
        end
      end

      // Read validation. A bus response is expected for every port-B access
      // (loads and stores), so B_RVALID also follows writes.
      always_ff @(posedge CLK) begin
        if (RST_N == 1'b0) begin
          A_RVALID <= 1'b0;
          B_RVALID <= 1'b0;
        end else if (resetting) begin
          A_RVALID <= 1'b0;
          B_RVALID <= 1'b0;
        end else begin
          A_RVALID <= A_RE;
          B_RVALID <= B_RE | (|B_WE);
        end
      end
    end
  endgenerate
`endif
endmodule
