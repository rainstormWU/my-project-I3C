module packet_sram (
    // 时钟和复位
    input clk,
    input rst_n,
    // M1 (APB) 写端口
    input apb_wr_en,
    input [2:0] apb_addr,
    input [31:0] apb_wr_data,
    // M1 (APB) 读端口 (组合逻辑输出)
    input apb_rd_en,
    output wire [31:0] apb_rd_data,
    // M3 (处理核) 读端口 (寄存器输出)
    input proc_rd_en,
    input [2:0] proc_rd_addr,
    output reg [31:0] proc_rd_data
);
    reg [31:0] sram_data [0:7];
    integer i;

    // 复位：清零所有 SRAM 单元
    always@(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            for(i=0; i<8; i=i+1) begin
                sram_data[i] <= 32'd0;
            end
        end
        else begin
            // 写优先于读
            if(apb_wr_en) begin
                sram_data[apb_addr] <= apb_wr_data;
            end
            // M3 处理核读口 (寄存器输出，用于时序同步)
            if(proc_rd_en) begin
                proc_rd_data <= sram_data[proc_rd_addr];
            end
        end
    end

    // APB读口: 组合逻辑直接输出，无延迟
    assign apb_rd_data = sram_data[apb_addr];

endmodule
