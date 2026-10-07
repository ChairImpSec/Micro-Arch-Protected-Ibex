// Copyright (c) 2026 Niels Wieser, TU Darmstadt
// SPDX-License-Identifier: MIT

module encrypt_vmem_tb;
  logic clk, rst_n;
  logic [31:0] addr, data_in, data_out;
  logic [31:0] key_lo, key_hi;
  logic [ 2:0] rounds;
  logic [31:0] mem [1024*1024]; // 4MB max for now
  string input_file, output_file;
  int f;
  int i;

  mem_crypt u_mem_crypt (
    .clk_i        (clk),
    .rst_ni       (rst_n),
    .cfg_addr_i   (cfg_addr),
    .cfg_wr_en_i  (cfg_we),
    .cfg_wdata_i  (cfg_wdata),
    .cfg_rdata_o  (),
    .data_addr_i  (addr),
    .data_in_i    (data_in),
    .data_req_i   (data_req),
    .data_valid_i (data_valid),
    .data_done_o  (data_done),
    .data_out_o   (data_out)
  );

  logic [31:0] cfg_addr, cfg_wdata;
  logic        cfg_we, data_req, data_valid, data_done;

  initial begin
    clk = 0;
    rst_n = 0;
    cfg_we = 0;
    data_req = 0;
    data_valid = 0;

    if (!$value$plusargs("key_lo=%h", key_lo)) key_lo = 32'h0;
    if (!$value$plusargs("key_hi=%h", key_hi)) key_hi = 32'h0;
    if (!$value$plusargs("rounds=%d", rounds)) rounds = 3'h0;
    if (!$value$plusargs("input=%s", input_file)) begin
      $display("Missing +input=<file>");
      $finish;
    end
    if (!$value$plusargs("output=%s", output_file)) begin
      $display("Missing +output=<file>");
      $finish;
    end

    for (int k=0; k<1024*1024; k++) mem[k] = 32'hxxxx_xxxx;
    $readmemh(input_file, mem);
    
    #1 rst_n = 1;
    #1 clk = 1; #1 clk = 0;

    // Load key_lo
    #1 cfg_addr = 32'h0; cfg_wdata = key_lo; cfg_we = 1;
    #1 clk = 1; #1 clk = 0;
    
    // Load key_hi
    #1 cfg_addr = 32'h4; cfg_wdata = key_hi; cfg_we = 1;
    #1 clk = 1; #1 clk = 0;

    // Load rounds
    #1 cfg_addr = 32'h8; cfg_wdata = {29'b0, rounds}; cfg_we = 1;
    #1 clk = 1; #1 clk = 0;
    cfg_we = 0;
    
    f = $fopen(output_file, "w");
    for (i = 0; i < 1024*1024; i++) begin
      if (mem[i] !== 32'hxxxx_xxxx) begin
        addr = i << 2;
        data_in = mem[i];
        data_req = 1;
        data_valid = 1;
        #1 clk = 1; #1 clk = 0;
        data_req = 0;
        while (!data_done) begin
            #1 clk = 1; #1 clk = 0;
        end
        $fdisplay(f, "@%h %h", i, data_out);
      end
    end
    $fclose(f);
    $finish;
  end
endmodule
