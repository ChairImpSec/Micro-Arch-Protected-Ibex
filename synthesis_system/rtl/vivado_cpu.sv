// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
// Modified 2026 by Niels Wieser, TU Darmstadt:
// adapted as evaluation system for the micro-architecturally protected Ibex.

module vivado_cpu #(
  parameter bit                 SecureIbex       = 1'b0,
  parameter bit                 ICacheScramble   = 1'b0,
  parameter bit                 PMPEnable        = 1'b0,
  parameter int unsigned        PMPGranularity   = 0,
  parameter int unsigned        PMPNumRegions    = 4,
  parameter int unsigned        MHPMCounterNum   = 0,
  parameter int unsigned        MHPMCounterWidth = 40,
  parameter bit                 RV32E            = 1'b0,
  parameter ibex_pkg::rv32m_e   RV32M            = ibex_pkg::RV32MNone,
  parameter ibex_pkg::rv32b_e   RV32B            = ibex_pkg::RV32BNone,
  parameter ibex_pkg::regfile_e RegFile          = ibex_pkg::RegFileFF,
  parameter bit                 BranchTargetALU  = 1'b0,
  parameter bit                 WritebackStage   = 1'b0,
  parameter bit                 ICache           = 1'b0,
  parameter bit                 DbgTriggerEn     = 1'b0,
  parameter bit                 ICacheECC        = 1'b0,
  parameter bit                 BranchPredictor  = 1'b0
) (
  input  logic clk,
  input  logic rst_n,

  // Instruction fetch interface (ROM port A)
  output logic [31:0] instr_addr_o,
  output logic        instr_req_o,
  input  logic [31:0] instr_rdata_i,
  input  logic        instr_rvalid_i,
  input  logic        rom_busy_i,

  // ROM data interface (ROM port B - read only, bootloader / rodata reads)
  output logic [31:0] rom_addr_o,
  output logic [31:0] rom_wdata_o,
  output logic [ 3:0] rom_be_o,
  output logic        rom_we_o,
  output logic        rom_re_o,
  input  logic [31:0] rom_rdata_i,
  input  logic        rom_rvalid_i,

  // RAM interface (data side, own bus address range)
  output logic [31:0] ram_addr_o,
  output logic [31:0] ram_wdata_o,
  output logic [ 3:0] ram_be_o,
  output logic        ram_we_o,
  output logic        ram_re_o,
  input  logic [31:0] ram_rdata_i,
  input  logic        ram_rvalid_i,
  input  logic        ram_busy_i,

  // Cipher config interface (MMIO for the encrypted RAM)
  output logic [31:0] cfg_addr_o,
  output logic        cfg_req_o,
  output logic        cfg_we_o,
  output logic [31:0] cfg_wdata_o,
  input  logic [31:0] cfg_rdata_i,
  input  logic        cfg_rvalid_i,

  // IO Interface (Memory mapped registers in wrapper)
  output logic [31:0] io_addr_o,
  output logic [ 3:0] io_we_o,
  output logic [31:0] io_wdata_o,
  output logic        io_req_o,
  input  logic [31:0] io_rdata_i,
  input  logic        io_rvalid_i,
  input  logic        io_busy_i
);

  typedef enum logic {
    CoreD
  } bus_host_e;

  typedef enum logic[1:0] {
    Rom      = 2'h0,
    Ram      = 2'h1,
    MemCrypt = 2'h2,
    IO       = 2'h3
  } bus_device_e;

  localparam int NrDevices = 4;
  localparam int NrHosts = 1;

  // host and device signals
  logic           host_req    [NrHosts];
  logic           host_gnt    [NrHosts];
  logic [31:0]    host_addr   [NrHosts];
  logic           host_we     [NrHosts];
  logic [ 3:0]    host_be     [NrHosts];
  logic [31:0]    host_wdata  [NrHosts];
  logic           host_rvalid [NrHosts];
  logic [31:0]    host_rdata  [NrHosts];
  logic           host_err    [NrHosts];

  logic [6:0]     data_rdata_intg;
  logic [6:0]     instr_rdata_intg;

  // devices (slaves)
  logic           device_req    [NrDevices];
  logic [31:0]    device_addr   [NrDevices];
  logic           device_we     [NrDevices];
  logic [ 3:0]    device_be     [NrDevices];
  logic [31:0]    device_wdata  [NrDevices];
  logic           device_rvalid [NrDevices];
  logic [31:0]    device_rdata  [NrDevices];
  logic           device_err    [NrDevices];

  // Device address mapping
  logic [31:0] cfg_device_addr_base [NrDevices];
  logic [31:0] cfg_device_addr_mask [NrDevices];
  assign cfg_device_addr_base[Rom]      = 32'h100000;
  assign cfg_device_addr_mask[Rom]      =~32'h0001FFFF; // Instr (0x10xxxx) + ROM rodata (0x11xxxx)
  assign cfg_device_addr_base[Ram]      = 32'h120000;
  assign cfg_device_addr_mask[Ram]      =~32'h0001FFFF; // RAM (0x12xxxx / 0x13xxxx)
  assign cfg_device_addr_base[MemCrypt] = 32'h140000;
  assign cfg_device_addr_mask[MemCrypt] =~32'h0003FF;   // 1 KB cipher config
  assign cfg_device_addr_base[IO]       = 32'h150000;
  assign cfg_device_addr_mask[IO]       =~32'h000FFF;   // 4 KB

  // Instruction fetch signals
  logic        instr_req;
  logic        instr_gnt;
  logic [31:0] instr_addr;

  assign instr_req_o  = instr_req;
  assign instr_addr_o = instr_addr;
  assign instr_gnt    = instr_req & ~rom_busy_i;

  bus #(
    .NrDevices    ( NrDevices ),
    .NrHosts      ( NrHosts   ),
    .DataWidth    ( 32        ),
    .AddressWidth ( 32        )
  ) u_bus (
    .clk_i               (clk),
    .rst_ni              (rst_n),

    .host_req_i          (host_req     ),
    .host_gnt_o          (host_gnt     ),
    .host_addr_i         (host_addr    ),
    .host_we_i           (host_we      ),
    .host_be_i           (host_be      ),
    .host_wdata_i        (host_wdata   ),
    .host_rvalid_o       (host_rvalid  ),
    .host_rdata_o        (host_rdata   ),
    .host_err_o          (host_err     ),

    .device_req_o        (device_req   ),
    .device_addr_o       (device_addr  ),
    .device_we_o         (device_we    ),
    .device_be_o         (device_be    ),
    .device_wdata_o      (device_wdata ),
    .device_rvalid_i     (device_rvalid),
    .device_rdata_i      (device_rdata ),
    .device_err_i        (device_err   ),

    .cfg_device_addr_base,
    .cfg_device_addr_mask
  );

  assign device_err[Rom]      = 1'b0;
  assign device_err[Ram]      = 1'b0;
  assign device_err[MemCrypt] = 1'b0;
  assign device_err[IO]       = 1'b0;

  if (SecureIbex) begin : g_mem_rdata_ecc
    logic [31:0] unused_data_rdata;
    logic [31:0] unused_instr_rdata;

    prim_secded_inv_39_32_enc u_data_rdata_intg_gen (
      .data_i (host_rdata[CoreD]),
      .data_o ({data_rdata_intg, unused_data_rdata})
    );

    prim_secded_inv_39_32_enc u_instr_rdata_intg_gen (
      .data_i (instr_rdata_i),
      .data_o ({instr_rdata_intg, unused_instr_rdata})
    );
  end else begin : g_no_mem_rdata_ecc
    assign data_rdata_intg = '0;
    assign instr_rdata_intg = '0;
  end

  ibex_top #(
      .SecureIbex      ( SecureIbex       ),
      .ICacheScramble  ( ICacheScramble   ),
      .PMPEnable       ( PMPEnable        ),
      .PMPGranularity  ( PMPGranularity   ),
      .PMPNumRegions   ( PMPNumRegions    ),
      .MHPMCounterNum  ( MHPMCounterNum   ),
      .MHPMCounterWidth( MHPMCounterWidth ),
      .RV32E           ( RV32E            ),
      .RV32M           ( RV32M            ),
      .RV32B           ( RV32B            ),
      .RegFile         ( RegFile          ),
      .BranchTargetALU ( BranchTargetALU  ),
      .ICache          ( ICache           ),
      .ICacheECC       ( ICacheECC        ),
      .WritebackStage  ( WritebackStage   ),
      .BranchPredictor ( BranchPredictor  ),
      .DbgTriggerEn    ( DbgTriggerEn     ),
      .DmBaseAddr      ( 32'h00100000     ),
      .DmAddrMask      ( 32'h00000003     ),
      .DmHaltAddr      ( 32'h00100000     ),
      .DmExceptionAddr ( 32'h00100000     )
    ) u_top (
      .clk_i                     (clk),
      .rst_ni                    (rst_n),

      .test_en_i                 (1'b0),
      .scan_rst_ni               (1'b1),
      .ram_cfg_icache_tag_i      (prim_ram_1p_pkg::RAM_1P_CFG_DEFAULT),
      .ram_cfg_rsp_icache_tag_o  (),
      .ram_cfg_icache_data_i     (prim_ram_1p_pkg::RAM_1P_CFG_DEFAULT),
      .ram_cfg_rsp_icache_data_o (),

      .hart_id_i                 (32'b0),
      .boot_addr_i               (32'h00100000),

      .instr_req_o               (instr_req),
      .instr_gnt_i               (instr_gnt),
      .instr_rvalid_i            (instr_rvalid_i),
      .instr_addr_o              (instr_addr),
      .instr_rdata_i             (instr_rdata_i),
      .instr_rdata_intg_i        (instr_rdata_intg),
      .instr_err_i               (1'b0),

      .data_req_o                (host_req[CoreD]),
      .data_gnt_i                (host_gnt[CoreD]),
      .data_rvalid_i             (host_rvalid[CoreD]),
      .data_we_o                 (host_we[CoreD]),
      .data_be_o                 (host_be[CoreD]),
      .data_addr_o               (host_addr[CoreD]),
      .data_wdata_o              (host_wdata[CoreD]),
      .data_wdata_intg_o         (),
      .data_rdata_i              (host_rdata[CoreD]),
      .data_rdata_intg_i         (data_rdata_intg),
      .data_err_i                (host_err[CoreD]),

      .irq_software_i            (1'b0),
      .irq_timer_i               (1'b0),
      .irq_external_i            (1'b0),
      .irq_fast_i                (15'b0),
      .irq_nm_i                  (1'b0),

      .scramble_key_valid_i      ('0),
      .scramble_key_i            ('0),
      .scramble_nonce_i          ('0),
      .scramble_req_o            (),

      .debug_req_i               (1'b0),
      .crash_dump_o              (),
      .double_fault_seen_o       (),

      .fetch_enable_i            (ibex_pkg::IbexMuBiOn),
      .alert_minor_o             (),
      .alert_major_internal_o    (),
      .alert_major_bus_o         (),
      .core_sleep_o              ()
    );

  // ROM data interface (read only). Any request is treated as a read so the
  // ROM always produces a bus response; writes are never applied.
  assign rom_addr_o        = device_addr[Rom];
  assign rom_wdata_o       = 32'b0;
  assign rom_be_o          = 4'b0;
  assign rom_we_o          = 1'b0;
  assign rom_re_o          = device_req[Rom];
  assign device_rdata[Rom]  = rom_rdata_i;
  assign device_rvalid[Rom] = rom_rvalid_i;

  // RAM interface (data side, own address range).
  assign ram_addr_o        = device_addr[Ram];
  assign ram_wdata_o       = device_wdata[Ram];
  assign ram_be_o          = device_be[Ram];
  assign ram_we_o          = device_req[Ram] &  device_we[Ram];
  assign ram_re_o          = device_req[Ram] & ~device_we[Ram];
  assign device_rdata[Ram]  = ram_rdata_i;
  assign device_rvalid[Ram] = ram_rvalid_i;

  // Cipher config interface (MMIO for the encrypted RAM)
  assign cfg_addr_o             = device_addr[MemCrypt];
  assign cfg_req_o              = device_req[MemCrypt];
  assign cfg_we_o               = device_we[MemCrypt];
  assign cfg_wdata_o            = device_wdata[MemCrypt];
  assign device_rdata[MemCrypt]  = cfg_rdata_i;
  assign device_rvalid[MemCrypt] = cfg_rvalid_i;

  // IO Interface
  assign io_addr_o       = device_addr[IO];
  assign io_we_o         = device_we[IO] ? device_be[IO] : 4'b0;
  assign io_wdata_o      = device_wdata[IO];
  assign io_req_o        = device_req[IO];
  assign device_rdata[IO] = io_rdata_i;
  assign device_rvalid[IO]= io_rvalid_i;

endmodule
