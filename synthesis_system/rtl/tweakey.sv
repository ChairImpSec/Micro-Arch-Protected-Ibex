/* Copyright 2025 NXP
 * This work is licensed under a Creative Commons Attribution-ShareAlike 4.0 International License.
 * You should have received a copy of the license along with this work (LICENSES/CC-BY-SA-4.0.txt).
 * If not, see <https://creativecommons.org/licenses/by-sa/4.0/>.
 * SPDX-License-Identifier: CC-BY-SA-4.0
 *
 * Based on tweakey.sv of the BEANIE reference hardware implementation
 * (https://github.com/NXP-Research/beanie_cipher).
 * Modified 2026 by Niels Wieser, TU Darmstadt:
 * adapted the tweakey schedule for mem_crypt.
 */
package ksa_package;

localparam logic [15:0][3:0] SHIFT_ROW      = 64'hFA50_B61C_72D8_3E94; 

function automatic logic [0:15][3:0] sbox_64_ksa_f(logic [63:0] in, logic [0:15][3:0] sb);
    logic [63:0] s_out;   
    s_out[00+:4] = sb[in[00+:4]];
    s_out[04+:4] = sb[in[04+:4]];
    s_out[08+:4] = sb[in[08+:4]];
    s_out[12+:4] = sb[in[12+:4]];
    s_out[16+:4] = sb[in[16+:4]];
    s_out[20+:4] = sb[in[20+:4]];
    s_out[24+:4] = sb[in[24+:4]];
    s_out[28+:4] = sb[in[28+:4]];
    s_out[32+:4] = sb[in[32+:4]];
    s_out[36+:4] = sb[in[36+:4]];
    s_out[40+:4] = sb[in[40+:4]];
    s_out[44+:4] = sb[in[44+:4]];
    s_out[48+:4] = sb[in[48+:4]];
    s_out[52+:4] = sb[in[52+:4]];
    s_out[56+:4] = sb[in[56+:4]];
    s_out[60+:4] = sb[in[60+:4]];
    return s_out;
endfunction


function automatic logic [15:0][3:0] shift_rows_f(logic [15:0][3:0] d_in, logic [15:0][3:0] shift);
    logic [15:0][3:0] shifted;

     shifted[00] = d_in[shift[00]];
     shifted[01] = d_in[shift[01]];
     shifted[02] = d_in[shift[02]];
     shifted[03] = d_in[shift[03]];
     shifted[04] = d_in[shift[04]];
     shifted[05] = d_in[shift[05]];
     shifted[06] = d_in[shift[06]];
     shifted[07] = d_in[shift[07]];
     shifted[08] = d_in[shift[08]];
     shifted[09] = d_in[shift[09]];
     shifted[10] = d_in[shift[10]];
     shifted[11] = d_in[shift[11]];
     shifted[12] = d_in[shift[12]];
     shifted[13] = d_in[shift[13]];
     shifted[14] = d_in[shift[14]];
     shifted[15] = d_in[shift[15]];

    return shifted;
endfunction


  localparam logic [15:0] PRINCE_SHIFT_ROWS_CONST0 = 16'h7BDE;
  localparam logic [15:0] PRINCE_SHIFT_ROWS_CONST1 = 16'hBDE7;
  localparam logic [15:0] PRINCE_SHIFT_ROWS_CONST2 = 16'hDE7B;
  localparam logic [15:0] PRINCE_SHIFT_ROWS_CONST3 = 16'hE7BD;

  function automatic logic [3:0] prince_nibble_red16(logic [15:0] vect);
    return vect[0 +: 4] ^ vect[4 +: 4] ^ vect[8 +: 4] ^ vect[12 +: 4];
  endfunction : prince_nibble_red16

  function automatic logic [63:0] prince_mult_prime_64bit(logic [63:0] state_in);
    logic [63:0] state_out;
    state_out[0  +: 4] = prince_nibble_red16(state_in[ 0 +: 16] & PRINCE_SHIFT_ROWS_CONST3);
    state_out[4  +: 4] = prince_nibble_red16(state_in[ 0 +: 16] & PRINCE_SHIFT_ROWS_CONST2);
    state_out[8  +: 4] = prince_nibble_red16(state_in[ 0 +: 16] & PRINCE_SHIFT_ROWS_CONST1);
    state_out[12 +: 4] = prince_nibble_red16(state_in[ 0 +: 16] & PRINCE_SHIFT_ROWS_CONST0);
    state_out[16 +: 4] = prince_nibble_red16(state_in[16 +: 16] & PRINCE_SHIFT_ROWS_CONST0);
    state_out[20 +: 4] = prince_nibble_red16(state_in[16 +: 16] & PRINCE_SHIFT_ROWS_CONST3);
    state_out[24 +: 4] = prince_nibble_red16(state_in[16 +: 16] & PRINCE_SHIFT_ROWS_CONST2);
    state_out[28 +: 4] = prince_nibble_red16(state_in[16 +: 16] & PRINCE_SHIFT_ROWS_CONST1);
    state_out[32 +: 4] = prince_nibble_red16(state_in[32 +: 16] & PRINCE_SHIFT_ROWS_CONST0);
    state_out[36 +: 4] = prince_nibble_red16(state_in[32 +: 16] & PRINCE_SHIFT_ROWS_CONST3);
    state_out[40 +: 4] = prince_nibble_red16(state_in[32 +: 16] & PRINCE_SHIFT_ROWS_CONST2);
    state_out[44 +: 4] = prince_nibble_red16(state_in[32 +: 16] & PRINCE_SHIFT_ROWS_CONST1);
    state_out[48 +: 4] = prince_nibble_red16(state_in[48 +: 16] & PRINCE_SHIFT_ROWS_CONST3);
    state_out[52 +: 4] = prince_nibble_red16(state_in[48 +: 16] & PRINCE_SHIFT_ROWS_CONST2);
    state_out[56 +: 4] = prince_nibble_red16(state_in[48 +: 16] & PRINCE_SHIFT_ROWS_CONST1);
    state_out[60 +: 4] = prince_nibble_red16(state_in[48 +: 16] & PRINCE_SHIFT_ROWS_CONST0);
    return state_out;
  endfunction : prince_mult_prime_64bit


