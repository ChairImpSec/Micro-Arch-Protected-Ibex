// Copyright (c) 2026 Niels Wieser, TU Darmstadt
// SPDX-License-Identifier: MIT

(* DONT_TOUCH = "yes" *)
module custom_rom(CLK,
            A1ADDR,
            A1EN,
            A1DATA);

   (* syn_keep = 1 *) parameter                      FILE = "";
   (* syn_keep = 1 *) parameter                      ADDR_WIDTH = 1;
   (* syn_keep = 1 *) parameter                      DATA_WIDTH = 1;
   (* syn_keep = 1 *) parameter                      MEMSIZE    = 1;

   input                          CLK;

   input  [ADDR_WIDTH-1:0]        A1ADDR;
   output [DATA_WIDTH-1:0]        A1DATA;
   input                          A1EN;
endmodule // CUSTOM_ROM
