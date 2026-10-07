// Copyright (c) 2026 Niels Wieser, TU Darmstadt
// SPDX-License-Identifier: MIT

module INV_gate #(
  parameter N = 1
)(
  input  wire [N-1:0] A, 
  output wire [N-1:0] ZN
);
  generate
    genvar i;
    for (i = 0; i < N; i = i + 1) begin: fanout
      INV_X1 nang45_inv ( .A(A[i]), .ZN(ZN[i]) );
    end
  endgenerate
endmodule