// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
// Modified 2026 by Niels Wieser, TU Darmstadt:
// adapted as evaluation system for the micro-architecturally protected Ibex.

`ifndef RV32M
  `define RV32M ibex_pkg::RV32MFast
`endif

`ifndef RV32B
  `define RV32B ibex_pkg::RV32BNone
`endif

`ifndef RegFile
  `define RegFile ibex_pkg::RegFileFF
`endif

/**
 * Ibex simple system for synthesis
 *
 * This is a basic system consisting of an ibex, a 1 MB sram for instruction/data,
 * a timer peripheral, and the memory encryption unit.
 */

module ibex_simple_system (
  input  IO_CLK,
  input  IO_RST_N,
  output [31:0] addr,
  output [31:0] data
);

  parameter bit                 SecureIbex               = 1'b0;
  parameter bit                 ICacheScramble           = 1'b0;
  parameter bit                 PMPEnable                = 1'b0;
  parameter int unsigned        PMPGranularity           = 0;
  parameter int unsigned        PMPNumRegions            = 4;
  parameter int unsigned        MHPMCounterNum           = 0;
  parameter int unsigned        MHPMCounterWidth         = 40;
  parameter bit                 RV32E                    = 1'b0;
  parameter ibex_pkg::rv32m_e   RV32M                    = `RV32M;
  parameter ibex_pkg::rv32b_e   RV32B                    = `RV32B;
  parameter ibex_pkg::regfile_e RegFile                  = `RegFile;
  parameter bit                 BranchTargetALU          = 1'b0;
  parameter bit                 WritebackStage           = 1'b0;
  parameter bit                 ICache                   = 1'b0;
  parameter bit                 DbgTriggerEn             = 1'b0;
  parameter bit                 ICacheECC                = 1'b0;
  parameter bit                 BranchPredictor          = 1'b0;
  parameter                     SRAMInitFile             = "";

  logic clk_sys, rst_sys_n;

  assign clk_sys = IO_CLK;
  assign rst_sys_n = IO_RST_N;

  typedef enum logic {
    CoreD
  } bus_host_e;

  typedef enum logic[1:0] {
    Ram,
    Timer,
    MemCrypt
  } bus_device_e;

  localparam int NrDevices = 3;
  localparam int NrHosts = 1;

  // interrupts
  logic timer_irq;

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
  assign cfg_device_addr_base[Ram] = 32'h100000;
  assign cfg_device_addr_mask[Ram] = ~32'hFFFFF; // 1 MB
  assign cfg_device_addr_base[Timer] = 32'h30000;
  assign cfg_device_addr_mask[Timer] = ~32'h3FF; // 1 kB
  assign cfg_device_addr_base[MemCrypt] = 32'h140000;
  assign cfg_device_addr_mask[MemCrypt] = ~32'h3FF; // 1 kB

  // Instruction fetch signals
  logic instr_req;
  logic instr_gnt;
  logic instr_rvalid;
  logic [31:0] instr_addr;
  logic [31:0] instr_rdata;
  logic instr_err;

  assign instr_gnt = instr_req;
  assign instr_err = '0;

  // Tie-off unused error signals
  assign device_err[Ram] = 1'b0;
  assign device_err[MemCrypt] = 1'b0;

  bus #(
    .NrDevices    ( NrDevices ),
    .NrHosts      ( NrHosts   ),
    .DataWidth    ( 32        ),
    .AddressWidth ( 32        )
  ) u_bus (
    .clk_i               (clk_sys),
    .rst_ni              (rst_sys_n),

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

  if (SecureIbex) begin : g_mem_rdata_ecc
    logic [31:0] unused_data_rdata;
    logic [31:0] unused_instr_rdata;

    prim_secded_inv_39_32_enc u_data_rdata_intg_gen (
      .data_i (host_rdata[CoreD]),
      .data_o ({data_rdata_intg, unused_data_rdata})
    );

    prim_secded_inv_39_32_enc u_instr_rdata_intg_gen (
      .data_i (instr_rdata),
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
      .clk_i                     (clk_sys),
      .rst_ni                    (rst_sys_n),

      .test_en_i                 (1'b0),
      .scan_rst_ni               (1'b1),
      .ram_cfg_icache_tag_i      (prim_ram_1p_pkg::RAM_1P_CFG_DEFAULT),
      .ram_cfg_rsp_icache_tag_o  (),
      .ram_cfg_icache_data_i     (prim_ram_1p_pkg::RAM_1P_CFG_DEFAULT),
      .ram_cfg_rsp_icache_data_o (),

      .hart_id_i                 (32'b0),
      // First instruction executed is at 0x0 + 0x80
      .boot_addr_i               (32'h00100000),

      .instr_req_o               (instr_req),
      .instr_gnt_i               (instr_gnt),
      .instr_rvalid_i            (instr_rvalid),
      .instr_addr_o              (instr_addr),
      .instr_rdata_i             (instr_rdata),
      .instr_rdata_intg_i        (instr_rdata_intg),
      .instr_err_i               (instr_err),

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
      .irq_timer_i               (timer_irq),
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

  // MemCrypt implementation
  logic [31:0] crypt_ram_addr;
  logic [31:0] crypt_ram_wdata;
  logic [ 3:0] crypt_ram_be;
  logic        crypt_ram_we;
  logic        crypt_ram_re;
  
  logic [31:0] ram_rdata_raw;
  logic        ram_rvalid_raw;

  mem_crypt u_mem_crypt (
    .clk_i        (clk_sys),
    .rst_ni       (rst_sys_n),

    // CPU Interface
    .cpu_addr_i   (device_addr[Ram]),
    .cpu_wdata_i  (device_wdata[Ram]),
    .cpu_be_i     (device_be[Ram]),
    .cpu_we_i     (device_we[Ram]),
    .cpu_req_i    (device_req[Ram]),
    .cpu_rdata_o  (device_rdata[Ram]),
    .cpu_done_o   (device_rvalid[Ram]),

    // RAM Interface
    .ram_addr_o   (crypt_ram_addr),
    .ram_wdata_o  (crypt_ram_wdata),
    .ram_be_o     (crypt_ram_be),
    .ram_we_o     (crypt_ram_we),
    .ram_re_o     (crypt_ram_re),
    .ram_rdata_i  (ram_rdata_raw),
    .ram_rvalid_i (ram_rvalid_raw),

    // Config (MMIO)
    .cfg_addr_i   (device_addr[MemCrypt]),
    .cfg_req_i    (device_req[MemCrypt]),
    .cfg_wr_en_i  (device_we[MemCrypt]),
    .cfg_wdata_i  (device_wdata[MemCrypt]),
    .cfg_rdata_o  (device_rdata[MemCrypt]),
    .cfg_rvalid_o (device_rvalid[MemCrypt])
  );

  custom_sram #(
    .ADDR_WIDTH(32),
    .DATA_WIDTH(32),
    .MEMSIZE(1024*1024/4)
  ) u_ram (
    .CLK       (clk_sys),
    .A1ADDR    ({2'b0, crypt_ram_addr[31:2]}),
    .A1EN      ({4{crypt_ram_we}} & crypt_ram_be),
    .A1DATA    (crypt_ram_wdata),
    .B1ADDR    ({2'b0, crypt_ram_addr[31:2]}),
    .B1EN      (crypt_ram_re),
    .B1DATA    (ram_rdata_raw),

    .B2ADDR    ({2'b0, instr_addr[31:2]}),
    .B2EN      (instr_req),
    .B2DATA    (instr_rdata)
  );

  assign addr = device_addr[Ram][31:0];
  assign data = device_wdata[Ram];

  always_ff @(posedge clk_sys or negedge rst_sys_n) begin
    if (!rst_sys_n) begin
      instr_rvalid <= '0;
      ram_rvalid_raw <= '0;
    end else begin
      instr_rvalid <= instr_req;
      ram_rvalid_raw <= crypt_ram_re;
    end
  end


  timer #(
    .DataWidth    (32),
    .AddressWidth (32)
    ) u_timer (
      .clk_i          (clk_sys),
      .rst_ni         (rst_sys_n),

      .timer_req_i    (device_req[Timer]),
      .timer_we_i     (device_we[Timer]),
      .timer_be_i     (device_be[Timer]),
      .timer_addr_i   (device_addr[Timer]),
      .timer_wdata_i  (device_wdata[Timer]),
      .timer_rvalid_o (device_rvalid[Timer]),
      .timer_rdata_o  (device_rdata[Timer]),
      .timer_err_o    (device_err[Timer]),
      .timer_intr_o   (timer_irq)
    );

endmodule
