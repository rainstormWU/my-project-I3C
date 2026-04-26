// ============================================================================
// APB Slave Interface - PPA-Lite 控制寄存器与SRAM访问模块
// ============================================================================
// 功能说明：
//   1. 作为APB从设备接口，接收APB Master的读写操作
//   2. 管理CSR (Control & Status Register) 寄存器
//   3. 提供Packet SRAM的读写访问接口
//   4. 产生中断信号给系统
//
// APB协议说明 (2周期无锁存版本):
//   APB传输分为两个阶段：SETUP -> ACCESS
//   - SETUP: PSEL=1, PENABLE=0, 地址和数据在整个周期保持稳定
//   - ACCESS: PSEL=1, PENABLE=1, 在上升沿采样地址执行读写
//   每次传输持续2个时钟周期
//
// ============================================================================

module apb_slave_if (
    // ========================================================================
    // APB接口信号 (AMBA APB2协议)
    // ========================================================================
    input PCLK,                // 时钟信号，上升沿有效
    input PRESETn,             // 异步复位，低有效
    input PSEL,                // 从设备选择，Master发起传输时置1
    input PENABLE,             // 使能信号，区分SETUP(0)和ACCESS(1)阶段
    input PWRITE,              // 写使能，1=写操作，0=读操作
    input [11:0] PADDR,        // 地址总线，12位地址空间
    input [31:0] PWDATA,       // 写数据总线
    output wire [31:0] PRDATA,  // 读数据总线 (组合逻辑输出)
    output wire PREADY,        // 就绪信号，本设计固定为1 (无等待周期)
    output wire PSLVERR,       // 错误响应，指示传输失败

    // ========================================================================
    // CSR寄存器输出 (控制PPA模块运行)
    // ========================================================================
    output wire enable_o,      // PPA模块使能信号
    output wire start_o,       // PPA启动脉冲 (一个周期)
    output wire algo_mode_o,   // 算法模式: 0=累加和, 1=异或和
    output wire [3:0] type_mask_o,  // 包类型掩码 (bit0=类型1, bit1=类型2...)
    output wire [5:0] exp_pkt_len_o, // 期望包长度
    output wire done_irq_en_o, // 完成中断使能
    output wire err_irq_en_o,  // 错误中断使能

    // ========================================================================
    // SRAM接口 (M1 <-> M2数据交换)
    // ========================================================================
    output reg pkt_mem_we_o,       // SRAM写使能
    output reg pkt_mem_re_o,       // SRAM读使能
    output reg [2:0] pkt_mem_addr_o,  // SRAM地址 (8个word, 深度8)
    output reg [31:0] pkt_mem_wdata_o, // SRAM写数据
    input [31:0] pkt_mem_rdata_i,    // SRAM读数据

    // ========================================================================
    // M3模块状态输入 (只读寄存器源)
    // ========================================================================
    input busy_i,             // PPA模块忙标志
    input done_i,             // PPA处理完成标志
    input format_ok_i,        // 格式校验通过
    input length_error_i,     // 长度错误标志
    input type_error_i,       // 类型错误标志
    input chk_error_i,        // 校验错误标志
    input [5:0] res_pkt_len_i,     // 结果包长度 (RO)
    input [7:0] res_pkt_type_i,    // 结果包类型 (RO)
    input [7:0] res_payload_sum_i, // 累加和结果 (RO)
    input [7:0] res_payload_xor_i, // 异或和结果 (RO)

    // ========================================================================
    // 中断输出
    // ========================================================================
    output wire irq_o          // 组合中断输出
);

    // ========================================================================
    // CSR寄存器定义
    // ========================================================================

    // --- 可读写寄存器 (RW) ---
    reg ctrl_reg;                 // bit[0]: enable, bit[1]: start脉冲
    reg cfg_algo_mode;             // bit[0]: 0=累加和, 1=异或和 (RW, 复位值=0)
    reg [3:0] cfg_type_mask;       // bit[7:4]: 包类型掩码
    reg irq_en_done;              // bit[0]: 完成中断使能
    reg irq_en_err;               // bit[1]: 错误中断使能
    reg [5:0] exp_pkt_len;        // bit[5:0]: 期望包长度
    reg start_pulse;              // start信号脉冲寄存器

    // --- 只读状态寄存器 (RO) - 由M3模块驱动 ---
    reg irq_sta_done;             // bit[0]: 完成中断状态 (RW1C: 写1清零)
    reg irq_sta_err;              // bit[1]: 错误中断状态 (RW1C)
    reg [5:0] res_pkt_len;        // 实际处理包长度
    reg [7:0] res_pkt_type;       // 包类型
    reg [7:0] res_payload_sum;    // 累加和
    reg [7:0] res_payload_xor;    // 异或和

    // --- 只读错误标志寄存器 (ERR_FLAG) - 由M3模块驱动 ---
    reg err_length_error;          // bit[0]: 长度错误 (RO)
    reg err_type_error;           // bit[1]: 类型错误 (RO)
    reg err_chk_error;            // bit[2]: 校验错误 (RO)

    // ========================================================================
    // APB阶段判断 (组合逻辑)
    // ========================================================================
    // APB协议只需要两个阶段：
    // - SETUP: PSEL=1, PENABLE=0 -> 地址和数据保持稳定
    // - ACCESS: PSEL=1, PENABLE=1 -> 在上升沿采样地址执行读写
    // ========================================================================
    wire apb_setup  = PSEL && !PENABLE;   // SETUP阶段
    wire apb_access = PSEL && PENABLE;    // ACCESS阶段

    // ========================================================================
    // 地址解码 (直接使用PADDR，无锁存)
    // ========================================================================
    // CSR区域: PADDR[11:5] = 7'b000_0000  -> 0x000 ~ 0x028
    // SRAM区域: PADDR[11:5] = 7'b000_0100 -> 0x040 ~ 0x05C
    // 非法区域: 其他地址空间
    // ========================================================================
    wire csr_area      = (PADDR[11:5] == 7'd0);       // CSR寄存器区
    wire pkt_mem_area  = (PADDR[11:5] == 7'd4);      // Packet SRAM区
    wire illegal_area  = !(csr_area || pkt_mem_area);         // 非法访问区
    wire pwrite = PWRITE && apb_access;  // 写操作：SETUP期间PWRITE稳定，ACCESS采样
    wire [3:0] csr_addr = PADDR[5:2];                // CSR内部偏移地址 (0~10)
    wire [2:0] mem_addr  = PADDR[4:2];                // SRAM word地址 (0~7)

    // ========================================================================
    // CSR寄存器写操作
    // ========================================================================
    // 规格定义的寄存器映射 (按PADDR[5:2]):
    // 4'd0  (0x00): CTRL        - RW  (bit[0]=enable, bit[1]=start脉冲)
    // 4'd1  (0x04): CFG          - RW  (bit[0]=algo_mode, bit[7:4]=type_mask)
    // 4'd2  (0x08): STATUS       - RO  (bit[0]=busy, bit[1]=done, bit[2]=error, bit[3]=format_ok)
    // 4'd3  (0x0C): IRQ_EN       - RW  (bit[0]=done_irq_en, bit[1]=err_irq_en)
    // 4'd4  (0x10): IRQ_STA      - RW1C (bit[0]=done_irq, bit[1]=err_irq)
    // 4'd5  (0x14): PKT_LEN_EXP  - RW  (bit[5:0]=exp_pkt_len)
    // 4'd6  (0x18): RES_PKT_LEN  - RO  (由M3驱动)
    // 4'd7  (0x1C): RES_PKT_TYPE - RO  (由M3驱动)
    // 4'd8  (0x20): RES_PAYLOAD_SUM - RO (由M3驱动)
    // 4'd9  (0x24): RES_PAYLOAD_XOR - RO (由M3驱动)
    // 4'd10 (0x28): ERR_FLAG     - RO  (bit[0]=length_error, bit[1]=type_error, bit[2]=chk_error)
    // ========================================================================
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            ctrl_reg      <= 1'b0;
            cfg_algo_mode <= 1'b0;    // 规格要求: 复位值为0 (0=累加和模式)
            cfg_type_mask <= 4'b1111;  // 默认全部使能
            irq_en_done   <= 1'b0;
            irq_en_err    <= 1'b0;
            exp_pkt_len   <= 6'd0;
            start_pulse   <= 1'b0;
        end
        else if (apb_access && csr_area && pwrite) begin
            case (csr_addr)
                4'd0: begin
                    // CTRL寄存器 (0x00)
                    // bit[0]: enable - PPA模块使能
                    // bit[1]: start  - 启动脉冲 (写1启动)
                    // 规格要求: 仅在enable=1 && busy=0时被接受
                    ctrl_reg    <= PWDATA[0];
                    start_pulse <= PWDATA[1] && PWDATA[0] && !busy_i;
                end
                4'd1: begin
                    // CFG寄存器 (0x04)
                    // bit[0]: algo_mode - 0=累加和, 1=异或和
                    // bit[7:4]: type_mask - 包类型掩码
                    // 规格要求: algo_mode复位值为0, type_mask复位值为4'b1111
                    cfg_algo_mode <= PWDATA[0];
                    cfg_type_mask <= PWDATA[7:4];
                end
                4'd3: begin
                    // IRQ_EN寄存器 (0x0C)
                    // bit[0]: done_irq_en - 完成中断使能
                    // bit[1]: err_irq_en  - 错误中断使能
                    irq_en_done <= PWDATA[0];
                    irq_en_err  <= PWDATA[1];
                end
                4'd5: begin
                    // PKT_LEN寄存器 (0x14)
                    // bit[5:0]: exp_pkt_len - 期望包长度
                    exp_pkt_len <= PWDATA[5:0];
                end
                // 4'd2, 4'd4, 4'd6~4'd10: RO寄存器，写入由PSLVERR处理
                default: ;
            endcase
        end
        else begin
            // start_pulse只持续一个周期
            start_pulse <= 1'b0;
        end
    end

    // ========================================================================
    // 中断状态寄存器 (RW1C: Write-1-to-Clear)
    // ========================================================================
    // 置位条件：M3模块处理完成且不忙时
    // 清零条件：APB写IRQ_STA寄存器对应bit为1
    // ========================================================================
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            irq_sta_done <= 1'b0;
            irq_sta_err  <= 1'b0;
        end
        else if (done_i && !busy_i) begin
            // M3完成时置位中断状态
            // 规格要求: done_irq置位需done_irq_en=1; err_irq置位需err_irq_en=1
            irq_sta_done <= irq_en_done;
            irq_sta_err  <= (length_error_i || type_error_i || chk_error_i) && irq_en_err;
        end
        else if (apb_access && csr_area && pwrite && csr_addr == 4'd4) begin
            // 写1清零 (RW1C机制)
            if (PWDATA[0]) irq_sta_done <= 1'b0;
            if (PWDATA[1]) irq_sta_err  <= 1'b0;
        end
    end

    // ========================================================================
    // 只读结果寄存器 (由M3模块驱动更新)
    // ========================================================================
    // 这些寄存器反映PPA处理结果，只能由M3模块写入
    // APB Master只能读取，写入会触发PSLVERR错误
    // ========================================================================
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            res_pkt_len      <= 6'd0;
            res_pkt_type     <= 8'd0;
            res_payload_sum  <= 8'd0;
            res_payload_xor  <= 8'd0;
            err_length_error <= 1'b0;
            err_type_error   <= 1'b0;
            err_chk_error    <= 1'b0;
        end
        else if (done_i) begin
            // M3完成时更新结果寄存器和错误标志
            res_pkt_len      <= res_pkt_len_i;
            res_pkt_type     <= res_pkt_type_i;
            res_payload_sum  <= res_payload_sum_i;
            res_payload_xor  <= res_payload_xor_i;
            err_length_error <= length_error_i;
            err_type_error   <= type_error_i;
            err_chk_error    <= chk_error_i;
        end
    end

    // ========================================================================
    // Packet SRAM写操作
    // ========================================================================
    // SRAM通过APB接口写入，包数据从M1模块传输到M2模块
    // 注意：当PPA忙时(busy_i=1)不允许写入，防止数据竞争
    // ========================================================================
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            pkt_mem_we_o    <= 1'b0;
            pkt_mem_addr_o  <= 3'd0;
            pkt_mem_wdata_o <= 32'd0;
        end
        else if (apb_access && pkt_mem_area && pwrite) begin
            if (busy_i) begin
                // PPA忙时不写入，防止数据不一致
                pkt_mem_we_o    <= 1'b0;
                pkt_mem_addr_o  <= 3'd0;
                pkt_mem_wdata_o <= 32'd0;
            end
            else begin
                // 正常写入：使能=1，直接使用PADDR和PWDATA
                pkt_mem_we_o    <= 1'b1;
                pkt_mem_addr_o  <= mem_addr;
                pkt_mem_wdata_o <= PWDATA;
            end
        end
        else begin
            // 非写周期保持低
            pkt_mem_we_o    <= 1'b0;
            pkt_mem_addr_o  <= 3'd0;
            pkt_mem_wdata_o <= 32'd0;
        end
    end

    // ========================================================================
    // Packet SRAM读操作
    // ========================================================================
    // SRAM通过APB接口读取，包数据从M2模块传输到M1 APB读口
    // 读操作不受busy_i限制，因为读不会改变SRAM状态
    // ========================================================================
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)
            pkt_mem_re_o <= 1'b0;
        else if (apb_access && pkt_mem_area && !pwrite)
            pkt_mem_re_o <= 1'b1;
        else
            pkt_mem_re_o <= 1'b0;
    end

    // ========================================================================
    // PRDATA读数据选择 (组合逻辑输出)
    // ========================================================================
    // 在ACCESS阶段组合逻辑直接输出，实现2周期读
    // 优点：减少延迟，周期更紧凑
    // 缺点：可能读到过渡值（testbench需注意采样时机）
    // ========================================================================
    // 组合逻辑计算 error 标志
    wire status_error = err_length_error | err_type_error | err_chk_error;

    wire csr_read = apb_access && csr_area && !pwrite;
    wire mem_read = apb_access && pkt_mem_area && !pwrite;

    // 组合逻辑输出：直接选择读数据
    wire [31:0] csr_rdata;
    assign csr_rdata = (csr_addr == 4'd0) ? {{31{1'b0}}, ctrl_reg}      :  // CTRL (0x00)
                       // CFG (0x04): [7:4]=type_mask, [0]=algo_mode
                       (csr_addr == 4'd1) ? {{20{1'b0}}, cfg_type_mask, 4'b0000, cfg_algo_mode} :
                       // STATUS (0x08): [3]=format_ok, [2]=error, [1]=done, [0]=busy
                       (csr_addr == 4'd2) ? {{28{1'b0}}, format_ok_i, status_error, done_i, busy_i} :
                       (csr_addr == 4'd3) ? {{30{1'b0}}, irq_en_err, irq_en_done} :  // IRQ_EN (0x0C)
                       (csr_addr == 4'd4) ? {{30{1'b0}}, irq_sta_err, irq_sta_done} :  // IRQ_STA (0x10)
                       (csr_addr == 4'd5) ? {{26{1'b0}}, exp_pkt_len} :  // PKT_LEN_EXP (0x14)
                       (csr_addr == 4'd6) ? {{26{1'b0}}, res_pkt_len} :  // RES_PKT_LEN (0x18)
                       (csr_addr == 4'd7) ? {{24{1'b0}}, res_pkt_type} :  // RES_PKT_TYPE (0x1C)
                       (csr_addr == 4'd8) ? {{24{1'b0}}, res_payload_sum} :  // RES_PAYLOAD_SUM (0x20)
                       (csr_addr == 4'd9) ? {{24{1'b0}}, res_payload_xor} :  // RES_PAYLOAD_XOR (0x24)
                       // ERR_FLAG (0x28): [2]=chk_error, [1]=type_error, [0]=length_error
                       (csr_addr == 4'd10) ? {{29{1'b0}}, err_chk_error, err_type_error, err_length_error} :
                       32'd0;  // 非法地址

    assign PRDATA = csr_read ? csr_rdata :
                    mem_read ? pkt_mem_rdata_i :
                    32'd0;

    // ========================================================================
    // PREADY信号 - 固定为1，无等待周期
    // ========================================================================
    assign PREADY = 1'b1;

    // ========================================================================
    // PSLVERR错误响应
    // ========================================================================
    // 产生错误的情况：
    //   1. 访问非法地址区域
    //   2. 写入只读(RO)寄存器 (addr >= 0x18)
    //   3. PPA忙时写入SRAM
    // 注意：即使产生PSLVERR，PREADY仍为1，数据仍会写入/读取
    // ========================================================================
    wire is_write_ro_csr = csr_area && pwrite && (csr_addr >= 4'd6);  // 0x18~0x28是RO寄存器

    assign PSLVERR = apb_access && PREADY && (
        illegal_area      ||  // 非法地址区
        is_write_ro_csr   ||  // 写RO寄存器
        (pkt_mem_area && pwrite && busy_i)  // 忙时写SRAM
    );

    // ========================================================================
    // 输出信号分配
    // ========================================================================
    assign enable_o       = ctrl_reg;
    assign algo_mode_o    = cfg_algo_mode;
    assign type_mask_o    = cfg_type_mask;
    assign exp_pkt_len_o  = exp_pkt_len;
    assign done_irq_en_o  = irq_en_done;
    assign err_irq_en_o   = irq_en_err;
    assign start_o        = start_pulse;

    // 组合逻辑产生中断：任一中断条件满足且使能时触发
    assign irq_o = (irq_sta_done & irq_en_done) | (irq_sta_err & irq_en_err);

endmodule
