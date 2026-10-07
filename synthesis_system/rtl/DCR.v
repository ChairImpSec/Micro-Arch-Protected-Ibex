// Copyright (c) 2026 Niels Wieser, TU Darmstadt
// SPDX-License-Identifier: MIT

// --- Generic DCR Module ---
// A DCR module behaves like a register, which is clocked on both edges,
// Using one half cycle to reset (precharge phase) and one to output the captured value.
// The parameter IS_POSEDGE can be used in order to define the clock edge capturing data.
// The other edge will then introduce the precharge phase.
// This in consequence means, that every DCR at rising edge will need a counterpart
// at falling edge, otherwise the data is set to 0 for the following rising edge register.
module DCR #(
    parameter IS_POSEDGE = 1,
    parameter N = 1
  )(
    input  wire         clk,
    input  wire         EN,
    input  wire         RST_N,
    input  wire [N-1:0] D,
    output reg  [N-1:0] Q
  );
  
  // Internal signals
  wire neg_clk;
  wire data_latch, en_latch;
  wire toggle, toggle_bar;
  wire overwrite, overwrite_bar;
  wire switch, switch_bar;
  wire [N-1:0] r1;
  wire [N-1:0] r2;
  wire [N-1:0] d_and_toggle;
  wire [N-1:0] d_and_toggle_bar;
  wire [N-1:0] r1_masked;
  wire [N-1:0] r2_masked;

  // Inverter for toggle signal
  INV_gate clk_inverter (.A(clk), .ZN(neg_clk));


  XOR_gate combine     (.A(overwrite), .B(toggle), .Z(switch));
  XOR_gate combine_bar (.A(overwrite), .B(toggle_bar), .Z(switch_bar));
  // The core logic is split based on the clock edge configuration.


  // Combinational logic for r1 and r2 register inputs
  AND_gate #(.N(N)) r1_input_logic (.A1(D), .A2({N{switch}}), .ZN(d_and_toggle));
  AND_gate #(.N(N)) r2_input_logic (.A1(D), .A2({N{switch_bar}}), .ZN(d_and_toggle_bar));



  generate
    if (IS_POSEDGE == 1) begin: POSEDGE_IMPL
      DFF_cell toggle_reg  (.D(toggle_bar),    .CK(neg_clk), .Q(toggle), .QN(toggle_bar));
      DFFE_cell en_reg      (.D(overwrite_bar), .CK(clk), .EN(!EN), .RST_N(RST_N), .Q(overwrite), .QN(overwrite_bar));

      // r1 and r2 registers, using the regular clock
      DFFE_cell #(.N(N)) r1_reg (.D(d_and_toggle),     .CK(clk), .EN(EN), .RST_N(RST_N), .Q(r1));
      DFFE_cell #(.N(N)) r2_reg (.D(d_and_toggle_bar), .CK(clk), .EN(EN), .RST_N(RST_N), .Q(r2));
    end else begin: NEGEDGE_IMPL
      // Configuration for IS_POSEDGE = 0:
      DFF_cell toggle_reg (.D(toggle_bar),    .CK(clk),        .Q(toggle),    .QN(toggle_bar));
      DFFE_cell en_reg     (.D(overwrite_bar), .CK(neg_clk), .EN(!EN), .RST_N(RST_N), .Q(overwrite), .QN(overwrite_bar));

      // r1 and r2 registers, using the inverted clock
      DFFE_cell #(.N(N)) r1_reg (.D(d_and_toggle),     .CK(neg_clk), .EN(EN), .RST_N(RST_N), .Q(r1));
      DFFE_cell #(.N(N)) r2_reg (.D(d_and_toggle_bar), .CK(neg_clk), .EN(EN), .RST_N(RST_N), .Q(r2));
    end
  endgenerate
  
  // Output multiplexer
  AND_gate #(.N(N)) out_and1 (.A1(r1), .A2({N{switch}}), .ZN(r1_masked));
  AND_gate #(.N(N)) out_and2 (.A1(r2), .A2({N{switch_bar}}), .ZN(r2_masked));
  OR_gate  #(.N(N)) out_or   (.A1(r1_masked), .A2(r2_masked), .ZN(Q));

endmodule