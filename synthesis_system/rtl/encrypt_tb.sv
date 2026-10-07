// Copyright (c) 2026 Niels Wieser, TU Darmstadt
// SPDX-License-Identifier: MIT

// Simulation models for Nangate45 cells
module AND2_X1(input A1, input A2, output ZN);
  assign ZN = A1 & A2;
endmodule

module OR2_X1(input A1, input A2, output ZN);
  assign ZN = A1 | A2;
endmodule

module XOR2_X1(input A, input B, output Z);
  assign Z = A ^ B;
endmodule

module INV_X1(input A, output ZN);
  assign ZN = ~A;
endmodule

module DLL_X1(input D, input GN, output reg Q);
  // Active low latch (transparent when GN=0)
  initial Q = 0;
  always @(D or GN) begin
    if (!GN) Q = D;
  end
endmodule

module DFF_X2(input D, input CK, output reg Q, output wire QN);
  initial Q = 0;
  always @(posedge CK) begin
    Q <= D;
  end
  assign QN = ~Q;
endmodule

module encrypt_tb;
  logic clk, rst_n;
  logic [31:0] cfg_addr, cfg_wdata, cfg_rdata;
  logic        cfg_req, cfg_we, cfg_rvalid;
  
  logic [31:0] cpu_addr, cpu_wdata, cpu_rdata;
  logic [ 3:0] cpu_be;
  logic        cpu_we, cpu_req, cpu_done;

  logic [31:0] ram_addr, ram_wdata, ram_rdata;
  logic [ 3:0] ram_be;
  logic        ram_we, ram_re, ram_rvalid;

  logic [31:0] addr_in, data_in;
  logic [31:0] key_lo, key_hi;
  logic [ 2:0] rounds;
  
  mem_crypt u_mem_crypt (
    .clk_i        (clk),
    .rst_ni       (rst_n),

    .cfg_addr_i   (cfg_addr),
    .cfg_req_i    (cfg_req),
    .cfg_wr_en_i  (cfg_we),
    .cfg_wdata_i  (cfg_wdata),
    .cfg_rdata_o  (cfg_rdata),
    .cfg_rvalid_o (cfg_rvalid),

    .cpu_addr_i   (cpu_addr),
    .cpu_wdata_i  (cpu_wdata),
    .cpu_be_i     (cpu_be),
    .cpu_we_i     (cpu_we),
    .cpu_req_i    (cpu_req),
    .cpu_rdata_o  (cpu_rdata),
    .cpu_done_o   (cpu_done),

    .ram_addr_o   (ram_addr),
    .ram_wdata_o  (ram_wdata),
    .ram_be_o     (ram_be),
    .ram_we_o     (ram_we),
    .ram_re_o     (ram_re),
    .ram_rdata_i  (ram_rdata),
    .ram_rvalid_i (ram_rvalid)
  );

  int latency;
  logic [31:0] captured_wdata, captured_rdata;

  initial begin
    $dumpfile("encrypt.vcd");
    $dumpvars(0, encrypt_tb);
    clk = 0;
    rst_n = 0;
    cfg_req = 0;
    cfg_we = 0;
    cpu_req = 0;
    cpu_we = 0;
    cpu_be = 4'hF;
    ram_rvalid = 0;
    ram_rdata = 32'h600C5f26;
    latency = 0;

    if (!$value$plusargs("addr=%h", addr_in)) addr_in = 32'h0;
    if (!$value$plusargs("key_lo=%h", key_lo)) key_lo = 32'h0;
    if (!$value$plusargs("key_hi=%h", key_hi)) key_hi = 32'h0;
    if (!$value$plusargs("rounds=%d", rounds)) rounds = 3'h2;
    
    rst_n = 1;
    #1 clk = 1; #1 clk = 0; // Sync reset

    // Load key_lo
    cfg_addr = 32'h0; cfg_wdata = key_lo; cfg_we = 1; cfg_req = 1;
    #1 clk = 1; #1 clk = 0;
    
    // Load key_hi
    cfg_addr = 32'h4; cfg_wdata = key_hi; cfg_we = 1; cfg_req = 1;
    #1 clk = 1; #1 clk = 0;
    ram_rvalid = 1;

    // Load rounds
    cfg_addr = 32'h8; cfg_wdata = {29'b0, rounds}; cfg_we = 1; cfg_req = 1;
    #1 clk = 1; #1 clk = 0;
    ram_rvalid = 0;
    cfg_we = 0; cfg_req = 0;

    // Start Write request (Encryption)
    if (!$value$plusargs("data=%h", data_in)) data_in = 32'h0;
    cpu_addr = addr_in; cpu_wdata = data_in; cpu_we = 1; cpu_req = 1;
    
    // Cycle 1: Check for zero-out write (combinational logic in ST_IDLE)
    #0.1;
    if (ram_we !== 1'b1 || ram_wdata !== 32'h0) begin
        $display("ERROR: Leading zero-out write failed! ram_we=%b, ram_wdata=%h", ram_we, ram_wdata);
    end else begin
        $display("SUCCESS: Leading zero-out write detected.");
    end

    #0.9;
    clk = 1; #1 clk = 0;
    cpu_req = 0;
    latency = 1;

    // Wait for completion
    begin : wait_write
        int timeout;
        timeout = 0;
        while (timeout < 100) begin
           #1 clk = 1; 
           #0.1; // Small delay to allow combinational logic to settle after edge
           if (cpu_done) begin
               #0.4;
               captured_wdata = ram_wdata;
               #0.5; clk = 0;
               latency = latency + 1; // Count this cycle
               disable wait_write;
           end
           #0.9; clk = 0;
           latency = latency + 1;
           timeout = timeout + 1;
        end
        if (!cpu_done) $display("ERROR: Timeout waiting for Write cpu_done");
    end
    
    $display("Encrypted Data: %h", captured_wdata);
    $display("Write Latency: %d cycles", latency);

    // --- Start Read request (Decryption) ---
    cpu_addr = addr_in; cpu_we = 0; cpu_req = 1;
    #1 clk = 1; #1 clk = 0;
    cpu_req = 0;
    latency = 1;

    // SRAM response for Read
    ram_rvalid = 1; ram_rdata = captured_wdata; // Use the encrypted value we just captured
    
    // Wait for completion
    begin : wait_read
        int timeout;
        timeout = 0;
        while (timeout < 100) begin
           #1 clk = 1;
           #0.1;
           if (cpu_done) begin
               #0.4;
               captured_rdata = cpu_rdata;
               #0.5; clk = 0;
               latency = latency + 1;
               disable wait_read;
           end
           #0.9; clk = 0;
           latency = latency + 1;
           timeout = timeout + 1;
        end
        if (!cpu_done) $display("ERROR: Timeout waiting for Read cpu_done");
    end
    
    $display("Decrypted Data: %h", captured_rdata);
    $display("Read Latency: %d cycles", latency);
    
    if (captured_rdata === data_in) begin
        $display("SUCCESS: Decryption matches input.");
    end else begin
        $display("ERROR: Decryption FAILED! Expected %h, Got %h", data_in, captured_rdata);
    end

    ram_rvalid = 0;
    #1 clk = 1; #1 clk = 0;
    $finish;
  end
endmodule
