// Copyright (c) 2026 Niels Wieser, TU Darmstadt
// SPDX-License-Identifier: MIT

(* DONT_TOUCH = "yes" *)
module custom_sram(CLK,
             A1ADDR,
             A1EN,
             A1DATA,
             B1ADDR,
             B1EN,
             B1DATA,
             A2ADDR,
             A2EN,
             A2DATA,
             B2ADDR,
             B2EN,
             B2DATA);

   parameter                      ADDR_WIDTH = 1;
   parameter                      DATA_WIDTH = 1;
   parameter                      MEMSIZE    = 1;

   input                          CLK;

   input  [ADDR_WIDTH-1:0]        A1ADDR;
   input  [DATA_WIDTH-1:0]        A1DATA;
   input  [3:0]                   A1EN;

   input  [ADDR_WIDTH-1:0]        B1ADDR;
   output [DATA_WIDTH-1:0]        B1DATA;
   input                          B1EN;

   input  [ADDR_WIDTH-1:0]        A2ADDR;
   input  [DATA_WIDTH-1:0]        A2DATA;
   input  [3:0]                   A2EN;

   input  [ADDR_WIDTH-1:0]        B2ADDR;
   output [DATA_WIDTH-1:0]        B2DATA;
   input                          B2EN;
endmodule // CUSTOM_BRAM
