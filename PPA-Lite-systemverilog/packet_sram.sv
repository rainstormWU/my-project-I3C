// ============================================================================
// Packet SRAM - PPA-Lite
// Dual-port SRAM: M1 (APB) for read/write, M3 (Processing Core) for read
// ============================================================================
module packet_sram (
    // Clock and Reset
    input  logic       clk,
    input  logic       rst_n,

    // M1 (APB Master) Write Port
    input  logic       apb_wr_en,
    input  logic [2:0] apb_addr,
    input  logic [31:0] apb_wr_data,

    // M1 (APB Master) Read Port (Combinational output - no delay)
    input  logic       apb_rd_en,
    output logic [31:0] apb_rd_data,

    // M3 (Processing Core) Read Port (Registered output - timing sync)
    input  logic       proc_rd_en,
    input  logic [2:0] proc_rd_addr,
    output logic [31:0] proc_rd_data
);

    // ==========================================================================
    // SRAM Memory Array (8 words × 32 bits)
    // ==========================================================================
    logic [31:0] sram_data [0:7];

    // ==========================================================================
    // Write Operation & M3 Read Operation (Synchronous)
    // ==========================================================================
    // Write takes priority over M3 read in the same cycle
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Asynchronous reset: clear all SRAM cells
            for (int i = 0; i < 8; i++) begin
                sram_data[i] <= 32'd0;
            end
        end
        else begin
            // M1 (APB) Write Port - Write takes priority
            if (apb_wr_en) begin
                sram_data[apb_addr] <= apb_wr_data;
            end

            // M3 (Processing Core) Read Port - Registered output for timing sync
            if (proc_rd_en) begin
                proc_rd_data <= sram_data[proc_rd_addr];
            end
        end
    end

    // ==========================================================================
    // M1 (APB) Read Port - Combinational Output
    // ==========================================================================
    // Combinational read: data available in the same cycle as address
    // This meets the APB spec requirement: "PRDATA in the same cycle output"
    assign apb_rd_data = sram_data[apb_addr];

endmodule : packet_sram