function automatic logic [63:0] m_prime_mul_f(logic [63:0] data_in);
    logic [63:0] m_prime_mul;
    m_prime_mul[63]  =  ^(data_in &64'b0000100010001000000000000000000000000000000000000000000000000000 );
    m_prime_mul[62]  =  ^(data_in &64'b0100000001000100000000000000000000000000000000000000000000000000 );
    m_prime_mul[61]  =  ^(data_in &64'b0010001000000010000000000000000000000000000000000000000000000000 );
    m_prime_mul[60]  =  ^(data_in &64'b0001000100010000000000000000000000000000000000000000000000000000 );
    m_prime_mul[59]  =  ^(data_in &64'b1000100010000000000000000000000000000000000000000000000000000000 );
    m_prime_mul[58]  =  ^(data_in &64'b0000010001000100000000000000000000000000000000000000000000000000 );
    m_prime_mul[57]  =  ^(data_in &64'b0010000000100010000000000000000000000000000000000000000000000000 );
    m_prime_mul[56]  =  ^(data_in &64'b0001000100000001000000000000000000000000000000000000000000000000 );
    m_prime_mul[55]  =  ^(data_in &64'b1000100000001000000000000000000000000000000000000000000000000000 );
    m_prime_mul[54]  =  ^(data_in &64'b0100010001000000000000000000000000000000000000000000000000000000 );
    m_prime_mul[53]  =  ^(data_in &64'b0000001000100010000000000000000000000000000000000000000000000000 );
    m_prime_mul[52]  =  ^(data_in &64'b0001000000010001000000000000000000000000000000000000000000000000 );
    m_prime_mul[51]  =  ^(data_in &64'b1000000010001000000000000000000000000000000000000000000000000000 );
    m_prime_mul[50]  =  ^(data_in &64'b0100010000000100000000000000000000000000000000000000000000000000 );
    m_prime_mul[49]  =  ^(data_in &64'b0010001000100000000000000000000000000000000000000000000000000000 );
    m_prime_mul[48]  =  ^(data_in &64'b0000000100010001000000000000000000000000000000000000000000000000 );
    m_prime_mul[47]  =  ^(data_in &64'b0000000000000000100010001000000000000000000000000000000000000000 );
    m_prime_mul[46]  =  ^(data_in &64'b0000000000000000000001000100010000000000000000000000000000000000 );
    m_prime_mul[45]  =  ^(data_in &64'b0000000000000000001000000010001000000000000000000000000000000000 );
    m_prime_mul[44]  =  ^(data_in &64'b0000000000000000000100010000000100000000000000000000000000000000 );
    m_prime_mul[43]  =  ^(data_in &64'b0000000000000000100010000000100000000000000000000000000000000000 );
    m_prime_mul[42]  =  ^(data_in &64'b0000000000000000010001000100000000000000000000000000000000000000 );
    m_prime_mul[41]  =  ^(data_in &64'b0000000000000000000000100010001000000000000000000000000000000000 );
    m_prime_mul[40]  =  ^(data_in &64'b0000000000000000000100000001000100000000000000000000000000000000 );
    m_prime_mul[39]  =  ^(data_in &64'b0000000000000000100000001000100000000000000000000000000000000000 );
    m_prime_mul[38]  =  ^(data_in &64'b0000000000000000010001000000010000000000000000000000000000000000 );
    m_prime_mul[37]  =  ^(data_in &64'b0000000000000000001000100010000000000000000000000000000000000000 );
    m_prime_mul[36]  =  ^(data_in &64'b0000000000000000000000010001000100000000000000000000000000000000 );
    m_prime_mul[35]  =  ^(data_in &64'b0000000000000000000010001000100000000000000000000000000000000000 );
    m_prime_mul[34]  =  ^(data_in &64'b0000000000000000010000000100010000000000000000000000000000000000 );
    m_prime_mul[33]  =  ^(data_in &64'b0000000000000000001000100000001000000000000000000000000000000000 );
    m_prime_mul[32]  =  ^(data_in &64'b0000000000000000000100010001000000000000000000000000000000000000 );
    m_prime_mul[31]  =  ^(data_in &64'b0000000000000000000000000000000010001000100000000000000000000000 );
    m_prime_mul[30]  =  ^(data_in &64'b0000000000000000000000000000000000000100010001000000000000000000 );
    m_prime_mul[29]  =  ^(data_in &64'b0000000000000000000000000000000000100000001000100000000000000000 );
    m_prime_mul[28]  =  ^(data_in &64'b0000000000000000000000000000000000010001000000010000000000000000 );
    m_prime_mul[27]  =  ^(data_in &64'b0000000000000000000000000000000010001000000010000000000000000000 );
    m_prime_mul[26]  =  ^(data_in &64'b0000000000000000000000000000000001000100010000000000000000000000 );
    m_prime_mul[25]  =  ^(data_in &64'b0000000000000000000000000000000000000010001000100000000000000000 );
    m_prime_mul[24]  =  ^(data_in &64'b0000000000000000000000000000000000010000000100010000000000000000 );
    m_prime_mul[23]  =  ^(data_in &64'b0000000000000000000000000000000010000000100010000000000000000000 );
    m_prime_mul[22]  =  ^(data_in &64'b0000000000000000000000000000000001000100000001000000000000000000 );
    m_prime_mul[21]  =  ^(data_in &64'b0000000000000000000000000000000000100010001000000000000000000000 );
    m_prime_mul[20]  =  ^(data_in &64'b0000000000000000000000000000000000000001000100010000000000000000 );
    m_prime_mul[19]  =  ^(data_in &64'b0000000000000000000000000000000000001000100010000000000000000000 );
    m_prime_mul[18]  =  ^(data_in &64'b0000000000000000000000000000000001000000010001000000000000000000 );
    m_prime_mul[17]  =  ^(data_in &64'b0000000000000000000000000000000000100010000000100000000000000000 );
    m_prime_mul[16]  =  ^(data_in &64'b0000000000000000000000000000000000010001000100000000000000000000 );
    m_prime_mul[15]  =  ^(data_in &64'b0000000000000000000000000000000000000000000000000000100010001000 );
    m_prime_mul[14]  =  ^(data_in &64'b0000000000000000000000000000000000000000000000000100000001000100 );
    m_prime_mul[13]  =  ^(data_in &64'b0000000000000000000000000000000000000000000000000010001000000010 );
    m_prime_mul[12]  =  ^(data_in &64'b0000000000000000000000000000000000000000000000000001000100010000 );
    m_prime_mul[11]  =  ^(data_in &64'b0000000000000000000000000000000000000000000000001000100010000000 );
    m_prime_mul[10]  =  ^(data_in &64'b0000000000000000000000000000000000000000000000000000010001000100 );
    m_prime_mul[ 9]  =  ^(data_in &64'b0000000000000000000000000000000000000000000000000010000000100010 );
    m_prime_mul[ 8]  =  ^(data_in &64'b0000000000000000000000000000000000000000000000000001000100000001 );
    m_prime_mul[ 7]  =  ^(data_in &64'b0000000000000000000000000000000000000000000000001000100000001000 );
    m_prime_mul[ 6]  =  ^(data_in &64'b0000000000000000000000000000000000000000000000000100010001000000 );
    m_prime_mul[ 5]  =  ^(data_in &64'b0000000000000000000000000000000000000000000000000000001000100010 );
    m_prime_mul[ 4]  =  ^(data_in &64'b0000000000000000000000000000000000000000000000000001000000010001 );
    m_prime_mul[ 3]  =  ^(data_in &64'b0000000000000000000000000000000000000000000000001000000010001000 );
    m_prime_mul[ 2]  =  ^(data_in &64'b0000000000000000000000000000000000000000000000000100010000000100 );
    m_prime_mul[ 1]  =  ^(data_in &64'b0000000000000000000000000000000000000000000000000010001000100000 );
    m_prime_mul[ 0]  =  ^(data_in &64'b0000000000000000000000000000000000000000000000000000000100010001 );
    return m_prime_mul;
endfunction


  localparam logic [0:15][3:0] G7_sbox = {
    4'h0, 4'h4, 4'h2, 4'hB, 4'hA, 4'hC, 4'h9, 4'h8, 4'h5, 4'hF, 4'hD, 4'h3, 4'h7, 4'h1, 4'h6, 4'hE
  };

  function automatic logic [0:127] sbox_ksa_f(logic [127:0] in, logic [0:15][3:0] sb);
  
      logic [63:0] s_out_msbs,s_out_lsbs;
      logic [127:0] s_out;
  
      s_out_msbs = sbox_64_ksa_f(in[127:64],sb);
      s_out_lsbs = sbox_64_ksa_f(in[063:00],sb);
      s_out = {s_out_msbs,s_out_lsbs};
  
      return s_out;
  endfunction


  function automatic logic [0:127] feistel_round(logic [0:3][0:31] in);

    return {in[0]^in[1],in[2],in[2]^in[3],in[0]};

  endfunction

  localparam logic [0:31][5:0] Cell_permutation = {6'd0,6'd9,6'd18,6'd27,6'd4,6'd13,6'd22,6'd31,6'd8,6'd17,6'd26,6'd3,6'd12,6'd21,6'd30,6'd7,6'd16,6'd25,6'd2,6'd11,6'd20,6'd29,6'd6,6'd15,6'd24,6'd1,6'd10,6'd19,6'd28,6'd5,6'd14,6'd23};


  function automatic logic [0:127] feistel_rot(logic [0:31][0:3] in);

    logic [0:31][0:3] out;

    for (int i=0 ; i<=31; i++) begin 
      out[i] = in[Cell_permutation[i]];
    end

    return out;

  endfunction

  function automatic logic [0:127] round(logic [0:127] in );

    logic [0:127] rnd_data;

    rnd_data = sbox_ksa_f(in,G7_sbox);
    rnd_data = {m_prime_mul_f(rnd_data[0:63]),m_prime_mul_f(rnd_data[64:127])};
    rnd_data = {shift_rows_f(rnd_data[0:63],SHIFT_ROW),shift_rows_f(rnd_data[64:127],SHIFT_ROW)};
    rnd_data = feistel_round(rnd_data);
    rnd_data = feistel_rot(rnd_data);


    return rnd_data;

  endfunction

endpackage

module  tweakey  
#(
  parameter ROUNDS = 5,
  parameter N_KEYS = 6
) (
      input  logic           clk,
      input   logic [0:127]  i_tweak,
      input   logic [0:127]  i_key,
      output  logic [0:31]   o_round_keys[N_KEYS]      
  ) ;

import ksa_package::*;

localparam [0:127] RC [10] = '{128'h0000000000000000,128'h13198a2e03707344,128'ha4093822299f31d0,128'h082efa98ec4e6c89,128'h452821e638d01377,128'hbe5466cf34e90c6c,128'h7ef84f78fd955cb1,128'h85840851f1ac43aa,128'hc882d32f25323c54,128'h64a51195e0e3610d};
logic [ROUNDS:0][0:127] round_data;
logic [0:3][0:31] key_output;

assign round_data[0] = i_tweak;

for (genvar i = 0; i < ROUNDS; i++) begin

    assign round_data[i+1] = round(round_data[i] ^ RC[i] ^ i_key);

end

assign key_output = round_data[ROUNDS] ^ i_key ^ RC[ROUNDS];
assign o_round_keys[0] = key_output[0];
assign o_round_keys[1] = key_output[1];
assign o_round_keys[2] = key_output[2];
assign o_round_keys[3] = key_output[3];

if (N_KEYS > 4) 
  assign o_round_keys[4] = key_output[1] ^ key_output[0];
if (N_KEYS > 5)
  assign o_round_keys[5] = key_output[3] ^ key_output[2];
if (N_KEYS > 6)
  assign o_round_keys[6] = key_output[0] ^ key_output[2];
if (N_KEYS > 7)
  assign o_round_keys[7] = key_output[1] ^ key_output[3];
if (N_KEYS > 8)
  assign o_round_keys[8] = key_output[0] ^ key_output[3];
if (N_KEYS > 9)
  assign o_round_keys[9] = key_output[1] ^ key_output[2];
   
endmodule
