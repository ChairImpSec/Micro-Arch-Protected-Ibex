// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
// Modified 2026 by Niels Wieser, TU Darmstadt:
// adapted as evaluation system for the micro-architecturally protected Ibex.

`ifndef RV32M
  `define RV32M ibex_pkg::RV32MNone
`endif

`ifndef RV32B
  `define RV32B ibex_pkg::RV32BNone
`endif

`ifndef RegFile
  `define RegFile ibex_pkg::RegFileFF
`endif

/**
 * Ibex simple system for synthesis (Vivado Wrapper)
 */

module vivado_wrapper (
  // Clk IO
  input  logic         clk,
  input  logic         reset,
  // Cipher IO
  input  logic [127:0] plaintext_s0,
  input  logic [127:0] plaintext_s1,
  input  logic [127:0] key_s0,
  input  logic [127:0] key_s1,
  input  logic [1359:0] Fresh,
  output logic [127:0] ciphertext_s0,
  output logic [127:0] ciphertext_s1,
  output logic         done,
  // Debug
  input logic          BUTTON,
  output logic         reached_main,
  output logic [9:0]   LED
);

//    Memory Depths
    parameter int ROM_DEPTH  = 8192;   // instr (0x10) + rom (0x11), decode {addr[16],addr[13:2]}
    parameter int RAM_DEPTH  = 1536;   // 8 KB, matches linker ram region (0x120000, LENGTH 0x2000)
//    RAM implementation style: "BRAM" | "LUT" | "FF"
    parameter     RAM_IMPL  = "PRNG";

    logic rst_n;
    logic do_rst;
    assign do_rst = reset ^ BUTTON;
    assign rst_n = !do_rst;

  // CPU Interface Signals
  logic [31:0] instr_addr;
  logic        instr_req;
  logic [31:0] instr_rdata;
  logic        instr_rvalid;

  // ROM data port (bootloader / rodata reads)
  logic [31:0] rom_addr;
  logic [31:0] rom_wdata;
  logic [ 3:0] rom_be;
  logic        rom_we;
  logic        rom_re;
  logic [31:0] rom_rdata;
  logic        rom_rvalid;

  logic [31:0] ram_addr;
  logic [31:0] ram_wdata;
  logic [ 3:0] ram_be;
  logic        ram_we;
  logic        ram_re;
  logic [31:0] ram_rdata;
  logic        ram_rvalid;

  // Cipher config (MMIO) for the encrypted RAM
  logic [31:0] cfg_addr;
  logic        cfg_req;
  logic        cfg_we;
  logic [31:0] cfg_wdata;
  logic [31:0] cfg_rdata;
  logic        cfg_rvalid;

  logic [31:0] instr_rdata_raw;
  logic [31:0] rom_rdata_raw;
  logic [31:0] ram_rdata_raw;

  prim_buf #(.Width(32)) u_instr_rdata_buf (.in_i(instr_rdata_raw), .out_o(instr_rdata));
  prim_buf #(.Width(32)) u_rom_rdata_buf   (.in_i(rom_rdata_raw),   .out_o(rom_rdata));
  prim_buf #(.Width(32)) u_ram_rdata_buf   (.in_i(ram_rdata_raw),   .out_o(ram_rdata));
  
  logic        mem_busy;
  logic        rom_busy;
  logic        ram_busy;
  assign mem_busy = rom_busy | ram_busy;

  logic [31:0] io_addr;
  logic [31:0] io_addr_word;
  logic [ 3:0] io_be;
  logic [31:0] io_wdata;
  logic        io_req;
  logic [31:0] io_rdata;
  logic        io_rvalid;
  logic        io_busy;

  // --- 128-bit / 32-bit IO Registers ---
  logic [127:0] plaintext_s0_reg;
  logic [127:0] plaintext_s1_reg;
  logic [127:0] key_s0_reg;
  logic [127:0] key_s1_reg;
  logic [127:0] ciphertext_s0_reg;
  logic [127:0] ciphertext_s1_reg;
  logic        cpu_done_reg;
  logic        cpu_start_reg;


    // --- Controller FSM ---
  typedef enum logic [1:0] {
    ST_IDLE,
    ST_PREPARE,
    ST_WAIT_CPU,
    ST_DONE
  } state_e;

  state_e state_q, state_d;

  // Write enable one-hot decoding
  logic [27:0] write_en_onehot;
  always_comb begin
    write_en_onehot = '0;
    if (io_addr_word <= 32'h1b) begin
      write_en_onehot[io_addr_word] = 1'b1;
    end
  end

  logic [31:0] p0_d, p1_d, k0_d, k1_d, fr_d;
  logic        p0_en, p1_en, k0_en, k1_en, fr_en;

  logic [31:0] c0_d, c1_d;
  logic        done_d, start_d;
  logic        c0_en_dummy, c1_en_dummy, done_en, start_en;

  assign framework_io_en = (state_q == ST_PREPARE);

  DFFE_cell #(.N(128 * 4)) u_input_regs (
    .CK    (clk),
    .D     ({plaintext_s0, plaintext_s1, key_s0, key_s1}),
    .EN    (framework_io_en),
    .RST_N (rst_n),
    .Q     ({plaintext_s0_reg, plaintext_s1_reg, key_s0_reg, key_s1_reg}),
    .QN    ()
  );


  logic [3:0] c0_en;
  logic [3:0] c1_en;

  genvar w;
  generate
    for (w = 0; w < 4; w = w + 1) begin : gen_c0_reg
      assign c0_en[w] = (state_q == ST_PREPARE) || (state_q == ST_WAIT_CPU && io_req && |io_be && write_en_onehot[18 + w]);
      DFFE_cell #(.N(32)) u_c0_reg_word (
        .CK    (clk),
        .D     (io_wdata),
        .EN    (c0_en[w]),
        .RST_N (rst_n),
        .Q     (ciphertext_s0_reg[(3-w)*32 +: 32]),
        .QN    ()
      );
    end
    for (w = 0; w < 4; w = w + 1) begin : gen_c1_reg
      assign c1_en[w] = (state_q == ST_PREPARE) || (state_q == ST_WAIT_CPU && io_req && |io_be && write_en_onehot[22 + w]);
      DFFE_cell #(.N(32)) u_c1_reg_word (
        .CK    (clk),
        .D     (io_wdata),
        .EN    (c1_en[w]),
        .RST_N (rst_n),
        .Q     (ciphertext_s1_reg[(3-w)*32 +: 32]),
        .QN    ()
      );
    end
  endgenerate

  assign done_en  = (state_q == ST_PREPARE) || (state_q == ST_WAIT_CPU && io_req && |io_be && write_en_onehot[26]) || (state_q == ST_DONE);
  assign start_en = (state_q == ST_PREPARE) || (state_q == ST_WAIT_CPU && io_req && |io_be && write_en_onehot[27]) || (state_q == ST_DONE);


  DFFE_cell #(.N(1))  u_done_reg  (.CK(clk), .D(io_wdata[0]), .EN(done_en),  .RST_N(rst_n), .Q(cpu_done_reg),      .QN());
  DFFE_cell #(.N(1))  u_start_reg (.CK(clk), .D(io_wdata[0]), .EN(start_en), .RST_N(rst_n), .Q(cpu_start_reg),     .QN());

  // Framework Outputs
  assign ciphertext_s0 = ciphertext_s0_reg;
  assign ciphertext_s1 = ciphertext_s1_reg;
  

  logic ctrl_mem_rst_q, ctrl_mem_rst_d;

  logic start;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        start <= 1'b1;
    end else if (state_q == ST_WAIT_CPU) begin
        start <= 1'b0;
    end
  end

  assign done = (state_q == ST_DONE);
  assign reached_main = cpu_start_reg;

  // Memories resetting logic
  logic ram_rst_n;
  assign ram_rst_n = rst_n && !ctrl_mem_rst_q;
  // assign ram_rst_n = 1'b1;

  // Forward the random bits from the framework PRNG to our circuit.
  logic [31:0] fresh_q;
  DFFR_cell #(.N(32)) u_fresh_reg (.CK(clk), .D(Fresh[31:0]), .RN(rst_n), .Q(fresh_q), .QN());

  always_comb begin
    state_d = state_q;
    ctrl_mem_rst_d = 1'b0;

    case (state_q)
      ST_IDLE: begin
        if (start && !mem_busy) begin
          state_d = ST_PREPARE;
        end
      end

      ST_PREPARE: begin
        state_d = ST_WAIT_CPU;
      end

      ST_WAIT_CPU: begin
        if (cpu_done_reg) begin
          state_d = ST_DONE;
        end
      end

      ST_DONE: begin
        ctrl_mem_rst_d = 1'b1;
        if (start) state_d = ST_IDLE;
      end
      
      default: state_d = ST_IDLE;
    endcase
  end

  // Register Bank Logic (CPU and Wrapper access)
  assign io_addr_word = io_addr[11:2];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_IDLE;
      ctrl_mem_rst_q <= 1'b0;
    end else begin
      state_q <= state_d;
      ctrl_mem_rst_q <= ctrl_mem_rst_d;
    end
  end

  // CPU Read from Registers
  logic [27:0] select_read_value;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      io_rvalid <= 1'b0;
      select_read_value <= '0;
    end else begin
      io_rvalid <= io_req;
      select_read_value <= '0;
      if (io_addr_word <= 32'h1b) begin
        select_read_value[io_addr_word] <= 1'b1;
      end
    end
  end

  logic [31:0] read_words[28];
  assign read_words[0]  = 32'b0; // reserved
  assign read_words[1]  = plaintext_s0_reg[127:96];
  assign read_words[2]  = plaintext_s0_reg[95:64];
  assign read_words[3]  = plaintext_s0_reg[63:32];
  assign read_words[4]  = plaintext_s0_reg[31:0];
  assign read_words[5]  = plaintext_s1_reg[127:96];
  assign read_words[6]  = plaintext_s1_reg[95:64];
  assign read_words[7]  = plaintext_s1_reg[63:32];
  assign read_words[8]  = plaintext_s1_reg[31:0];
  assign read_words[9]  = key_s0_reg[127:96];
  assign read_words[10] = key_s0_reg[95:64];
  assign read_words[11] = key_s0_reg[63:32];
  assign read_words[12] = key_s0_reg[31:0];
  assign read_words[13] = key_s1_reg[127:96];
  assign read_words[14] = key_s1_reg[95:64];
  assign read_words[15] = key_s1_reg[63:32];
  assign read_words[16] = key_s1_reg[31:0];
  assign read_words[17] = Fresh[31:0];
  assign read_words[18] = ciphertext_s0_reg[31:0];
  assign read_words[19] = ciphertext_s0_reg[63:32];
  assign read_words[20] = ciphertext_s0_reg[95:64];
  assign read_words[21] = ciphertext_s0_reg[127:96];
  assign read_words[22] = ciphertext_s1_reg[31:0];
  assign read_words[23] = ciphertext_s1_reg[63:32];
  assign read_words[24] = ciphertext_s1_reg[95:64];
  assign read_words[25] = ciphertext_s1_reg[127:96];
  assign read_words[26] = {31'b0, cpu_done_reg};
  assign read_words[27] = {31'b0, cpu_start_reg};

  logic [31:0] read_out_selected[28];
  genvar k;
  generate
    for (k = 0; k < 28; k = k + 1) begin : gen_read_mux
      AND_gate #(.N(32)) u_and (
        .A1({32{select_read_value[k]}}),
        .A2(read_words[k]),
        .ZN(read_out_selected[k])
      );
    end
  endgenerate

  integer m;
  always_comb begin
    io_rdata = '0;
    for (m = 0; m < 28; m = m + 1) begin
      io_rdata = io_rdata | read_out_selected[m];
    end
  end


  assign io_busy = 1'b0;

  // CPU Instantiation
  vivado_cpu u_cpu (
    .clk                     (clk),
    .rst_n                   (state_q == ST_WAIT_CPU),

    .instr_addr_o            (instr_addr),
    .instr_req_o             (instr_req),
    .instr_rdata_i           (instr_rdata),
    .instr_rvalid_i          (instr_rvalid),
    .rom_busy_i              (mem_busy),

    .rom_addr_o              (rom_addr),
    .rom_wdata_o             (rom_wdata),
    .rom_be_o                (rom_be),
    .rom_we_o                (rom_we),
    .rom_re_o                (rom_re),
    .rom_rdata_i             (rom_rdata),
    .rom_rvalid_i            (rom_rvalid),

    .ram_addr_o              (ram_addr),
    .ram_wdata_o             (ram_wdata),
    .ram_be_o                (ram_be),
    .ram_we_o                (ram_we),
    .ram_re_o                (ram_re),
    .ram_rdata_i             (ram_rdata),
    .ram_rvalid_i            (ram_rvalid),
    .ram_busy_i              (mem_busy),

    .cfg_addr_o              (cfg_addr),
    .cfg_req_o               (cfg_req),
    .cfg_we_o                (cfg_we),
    .cfg_wdata_o             (cfg_wdata),
    .cfg_rdata_i             (cfg_rdata),
    .cfg_rvalid_i            (cfg_rvalid),

    .io_addr_o               (io_addr),
    .io_we_o                 (io_be),
    .io_wdata_o              (io_wdata),
    .io_req_o                (io_req),
    .io_rdata_i              (io_rdata),
    .io_rvalid_i             (io_rvalid),
    .io_busy_i               (io_busy)
  );

  // --- ROM (BRAM, loaded from firmware image) ---
  // Holds the instruction region (0x10xxxx) and the read-only ROM/rodata
  // region (0x11xxxx), distinguished by address bit 16. Port A serves the
  // instruction fetch, port B serves data-side reads (bootloader / rodata).
  // Not cleared on reset.
  memory #(
    .MEM_STYLE("BRAM"),
    .DEPTH(ROM_DEPTH),
    .CLEAR_ON_RESET(0),
    .INIT_FILE("firmware/aes/firmware.mem")
  ) u_rom (
    .CLK(clk),
    .RST_N(rst_n),
    .BUSY(rom_busy),

    // Port A: Instruction fetch. Index = {addr[16], addr[13:2]} (instr 0x10 -> 0..4095,
    // rom 0x11 -> 4096..8191). addr[17] is always 0 for the ROM, so it is not decoded.
    .A_ADDR({19'b0, instr_addr[16], instr_addr[13:2]}),
    .A_WE(4'b0),
    .A_WDATA(32'b0),
    .A_RE(instr_req),
    .A_RDATA(instr_rdata_raw),
    .A_RVALID(instr_rvalid),

    // Port B: Data-side ROM reads (same decode)
    .B_ADDR({19'b0, rom_addr[16], rom_addr[13:2]}),
    .B_WE(4'b0),
    .B_WDATA(32'b0),
    .B_RE(rom_re),
    .B_RDATA(rom_rdata_raw),
    .B_RVALID(rom_rvalid)
  );

  // --- RAM (separate address range 0x12xxxx) ---
  // Implementation chosen by RAM_IMPL:
  //   "FF"   -> FDRE register file
  //   "BRAM" -> inferred block RAM       (cleared by the reset FSM)
  //   "LUT"  -> inferred distributed RAM (cleared by the reset FSM)
  //   "ENC"  -> enc_memory (mem_crypt block cipher)
  //   "PRNG" -> enc_memory (mem_prng d+1 shared memory)
  // Data uses port B; port A is unused. Cleared whenever ram_rst_n is low.
  generate
    if (RAM_IMPL == "ENC" || RAM_IMPL == "PRNG" || (1'b1 == 1'b1)) begin : g_enc_ram
      // Encrypted RAM. The engine needs the full byte address as its tweak, so
      // the untruncated ram_addr is passed on port B.
      localparam ENC_ENGINE = (RAM_IMPL == "PRNG") ? "PRNG" : "CRYPT";
      enc_memory #(
        .ENGINE("PRNG"),
        .MEM_STYLE("BRAM"),
        .DEPTH(RAM_DEPTH)
      ) u_ram (
        .CLK(clk),
        .RST_N(ram_rst_n),
        .BUSY(ram_busy),

        // Fresh randomness (one-time mask) for the PRNG secret-sharing engine
        .RND(fresh_q),

        // Port A: unused
        .A_ADDR(32'b0),
        .A_WE(4'b0),
        .A_WDATA(32'b0),
        .A_RE(1'b0),
        .A_RDATA(),
        .A_RVALID(),

        // Port B: data (full byte address for the cipher tweak)
        .B_ADDR(ram_addr),
        .B_WE(ram_we ? ram_be : 4'b0),
        .B_WDATA(ram_wdata),
        .B_RE(ram_re),
        .B_RDATA(ram_rdata_raw),
        .B_RVALID(ram_rvalid),

        // Cipher config (MMIO)
        .cfg_addr_i(cfg_addr),
        .cfg_req_i(cfg_req),
        .cfg_wr_en_i(cfg_we),
        .cfg_wdata_i(cfg_wdata),
        .cfg_rdata_o(cfg_rdata),
        .cfg_rvalid_o(cfg_rvalid)
      );
    end else begin : g_plain_ram
      // Plain (unencrypted) RAM.
      memory #(
        .MEM_STYLE(RAM_IMPL),
        .DEPTH(RAM_DEPTH),
        .CLEAR_ON_RESET(1),
        .RESET_START(0),
        .RESET_DEPTH(RAM_DEPTH),
        .INIT_FILE("")
      ) u_ram (
        .CLK(clk),
        .RST_N(ram_rst_n),
        .BUSY(ram_busy),

        // Port A: unused
        .A_ADDR(32'b0),
        .A_WE(4'b0),
        .A_WDATA(32'b0),
        .A_RE(1'b0),
        .A_RDATA(),
        .A_RVALID(),

        // Port B: data (word index)
        .B_ADDR({20'b0, ram_addr[13:2]}),
        .B_WE(ram_we ? ram_be : 4'b0),
        .B_WDATA(ram_wdata),
        .B_RE(ram_re),
        .B_RDATA(ram_rdata_raw),
        .B_RVALID(ram_rvalid)
      );

      // Cipher config device is unused; keep it responding on the bus so an
      // (accidental) access to the config range still completes.
      assign cfg_rdata = 32'b0;
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) cfg_rvalid <= 1'b0;
        else        cfg_rvalid <= cfg_req;
      end
    end
  endgenerate

  // ---- DEBUG LEDs
  logic dbg_fetch_moved;  // CPU fetched past the boot word  -> executing
  logic dbg_data_req;     // any data access issued
  logic dbg_data_resp;    // any device returned rvalid
  logic dbg_rom_rd;       // data-side ROM read (copy loop reading .data)
  logic dbg_ram_wr;       // RAM write (copy dest / bss / stack)
  logic dbg_ram_rd;       // RAM read
  logic dbg_io_req;       // framework/IO access reached (~ reached_main store)
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dbg_fetch_moved <= 1'b0;
      dbg_data_req    <= 1'b0;
      dbg_data_resp   <= 1'b0;
      dbg_rom_rd      <= 1'b0;
      dbg_ram_wr      <= 1'b0;
      dbg_ram_rd      <= 1'b0;
      dbg_io_req      <= 1'b0;
    end else begin
      if (instr_req && instr_addr != 32'h00100000)         dbg_fetch_moved <= 1'b1;
      if (rom_re | ram_re | ram_we | io_req | cfg_req)      dbg_data_req    <= 1'b1;
      if (rom_rvalid | ram_rvalid | io_rvalid | cfg_rvalid) dbg_data_resp   <= 1'b1;
      if (rom_re)                                           dbg_rom_rd      <= 1'b1;
      if (ram_we)                                           dbg_ram_wr      <= 1'b1;
      if (ram_re)                                           dbg_ram_rd      <= 1'b1;
      if (io_req)                                           dbg_io_req      <= 1'b1;
    end
  end

  assign LED[0] = dbg_fetch_moved;        // off -> stuck at boot (ROM fetch broken)
  assign LED[1] = dbg_data_req;           // off -> never did a load/store
  assign LED[2] = dbg_data_resp;          // req on but this off -> a device never answered (hang)
  assign LED[3] = dbg_rom_rd;             // data-side ROM read happened
  assign LED[4] = dbg_ram_wr;             // RAM write happened
  assign LED[5] = dbg_ram_rd;             // RAM read happened
  assign LED[6] = state_q == ST_WAIT_CPU; // (reference)
  assign LED[7] = dbg_io_req;             // reached the framework/IO write
  assign LED[8] = done;




  logic [19:0] flicker_cnt;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) flicker_cnt[0] <= 1'b0;
    else        flicker_cnt[0] <= ~flicker_cnt[0];
  end

  genvar i;
  generate
    for (i = 1; i < 20; i = i + 1) begin : gen_flicker_ripple
      always_ff @(posedge flicker_cnt[i-1] or negedge rst_n) begin
        if (!rst_n) flicker_cnt[i] <= 1'b0;
        else        flicker_cnt[i] <= ~flicker_cnt[i];
      end
    end
  endgenerate

  assign LED[9] = flicker_cnt[19];

endmodule
