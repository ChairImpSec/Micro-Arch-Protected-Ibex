// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
// Modified 2026 by Niels Wieser, TU Darmstadt:
// countermeasures against micro-architectural leakage.

// Example clock gating module for yosys synthesis
(* DONT_TOUCH = true *)
module prim_clock_gating (
  input  clk_i,
  input  en_i,
  input  test_en_i,
  output clk_o
);

`ifdef TARGET_ASIC
  // reg en_latch;

  // always @* begin
  //   if (!clk_i) begin
  //     en_latch = en_i | test_en_i;
  //   end
  // end
  // assign clk_o = en_latch & clk_i;
  assign clk_o = clk_i;
`endif
endmodule
