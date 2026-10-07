// Copyright (c) 2026 Niels Wieser, TU Darmstadt
// SPDX-License-Identifier: MIT

module OR_gate #(
  parameter N = 1
)(
  input  wire [N-1:0] A1, 
  input  wire [N-1:0] A2,
  output wire [N-1:0] ZN
);
  generate
    genvar i;
    for (i = 0; i < N; i = i + 1) begin: fanout
      OR2_X1 nang45_or (.A1(A1[i]), .A2(A2[i]), .ZN(ZN[i]));
    end
  endgenerate
endmodule