// ============================================================================
// APB Slave Interface - PPA-Lite
// Handles APB protocol, CSR registers, and SRAM access coordination
// ============================================================================
module apb_slave_if (
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

    // Control Signal Outputs to CSR Registers
    output logic       enable_o,
    output logic       start_o,
    output logic       algo_mode_o,
    output logic [3:0] type_mask_o,
    output logic [5:0] exp_pkt_len_o,
    output logic       done_irq_en_o,
    output logic       err_irq_en_o,

    // SRAM Write Interface (M1 -> M2)
    output logic       pkt_mem_we_o,
    output logic       pkt_mem_re_o,
    output logic [2:0] pkt_mem_addr_o,
    output logic [31:0] pkt_mem_wdata_o,

    // SRAM Read Data (M2 -> M1 APB Read Port)
    input  logic [31:0] pkt_mem_rdata_i,

    // Input Signals from M3 (Processing Core)
    input  logic       busy_i,
    input  logic       done_i,
    input  logic       format_ok_i,
    input  logic       length_error_i,
    input  logic       type_error_i,
    input  logic       chk_error_i,
    input  logic [5:0] res_pkt_len_i,
    input  logic [7:0] res_pkt_type_i,
    input  logic [7:0] res_payload_sum_i,
    input  logic [7:0] res_payload_xor_i,

    // Interrupt Output
    output logic       irq_o
);

    // ==========================================================================
    // CSR Registers
    // ==========================================================================
    // WO Registers (APB writable)
    logic       ctrl_reg;
    logic       cfg_algo_mode;
    logic [3:0] cfg_type_mask;
    logic       irq_en_done;
    logic       irq_en_err;
    logic [5:0] exp_pkt_len;
    logic       start_pulse;

    // Internal busy tracking (set by START pulse, cleared when M3 completes)
    // This ensures START acceptance check uses synchronized busy status
    logic       internal_busy;
    // Internal done tracking (set when M3 completes, cleared when START accepted)
    logic       internal_done;
    // Internal format_ok tracking (set when M3 completes without errors)
    logic       internal_format_ok;

    // RO Registers (M3 driven)
    logic [5:0] res_pkt_len;
    logic [7:0] res_pkt_type;
    logic [7:0] res_payload_sum;
    logic [7:0] res_payload_xor;

    // Interrupt Status Registers (RW1C: Write 1 to clear)
    logic       irq_sta_done;
    logic       irq_sta_err;

    // ==========================================================================
    // APB State Machine
    // ==========================================================================
    typedef enum logic [2:0] {
        IDLE   = 3'd0,
        SETUP  = 3'd1,
        ACCESS = 3'd2
    } apb_state_t;

    apb_state_t state_q;
    apb_state_t state_d;
    logic [11:0] latched_paddr;
    logic       latched_pwrite;
    logic [31:0] latched_pwdata;

    // State register update
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)
            state_q <= IDLE;
        else
            state_q <= state_d;
    end

    // Next state logic
    always_comb begin
        unique case (state_q)
            IDLE:   state_d = (PSEL && !PENABLE) ? SETUP : IDLE;
            SETUP:  state_d = ACCESS;
            ACCESS: state_d = (PSEL && !PENABLE) ? SETUP : IDLE;
            default: state_d = state_q;
        endcase
    end

    // Latch address and data in SETUP phase
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            latched_paddr  <= 12'd0;
            latched_pwrite <= 1'b0;
            latched_pwdata <= 32'd0;
        end
        else if (state_q == SETUP) begin
            latched_paddr  <= PADDR[11:0];
            latched_pwrite <= PWRITE;
            latched_pwdata <= PWDATA;
        end
    end

    // PREADY is always asserted (simple slave)
    assign PREADY = 1'b1;

    // ==========================================================================
    // Address Decoding
    // ==========================================================================
    // CSR Area: 0x000 ~ 0x02C (bits[11:5] = 0)
    // pkt_mem Area: 0x080 ~ 0x0BC (bits[11:5] = 4)
    logic       csr_area;
    logic       pkt_mem_area;
    logic       illegal_area;
    logic [4:0] csr_addr;
    logic [2:0] mem_addr;

    assign csr_area     = (latched_paddr[11:5] == 7'd0);
    assign pkt_mem_area = (latched_paddr[11:5] == 7'd4);
    assign illegal_area = !(csr_area || pkt_mem_area);
    assign csr_addr     = latched_paddr[4:0];
    assign mem_addr     = latched_paddr[4:2];  // SRAM word address (8 words × 4 bytes)

    // ==========================================================================
    // Write CSR Registers
    // ==========================================================================
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            ctrl_reg      <= 1'b0;
            cfg_algo_mode <= 1'b0;
            cfg_type_mask <= 4'b1111;
            irq_en_done   <= 1'b0;
            irq_en_err    <= 1'b0;
            exp_pkt_len   <= 6'd0;
            start_pulse   <= 1'b0;
        end
        else if (state_q == ACCESS && csr_area && latched_pwrite) begin
            case (csr_addr)
                5'd0: begin
                    ctrl_reg    <= latched_pwdata[0];
                    // START only accepted when enable=1 AND busy=0 (per spec §5.2)
                    // Use the new ctrl_reg value (latched_pwdata[0]) for this cycle
                    start_pulse <= latched_pwdata[1] && latched_pwdata[0] && !busy_i;
                end
                5'd1: begin
                    cfg_algo_mode <= latched_pwdata[0];
                    cfg_type_mask <= latched_pwdata[7:4];
                end
                5'd3: begin
                    irq_en_done <= latched_pwdata[0];
                    irq_en_err  <= latched_pwdata[1];
                end
                5'd5: exp_pkt_len <= latched_pwdata[5:0];
                default: ; // Other addresses: no change
            endcase
        end
        else begin
            start_pulse <= 1'b0;  // START is a pulse signal
        end
    end

    // ==========================================================================
    // Interrupt Status Registers (RW1C)
    // ==========================================================================
    // Set by M3 completion, cleared by APB write to CSR[4]
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            irq_sta_done <= 1'b0;
            irq_sta_err  <= 1'b0;
        end
        else if (done_i && !busy_i) begin
            // M3 completes: set status flags based on error conditions
            irq_sta_done <= 1'b1;
            irq_sta_err  <= (length_error_i || type_error_i || chk_error_i);
        end
        else if (state_q == ACCESS && csr_area && latched_pwrite && csr_addr == 5'd4) begin
            // APB write to CSR[4]: write-1-to-clear
            if (latched_pwdata[0]) irq_sta_done <= 1'b0;
            if (latched_pwdata[1]) irq_sta_err  <= 1'b0;
        end
    end

    // ==========================================================================
    // Internal Status Tracking
    // ==========================================================================
    // busy: set when START pulse is accepted, cleared when M3 completes (done_i && !busy_i)
    // done: set when M3 completes, cleared when next START is accepted
    // format_ok: set when M3 completes without errors, cleared when next START is accepted
    // This tracks M1's view of processing status per spec §5.2
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            internal_busy       <= 1'b0;
            internal_done       <= 1'b0;
            internal_format_ok  <= 1'b0;
        end
        else if (start_pulse) begin
            // New START accepted: clear previous status, set busy
            internal_busy       <= 1'b1;
            internal_done       <= 1'b0;
            internal_format_ok  <= 1'b0;
        end
        else if (done_i && !busy_i) begin
            // M3 completed processing: update done and format_ok status
            internal_busy       <= 1'b0;
            internal_done       <= 1'b1;
            internal_format_ok  <= !(length_error_i || type_error_i || chk_error_i);
        end
        // Otherwise: maintain current values
    end

    // ==========================================================================
    // Read-Only Registers (M3 Driven)
    // ==========================================================================
    // These registers are updated when M3 completes processing
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            res_pkt_len      <= 6'd0;
            res_pkt_type     <= 8'd0;
            res_payload_sum  <= 8'd0;
            res_payload_xor  <= 8'd0;
        end
        else if (done_i) begin
            res_pkt_len      <= res_pkt_len_i;
            res_pkt_type     <= res_pkt_type_i;
            res_payload_sum  <= res_payload_sum_i;
            res_payload_xor  <= res_payload_xor_i;
        end
    end

    // ==========================================================================
    // SRAM Write Interface (M1 -> M2)
    // ==========================================================================
    // Write is blocked if M1's internal busy tracking indicates processing in progress
    // This ensures proper write protection per spec §6.3
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            pkt_mem_we_o    <= 1'b0;
            pkt_mem_addr_o  <= 3'd0;
            pkt_mem_wdata_o <= 32'd0;
        end
        else if (state_q == ACCESS && pkt_mem_area && latched_pwrite) begin
            if (internal_busy) begin
                // Block write if M1's internal busy is set (M3 is processing)
                pkt_mem_we_o    <= 1'b0;
                pkt_mem_addr_o  <= 3'd0;
                pkt_mem_wdata_o <= 32'd0;
            end
            else begin
                pkt_mem_we_o    <= 1'b1;
                pkt_mem_addr_o  <= mem_addr;
                pkt_mem_wdata_o <= latched_pwdata;
            end
        end
        else begin
            pkt_mem_we_o    <= 1'b0;
            pkt_mem_addr_o  <= 3'd0;
            pkt_mem_wdata_o <= 32'd0;
        end
    end

    // ==========================================================================
    // SRAM Read Interface (M1 -> M2 APB Read Port)
    // ==========================================================================
    // Read enable flag (for status tracking, not required for data output)
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            pkt_mem_re_o <= 1'b0;
        end
        else if (state_q == ACCESS && pkt_mem_area && !latched_pwrite) begin
            pkt_mem_re_o <= 1'b1;
        end
        else begin
            pkt_mem_re_o <= 1'b0;
        end
    end

    // ==========================================================================
    // PRDATA Read Data Selection (Combinational)
    // ==========================================================================
    logic csr_read;
    logic mem_read;

    assign csr_read = (state_q == ACCESS) && csr_area && !latched_pwrite;
    assign mem_read = (state_q == ACCESS) && pkt_mem_area && !latched_pwrite;

    // Combinational read data multiplexer
    always_comb begin
        PRDATA = 32'd0;  // Default: all zeros
        if (csr_read) begin
            case (csr_addr)
                5'd0:  PRDATA = {31'd0, ctrl_reg};
                5'd1:  PRDATA = {24'd0, 3'b000, cfg_type_mask, 3'b000, cfg_algo_mode};
                5'd2:  PRDATA = {28'd0, internal_format_ok,
                                  (length_error_i || type_error_i || chk_error_i),
                                  internal_done, internal_busy};  // STATUS: [3]=format_ok, [2]=error, [1]=done, [0]=busy
                5'd3:  PRDATA = {30'd0, irq_en_err, irq_en_done};
                5'd4:  PRDATA = {30'd0, irq_sta_err, irq_sta_done};
                5'd5:  PRDATA = {26'd0, exp_pkt_len};
                5'd6:  PRDATA = {26'd0, res_pkt_len};
                5'd7:  PRDATA = {24'd0, res_pkt_type};
                5'd8:  PRDATA = {24'd0, res_payload_sum};
                5'd9:  PRDATA = {24'd0, res_payload_xor};
                5'd10: PRDATA = {29'd0, chk_error_i, type_error_i, length_error_i};
                default: PRDATA = 32'd0;
            endcase
        end
        else if (mem_read) begin
            PRDATA = pkt_mem_rdata_i;  // SRAM read data (same cycle output)
        end
    end

    // ==========================================================================
    // PSLVERR Error Response
    // ==========================================================================
    // Error conditions:
    // 1. Access to illegal address space
    // 2. Write to read-only CSR registers (addresses 6-10)
    // 3. Write to SRAM while M3 is busy
    logic is_write_ro_csr;
    logic is_write_sram_busy;

    assign is_write_ro_csr    = csr_area && latched_pwrite && (csr_addr >= 5'd6);
    assign is_write_sram_busy = pkt_mem_area && latched_pwrite && internal_busy;

    assign PSLVERR = (state_q == ACCESS) && (
        illegal_area ||
        is_write_ro_csr ||
        is_write_sram_busy
    );

    // ==========================================================================
    // Output Signal Assignments
    // ==========================================================================
    assign enable_o      = ctrl_reg;
    assign algo_mode_o   = cfg_algo_mode;
    assign type_mask_o   = cfg_type_mask;
    assign exp_pkt_len_o = exp_pkt_len;
    assign done_irq_en_o = irq_en_done;
    assign err_irq_en_o  = irq_en_err;
    assign start_o       = start_pulse;

    // Combined interrupt: DONE interrupt OR ERROR interrupt
    assign irq_o = (irq_sta_done & irq_en_done) | (irq_sta_err & irq_en_err);

endmodule : apb_slave_if
