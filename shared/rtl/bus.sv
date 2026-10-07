// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
// Modified 2026 by Niels Wieser, TU Darmstadt:
// countermeasures against micro-architectural leakage.

/**
 * Simplistic Ibex bus implementation
 *
 * This module is designed for demo and simulation purposes, do not use it in
 * a real-world system.
 *
 * This implementation doesn't handle the full bus protocol, but makes the
 * following simplifying assumptions.
 *
 * - All devices (slaves) must respond in the next cycle after the request.
 * - Host (master) arbitration is strictly priority based.
 */
module bus #(
  parameter int NrDevices    = 1,
  parameter int NrHosts      = 1,
  parameter int DataWidth    = 32,
  parameter int AddressWidth = 32
) (
  input                           clk_i,
  input                           rst_ni,

  // Hosts (masters)
  input                           host_req_i    [NrHosts],
  output logic                    host_gnt_o    [NrHosts],

  input        [AddressWidth-1:0] host_addr_i   [NrHosts],
  input                           host_we_i     [NrHosts],
  input        [ DataWidth/8-1:0] host_be_i     [NrHosts],
  input        [   DataWidth-1:0] host_wdata_i  [NrHosts],
  output logic                    host_rvalid_o [NrHosts],
  output logic [   DataWidth-1:0] host_rdata_o  [NrHosts],
  output logic                    host_err_o    [NrHosts],

  // Devices (slaves)
  output logic                    device_req_o    [NrDevices],

  output logic [AddressWidth-1:0] device_addr_o   [NrDevices],
  output logic                    device_we_o     [NrDevices],
  output logic [ DataWidth/8-1:0] device_be_o     [NrDevices],
  output logic [   DataWidth-1:0] device_wdata_o  [NrDevices],
  input                           device_rvalid_i [NrDevices],
  input        [   DataWidth-1:0] device_rdata_i  [NrDevices],
  input                           device_err_i    [NrDevices],

  // Device address map
  input        [AddressWidth-1:0] cfg_device_addr_base [NrDevices],
  input        [AddressWidth-1:0] cfg_device_addr_mask [NrDevices]
);

  localparam int unsigned NumBitsHostSel = NrHosts > 1 ? $clog2(NrHosts) : 1;
  localparam int unsigned NumBitsDeviceSel = NrDevices > 1 ? $clog2(NrDevices) : 1;

  logic host_sel_valid;
  logic device_sel_valid;
  logic decode_err_resp;

  logic [NumBitsHostSel-1:0] host_sel_req, host_sel_resp;
  logic [NumBitsDeviceSel-1:0] device_sel_req, device_sel_resp;
  logic [NrDevices-1:0] device_sel_oh_req, device_sel_oh_resp;

  // Master select priority arbiter
  always_comb begin
    host_sel_valid = 1'b0;
    host_sel_req = '0;
    for (integer host = NrHosts - 1; host >= 0; host = host - 1) begin
      if (host_req_i[host]) begin
        host_sel_valid = 1'b1;
        host_sel_req = NumBitsHostSel'(host);
      end
    end
  end

  // Device select
  always_comb begin
    device_sel_valid = 1'b0;
    device_sel_req = '0;
    device_sel_oh_req = '0;
    for (integer device = 0; device < NrDevices; device = device + 1) begin
      if ((host_addr_i[host_sel_req] & cfg_device_addr_mask[device])
          == cfg_device_addr_base[device]) begin
        device_sel_valid = 1'b1;
        device_sel_req = NumBitsDeviceSel'(device);
        device_sel_oh_req[device] = host_sel_valid;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
     if (!rst_ni) begin
        host_sel_resp <= '0;
        device_sel_resp <= '0;
        // device_sel_oh_resp <= '0;
        decode_err_resp <= 1'b0;
     end else begin
        // Responses are always expected 1 cycle after the request
        device_sel_resp <= device_sel_req;
        // device_sel_oh_resp <= device_sel_oh_req;
        host_sel_resp <= host_sel_req;
        // Decode failed; no device matched?
        decode_err_resp <= host_sel_valid & !device_sel_valid;
     end
  end

  // DCR one-hot encoded select signal
  logic [NrDevices-1:0] device_sel_oh_dcr;
  logic [NrDevices-1:0] device_sel_oh_dcr_in;
  logic                 clear_select;
  logic                 dcr_select_en;
  logic [NrDevices-1:0] device_rvalid_packed;

  always_comb begin
    for (integer i = 0; i < NrDevices; i = i + 1) begin
      device_rvalid_packed[i] = device_rvalid_i[i];
    end
  end

  assign clear_select  = |(device_rvalid_packed & device_sel_oh_resp);
  assign dcr_select_en = host_sel_valid | clear_select;
  assign device_sel_oh_dcr_in = device_sel_oh_req & {NrDevices{~clear_select}};

  DCR #(
    .IS_POSEDGE(1),
    .N(NrDevices)
  ) dcr_select (
    .clk   (clk_i),
    .EN    (dcr_select_en),
    .RST_N (rst_ni),
    .D     (device_sel_oh_dcr_in),
    .Q     (device_sel_oh_dcr)
  );
  DCR #(
    .IS_POSEDGE(0),
    .N(NrDevices)
  ) dcr_select_buf (
    .clk (clk_i),
    .EN  (1'b1),
    .RST_N (rst_ni),
    .D   (device_sel_oh_dcr),
    .Q   (device_sel_oh_resp)
  );


  always_comb begin
    for (integer device = 0; device < NrDevices; device = device + 1) begin
      if (device_sel_oh_req[device]) begin
        device_req_o[device]   = host_req_i[host_sel_req];
        device_we_o[device]    = host_we_i[host_sel_req];
        device_addr_o[device]  = host_addr_i[host_sel_req];
        device_wdata_o[device] = host_wdata_i[host_sel_req];
        device_be_o[device]    = host_be_i[host_sel_req];
      end else begin
        device_req_o[device]   = 1'b0;
        device_we_o[device]    = 1'b0;
        device_addr_o[device]  = 'b0;
        device_wdata_o[device] = 'b0;
        device_be_o[device]    = 'b0;
      end
    end
  end

  // Gating data based on 1-hot value
  logic [DataWidth-1:0] oh_read [NrDevices];
  for (genvar device = 0; device < NrDevices; device = device + 1) begin : gen_oh_read
    AND_gate #(.N(DataWidth)) device_and (
      .A1(device_rdata_i[device]),
      .A2({DataWidth{device_sel_oh_resp[device]}}),
      .ZN(oh_read[device])
    );
  end

  // Combining read data, valid, and error with one-hot logic
  logic [DataWidth-1:0] host_rdata;
  logic                 host_rvalid;
  logic                 host_err;

  always_comb begin
    host_rdata = '0;
    host_rvalid = decode_err_resp;
    host_err    = decode_err_resp;
    for (integer device = 0; device < NrDevices; device = device + 1) begin
      host_rdata  |= oh_read[device];
      host_rvalid |= (device_rvalid_i[device] & device_sel_oh_dcr[device]);
      host_err    |= (device_err_i[device]    & device_sel_oh_dcr[device]);
    end
  end

  // DCR one-hot encoded select signal
  logic host_err_buf;
  logic host_rvalid_buf;
  logic [DataWidth-1:0] host_rdata_buf;
  DCR #(
    .IS_POSEDGE(0),
    // .N(DataWidth+2)
    .N(2)
  ) dcr_buffer (
    .clk   (clk_i),
    .EN    (1'b1),
    .RST_N (rst_ni),
    .D     ({     host_rvalid,     host_err}),
    .Q     ({ host_rvalid_buf, host_err_buf})
  );

  always_comb begin
    for (integer host = 0; host < NrHosts; host = host + 1) begin
      host_gnt_o[host] = 1'b0;
      if (NumBitsHostSel'(host) == host_sel_resp) begin
        host_rvalid_o[host] = host_rvalid_buf || host_rvalid;
        host_err_o[host]    = host_err_buf || host_err;
        host_rdata_o[host]  = host_rdata;
      end else begin
        host_rvalid_o[host] = 1'b0;
        host_err_o[host]    = 1'b0;
        host_rdata_o[host]  = 'b0;
      end
    end
    host_gnt_o[host_sel_req] = host_req_i[host_sel_req];
  end

endmodule
