// ============================================================================
// PPA-Lite Testbench - Stage 1: APB Single Write Operation
// ============================================================================
// 本测试验证APB基本写操作的时序
// APB协议两段式传输: SETUP -> ACCESS (2周期版本，无锁存)
// 使用struct管理APB信号
// ============================================================================

`timescale 1ns / 1ps

// ============================================================================
// 1. 类型定义 (使用struct组织相关信号)
// ============================================================================
module ppa_lite_tb;

    // --------------------------------------------------------------------------
    // APB请求结构体 - 封装APB master需要发送的信号
    // --------------------------------------------------------------------------
    typedef struct {
        logic        sel;       // PSEL - 从设备选择
        logic        enable;    // PENABLE - 使能信号
        logic        write;     // PWRITE - 写使能
        logic [11:0] addr;      // PADDR - 地址
        logic [31:0] data;      // PWDATA - 数据
    } apb_req_t;

    // --------------------------------------------------------------------------
    // APB响应结构体 - 封装DUT返回的信号
    // --------------------------------------------------------------------------
    typedef struct {
        logic [31:0] data;      // PRDATA - 读数据
        logic        ready;      // PREADY - 就绪信号
        logic        error;      // PSLVERR - 错误信号
    } apb_rsp_t;

    // --------------------------------------------------------------------------
    // DUT输入/输出结构体实例化
    // --------------------------------------------------------------------------
    // APB Master信号 (驱动DUT)
    apb_req_t  apb_req;         // APB请求

    // DUT输出信号 (接收DUT响应)
    apb_rsp_t  apb_rsp;         // APB响应

    // 时钟和复位
    logic PCLK;                  // 时钟
    logic PRESETn;               // 复位(低有效)

    // 中断信号(本测试不关心)
    logic irq_o;

    // ==========================================================================
    // 2. DUT实例化 - 使用结构体连接信号
    // ==========================================================================
    ppa_top dut (
        .PCLK    (PCLK),
        .PRESETn (PRESETn),
        // APB Master -> DUT (使用结构体成员)
        .PSEL    (apb_req.sel),
        .PENABLE (apb_req.enable),
        .PWRITE  (apb_req.write),
        .PADDR   (apb_req.addr),
        .PWDATA  (apb_req.data),
        // DUT -> APB Master (使用结构体成员)
        .PRDATA  (apb_rsp.data),
        .PREADY  (apb_rsp.ready),
        .PSLVERR (apb_rsp.error),
        .irq_o   (irq_o)
    );

    // ==========================================================================
    // 3. 时钟生成
    // ==========================================================================
    // 周期20ns = 50MHz
    initial begin
        PCLK = 1'b0;
        forever #10 PCLK = ~PCLK;
    end

    // ==========================================================================
    // 4. 复位生成
    // ==========================================================================
    initial begin
        PRESETn = 1'b0;        // 复位有效
        #100;
        PRESETn = 1'b1;        // 撤销复位
    end

    // ==========================================================================
    // 5. APB写操作任务 - APB3协议（2周期：SETUP + ACCESS，无IDLE）
    // ==========================================================================
    // 说明：
    //   - T1 SETUP:  PSEL=1, PENABLE=0, PADDR和PWDATA保持稳定
    //   - T2 ACCESS: PSEL=1, PENABLE=1, 在上升沿采样PADDR/PWDATA执行写操作
    //   - T2结束后自动进入下一笔传输的SETUP阶段
    // ==========================================================================
    task automatic apb_write (
        input logic [11:0] addr,   // 地址
        input logic [31:0] data     // 数据
    );
        // T1 SETUP阶段: PSEL=1, PENABLE=0
        @(posedge PCLK);
        apb_req.sel     = 1'b1;
        apb_req.enable  = 1'b0;
        apb_req.write   = 1'b1;
        apb_req.addr    = addr;
        apb_req.data    = data;

        // T2 ACCESS阶段: PENABLE=1，在上升沿采样并执行写操作
        @(posedge PCLK);
        apb_req.enable  = 1'b1;

        // 2周期完成，立即开始下一笔传输的SETUP或直接进入IDLE
        @(posedge PCLK);
        apb_req.sel     = 1'b0;
        apb_req.enable  = 1'b0;
    endtask : apb_write

    // ==========================================================================
    // 6. APB读操作任务 - APB3协议（2周期：SETUP + ACCESS，无IDLE）
    // ==========================================================================
    // 说明：
    //   - T1 SETUP:  PSEL=1, PENABLE=0, PADDR保持稳定
    //   - T2 ACCESS: PSEL=1, PENABLE=1, PRDATA在上升沿后组合逻辑输出
    //   - 采样时机: T2上升沿后#1延时采样PRDATA
    // ==========================================================================
    task automatic apb_read (
        input  logic [11:0] addr,
        output logic [31:0] data,
        output logic        error
    );
        // T1 SETUP阶段: PSEL=1, PENABLE=0
        @(posedge PCLK);
        apb_req.sel     = 1'b1;
        apb_req.enable  = 1'b0;
        apb_req.write   = 1'b0;
        apb_req.addr    = addr;

        // T2 ACCESS阶段: PENABLE=1，PRDATA组合逻辑输出
        @(posedge PCLK);
        apb_req.enable  = 1'b1;

        // 采样PRDATA (ACCESS上升沿后#1延时)
        #1;
        data  = apb_rsp.data;
        error = apb_rsp.error;

        // 2周期完成，进入IDLE
        @(posedge PCLK);
        apb_req.sel     = 1'b0;
        apb_req.enable  = 1'b0;
    endtask : apb_read

    // ==========================================================================
    // 7. 辅助任务: 打印APB响应
    // ==========================================================================
    task automatic print_response (
        input apb_rsp_t rsp,
        input string    test_name
    );
        $display("[%s] PREADY  = %b (expected: 1)", test_name, rsp.ready);
        $display("[%s] PSLVERR = %b (expected: 0)", test_name, rsp.error);
    endtask : print_response

    // ==========================================================================
    // 8. 辅助任务: 打印读回的数据
    // ==========================================================================
    task automatic print_read_data (
        input logic [31:0] data,
        input logic        error,
        input string       test_name
    );
        $display("[%s] PRDATA  = 0x%h", test_name, data);
        $display("[%s] PSLVERR = %b",   test_name, error);
    endtask : print_read_data

    // ==========================================================================
    // 9. 主测试程序
    // ==========================================================================
    logic [31:0] read_data;
    logic        read_error;

    initial begin
        // 显示测试开始
        $display("========================================");
        $display("  APB Single   Write Test - Stage 1");
        $display("========================================");

        // 初始化APB请求信号
        apb_req.sel     = 1'b0;
        apb_req.enable  = 1'b0;
        apb_req.write   = 1'b0;
        apb_req.addr    = '0;
        apb_req.data    = '0;

        // 等待复位完成
        wait (PRESETn === 1'b1);
        #100;

        // =========================================
        // 测试1: APB写操作 - 写入CTRL寄存器
        // =========================================
        $display("");
        $display("[TEST 1] Writing to CTRL register at 0x000...");
        $display("         Data: 0x0000_0003 (enable=1, start=1)");

        apb_write(12'h000, 32'h0000_0003);
        print_response(apb_rsp, "TEST 1");

        #50;

        // =========================================
        // 测试2: 读回CTRL寄存器
        // =========================================
        $display("");
        $display("[TEST 2] Reading back CTRL register...");

        apb_read(12'h000, read_data, read_error);
        print_read_data(read_data, read_error, "TEST 2");

        // 验证
        if (read_data[0] === 1'b1) begin
            $display("[PASS] CTRL.enable = 1");
        end else begin
            $display("[FAIL] CTRL.enable = %b (expected: 1)", read_data[0]);
        end

        // =========================================
        // 测试3: 写入CFG寄存器
        // =========================================
        $display("");
        $display("[TEST 3] Writing to CFG register at 0x004...");
        $display("         Data: 0x0000_0011 (algo_mode=1, type_mask=0001)");

        apb_write(12'h004, 32'h0000_0011);
        print_response(apb_rsp, "TEST 3");

        #50;

        // =========================================
        // 测试4: 读回CFG寄存器
        // =========================================
        $display("");
        $display("[TEST 4] Reading back CFG register...");

        apb_read(12'h004, read_data, read_error);
        print_read_data(read_data, read_error, "TEST 4");

        // 验证
        if (read_data[0] === 1'b1) begin
            $display("[PASS] CFG.algo_mode = 1");
        end else begin
            $display("[FAIL] CFG.algo_mode = %b (expected: 1)", read_data[0]);
        end

        // =========================================
        // 测试总结
        // =========================================
        $display("");
        $display("========================================");
        $display("  Test Completed!");
        $display("========================================");

        #500;
        $finish;
    end

    // ==========================================================================
    // 10. 波形导出
    // ==========================================================================
    initial begin
        $dumpfile("ppa_lite_tb.vcd");
        $dumpvars(0, ppa_lite_tb);
    end

endmodule : ppa_lite_tb
