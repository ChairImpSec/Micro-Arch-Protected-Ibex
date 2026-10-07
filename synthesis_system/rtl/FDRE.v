// Copyright (c) 2026 Niels Wieser, TU Darmstadt
// SPDX-License-Identifier: MIT

(* DONT_TOUCH = true *)
module FDRE #(
  parameter bit INIT = 1'b0
)(
  input  wire         C,
  input  wire         CE,
  input  wire         D, 
  output reg          Q,
  input  wire         R
);

  initial Q = INIT;

  always @(posedge C) begin
    if (R) begin
      Q <= 1'b0;
    end else if (CE) begin
      Q <= D;
    end
  end

endmodule