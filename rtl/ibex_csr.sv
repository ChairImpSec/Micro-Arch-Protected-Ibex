// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
// Modified 2026 by Niels Wieser, TU Darmstadt:
// countermeasures against micro-architectural leakage.

/**
 * Control / status register primitive
 */

`include "prim_assert.sv"

module ibex_csr #(
  parameter int unsigned    Width      = 32,
  parameter bit             ShadowCopy = 1'b0,
  parameter bit [Width-1:0] ResetValue = '0
 ) (
  input  logic             clk_i,
  input  logic             rst_ni,

  input  logic [Width-1:0] wr_data_i,
  input  logic             wr_en_i,
  output logic [Width-1:0] rd_data_o,

  output logic             rd_error_o
);

  logic [Width-1:0] rdata_q_int;

  if (ShadowCopy) begin : gen_shadow
    logic [Width-1:0] shadow_q_int;

    // Since DFFE_cell only supports a reset to 0, we XOR the data with the ResetValue
    // at the input and output to effectively support a non-zero reset value.
    DFFE_cell #(.N(Width * 2)) u_grouped_csr_reg (
      .CK     (clk_i),
      .D      ({wr_data_i ^ ResetValue, ~wr_data_i ^ ~ResetValue}),
      .EN     (wr_en_i),
      .RST_N  (rst_ni),
      .Q      ({rdata_q_int, shadow_q_int}),
      .QN     ()
    );

    // The shadow register is kept bitwise inverted compared to the main register.
    // We check for consistency by comparing the reconstructed values.
    assign rd_error_o = (rdata_q_int ^ ResetValue) != ~(shadow_q_int ^ ~ResetValue);

  end else begin : gen_no_shadow
    // Since DFFE_cell only supports a reset to 0, we XOR the data with the ResetValue
    // at the input and output to effectively support a non-zero reset value.
    DFFE_cell #(.N(Width)) u_rdata_reg (
      .CK     (clk_i),
      .D      (wr_data_i ^ ResetValue),
      .EN     (wr_en_i),
      .RST_N  (rst_ni),
      .Q      (rdata_q_int),
      .QN     ()
    );

    assign rd_error_o = 1'b0;
  end

  assign rd_data_o = rdata_q_int ^ ResetValue;

  `ASSERT_KNOWN(IbexCSREnValid, wr_en_i)

endmodule
