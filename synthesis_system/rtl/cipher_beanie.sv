/* Copyright 2025 NXP
 * This work is licensed under a Creative Commons Attribution-ShareAlike 4.0 International License.
 * You should have received a copy of the license along with this work (LICENSES/CC-BY-SA-4.0.txt).
 * If not, see <https://creativecommons.org/licenses/by-sa/4.0/>.
 * SPDX-License-Identifier: CC-BY-SA-4.0
 *
 * Based on data_processing.sv of the BEANIE reference hardware implementation
 * (https://github.com/NXP-Research/beanie_cipher).
 * Modified 2026 by Niels Wieser, TU Darmstadt:
 * added the cipher_beanie wrapper for mem_crypt and adapted data_processing.
 */
// Top-level module compatible with mem_crypt.sv
module cipher_beanie (
  input  logic         clk_i,
  input  logic         rst_ni,
  input  logic         init_i,
  input  logic         en_i,
  input  logic         clear_i,
  input  logic         dec_i,    // 0: Encrypt, 1: Decrypt
  input  logic         last_i,
  input  logic [31:0]  addr_i,   // Used as tweak
  input  logic [127:0] key_i,
  input  logic [3:0]   step_i,
  input  logic [31:0]  data_i,
  output logic [31:0]  data_o
);

  localparam int ROUNDS = 5; // Default for Beanie
  localparam int N_KEYS = ROUNDS + 1;

  logic [31:0] round_keys[N_KEYS];

  // Bit order conversion if necessary, Beanie seems to use [0:31]
  // We'll map [31:0] to [0:31] carefully.
  
  tweakey #(
    .ROUNDS(ROUNDS),
    .N_KEYS(N_KEYS)
  ) u_tweakey (
    .clk(clk_i),
    .i_tweak({96'h0, addr_i}), // Assuming 128-bit tweak with addr in lower 32 bits
    .i_key(key_i),
    .o_round_keys(round_keys)
  );

  data_processing #(
  ) u_data_processing (
    .clk(clk_i),
    .dec_i(dec_i),
    .data_i(data_i),
    .k_i(round_keys),
    .data_o(data_o)
  );

endmodule

 module data_processing (
  input  logic              clk,
  input  logic              dec_i,
  input  logic [31:0]       data_i,
  input  logic [31:0]       k_i[6], // Hardcoded for ROUNDS=5
  output logic [31:0]       data_o
);

  // Constants and logic from original data_processing, 
  // but updated to use standard [31:0] bit order for simplicity in top-level,
  // or keeping [0:31] if internal logic depends on it.
  // The provided snippet used `ROUNDS macro, which is problematic.
  
  localparam int ROUNDS = 5;

  parameter logic [0:15][3:0] G7_sbox = {
    4'h0, 4'h4, 4'h2, 4'hB, 4'hA, 4'hC, 4'h9, 4'h8, 4'h5, 4'hF, 4'hD, 4'h3, 4'h7, 4'h1, 4'h6, 4'hE
  };
  parameter logic [0:15][3:0] G7_sbox_inv = {
    4'h0, 4'hd, 4'h2, 4'hb, 4'h1, 4'h8, 4'he, 4'hc, 4'h7, 4'h6, 4'h4, 4'h3, 4'h5, 4'ha, 4'hf, 4'h9
  };
  parameter logic [0:31][3:0] G7_sbox_uni = {
    4'h0, 4'h4, 4'h2, 4'hB, 4'hA, 4'hC, 4'h9, 4'h8, 4'h5, 4'hF, 4'hD, 4'h3, 4'h7, 4'h1, 4'h6, 4'hE, 
    4'h0, 4'hd, 4'h2, 4'hb, 4'h1, 4'h8, 4'he, 4'hc, 4'h7, 4'h6, 4'h4, 4'h3, 4'h5, 4'ha, 4'hf, 4'h9
  };
  parameter logic [0:15][0:15] M4i4_MDS = {
    {1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1},
    {1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0},
    {1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0},
    {1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b1},
    {1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0},
    {1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0},
    {1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0},
    {1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1},
    {1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0},
    {1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0},
    {1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0},
    {1'b0, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1},
    {1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0},
    {1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0},
    {1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1},
    {1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0}
  };
  function automatic logic [31:0] S(logic [31:0] data_i);
  begin
    logic [31:0] data_o;

    for (int i = 0; i < 8; i++) begin
      data_o[4*i+:4] = G7_sbox[data_i[4*i+:4]];
    end

    return data_o;
  end
  endfunction

  function automatic logic [31:0] S_uni(logic dec, logic [31:0] data_i);
  begin
    logic [31:0] data_o;

        for (int i = 0; i < 8; i++) begin
            data_o[4*i+:4] = G7_sbox_uni[{dec, data_i[4*i+:4]}];
        end

    return data_o;
  end
  endfunction

  function automatic logic [31:0] S_inv(logic [31:0] data_i);
  begin
    logic [31:0] data_o;

    for (int i = 0; i < 8; i++) begin
      data_o[4*i+:4] = G7_sbox_inv[data_i[4*i+:4]];
    end

    return data_o;
  end
  endfunction

  function automatic logic [31:0] Rot(logic [31:0] data_i);  
  begin
    // Mapping from [0:31] to [31:0] for Rot
    // Original: {data_i[0:3], data_i[20:23], data_i[8:11], data_i[28:31], data_i[16:19], data_i[4:7], data_i[24:27], data_i[12:15]}
    // In [31:0] terms:
    // data_i[0:3]   is data_i[31:28]
    // data_i[20:23] is data_i[11:8]
    // ...
    return {data_i[31:28], data_i[11:8], data_i[23:20], data_i[3:0], data_i[15:12], data_i[27:24], data_i[7:4], data_i[19:16]};
  end
  endfunction

  function automatic logic [31:0] M_MDS(logic [31:0] data_i);
  begin
    logic [15:0] col1_in, col2_in, col1_out, col2_out;

    col1_in = data_i[31:16];
    col2_in = data_i[15:0];

    for (int i = 0; i < 16; i++) begin
      col1_out[i] = 0;
      col2_out[i] = 0;

      for (int j = 0; j < 16; j++) begin
        // M4i4_MDS is [0:15][0:15]
        col1_out[i] = col1_out[i] ^ (M4i4_MDS[15-i][15-j] & col1_in[j]);
        col2_out[i] = col2_out[i] ^ (M4i4_MDS[15-i][15-j] & col2_in[j]);
      end
    end

    return {col1_out, col2_out};
  end
  endfunction

  function automatic logic [31:0] R(logic [31:0] data);
  begin
    return M_MDS(S(Rot(data)));
  end
  endfunction

  function automatic logic [31:0] R_inv(logic [31:0] data);
  begin
    return S_inv(Rot(M_MDS(data)));
  end
  endfunction

  logic [ROUNDS:0][31:0] round_data ;
  logic [ROUNDS:0][31:0] enc_round_key ;
  logic [ROUNDS:0][31:0] dec_round_key ;
  
  always_comb begin
    for (int i = 0; i < ROUNDS+1; i++) begin
      enc_round_key[i] = {32{~dec_i}} & k_i[i];
      dec_round_key[i] = {32{dec_i}} & k_i[ROUNDS-i];
    end
  end

  always_comb
  begin
    // Defaulting MERGED=1 for now as it seems most complete in original code
    round_data[0] = dec_round_key[0] ^ data_i;
    round_data[1] = dec_round_key[1] ^ S_uni(dec_i, Rot(enc_round_key[0] ^ round_data[0]));
    for (int i = 1; i < ROUNDS; i++) begin
      round_data[i+1] = dec_round_key[i+1] ^ S_uni(dec_i, Rot(enc_round_key[i] ^ M_MDS(round_data[i])));
    end
    data_o = enc_round_key[ROUNDS] ^ round_data[ROUNDS];
  end

endmodule : data_processing