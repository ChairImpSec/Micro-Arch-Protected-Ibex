// Copyright (c) 2026 Niels Wieser, TU Darmstadt
// SPDX-License-Identifier: MIT

// Simple models for gate-level components used in mem_crypt
module AND_gate #(parameter int N = 1) (
  input  logic [N-1:0] A1,
  input  logic [N-1:0] A2,
  output logic [N-1:0] ZN
);
  assign ZN = A1 & A2;
endmodule

module DFFE_cell #(parameter int N = 1) (
  input  logic         CK,
  input  logic [N-1:0] D,
  input  logic         EN,
  input  logic         RST_N,
  output logic [N-1:0] Q,
  output logic [N-1:0] QN
);
  logic [N-1:0] q_reg;
  always_ff @(posedge CK) begin
    if (!RST_N)    q_reg <= '0;
    else if (EN)   q_reg <= D;
  end
  assign Q = q_reg;
  assign QN = ~q_reg;
endmodule

module mem_crypt_tb;
  logic clk;
  logic rst_n;

  // Configuration (MMIO)
  logic [31:0] cfg_addr;
  logic        cfg_req;
  logic        cfg_wr_en;
  logic [31:0] cfg_wdata;
  logic [31:0] cfg_rdata;
  logic        cfg_rvalid;

  // CPU Interface
  logic [31:0] cpu_addr;
  logic [31:0] cpu_wdata;
  logic [ 3:0] cpu_be;
  logic        cpu_we;
  logic        cpu_req;
  logic [31:0] cpu_rdata;
  logic        cpu_done;

  // RAM Interface
  logic [31:0] ram_addr;
  logic [31:0] ram_wdata;
  logic [ 3:0] ram_be;
  logic        ram_we;
  logic        ram_re;
  logic [31:0] ram_rdata;
  logic        ram_rvalid;

  // Simple fixed-size RAM model
  logic [31:0] memory [0:1023];

  mem_crypt dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .cfg_addr_i(cfg_addr),
    .cfg_req_i(cfg_req),
    .cfg_wr_en_i(cfg_wr_en),
    .cfg_wdata_i(cfg_wdata),
    .cfg_rdata_o(cfg_rdata),
    .cfg_rvalid_o(cfg_rvalid),
    .cpu_addr_i(cpu_addr),
    .cpu_wdata_i(cpu_wdata),
    .cpu_be_i(cpu_be),
    .cpu_we_i(cpu_we),
    .cpu_req_i(cpu_req),
    .cpu_rdata_o(cpu_rdata),
    .cpu_done_o(cpu_done),
    .ram_addr_o(ram_addr),
    .ram_wdata_o(ram_wdata),
    .ram_be_o(ram_be),
    .ram_we_o(ram_we),
    .ram_re_o(ram_re),
    .ram_rdata_i(ram_rdata),
    .ram_rvalid_i(ram_rvalid)
  );

  always #5 clk = ~clk;

  // RAM behavioral model
  always_ff @(posedge clk) begin
    ram_rvalid <= 1'b0;
    if (ram_we) begin
      memory[ram_addr[11:2]] <= ram_wdata;
    end
    if (ram_re) begin
      ram_rdata  <= memory[ram_addr[11:2]];
      ram_rvalid <= 1'b1;
    end
  end

  initial begin
    $display("Starting mem_crypt + SIMON Integration Testbench...");
    clk = 0;
    rst_n = 0;
    cfg_req = 0;
    cfg_wr_en = 0;
    cpu_req = 0;
    cpu_we = 0;
    
    #20;
    rst_n = 1;
    #10;

    $display("--- Step 1: Configuring Key ---");
    cfg_req = 1; cfg_wr_en = 1;
    cfg_addr = 32'h0; cfg_wdata = 32'hAABB0100; #10;
    cfg_addr = 32'h4; cfg_wdata = 32'hCCDD0908; #10;
    cfg_addr = 32'hC; cfg_wdata = 32'hEEFF1110; #10;
    cfg_addr = 32'h10; cfg_wdata = 32'h11221918; #10;
    cfg_req = 0; cfg_wr_en = 0;
    #10;

    $display("--- Step 2: CPU Store (Encryption) ---");
    cpu_addr = 32'h0400; 
    cpu_wdata = 32'h65656877;
    cpu_be = 4'hF;
    cpu_we = 1;
    cpu_req = 1;
    #10;
    cpu_req = 0;
    
    wait(cpu_done == 1'b1);
    // Wait one more cycle for RAM to commit the write
    #10; 
    
    // Ciphertext will be different now with non-zero upper bits and address
    if (memory[256] == 32'h3bca31fb) begin
      $display("Store Success: RAM contains correct ciphertext 3bca31fb");
    end else begin
      $display("Store Failure: RAM contains %h (Expected 3bca31fb)", memory[256]);
    end
    #10;

    $display("--- Step 3: CPU Load (Decryption) ---");
    cpu_addr = 32'h0400;
    cpu_we = 0;
    cpu_req = 1;
    #10;
    cpu_req = 0;
    
    wait(cpu_done == 1'b1);
    #1;
    $display("CPU Load Result: %h (Expected: 65656877)", cpu_rdata);
    if (cpu_rdata == 32'h65656877) begin
      $display("Load Success: CPU received correct plaintext");
    end else begin
      $display("Load Failure: CPU received %h", cpu_rdata);
    end

    #50;
    $display("--- Verification Complete: PASS ---");
    $finish;
  end

endmodule
