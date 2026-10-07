// Copyright (c) 2026 Niels Wieser, TU Darmstadt
// SPDX-License-Identifier: MIT

module mem_crypt (
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

  // RAM Interface
  output logic [31:0] ram_addr_o,
  output logic [31:0] ram_wdata_o,
  output logic [ 3:0] ram_be_o,
  output logic        ram_we_o,
  output logic        ram_re_o,
  input  logic [31:0] ram_rdata_i,
  input  logic        ram_rvalid_i
);


  // Signal Definitions
  // MMIO config
  logic [31:0] master_key_0_q, master_key_1_q, master_key_2_q, master_key_3_q;
  logic [ 2:0] additional_rounds_q;
  logic [ 2:0] cfg_rounds_d;
  logic        cfg_k0_en, cfg_k1_en, cfg_k2_en, cfg_k3_en, cfg_rounds_en;
  logic        cfg_rvalid_next;
  logic [31:0] cfg_rdata_next;


  // --- Configuration Logic ---
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

  DFFE_cell #(.N(32)) u_k0_reg  (.CK(clk_i), .D(cfg_wdata_i), .EN(cfg_k0_en), .RST_N(rst_ni), .Q(master_key_0_q), .QN());
  DFFE_cell #(.N(32)) u_k1_reg  (.CK(clk_i), .D(cfg_wdata_i), .EN(cfg_k1_en), .RST_N(rst_ni), .Q(master_key_1_q), .QN());
  DFFE_cell #(.N(32)) u_k2_reg  (.CK(clk_i), .D(cfg_wdata_i), .EN(cfg_k2_en), .RST_N(rst_ni), .Q(master_key_2_q), .QN());
  DFFE_cell #(.N(32)) u_k3_reg  (.CK(clk_i), .D(cfg_wdata_i), .EN(cfg_k3_en), .RST_N(rst_ni), .Q(master_key_3_q), .QN());
  DFFE_cell #(.N(3))  u_rounds_reg   (.CK(clk_i), .D(cfg_rounds_d),   .EN(cfg_rounds_en), .RST_N(1'b1), .Q(additional_rounds_q), .QN());

  // --- MMIO Read Path ---
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
  assign cfg_rdata_o = cfg_rdata_next;


  // Data request
  logic [31:0] addr_q;
  logic [ 3:0] be_q, be_qn;
  logic cpu_done;
  
  
  // Status FSM
  logic state_idle_d, state_idle_q, state_idle_dcr;     // Wait for a request. loads can be issued immediatly, but need to configure the cipher.
  logic state_load_d, state_load_q, state_load_dcr;     // Send cipher output to cpu and reset state.
  logic state_store_d, state_store_q, state_store_dcr;  // Send cipher output to ram and resond to cpu.
  logic state_rmw_d, state_rmw_q, state_rmw_dcr;        // Wait for data, then store decrypted bytes, merging with write data. Then go into store.  
  logic state_clear_d, state_clear_q, state_clear_dcr;  // Wait one clock cycle, so the cipher can clear transitions.  
  always_comb begin
    // States are unique
    
    // Defaults
    state_idle_d  = 1'b0;
    state_load_d  = 1'b0;
    state_store_d = 1'b0;
    state_rmw_d   = 1'b0;
    state_clear_d = 1'b0;
    
    // Idle state
    if (state_idle_q) begin
      if (cpu_req_i) begin
        // If we receive a request, we have to transition in one of the 3 other states and prepare the data.
        state_load_d  = cpu_we_i == 1'b0;
        state_store_d = cpu_we_i == 1'b1 && cpu_be_i == 4'b1111;
        state_rmw_d   = cpu_we_i == 1'b1 && cpu_be_i != 4'b1111;
      end else begin
        state_idle_d  = 1'b1;
      end
    end

    // Load state
    if(state_load_q) begin
      if(ram_rvalid_i) begin
        state_idle_d  = 1'b1;
      end else begin
        state_load_d  = 1'b1;
      end
    end

    // Store state
    if(state_store_q) begin
      state_idle_d    = 1'b1;
    end

    // RMW state
    if(state_rmw_q) begin
      if(ram_rvalid_i) begin
        state_clear_d = 1'b1;
      end else begin
        state_rmw_d  = 1'b1;
      end
    end

    // Clear state (RMW2)
    if(state_clear_q) begin
      state_store_d = 1'b1;
    end
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) begin
      state_idle_q <= 1'b1;
      state_load_q <= 1'b0;
      state_store_q <= 1'b0;
      state_rmw_q <= 1'b0;
      state_clear_q <= 1'b0;

      addr_q <= 32'b0;
      be_q   <= 4'b0;
      be_qn  <= 4'b0;
    end else begin
      state_idle_q <= state_idle_d;
      state_load_q <= state_load_d;
      state_store_q <= state_store_d;
      state_rmw_q <= state_rmw_d;
      state_clear_q <= state_clear_d;

      if (cpu_req_i | cpu_done) begin
        addr_q <= cpu_addr_i & {32{~cpu_done}};
        be_q   <=  cpu_be_i  & {4{~cpu_done}};
        be_qn  <= ~cpu_be_i  & {4{~cpu_done}};
      end
    end
  end

  // Data register. Required to encrypt and store, as well as merge data.
  logic [7:0] byte_0_q, byte_1_q, byte_2_q, byte_3_q;
  logic [7:0] byte_0_d, byte_1_d, byte_2_d, byte_3_d;
  logic byte_0_en, byte_1_en, byte_2_en, byte_3_en;
  logic [31:0] data_q;
  assign data_q = {byte_3_q, byte_2_q, byte_1_q, byte_0_q};

  logic [31:0] cipher_data_out;


  // --- Byte-Merging Logic ---
  logic [31:0] cpu_to_merge_gated, ram_to_merge_gated;
  logic [31:0] cpu_merge_mask, ram_merge_mask;

  assign cpu_done = state_idle_d == 1'b1 && state_idle_q == 1'b0;
  DCR #(
    .IS_POSEDGE(0),
    .N(5) 
  ) dcr_buffer (
    .clk   (clk_i),
    .EN    (1'b1),
    .RST_N (rst_ni),
    .D     ({state_idle_q,   state_load_q,   state_store_q,   state_rmw_q,  state_clear_q}),
    .Q     ({state_idle_dcr, state_load_dcr, state_store_dcr, state_rmw_dcr, state_clear_dcr})
  );
  

  // Bitmask Inputs
  AND_gate #(.N(8)) bitmask_cpu_0  (.A1({8{cpu_be_i[0]}}), .A2({8{state_idle_dcr}}), .ZN(cpu_merge_mask[ 7: 0]));
  AND_gate #(.N(8)) bitmask_cpu_1  (.A1({8{cpu_be_i[1]}}), .A2({8{state_idle_dcr}}), .ZN(cpu_merge_mask[15: 8]));
  AND_gate #(.N(8)) bitmask_cpu_2  (.A1({8{cpu_be_i[2]}}), .A2({8{state_idle_dcr}}), .ZN(cpu_merge_mask[23:16]));
  AND_gate #(.N(8)) bitmask_cpu_3  (.A1({8{cpu_be_i[3]}}), .A2({8{state_idle_dcr}}), .ZN(cpu_merge_mask[31:24]));

  AND_gate #(.N(8)) bitmask_ram_0  (.A1({8{be_qn[0]}}), .A2({8{state_rmw_dcr}}), .ZN(ram_merge_mask[ 7: 0]));
  AND_gate #(.N(8)) bitmask_ram_1  (.A1({8{be_qn[1]}}), .A2({8{state_rmw_dcr}}), .ZN(ram_merge_mask[15: 8]));
  AND_gate #(.N(8)) bitmask_ram_2  (.A1({8{be_qn[2]}}), .A2({8{state_rmw_dcr}}), .ZN(ram_merge_mask[23:16]));
  AND_gate #(.N(8)) bitmask_ram_3  (.A1({8{be_qn[3]}}), .A2({8{state_rmw_dcr}}), .ZN(ram_merge_mask[31:24]));


  // Apply masks to gate data
  AND_gate #(.N(32)) mer_cpu_gate  (.A1(cpu_wdata_i),     .A2(cpu_merge_mask), .ZN(cpu_to_merge_gated));
  AND_gate #(.N(32)) mer_ram_gate  (.A1(cipher_data_out), .A2(ram_merge_mask), .ZN(ram_to_merge_gated));

  // Merge Both inputs
  OR_gate #(.N(8)) mer_byte_0  (.A1(cpu_to_merge_gated[ 7: 0]), .A2(ram_to_merge_gated[ 7: 0]), .ZN(byte_0_d));
  OR_gate #(.N(8)) mer_byte_1  (.A1(cpu_to_merge_gated[15: 8]), .A2(ram_to_merge_gated[15: 8]), .ZN(byte_1_d));
  OR_gate #(.N(8)) mer_byte_2  (.A1(cpu_to_merge_gated[23:16]), .A2(ram_to_merge_gated[23:16]), .ZN(byte_2_d));
  OR_gate #(.N(8)) mer_byte_3  (.A1(cpu_to_merge_gated[31:24]), .A2(ram_to_merge_gated[31:24]), .ZN(byte_3_d));

  // Enable bytes, for store / merge / reset
  assign byte_0_en = (state_idle_q & cpu_be_i[0] & cpu_we_i) | (state_rmw_q & ~be_q[0]) | (cpu_done); 
  assign byte_1_en = (state_idle_q & cpu_be_i[1] & cpu_we_i) | (state_rmw_q & ~be_q[1]) | (cpu_done); 
  assign byte_2_en = (state_idle_q & cpu_be_i[2] & cpu_we_i) | (state_rmw_q & ~be_q[2]) | (cpu_done); 
  assign byte_3_en = (state_idle_q & cpu_be_i[3] & cpu_we_i) | (state_rmw_q & ~be_q[3]) | (cpu_done); 

  DFFE_cell #(.N(8)) u_byte_0_reg (.CK(clk_i), .D(byte_0_d), .EN(byte_0_en), .RST_N(rst_ni), .Q(byte_0_q), .QN());
  DFFE_cell #(.N(8)) u_byte_1_reg (.CK(clk_i), .D(byte_1_d), .EN(byte_1_en), .RST_N(rst_ni), .Q(byte_1_q), .QN());
  DFFE_cell #(.N(8)) u_byte_2_reg (.CK(clk_i), .D(byte_2_d), .EN(byte_2_en), .RST_N(rst_ni), .Q(byte_2_q), .QN());
  DFFE_cell #(.N(8)) u_byte_3_reg (.CK(clk_i), .D(byte_3_d), .EN(byte_3_en), .RST_N(rst_ni), .Q(byte_3_q), .QN());





  // Preparation of data and cipher input
  // As the sates are unique, they can be assigned without the negative term.

  // Cipher input has to be the stored data or ram data.
  logic [31:0] cipher_in_wire;
  logic [31:0] cipher_in_ram;
  logic [31:0] cipher_in_cpu;
  // We can only transition from idle -> state or rmw -> store. If we transition rmw->store, we leak the same data
  AND_gate #(.N(32)) g_cipher_in_ram (.A1(ram_rdata_i),   .A2({32{state_load_dcr || state_rmw_dcr}}), .ZN(cipher_in_ram));
  AND_gate #(.N(32)) g_cipher_in_cpu (.A1(data_q),        .A2({32{state_store_dcr}}),              .ZN(cipher_in_cpu));
  OR_gate  #(.N(32)) g_cipher_merge  (.A1(cipher_in_cpu), .A2(cipher_in_ram),                    .ZN(cipher_in_wire));
  

  // The cipher output might be combinational, but has to be protected against transitional leakage outside of this module.
  logic [31:0] cipher_data_out_encrypted;
  cipher_beanie u_cipher (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .init_i(1'b1),
    .en_i(addr_q[17]),
    .clear_i(1'b0),
    .dec_i(state_load_q || state_rmw_q),
    .addr_i(addr_q),
    .key_i({master_key_3_q[31:16], master_key_2_q[31:16], master_key_1_q[31:16], master_key_0_q[31:16],
            master_key_3_q[15:0], master_key_2_q[15:0], master_key_1_q[15:0], master_key_0_q[15:0]}), // {k7-k4, k3-k0}
    .step_i(4'd0),
    .last_i(1'b1),
    .data_i(cipher_in_wire),
    .data_o(cipher_data_out_encrypted)
  );

  logic crypt_active_dcr, crypt_bypass_dcr;
  DCR #(
    .IS_POSEDGE(0),
    .N(2)
  ) dcr_crypt_sel (
    .clk   (clk_i),
    .EN    (1'b1),
    .RST_N (rst_ni),
    .D     ({addr_q[17] & (state_load_q | state_rmw_q | state_store_q), 
             ~addr_q[17] & (state_load_q | state_rmw_q | state_store_q)}),
    .Q     ({crypt_active_dcr, crypt_bypass_dcr})
  );

  logic [31:0] cipher_data_out_enc_gated;
  logic [31:0] cipher_data_out_bypass_gated;

  AND_gate #(.N(32)) g_out_enc    (.A1(cipher_data_out_encrypted), .A2({32{crypt_active_dcr}}), .ZN(cipher_data_out_enc_gated));
  AND_gate #(.N(32)) g_out_bypass (.A1(cipher_in_wire),            .A2({32{crypt_bypass_dcr}}), .ZN(cipher_data_out_bypass_gated));

  OR_gate #(.N(32)) g_out_merge   (.A1(cipher_data_out_enc_gated), .A2(cipher_data_out_bypass_gated), .ZN(cipher_data_out));



  

  assign ram_be_o = 4'hF;
  assign ram_we_o = state_store_q;
  assign ram_re_o = state_idle_q || state_store_q;

  logic [31:0] addr_store, addr_load;
  AND_gate #(.N(32)) gate_addr_store (.A1(addr_q),     .A2({32{state_store_dcr}}), .ZN(addr_store));
  AND_gate #(.N(32)) gate_addr_load  (.A1(cpu_addr_i), .A2({32{state_idle_dcr}}),  .ZN(addr_load));
  OR_gate  #(.N(32)) gate_addr       (.A1(addr_store), .A2(addr_load),  .ZN(ram_addr_o));

  AND_gate #(.N(32)) gate_ram_wdata (.A1(cipher_data_out), .A2({32{state_store_dcr}}), .ZN(ram_wdata_o));
  
  
  assign cpu_done_o = cpu_done; // We transition back to idle
  logic cpu_rdata_gate;
  AND_gate #(.N(1)) gate_ctl_rdata (.A1(cpu_done), .A2(state_load_q), .ZN(cpu_rdata_gate));
  logic [3:0] out_be;
  AND_gate #(.N(4)) out_be_g0 (.A1({4{cpu_rdata_gate}}), .A2(be_q), .ZN(out_be));
  AND_gate #(.N(8)) gate_cpu_rdata0 (.A1(cipher_data_out[ 7: 0]), .A2({8{out_be[0]}}), .ZN(cpu_rdata_o[ 7: 0]));
  AND_gate #(.N(8)) gate_cpu_rdata1 (.A1(cipher_data_out[15: 8]), .A2({8{out_be[1]}}), .ZN(cpu_rdata_o[15: 8]));
  AND_gate #(.N(8)) gate_cpu_rdata2 (.A1(cipher_data_out[23:16]), .A2({8{out_be[2]}}), .ZN(cpu_rdata_o[23:16]));
  AND_gate #(.N(8)) gate_cpu_rdata3 (.A1(cipher_data_out[31:24]), .A2({8{out_be[3]}}), .ZN(cpu_rdata_o[31:24]));
endmodule
