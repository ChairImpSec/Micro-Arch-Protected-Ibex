// Copyright lowRISC contributors.
// Copyright 2018 ETH Zurich and University of Bologna, see also CREDITS.md.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
// Modified 2026 by Niels Wieser, TU Darmstadt:
// countermeasures against micro-architectural leakage.

/**
 * RISC-V register file
 *
 * Register file with 31 or 15x 32 bit wide registers. Register 0 is fixed to 0.
 * This register file is based on flip flops. Use this register file when
 * targeting FPGA synthesis or Verilator simulation.
 */
module ibex_register_file_ff #(
  parameter bit                   RV32E             = 0,
  parameter int unsigned          DataWidth         = 32,
  parameter bit                   DummyInstructions = 0,
  parameter bit                   WrenCheck         = 0,
  parameter bit                   RdataMuxCheck     = 0,
  parameter logic [DataWidth-1:0] WordZeroVal       = '0
) (
  // Clock and Reset
  input  logic                 clk_i,
  input  logic                 rst_ni,

  input  logic                 test_en_i,
  input  logic                 dummy_instr_id_i,
  input  logic                 dummy_instr_wb_i,

  //Read port R1
  input  logic [4:0]           raddr_a_i,
  output logic [DataWidth-1:0] rdata_a_o,

  //Read port R2
  input  logic [4:0]           raddr_b_i,
  output logic [DataWidth-1:0] rdata_b_o,


  // Write port W1
  input  logic [4:0]           waddr_a_i,
  input  logic [DataWidth-1:0] wdata_a_i,
  input  logic                 we_a_i,

  // This indicates whether spurious WE or non-one-hot encoded raddr are detected.
  output logic                 err_o
);

  localparam int unsigned ADDR_WIDTH = RV32E ? 4 : 5;
  localparam int unsigned NUM_WORDS  = 2**ADDR_WIDTH;

  logic [DataWidth-1:0] rf_reg   [NUM_WORDS];
  logic [NUM_WORDS-1:0] clock_enable_dec;
  logic [NUM_WORDS-1:0] we_old_dec;

  // Spare reg. This reg is used to capture all writes, such that the normal register file, can reset.
  // Internally a DCR module is used, so we dont have any transitional leakage for this reg.
  logic [DataWidth-1:0] spare_reg;
  logic [DataWidth-1:0] spare_buffer;
  
  // Addresses for output / overwrite determination
  logic [4:0] last_waddr;
  logic match_a, match_b, match_w, use_rf_a, use_spare_a, use_rf_b, use_spare_b, is_same_waddr, is_diff_waddr;

  // Outputs before merge
  logic [DataWidth-1:0] rf_read_a;
  logic [DataWidth-1:0] rf_read_b;
  logic [DataWidth-1:0] spare_read_a;
  logic [DataWidth-1:0] spare_read_b;


  logic oh_raddr_a_err, oh_raddr_b_err, oh_we_err;

  always_comb begin : we_ce_decoder
    for (int unsigned i = 0; i < NUM_WORDS; i++) begin
      // We always want to reset the current target register and allow setting the old.
      clock_enable_dec[i] = (waddr_a_i == 5'(i) || last_waddr == 5'(i)) && we_a_i;
    end
  end

  logic writeback_en;
  AND_gate writeback_en_g (.A1(~match_w), .A2(we_a_i), .ZN(writeback_en));
  always_comb begin : we_old_decoder
    for (int unsigned i = 0; i < NUM_WORDS; i++) begin
      // If we switch to a new register, we want to writeback our spare.
      we_old_dec[i] = (last_waddr == 5'(i)) ? writeback_en : 1'b0;
    end
  end

  // SEC_CM: DATA_REG_SW.GLITCH_DETECT
  // This checks for spurious WE strobes on the regfile.
  if (WrenCheck) begin : gen_wren_check
    // Buffer the decoded write enable bits so that the checker
    // is not optimized into the address decoding logic.
    logic [NUM_WORDS-1:0] we_a_dec_buf;
    prim_buf #(
      .Width(NUM_WORDS)
    ) u_prim_buf (
      .in_i(we_old_dec),
      .out_o(we_a_dec_buf)
    );

    prim_onehot_check #(
      .AddrWidth(ADDR_WIDTH),
      .AddrCheck(1),
      .EnableCheck(1)
    ) u_prim_onehot_check (
      .clk_i,
      .rst_ni,
      .oh_i(we_a_dec_buf),
      .addr_i(waddr_a_i),
      .en_i(we_a_i),
      .err_o(oh_we_err)
    );
  end else begin : gen_no_wren_check
    logic unused_strobe;
    assign unused_strobe = we_old_dec[0]; // this is never read from in this case
    assign oh_we_err = 1'b0;
  end

  // Always write to spare register.
  DCR #(
    .IS_POSEDGE(1),
    .N(DataWidth) 
  ) dcr_spare (
    .clk   (clk_i),
    .EN    (we_a_i),
    .RST_N (rst_ni),
    .D     (wdata_a_i),
    .Q     (spare_reg)
  );

  // Write down the used address, if we write.
  // The address is stable the entire cycle.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      last_waddr <= '0;
    end else if (we_a_i) begin
      last_waddr <= waddr_a_i;
    end
  end

  // Capute, if the target read-addr is matching.
  assign match_a = (raddr_a_i == last_waddr) && (raddr_a_i != '0);
  assign match_b = (raddr_b_i == last_waddr) && (raddr_b_i != '0);
  assign match_w = waddr_a_i == last_waddr;
  
  DCR #(
    .IS_POSEDGE(0),
    .N(6)
  ) precharge_matches (
    .clk   (clk_i),
    .EN    (1'b1), // We need to update every cycle, since while waddr wont change raddr can.
    .RST_N (rst_ni),
    .D     ({~match_a, match_a,     ~match_b, match_b,     match_w,       ~match_w}),
    .Q     ({use_rf_a, use_spare_a, use_rf_b, use_spare_b, is_same_waddr, is_diff_waddr})
  );

  // No flops for R0 as it's hard-wired to 0
  for (genvar i = 1; i < NUM_WORDS; i++) begin : g_rf_flops
    // Apply blind to spare_reg
    logic [DataWidth-1:0] rf_input;
    AND_gate #(.N(32)) input_blind (.A1(spare_buffer), .A2({32{we_old_dec[i]}}), .ZN(rf_input));
    // Register
    DFFE_cell #(.N(32)) register_cell (.D(rf_input), .CK(clk_i), .EN(clock_enable_dec[i]), .RST_N(rst_ni), .Q(rf_reg[i]));
  end

  // With dummy instructions enabled, R0 behaves as a real register but will always return 0 for
  // real instructions.
  if (DummyInstructions) begin : g_dummy_r0
    // SEC_CM: CTRL_FLOW.UNPREDICTABLE
    logic                 we_r0_dummy;
    logic [DataWidth-1:0] rf_r0_q;

    // Write enable for dummy R0 register (waddr_a_i will always be 0 for dummy instructions)
    assign we_r0_dummy = we_a_i & dummy_instr_wb_i;

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        rf_r0_q <= WordZeroVal;
      end else if (we_r0_dummy) begin
        rf_r0_q <= wdata_a_i;
      end
    end

    // Output the dummy data for dummy instructions, otherwise R0 reads as zero
    assign rf_reg[0] = dummy_instr_id_i ? rf_r0_q : WordZeroVal;

  end else begin : g_normal_r0
    logic unused_dummy_instr;
    assign unused_dummy_instr = dummy_instr_id_i ^ dummy_instr_wb_i;

    // R0 is nil
    assign rf_reg[0] = WordZeroVal;
  end

  // Encode raddr_a/b into one-hot encoded signals.
  logic [NUM_WORDS-1:0] raddr_onehot_a, raddr_onehot_b;
  logic [NUM_WORDS-1:0] raddr_onehot_a_buf, raddr_onehot_b_buf;
  prim_onehot_enc #(
    .OneHotWidth(NUM_WORDS)
  ) u_prim_onehot_enc_raddr_a (
    .in_i  (raddr_a_i),
    .en_i  (1'b1),
    .out_o (raddr_onehot_a)
  );
  
  prim_onehot_enc #(
    .OneHotWidth(NUM_WORDS)
  ) u_prim_onehot_enc_raddr_b (
    .in_i  (raddr_b_i),
    .en_i  (1'b1),
    .out_o (raddr_onehot_b)
  );
  
  // Buffer the one-hot encoded signals so that the checkers
  // are not optimized.
  prim_buf #(
    .Width(NUM_WORDS)
  ) u_prim_buf_raddr_a (
    .in_i (raddr_onehot_a),
    .out_o(raddr_onehot_a_buf)
  );
  
  prim_buf #(
    .Width(NUM_WORDS)
  ) u_prim_buf_raddr_b (
    .in_i (raddr_onehot_b),
    .out_o(raddr_onehot_b_buf)
  );
  
  // SEC_CM: DATA_REG_SW.GLITCH_DETECT
  // Check the one-hot encoded signals for glitches.
  prim_onehot_check #(
    .AddrWidth(ADDR_WIDTH),
    .OneHotWidth(NUM_WORDS),
    .AddrCheck(1),
    // When AddrCheck=1 also EnableCheck needs to be 1.
    .EnableCheck(1)
  ) u_prim_onehot_check_raddr_a (
    .clk_i,
    .rst_ni,
    .oh_i   (raddr_onehot_a_buf),
    .addr_i (raddr_a_i),
    // Set enable=1 as address is always valid.
    .en_i   (1'b1),
    .err_o  (oh_raddr_a_err)
  );
  
  prim_onehot_check #(
    .AddrWidth(ADDR_WIDTH),
    .OneHotWidth(NUM_WORDS),
    .AddrCheck(1),
    // When AddrCheck=1 also EnableCheck needs to be 1.
    .EnableCheck(1)
  ) u_prim_onehot_check_raddr_b (
    .clk_i,
    .rst_ni,
    .oh_i   (raddr_onehot_b_buf),
    .addr_i (raddr_b_i),
    // Set enable=1 as address is always valid.
    .en_i   (1'b1),
    .err_o  (oh_raddr_b_err)
  );

  // Capture the multiplexer output in a DCR module, so we have a valid signal inside the next stage.
  logic [NUM_WORDS-1:0] raddr_onehot_a_dcr;
  logic [NUM_WORDS-1:0] raddr_onehot_b_dcr;
  DCR #(
    .IS_POSEDGE(0),
    .N(2*NUM_WORDS+DataWidth) 
  ) dcr_output (
    .clk   (clk_i),
    .EN    (1'b1),
    .RST_N (rst_ni),
    .D     ({raddr_onehot_a,        raddr_onehot_b,       spare_reg   }),
    .Q     ({raddr_onehot_a_dcr,    raddr_onehot_b_dcr,   spare_buffer})
  );    

  
  // MUX register to rdata_a/b_o according to raddr_a/b_onehot.
  logic [DataWidth-1:0] rdata_oh_a, rdata_oh_b;
  logic [DataWidth-1:0] rdata_a_components [NUM_WORDS];
  logic [DataWidth-1:0] rdata_b_components [NUM_WORDS];

  for (genvar i = 0; i < NUM_WORDS; i++) begin : g_rdata_mux
    AND_gate #(.N(DataWidth)) u_rdata_a_and (.A1(rf_reg[i]), .A2({DataWidth{raddr_onehot_a_dcr[i]}}), .ZN(rdata_a_components[i]));
    AND_gate #(.N(DataWidth)) u_rdata_b_and (.A1(rf_reg[i]), .A2({DataWidth{raddr_onehot_b_dcr[i]}}), .ZN(rdata_b_components[i]));
  end

  always_comb begin
    rdata_oh_a = '0;
    rdata_oh_b = '0;
    for (int i = 0; i < NUM_WORDS; i++) begin
      rdata_oh_a |= rdata_a_components[i];
      rdata_oh_b |= rdata_b_components[i];
    end
  end
  //Removed non-one-hot case, since this will always leak.



  // Blind spare if we want to use the Register File. The blind has to be precharged.
  AND_gate #(.N(32)) blind_spare_a (.A1({32{use_spare_a}}), .A2(spare_buffer), .ZN(spare_read_a));
  AND_gate #(.N(32)) blind_spare_b (.A1({32{use_spare_b}}), .A2(spare_buffer), .ZN(spare_read_b));
  // Blind Register File if we want to use the spare. The blind has to be precharged.
  AND_gate #(.N(32)) blind_rf_a (.A1({32{use_rf_a}}), .A2(rdata_oh_a), .ZN(rf_read_a));
  AND_gate #(.N(32)) blind_rf_b (.A1({32{use_rf_b}}), .A2(rdata_oh_b), .ZN(rf_read_b));
  // Combine register_file with spare_reg, in case we want to read data we just read.
  OR_gate #(.N(32)) combine_rf_a (.A1(rf_read_a), .A2(spare_read_a), .ZN(rdata_a_o));
  OR_gate #(.N(32)) combine_rf_b (.A1(rf_read_b), .A2(spare_read_b), .ZN(rdata_b_o));


  assign err_o = oh_raddr_a_err || oh_raddr_b_err || oh_we_err;

  // Signal not used in FF register file
  logic unused_test_en;
  assign unused_test_en = test_en_i;

endmodule
