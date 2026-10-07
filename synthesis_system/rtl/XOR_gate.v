// Copyright (c) 2026 Niels Wieser, TU Darmstadt
// SPDX-License-Identifier: MIT

module XOR_gate #(
  parameter N = 1
)(
  input  wire [N-1:0] A, 
  input  wire [N-1:0] B,
  output wire [N-1:0] Z
);
  generate
    genvar i;
    for (i = 0; i < N; i = i + 1) begin: fanout
      XOR2_X1 nang45_or (.A(A[i]), .B(B[i]), .Z(Z[i]));
    end
  endgenerate
endmodule