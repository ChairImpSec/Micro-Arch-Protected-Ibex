// Copyright (c) 2026 Niels Wieser, TU Darmstadt
// SPDX-License-Identifier: MIT

module DFFR_cell #(
  parameter N = 1
)(
  input  wire         CK,
  input  wire [N-1:0] D, 
  input  wire         RN, 
  output wire [N-1:0] Q,
  output wire [N-1:0] QN
);
  generate
    genvar i;
    for (i = 0; i < N; i = i + 1) begin: fanout
      DFFR_X2 nang45_dff (.D(D[i]), .CK(CK), .RN(RN), .Q(Q[i]), .QN(QN[i]));
    end
  endgenerate
endmodule