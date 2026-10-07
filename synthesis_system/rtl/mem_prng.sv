// Copyright (c) 2026 Niels Wieser, TU Darmstadt
// SPDX-License-Identifier: MIT

//////////////////////////////////////////////////////////////////////////////////
// Module Name: mem_prng
// Description: Drop-in alternative to mem_crypt with the same interface, but the
//   block cipher is replaced by boolean masking (first-order secret sharing)
//   with a fresh one-time-pad mask.
//
//   A fresh random word (rnd_i, sampled from Fresh[31:0] in the wrapper) is used
//   as the mask. On a store the data is split into two shares:
//       main RAM   : share0 = data ^ rnd
//       second RAM : share1 = rnd            (the mask itself)
//   On a load both shares are read back and recombined:
//       data = share0 ^ share1 = (data ^ rnd) ^ rnd
//
//   Because each byte is masked independently and the mask is stored per word in
//   the second RAM, partial (byte) writes need NO read-modify-write: the byte
//   lanes are written straight through using the byte enables, and every byte is
//   recombined with its own stored mask on a read. The datapath therefore
//   reduces to: capture -> XOR -> store (writes) and read -> XOR -> register
//   (reads) with no FSM.
//
//   Timing (the Ibex issues at most one access every 2nd cycle):
//     Write  T   : capture wdata into data_q
//            T+1 : store  share0 = data_q ^ rnd   and   share1 = rnd
//            T+2 : assert done
//     Read   T   : issue the RAM read (both shares)
//            T+1 : recombine plaintext = share0 ^ share1, capture in output reg
//            T+2 : drive the registered read data + done
//
//   Every data register is loaded with 0 whenever it is not capturing, so its
//   only transitions are 0 <-> value. Combined with the one-access-per-two-
//   cycles spacing this keeps the register transitions glitch-safe, which is why
//   no explicit DCR output gating is needed here.
//////////////////////////////////////////////////////////////////////////////////

