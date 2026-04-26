module ppa_top (
    input PCLK,
    input PRESETn,
    input PSEL,
    input PENABLE,
    input PWRITE,
    input [11:0] PADDR,
    input [31:0] PWDATA,
    output wire [31:0] PRDATA,
    output wire PREADY,
    output wire PSLVERR,
    output wire irq_o
);

    wire pkt_mem_we_o;
    wire pkt_mem_re_o;
    wire [2:0] pkt_mem_addr_o;
    wire [31:0] pkt_mem_wdata_o;
    wire [31:0] pkt_mem_rdata_i;

    // M3模块信号 (暂时固定为默认值，待M3模块实现后再连接)
    // M3模块负责: IDLE->PROCESS->DONE三态FSM,包头解析,格式检查,sum/xor计算
    wire busy_i;           // M3忙标志 (固定=0, M3实现后由M3.busy_o驱动)
    wire done_i;           // M3完成标志 (固定=0, M3实现后由M3.done_o驱动)
    wire format_ok_i;      // M3格式校验通过 (固定=1, M3实现后由M3.format_ok_o驱动)
    wire length_error_i;   // M3长度错误 (固定=0, M3实现后由M3.length_error_o驱动)
    wire type_error_i;     // M3类型错误 (固定=0, M3实现后由M3.type_error_o驱动)
    wire chk_error_i;      // M3校验错误 (固定=0, M3实现后由M3.chk_error_o驱动)
    wire [5:0] res_pkt_len_i;     // M3解析包长 (固定=0, M3实现后由M3.res_pkt_len_o驱动)
    wire [7:0] res_pkt_type_i;    // M3解析包类型 (固定=0, M3实现后由M3.res_pkt_type_o驱动)
    wire [7:0] res_payload_sum_i;  // M3 payload累加和 (固定=0, M3实现后由M3.res_payload_sum_o驱动)
    wire [7:0] res_payload_xor_i;  // M3 payload异或和 (固定=0, M3实现后由M3.res_payload_xor_o驱动)

    // M3信号固定值赋值 (Stage1测试阶段: 假设M3始终空闲,格式校验通过)
    assign busy_i           = 1'b0;  // M3未实现前,认为始终空闲
    assign done_i            = 1'b0;  // M3未实现前,认为从未完成
    assign format_ok_i        = 1'b1;  // M3未实现前,假设格式始终正确
    assign length_error_i     = 1'b0;  // M3未实现前,无长度错误
    assign type_error_i       = 1'b0;  // M3未实现前,无类型错误
    assign chk_error_i        = 1'b0;  // M3未实现前,无校验错误
    assign res_pkt_len_i      = 6'd0;  // M3未实现前,结果为0
    assign res_pkt_type_i     = 8'd0;  // M3未实现前,结果为0
    assign res_payload_sum_i  = 8'd0;  // M3未实现前,结果为0
    assign res_payload_xor_i  = 8'd0;  // M3未实现前,结果为0

    // M3->M2接口信号 (M3模块实现后连接)
    wire m3_mem_rd_en;
    wire [2:0] m3_mem_rd_addr;
    wire [31:0] m3_mem_rd_data;

    apb_slave_if apb_slave_if_inst (
        .PCLK(PCLK),
        .PRESETn(PRESETn),
        .PSEL(PSEL),
        .PENABLE(PENABLE),
        .PWRITE(PWRITE),
        .PADDR(PADDR),
        .PWDATA(PWDATA),
        .PRDATA(PRDATA),
        .PREADY(PREADY),
        .PSLVERR(PSLVERR),
        .enable_o(),
        .start_o(),
        .algo_mode_o(),
        .type_mask_o(),
        .exp_pkt_len_o(),
        .done_irq_en_o(),
        .err_irq_en_o(),
        .pkt_mem_we_o(pkt_mem_we_o),
        .pkt_mem_re_o(pkt_mem_re_o),
        .pkt_mem_addr_o(pkt_mem_addr_o),
        .pkt_mem_wdata_o(pkt_mem_wdata_o),
        .pkt_mem_rdata_i(pkt_mem_rdata_i),
        .busy_i(busy_i),
        .done_i(done_i),
        .format_ok_i(format_ok_i),
        .length_error_i(length_error_i),
        .type_error_i(type_error_i),
        .chk_error_i(chk_error_i),
        .res_pkt_len_i(res_pkt_len_i),
        .res_pkt_type_i(res_pkt_type_i),
        .res_payload_sum_i(res_payload_sum_i),
        .res_payload_xor_i(res_payload_xor_i),
        .irq_o(irq_o)
    );

    packet_sram packet_sram_inst (
        .clk(PCLK),
        .rst_n(PRESETn),
        .apb_wr_en(pkt_mem_we_o),
        .apb_addr(pkt_mem_addr_o),
        .apb_wr_data(pkt_mem_wdata_o),
        .apb_rd_en(pkt_mem_re_o),
        .apb_rd_data(pkt_mem_rdata_i),
        .proc_rd_en(m3_mem_rd_en),       // M3读使能 (M3实现后连接)
        .proc_rd_addr(m3_mem_rd_addr),    // M3读地址 (M3实现后连接)
        .proc_rd_data(m3_mem_rd_data)     // M3读数据 (M3实现后连接)
    );

    /* ===== M3模块实例化 (待实现) =====
    // packet_proc_core M3模块实例
    // M3负责: 三态FSM(IDLE/PROCESS/DONE), 包头解析, 格式检查, sum/xor计算
    packet_proc_core packet_proc_core_inst (
        .clk(PCLK),                      // 时钟
        .rst_n(PRESETn),                 // 复位(低有效)
        .start_i(apb_slave_if_inst.start_o),   // 启动脉冲
        .algo_mode_i(apb_slave_if_inst.algo_mode_o), // 算法模式
        .type_mask_i(apb_slave_if_inst.type_mask_o),  // 类型掩码
        .exp_pkt_len_i(apb_slave_if_inst.exp_pkt_len_o), // 期望包长
        .mem_rd_en_o(m3_mem_rd_en),     // SRAM读使能
        .mem_rd_addr_o(m3_mem_rd_addr),  // SRAM读地址
        .mem_rd_data_i(m3_mem_rd_data),  // SRAM读数据
        .busy_o(busy_i),                // 忙标志 -> M1
        .done_o(done_i),                // 完成标志 -> M1
        .res_pkt_len_o(res_pkt_len_i),  // 解析包长 -> M1
        .res_pkt_type_o(res_pkt_type_i), // 解析包类型 -> M1
        .res_payload_sum_o(res_payload_sum_i), // sum -> M1
        .res_payload_xor_o(res_payload_xor_i), // xor -> M1
        .format_ok_o(format_ok_i),       // 格式通过 -> M1
        .length_error_o(length_error_i), // 长度错误 -> M1
        .type_error_o(type_error_i),     // 类型错误 -> M1
        .chk_error_o(chk_error_i)        // 校验错误 -> M1
    );
    ===== M3模块实例化 (待实现) ===== */

    // M3读接口固定值 (M3未实现前: 读使能=0, 地址=0, 数据=0)
    assign m3_mem_rd_en   = 1'b0;  // M3未实现前不读SRAM
    assign m3_mem_rd_addr = 3'd0;  // M3未实现前地址为0
    assign m3_mem_rd_data = 32'd0; // M3未实现前数据为0

endmodule
