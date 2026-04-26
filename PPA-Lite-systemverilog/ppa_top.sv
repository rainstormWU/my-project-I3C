// ============================================================================
// PPA-Lite Top Module
// Integrates: APB Slave Interface, Packet SRAM, Processing Core (M3 placeholder)
// ============================================================================
module ppa_top (
    // APB Interface
    input  logic       PCLK,
    input  logic       PRESETn,
    input  logic       PSEL,
    input  logic       PENABLE,
    input  logic       PWRITE,
    input  logic [12:0] PADDR,
    input  logic [31:0] PWDATA,
    output logic [31:0] PRDATA,
    output logic       PREADY,
    output logic       PSLVERR,

    // Interrupt Output
    output logic       irq_o
);

    // ==========================================================================
    // Internal Wires
    // ==========================================================================
    // SRAM Interface (M1 <-> M2)
    logic       pkt_mem_we_o;
    logic       pkt_mem_re_o;
    logic [2:0] pkt_mem_addr_o;
    logic [31:0] pkt_mem_wdata_o;
    logic [31:0] pkt_mem_rdata_i;

    // Control Signals (M1 -> M3)
    logic       enable_o;
    logic       start_o;
    logic       algo_mode_o;
    logic [3:0] type_mask_o;
    logic [5:0] exp_pkt_len_o;
    logic       done_irq_en_o;
    logic       err_irq_en_o;

    // Status/Result Signals (M3 -> M1)
    logic       busy_i;
    logic       done_i;
    logic       format_ok_i;
    logic       length_error_i;
    logic       type_error_i;
    logic       chk_error_i;
    logic [5:0] res_pkt_len_i;
    logic [7:0] res_pkt_type_i;
    logic [7:0] res_payload_sum_i;
    logic [7:0] res_payload_xor_i;

    // ==========================================================================
    // Instance 1: APB Slave Interface (M1)
    // ==========================================================================
    apb_slave_if apb_slave_if_inst (
        // APB Interface
        .PCLK          (PCLK),
        .PRESETn       (PRESETn),
        .PSEL          (PSEL),
        .PENABLE       (PENABLE),
        .PWRITE        (PWRITE),
        .PADDR         (PADDR),
        .PWDATA        (PWDATA),
        .PRDATA        (PRDATA),
        .PREADY        (PREADY),
        .PSLVERR       (PSLVERR),

        // Control Signal Outputs (to M3)
        .enable_o      (enable_o),
        .start_o       (start_o),
        .algo_mode_o   (algo_mode_o),
        .type_mask_o   (type_mask_o),
        .exp_pkt_len_o (exp_pkt_len_o),
        .done_irq_en_o (done_irq_en_o),
        .err_irq_en_o  (err_irq_en_o),

        // SRAM Interface (to M2)
        .pkt_mem_we_o    (pkt_mem_we_o),
        .pkt_mem_re_o    (pkt_mem_re_o),
        .pkt_mem_addr_o  (pkt_mem_addr_o),
        .pkt_mem_wdata_o (pkt_mem_wdata_o),
        .pkt_mem_rdata_i (pkt_mem_rdata_i),

        // Status/Result Inputs (from M3)
        .busy_i          (busy_i),
        .done_i          (done_i),
        .format_ok_i     (format_ok_i),
        .length_error_i   (length_error_i),
        .type_error_i     (type_error_i),
        .chk_error_i      (chk_error_i),
        .res_pkt_len_i   (res_pkt_len_i),
        .res_pkt_type_i  (res_pkt_type_i),
        .res_payload_sum_i (res_payload_sum_i),
        .res_payload_xor_i (res_payload_xor_i),

        // Interrupt Output
        .irq_o          (irq_o)
    );

    // ==========================================================================
    // Instance 2: Packet SRAM (M2)
    // ==========================================================================
    packet_sram packet_sram_inst (
        // Clock and Reset
        .clk            (PCLK),
        .rst_n          (PRESETn),

        // M1 (APB) Write Port
        .apb_wr_en      (pkt_mem_we_o),
        .apb_addr       (pkt_mem_addr_o),
        .apb_wr_data    (pkt_mem_wdata_o),

        // M1 (APB) Read Port
        .apb_rd_en      (pkt_mem_re_o),
        .apb_rd_data    (pkt_mem_rdata_i),

        // M3 (Processing Core) Read Port - disabled (M3 not implemented yet)
        .proc_rd_en     (1'b0),
        .proc_rd_addr   (3'd0),
        .proc_rd_data   ()  // Unused when M3 is not present
    );

    // ==========================================================================
    // M3 (Processing Core) Placeholder Connections
    // ==========================================================================
    // TODO: When M3 is implemented, connect these signals:
    //   - busy_i:       High when M3 is processing a packet
    //   - done_i:       Pulse when M3 completes processing
    //   - format_ok_i:  Packet format validation result
    //   - *_error_i:    Error flags from processing
    //   - res_*_i:      Processing results (length, type, checksums)

    // Current placeholder assignments (reset values):
    assign busy_i             = 1'b0;  // M3 not busy (not implemented)
    assign done_i             = 1'b0;  // M3 not done (not implemented)
    assign format_ok_i        = 1'b0;  // No format info yet
    assign length_error_i     = 1'b0;  // No errors
    assign type_error_i       = 1'b0;
    assign chk_error_i        = 1'b0;
    assign res_pkt_len_i       = 6'd0;
    assign res_pkt_type_i     = 8'd0;
    assign res_payload_sum_i   = 8'd0;
    assign res_payload_xor_i   = 8'd0;

    // ==========================================================================
    // Unused Control Signal Assignments
    // ==========================================================================
    // These outputs from apb_slave_if are currently unused:
    //   enable_o, start_o, algo_mode_o, type_mask_o, exp_pkt_len_o,
    //   done_irq_en_o, err_irq_en_o
    // They will be connected to M3 when implemented.
    // To avoid synthesis warnings, they can be marked as unused:
    // (* keep = "true" *) logic [15:0] unused_ctrl;
    // assign unused_ctrl = {enable_o, start_o, algo_mode_o, type_mask_o,
    //                       exp_pkt_len_o, done_irq_en_o, err_irq_en_o, 9'b0};

endmodule : ppa_top
