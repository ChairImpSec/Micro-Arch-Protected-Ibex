// Copyright (c) 2026 Niels Wieser, TU Darmstadt
// SPDX-License-Identifier: MIT

(* DONT_TOUCH = true *)
module DFFE_cell #(
  parameter N = 1
)(
  input  wire         CK,
  input  wire [N-1:0] D, 
  input  wire         EN, 
  input  wire         RST_N,
  output wire [N-1:0] Q,
  output wire [N-1:0] QN
);

generate 
  genvar i;
  `ifdef TARGET_ASIC
    // Latch clock input for each register.
    // This is used to hold values inside registers.
    logic enable_l;
    DLL_X1 clk_en_l (.D(EN), .GN(CK), .Q(enable_l));

    for (i = 0; i < N; i = i + 1) begin: fanout
      logic gated_clk;
      AND_gate gate_clk (.A1(enable_l), .A2(CK),  .ZN(gated_clk));
      DFFR_X1 nang45_dff (.D(D[i]), .CK(gated_clk), .RN(RST_N), .Q(Q[i]), .QN(QN[i]));
    end
  `else
    for (i = 0; i < N; i = i + 1) begin: fanout
      FDRE #(
        .INIT(1'b0)) 
      en_reg (
        .C(CK),
        .CE(EN),
        .D(D[i]),
        .Q(Q[i]),
        .R(~RST_N)
      );
    end
    assign QN = ~Q;
  `endif
endgenerate
endmodule