module mem_prng (
  // Clock and reset
  input  logic        clk_i,
  input  logic        rst_ni,

  // Configuration (MMIO)
  input  logic [31:0] cfg_addr_i,
  input  logic        cfg_req_i,
  input  logic        cfg_wr_en_i,
  input  logic [31:0] cfg_wdata_i,
  output logic [31:0] cfg_rdata_o,
  output logic        cfg_rvalid_o,

  // CPU Interface
  input  logic [31:0] cpu_addr_i,
  input  logic [31:0] cpu_wdata_i,
  input  logic [ 3:0] cpu_be_i,
  input  logic        cpu_we_i,
  input  logic        cpu_req_i,
  output logic [31:0] cpu_rdata_o,
  output logic        cpu_done_o,

  // Fresh randomness (sampled from Fresh[31:0] in the wrapper). Used as the
  // one-time mask for the secret sharing on stores.
  input  logic [31:0] rnd_i,

  // RAM Interface (share0 = data ^ mask)
  output logic [31:0] ram_addr_o,
  output logic [31:0] ram_wdata_o,
  output logic [ 3:0] ram_be_o,
  output logic        ram_we_o,
  output logic        ram_re_o,
  input  logic [31:0] ram_rdata_i,
  input  logic        ram_rvalid_i,

  // Second RAM interface (share1 = mask). Shares address/byte-enable/we/re with
  // the main RAM (driven by ram_*_o); only the data words differ.
  output logic [31:0] ram2_wdata_o,
  input  logic [31:0] ram2_rdata_i
);

  // Unused in the masking datapath (the mask comes from rnd_i, not the RAM
  // response strobe); kept so the interface matches mem_crypt.
  logic unused_ram_rvalid;
  assign unused_ram_rvalid = ram_rvalid_i;

  // ==========================================================================
  // Configuration Logic (MMIO)
  // ==========================================================================
  // A 128-bit key / rounds field is still writable and read back for interface
  // compatibility with mem_crypt, but it is NOT used by the masking datapath.
  logic [31:0] master_key_0_q, master_key_1_q, master_key_2_q, master_key_3_q;
  logic [ 2:0] additional_rounds_q;
  logic [ 2:0] cfg_rounds_d;
  logic        cfg_k0_en, cfg_k1_en, cfg_k2_en, cfg_k3_en, cfg_rounds_en;
  logic        cfg_rvalid_next;
  logic [31:0] cfg_rdata_next;

  // Key 128-bit:
  // 0x00: k0_low   (master_key_0)
  // 0x04: k0_high  (master_key_1)
  // 0x0C: k1_low   (master_key_2)
  // 0x10: k1_high  (master_key_3)
  assign cfg_k0_en     = (cfg_wr_en_i && cfg_req_i && cfg_addr_i[4:0] == 5'h00);
  assign cfg_k1_en     = (cfg_wr_en_i && cfg_req_i && cfg_addr_i[4:0] == 5'h04);
  assign cfg_k2_en     = (cfg_wr_en_i && cfg_req_i && cfg_addr_i[4:0] == 5'h0C);
  assign cfg_k3_en     = (cfg_wr_en_i && cfg_req_i && cfg_addr_i[4:0] == 5'h10);
  assign cfg_rounds_en = (!rst_ni) || (cfg_wr_en_i && cfg_req_i && cfg_addr_i[4:0] == 5'h08);

  assign cfg_rounds_d = rst_ni ? cfg_wdata_i[2:0] : 3'd1;

  DFFE_cell #(.N(32)) u_k0_reg     (.CK(clk_i), .D(cfg_wdata_i), .EN(cfg_k0_en),     .RST_N(rst_ni), .Q(master_key_0_q),     .QN());
  DFFE_cell #(.N(32)) u_k1_reg     (.CK(clk_i), .D(cfg_wdata_i), .EN(cfg_k1_en),     .RST_N(rst_ni), .Q(master_key_1_q),     .QN());
  DFFE_cell #(.N(32)) u_k2_reg     (.CK(clk_i), .D(cfg_wdata_i), .EN(cfg_k2_en),     .RST_N(rst_ni), .Q(master_key_2_q),     .QN());
  DFFE_cell #(.N(32)) u_k3_reg     (.CK(clk_i), .D(cfg_wdata_i), .EN(cfg_k3_en),     .RST_N(rst_ni), .Q(master_key_3_q),     .QN());
  DFFE_cell #(.N(3))  u_rounds_reg (.CK(clk_i), .D(cfg_rounds_d), .EN(cfg_rounds_en), .RST_N(1'b1),  .Q(additional_rounds_q), .QN());

  // MMIO read path
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      cfg_rvalid_next <= 1'b0;
      cfg_rdata_next  <= '0;
    end else begin
      cfg_rvalid_next <= cfg_req_i;
      unique case (cfg_addr_i[4:0])
        5'h00: cfg_rdata_next <= master_key_0_q;
        5'h04: cfg_rdata_next <= master_key_1_q;
        5'h08: cfg_rdata_next <= {29'b0, additional_rounds_q};
        5'h0C: cfg_rdata_next <= master_key_2_q;
        5'h10: cfg_rdata_next <= master_key_3_q;
        default: cfg_rdata_next <= '0;
      endcase
    end
  end
  assign cfg_rvalid_o = cfg_rvalid_next;
  assign cfg_rdata_o  = cfg_rdata_next;

  // ==========================================================================
  // Masking datapath (no FSM, no RMW)
  // ==========================================================================

  // --- Request acceptance ---
  // cpu_req_i is a single-cycle, always-granted pulse; accept it directly.
  logic acc_we, acc_rd;
  assign acc_we = cpu_req_i &  cpu_we_i;   // write request this cycle
  assign acc_rd = cpu_req_i & ~cpu_we_i;   // read  request this cycle

  // --- Request pipeline registers (valid the cycle after acceptance) ---
  // Address / byte-enables are held for the store that happens one cycle later;
  // wr_pend_q / rd_pend_q flag which operation is due. All auto-clear to 0.
  logic [31:0] addr_d,  addr_q;
  logic [ 3:0] be_d,    be_q;
  logic        wr_pend_q, rd_pend_q;

  AND_gate #(.N(32)) g_addr_gate (.A1(cpu_addr_i), .A2({32{acc_we}}), .ZN(addr_d));
  AND_gate #(.N(4))  g_be_gate   (.A1(cpu_be_i),   .A2({4{acc_we}}),  .ZN(be_d));

  DFFE_cell #(.N(32)) u_addr_reg (.CK(clk_i), .D(addr_d),  .EN(1'b1), .RST_N(rst_ni), .Q(addr_q),    .QN());
  DFFE_cell #(.N(4))  u_be_reg   (.CK(clk_i), .D(be_d),    .EN(1'b1), .RST_N(rst_ni), .Q(be_q),      .QN());
  DFFE_cell #(.N(1))  u_wrp_reg  (.CK(clk_i), .D(acc_we),  .EN(1'b1), .RST_N(rst_ni), .Q(wr_pend_q), .QN());
  DFFE_cell #(.N(1))  u_rdp_reg  (.CK(clk_i), .D(acc_rd),  .EN(1'b1), .RST_N(rst_ni), .Q(rd_pend_q), .QN());

  // --- Write-data capture register (loaded with 0 when not capturing) ---
  logic [31:0] data_cap, data_q;
  AND_gate #(.N(32)) g_data_gate (.A1(cpu_wdata_i), .A2({32{acc_we}}), .ZN(data_cap));
  DFFE_cell #(.N(32)) u_data_reg (.CK(clk_i), .D(data_cap), .EN(1'b1), .RST_N(rst_ni), .Q(data_q), .QN());

  // --- Store shares: main RAM = data ^ mask, second RAM = mask ---
  XOR_gate #(.N(32)) g_share0 (.A(data_q), .B(rnd_i), .Z(ram_wdata_o));
  assign ram2_wdata_o = rnd_i;

  // --- RAM control ---
  // Reads are issued in the request cycle (T) with the live address; the store
  // happens the following cycle (T+1) from the captured data/address. The second
  // RAM shares this control (see enc_memory).
  assign ram_re_o   = acc_rd;
  assign ram_we_o   = wr_pend_q;
  assign ram_be_o   = be_q;
  assign ram_addr_o = wr_pend_q ? addr_q : cpu_addr_i;

  // --- Read recombination: register the two shares, then XOR ---
  // The pipeline register sits before the XOR, so no register ever holds the
  // recombined (unmasked) value; only the combinational XOR at the output does.
  // Each share register is loaded with 0 whenever no recombination happens this
  // cycle (rd_pend_q low), keeping its transitions 0 <-> share.
  logic [31:0] share0_d, share1_d, share0_q, share1_q;
  AND_gate #(.N(32)) g_share0_gate (.A1(ram_rdata_i),  .A2({32{rd_pend_q}}), .ZN(share0_d));
  AND_gate #(.N(32)) g_share1_gate (.A1(ram2_rdata_i), .A2({32{rd_pend_q}}), .ZN(share1_d));
  DFFE_cell #(.N(32)) u_share0_reg (.CK(clk_i), .D(share0_d), .EN(1'b1), .RST_N(rst_ni), .Q(share0_q), .QN());
  DFFE_cell #(.N(32)) u_share1_reg (.CK(clk_i), .D(share1_d), .EN(1'b1), .RST_N(rst_ni), .Q(share1_q), .QN());
  XOR_gate #(.N(32)) g_recombine (.A(share0_q), .B(share1_q), .Z(cpu_rdata_o));

  // --- Completion: both reads and writes respond at T+2 ---
  // (one cycle after the store commits / the read data is captured), so
  // cpu_done_o lines up with the registered read data.
  logic wr_done_q, rd_done_q;
  DFFE_cell #(.N(1)) u_wrdone_reg (.CK(clk_i), .D(wr_pend_q), .EN(1'b1), .RST_N(rst_ni), .Q(wr_done_q), .QN());
  DFFE_cell #(.N(1)) u_rddone_reg (.CK(clk_i), .D(rd_pend_q), .EN(1'b1), .RST_N(rst_ni), .Q(rd_done_q), .QN());
  assign cpu_done_o = wr_done_q | rd_done_q;

endmodule
