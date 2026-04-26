PPA-Lite 课程项目要求书
APB Packet Processing Accelerator Lite — 实验设计与验证说明
版本：v1.02 · 日期：2026-04-24 · 适用课程：SystemVerilog & UVM系统验证 26年春季

文档版本管理
版本	日期	变更摘要
v1.01	2026-03-24	初版发布
v1.02	2026-04-24	补充 M1 对 PKT_MEM 的读接口定义；明确 M2 采用 1 写 2 读接口（M1/M3 可并行只读）；M2 端口命名语义化重构（apb_* 前缀表示 M1 侧，proc_* 前缀表示 M3 侧；M1/M3 端口名保持不变）

出处（实验问题来源说明）：
Lab3 集成中发现"APB 可读 PKT_MEM"已有行为定义，但 M1->M2 读接口未在端口规范中显式列出，导致实现歧义。

兼容性说明：本次为文档勘误与定义显式化，不改变既有实验目标、地址映射与已通过结果判定口径。M2 端口命名变更仅影响§2.3 M2 端口表，不影响 M1/M3 端口名及其与顶层 ppa_top 的连接约定。

目录
项目背景与教学目标
顶层框图与模块职责
数据模型与 Packet 格式
APB 接口与地址映射
CSR 寄存器表
PKT_MEM 窗口行为与访问限制
处理流程与状态机
done/irq 时序与异常响应
错误码定义与判定优先级
验收测试场景矩阵
四次实验阶段拆分与里程碑
评分标准与交付清单
附录 A：最小寄存器访问序列示例
附录 B：常见错误示例
附录 C：字段属性速查表

1 项目背景与教学目标

1.1 课程历史与开设背景

本课程由路科验证与西安电子科技大学微电子学院自 2015 年起联合开设，聚焦 SystemVerilog 与 UVM 验证基础，面向具备数字电路和 Verilog 基础的本科生与研究生讲授芯片验证的理论知识和语言技能。

2021 年春，课程引入西电广研院，此后每年春秋两季均在不同校区和学院同步开展，课程体系持续迭代。

2026 年春起，原 SV 语言课程进一步扩展为"SV 设计 + SV/UVM 验证"综合课程设计实践——这也是本实验项目所依托的课程形态。

1.2 时代背景与培养导向

AI 大模型在软件编程领域的快速落地，以及国内外 IC 公司对"AI + IC 设计流程"的持续投入，使得验证工程师的工作方式正在发生结构性变化。在这一背景下，我们的培养目标是：帮助初级工程师在进入验证岗位前打牢 SV/UVM 基础，使其能够适应 AI 生成代码、快速部署验证环境、完成测试收敛的新工作模式。

为此，2026 年起本课程同步引导同学们借助国内外 AI 编程工具辅助完成部分 RTL 设计与验证任务，在真实工具链上积累工程经验，为应对未来行业变化做好准备。

1.3 前置课程要求

参加本课程实验的同学应已具备以下基础：

前置课程	所需能力
数字电路设计	理解组合逻辑、时序逻辑、状态机基本概念
Verilog RTL 硬件设计语言	能读写模块端口、always 块、reg/wire 声明等基础 RTL

1.4 课程技术覆盖范围

类别	内容
核心语言	SystemVerilog（设计 + 验证语法）
核心方法学	UVM（Universal Verification Methodology）
基础工程配套技能	Shell 脚本基础、Makefile 编写、Questasim 仿真器操作（借助 AI 工具快速上手）
AI 辅助实践	使用国内外 AI 编程工具辅助 RTL 与 TB 的编写、调试和迭代

工程配套技能不作为考核重点，但同学们需要能够读懂并运行课程统一提供的 Makefile 脚本，完成 make smoke / make regress / make cov 等验收操作。

1.5 本实验项目定位

本实验围绕统一设计主线 PPA-Lite（APB Packet Processing Accelerator Lite，APB 包处理加速器精简版）展开，分四次实验递进完成：

PPA-Lite 是一个可编程的数据包处理加速器：软件端通过 APB 总线将一帧数据包写入片上缓冲区，配置控制寄存器后触发硬件处理；硬件完成包头解析与格式合法性检查，处理结束后通过状态位和中断通知软件，软件再通过 APB 读回处理结果。该设计不涉及外部高速流接口、DMA 或复杂协议栈，所有交互均通过 APB 完成，适合在课程时间（单次 4–6 小时）内分模块实现和验证。

1.6 分阶段能力目标

阶段	能力目标
实验 1（Lab1）	掌握 APB 3.0 从接口时序，实现 CSR 寄存器组与 SRAM 写入路径
实验 2（Lab2）	掌握 FSM 设计，实现包头解析与格式检查算法核
实验 3（Lab3）	掌握多模块集成方法，完成端到端驱动与结果验证
实验 4（Lab4）	掌握回归测试与覆盖率闭环方法，完成完整验证收尾

每次实验均采用现场演示 + 助教提问方式进行验收，要求学生独立完成 RTL 设计与 Testbench 编写。

2 顶层框图与模块职责

2.1 系统结构

APB Master  |  v
+------------------+      irq_o（顶层对外）
|     ppa_top      |------------------------------>
+------------------+  | 统一分发 PCLK/PRESETn 到 M1/M2/M3  |
                     |               控制下发 / 状态结果回传（M1<-> M3）
                +--> +----------------+ -------------->
                |    | apb_slave_if   |
                |    |      (M1)      |
                |    +--------+-------+             |
                |             | M1<->M2 读写接口    |
                |             v  |      +-------------+
                |      | packet_sram |  |
                |      |    (M2)     |  |
                |      +------+------+   |
                |             ^  |             |
                |             | M3->M2 处理读接口
                |    +--------+-------+  +--> | packet_proc    |
                |    |   core (M3)    |       |   core (M3)    |
                |    +----------------+       +----------------+

时钟/复位分发约定：ppa_top 对外接收 PCLK 与低有效 PRESETn，并统一分发到三子模块：M1 使用 PCLK/PRESETn，M2 使用 clk/rst_n（由 PCLK/PRESETn 映射），M3 使用 clk/rst_n（由 PCLK/PRESETn 映射）。

2.2 模块职责一览

模块	实例名	核心职责
apb_slave_if	M1	APB 3.0 从接口 + 全部 CSR 寄存器组；寄存器的置位/清零逻辑在本模块内实现；向外暴露字段信号，并负责 PKT_MEM APB 读窗口访问控制
packet_sram	M2	8×32-bit 1写2读同步 SRAM；写端口来自 M1（APB 访问），读端口分别供 M3（处理阶段）与 M1（APB 读窗口）使用，不做包语义判断
packet_proc_core	M3	3 态 FSM（IDLE→PROCESS→DONE）；负责读取 SRAM、解析包头、执行格式检查、计算 payload 摘要，输出结果和错误标志
ppa_top	顶层	三模块连线与引脚透传；统一分发时钟/复位到 M1/M2/M3；无额外状态逻辑

2.3 模块端口汇总

M1 apb_slave_if

方向	信号	位宽	说明
输入	PCLK	1	APB 时钟输入
输入	PRESETn	1	APB 复位（低有效）
输入	PSEL	1	从设备选择
输入	PENABLE	1	使能信号
输入	PWRITE	1	写使能
输入	PADDR	12	地址
输入	PWDATA	32	写数据
输出	PRDATA	32	读数据
输出	PREADY	1	固定为 1（无等待态）
输出	PSLVERR	1	访问错误标志
输出	enable_o	1	CTRL.enable 字段
输出	start_o	1	W1P 单拍脉冲（触发处理）
输出	algo_mode_o	1	CFG.algo_mode
输出	type_mask_o	4	CFG.type_mask
输出	exp_pkt_len_o	6	PKT_LEN_EXP.exp_pkt_len
输出	done_irq_en_o	1	IRQ_EN.done_irq_en
输出	err_irq_en_o	1	IRQ_EN.err_irq_en
输出	pkt_mem_we_o	1	SRAM 写使能（送 M2）
输出	pkt_mem_addr_o	3	SRAM 读写共享地址（送 M2）
输出	pkt_mem_wdata_o	32	SRAM 写数据（送 M2）
输出	pkt_mem_re_o	1	SRAM 读使能（送 M2 APB 读口）
输入	pkt_mem_rdata_i	32	SRAM 读数据（来自 M2 APB 读口）
输入	busy_i	1	M3 busy 状态
输入	done_i	1	M3 done 状态
输入	format_ok_i	1	M3 格式合法标志
输入	length_error_i	1	M3 长度错误标志
输入	type_error_i	1	M3 类型错误标志
输入	chk_error_i	1	M3 校验错误标志
输入	res_pkt_len_i	6	M3 解析包长
输入	res_pkt_type_i	8	M3 解析包类型
输入	res_payload_sum_i	8	M3 payload 字节和
输入	res_payload_xor_i	8	M3 payload XOR
输出	irq_o	1	中断输出（= done_irq | err_irq）

M2 packet_sram

方向	信号	位宽	说明
输入	clk	1	时钟（来自 ppa_top.PCLK）
输入	rst_n	1	复位（低有效，来自 ppa_top.PRESETn 映射）
输入	apb_wr_en	1	写使能（来自 M1）
输入	apb_addr	3	写/读地址（0–7，M1 共享地址）
输入	apb_wr_data	32	写数据
输入	proc_rd_en	1	读使能（来自 M3）
输入	proc_rd_addr	3	读地址（0–7，M3 读口）
输出	proc_rd_data	32	读数据（M3 读口）
输入	apb_rd_en	1	读使能（来自 M1 APB 读口）
输出	apb_rd_data	32	读数据（返回 M1 APB 读口）

M3 packet_proc_core

方向	信号	位宽	说明
输入	clk	1	时钟（来自 ppa_top.PCLK）
输入	rst_n	1	复位（低有效，来自 ppa_top.PRESETn 映射）
输入	start_i	1	触发脉冲（来自 M1.start_o）
输入	algo_mode_i	1	算法模式
输入	type_mask_i	4	类型掩码
输入	exp_pkt_len_i	6	期望包长
输出	mem_rd_en_o	1	SRAM 读使能
输出	mem_rd_addr_o	3	SRAM 读地址
输入	mem_rd_data_i	32	SRAM 读数据
输出	busy_o	1	正在处理
输出	done_o	1	处理完成（电平，DONE 态保持）
输出	res_pkt_len_o	6	解析包长
输出	res_pkt_type_o	8	解析包类型
输出	res_payload_sum_o	8	payload 字节和（8-bit 截断）
输出	res_payload_xor_o	8	payload 全字节 XOR
输出	format_ok_o	1	格式合法（长度/类型/校验均通过）
输出	length_error_o	1	长度越界错误
输出	type_error_o	1	类型非法错误
输出	chk_error_o	1	头校验错误

Top ppa_top

方向	信号	位宽	说明
输入	PCLK	1	APB 时钟
输入	PRESETn	1	APB 复位（低有效）
输入	PSEL	1	APB 从设备选择
输入	PENABLE	1	APB 使能信号
输入	PWRITE	1	APB 写使能
输入	PADDR	12	APB 地址
输入	PWDATA	32	APB 写数据
输出	PRDATA	32	APB 读数据
输出	PREADY	1	APB 就绪（固定 1）
输出	PSLVERR	1	APB 错误响应
输出	irq_o	1	中断输出（来自 M1，已覆盖 done/err 事件通知）

3 数据模型与 Packet 格式

3.1 包结构

每帧数据包由固定 4 字节头部和可变长 payload 组成：

字节偏移:  0        1        2        3        4 ... N-1
          ┌────────┬────────┬────────┬────────┬──────────────┐
          │pkt_len │pkt_type│ flags  │hdr_chk │   payload    │
          └────────┴────────┴────────┴────────┴──────────────┘
            总包长   包类型   保留=0   头校验    有效载荷

字段	偏移	位宽	说明
pkt_len	Byte 0	8	总包长（含 4B 头），单位 byte，合法范围 [4, 32]
pkt_type	Byte 1	8	包类型，合法值为 4 种 one-hot：0x01 / 0x02 / 0x04 / 0x08
flags	Byte 2	8	保留字段，当前版本固定为 0x00
hdr_chk	Byte 3	8	头校验：Byte0 XOR Byte1 XOR Byte2
payload	Byte 4–Byte(N-1)	可变	有效载荷，长度 = pkt_len - 4，最大 28 byte

3.2 包长约束

最小包长：4 bytes（纯头部，payload 为空）
最大包长：32 bytes（8 个 32-bit word）
pkt_len < 4 或 pkt_len > 32：判定为 length_error

3.3 写入方式

APB 每次写入 1 个 32-bit word（4 bytes），硬件负责将 word 拆分为字节存入 SRAM。
SRAM 地址窗口为 0x040 ~ 0x05C，共 8 个 word，详见第 6 章。

3.4 算法核输出

M3 处理完成后，以下字段写入状态寄存器（软件通过 APB 读回）：

字段	含义
res_pkt_len	从 Byte0 解析得到的总包长
res_pkt_type	从 Byte1 解析到的包类型
res_payload_sum	payload 各字节累加和（8-bit 截断）
res_payload_xor	payload 各字节逐位 XOR 结果

4 APB 接口与地址映射

4.1 APB 3.0 访问规则

使用标准 APB 两段式传输：SETUP（PSEL=1, PENABLE=0）→ ACCESS（PSEL=1, PENABLE=1）
PREADY 固定为 1，不引入等待状态
写传输在 ACCESS 阶段生效，读传输在 ACCESS 阶段返回 PRDATA
在 ACCESS 阶段上升沿采样地址/数据，PRDATA 在同一拍输出（组合或寄存器输出均可，需与测试向量对齐）

4.2 地址空间划分

地址范围	区域	用途
0x000 ~ 0x02C	CSR 区	控制/状态/中断/结果寄存器
0x02C ~ 0x03F	保留	访问返回 PSLVERR=1
0x040 ~ 0x05C	PKT_MEM 区	Packet 数据读写窗口（8 个 word）
0x05D ~ 0x05F	保留	访问返回 PSLVERR=1
0x060 及以上	未定义	访问返回 PSLVERR=1

5 CSR 寄存器表

5.1 字段属性说明

属性	全称	含义
RW	Read/Write	可读可写；写入后保持新值
RO	Read Only	只读；写入返回 PSLVERR=1，寄存器值不变
W1P	Write-One Pulse	写 1 产生单拍脉冲，不存储该值；读回为 0
RW1C	Read/Write-One-to-Clear	读出当前状态；写对应位为 1 则清零该位，写 0 无效

5.2 完整寄存器表

偏移	寄存器	位域	属性	复位值	说明
0x000	CTRL	[0] enable	RW	0	全局使能
				[1] start	W1P	0	触发处理；仅在 enable=1 && busy=0 时被接受，接受后置 busy=1
0x004	CFG	[0] algo_mode	RW	1	1 = 执行 hdr_chk 校验；0 = 跳过校验并令 chk_error=0
				[7:4] type_mask	RW	4'b1111	bit[n]=1 表示允许 pkt_type=(1<<n)
0x008	STATUS	[0] busy	RO	0	1 = 处理中；start 接受后置 1，DONE 态清 0
				[1] done	RO	0	1 = 本次处理完成；下一次合法 start 接受时清 0
				[2] error	RO	0	= ERR_FLAG 各位的或；下一次合法 start 接受时清 0
				[3] format_ok	RO	0	1 = 长度/类型/头校验均通过；下一次合法 start 接受时清 0
0x00C	IRQ_EN	[0] done_irq_en	RW	0	使能完成中断
				[1] err_irq_en	RW	0	使能错误中断
0x010	IRQ_STA	[0] done_irq	RW1C	0	处理完成且 done_irq_en=1 时置 1；写 1 清零
				[1] err_irq	RW1C	0	存在错误且 err_irq_en=1 时置 1；写 1 清零
0x014	PKT_LEN_EXP	[5:0] exp_pkt_len	RW	0	软件声明的期望总包长；与 pkt_len 不符时可产生 length_error
0x018	RES_PKT_LEN	[5:0] res_pkt_len	RO	0	M3 解析出的包长
0x01C	RES_PKT_TYPE	[7:0] res_pkt_type	RO	0	M3 解析出的包类型
0x020	RES_PAYLOAD_SUM	[7:0] res_payload_sum	RO	0	payload 字节和，8-bit 截断
0x024	RES_PAYLOAD_XOR	[7:0] res_payload_xor	RO	0	payload 全字节 XOR
0x028	ERR_FLAG	[0] length_error	RO	0	pkt_len 越界 [4,32] 或与 PKT_LEN_EXP 不符
				[1] type_error	RO	0	pkt_type 非有效 one-hot 或被 type_mask 屏蔽
				[2] chk_error	RO	0	仅 algo_mode=1 时有效；hdr_chk 与 B0^B1^B2 不符时置 1

未列出的位域读回为 0，写入无效。

6 PKT_MEM 窗口行为与访问限制

6.1 地址映射

PKT_MEM 窗口占 32 bytes，映射到 APB 地址 0x040 ~ 0x05C，共 8 个 32-bit word：

APB 地址	SRAM Word 编号	对应 Packet 字节
0x040	Word 0	Byte 0–3（头部：pkt_len / pkt_type / flags / hdr_chk）
0x044	Word 1	Byte 4–7
0x048	Word 2	Byte 8–11
0x04C	Word 3	Byte 12–15
0x050	Word 4	Byte 16–19
0x054	Word 5	Byte 20–23
0x058	Word 6	Byte 24–27
0x05C	Word 7	Byte 28–31

地址公式：APB 地址 0x040 + 4×N 对应 Word N（N = 0–7）

6.2 写入规则

每次 APB 写入为 32-bit（4 bytes），硬件按字节拆分存入 SRAM
最后一个 word 可部分有效，有效字节数由 pkt_len 决定（M3 处理时按 pkt_len 控制读取范围）
写入顺序建议从 Word 0 开始，先写头部再写 payload

6.3 访问限制

访问类型	时机	结果
APB 写 PKT_MEM	busy=0	正常写入，PSLVERR=0
APB 写 PKT_MEM	busy=1	写入无效，返回 PSLVERR=1（M3 正在读取，禁止修改）
APB 读 PKT_MEM	任意时刻	返回当前 SRAM 内容（不受 busy 保护）

教学提示 1：busy=1 期间写保护由 M1 的 PSLVERR 机制实现，M2 本身不做包语义判断。

教学提示 2（v1.02 勘误）：M2 定义为 1 写 2 读接口，M3 与 M1 的读请求使用独立读口。两侧可并行只读（同地址或不同地址均允许），因此顶层 ppa_top 无需新增读仲裁逻辑。

7 处理流程与状态机

7.1 M3 三态 FSM

M3 packet_proc_core 采用 IDLE → PROCESS → DONE 三态设计：

stateDiagram-v2
  [*] --> IDLE
  IDLE --> PROCESS: start_i = 1
  IDLE --> IDLE: 其他（保持）
  PROCESS --> DONE: 字节计数器达到 pkt_len
  PROCESS --> PROCESS: 其他（继续读取）
  DONE --> PROCESS: start_i = 1
  DONE --> DONE: 其他（保持）

若终端或平台不支持 Mermaid 渲染，请以 7.2 状态转移表为准。

7.2 状态转移表

当前状态	条件	下一状态	动作
IDLE	start_i=1	PROCESS	置 busy_o=1；清除上一帧结果；初始化字计数器；从 addr=0 开始读 M2
IDLE	其他	IDLE	保持 busy_o=0；若曾完成过则保持 done_o=1，否则保持 done_o=0
PROCESS	字节计数器达到 pkt_len	DONE	停止读取；写入结果和错误标志；置 busy_o=0；置 done_o=1
PROCESS	其他	PROCESS	每拍读一个 32-bit Word；累加 sum/XOR；更新计数器
DONE	start_i=1	PROCESS	同 IDLE→PROCESS（接受下一帧）
DONE	其他	DONE	保持 done_o=1；结果保持有效

7.3 PROCESS 内部数据流

拍次	操作
第 0 拍	读 Word0（Byte0–3）；提取 pkt_len / pkt_type / flags / hdr_chk；执行长度范围检查 [4,32]；执行类型合法性检查；执行 hdr_chk 校验（algo_mode=1 时）
第 1–(N-1) 拍	读 payload word；逐字节累加 res_payload_sum；逐字节累加 res_payload_xor
最后拍（第 ceil(pkt_len/4)-1 拍）	完成全部计算；进入 DONE

长度检测归属说明：SRAM（M2）本身不做包语义判断，只负责按地址读写存储。pkt_len 的范围检查和包尾判定均由 M3 在解析 Byte0 后完成。

7.4 各状态输出约定

状态	busy_o	done_o	mem_rd_en_o
IDLE	0	0（初始）或 0（start 清除后）	0
PROCESS	1	0	1（每拍）
DONE	0	1（保持）	0

8 done/irq 时序与异常响应

8.1 done 信号

done_o（M3 内部输出信号）：电平信号，DONE 态保持高电平，IDLE/PROCESS 态为低电平（用于驱动 M1 的 STATUS.done 与中断判定）

STATUS.done（M1 内部）：与 done_i（M3.done_o）直接相连，不额外锁存

8.2 中断生成时序

事件	置位条件	置位时机
IRQ_STA.done_irq 置 1	done_i 上升沿 且 done_irq_en=1	同拍立即置位
IRQ_STA.err_irq 置 1	done_i 上升沿 且 任意错误有效 且 err_irq_en=1	同拍立即置位
irq_o 输出	done_irq | err_irq	组合输出，无额外延迟

中断清除：软件向 IRQ_STA 对应位写 1，下一拍清零；irq_o 随即拉低。

教学提示：中断"同拍置位"比"延迟 1 拍"更容易在仿真波形中观察和验证。

8.3 PSLVERR 统一响应策略

访问类型	PSLVERR	效果
合法读写（CSR/PKT_MEM）	0	正常完成
写只读寄存器（RO/W1P）	1	寄存器值不变
busy=1 期间写 PKT_MEM	1	写入无效
访问未定义地址（保留/越界）	1	无副作用

教学提示：统一错误响应比"部分忽略、部分报错"更容易让学生编写 driver、monitor 和 checker。

9 错误码定义与判定优先级

9.1 错误标志位

所有错误标志位位于 ERR_FLAG 寄存器（0x028），均为 RO：

位字段	触发条件
[0] length_error	pkt_len < 4 或 pkt_len > 32；或 pkt_len ≠ exp_pkt_len（若 PKT_LEN_EXP 已配置）
[1] type_error	pkt_type 不是有效 one-hot（0x01/0x02/0x04/0x08）；或 pkt_type 对应 bit 被 type_mask 屏蔽
[2] chk_error	仅在 algo_mode=1 时有效；hdr_chk ≠ Byte0 XOR Byte1 XOR Byte2

9.2 判定优先级

三类错误可以同时成立，M3 不因一类错误而中止其他检查；全部检查完成后统一写入 ERR_FLAG，然后进入 DONE 态。

处理顺序（同一帧内，并行检查）：

  ┌─ length_error  ──┐
  ├─ type_error    ──┼─► ERR_FLAG 写入 → DONE
  └─ chk_error    ──┘
       ↑（algo_mode=0 时 chk_error 固定=0）

STATUS.error = length_error | type_error | chk_error，是三类错误的汇总。

9.3 清除时机

所有错误标志（ERR_FLAG、STATUS.error、STATUS.format_ok）在下一次合法 start 被接受时同步清零，软件无需手动清除错误标志。

10 验收测试场景矩阵

10.1 正常场景

编号	场景描述	写入内容	期望结果
N-1	最小合法包（纯头部）	pkt_len=4, pkt_type=0x01, flags=0x00, hdr_chk=0x05	done=1, format_ok=1, res_pkt_len=4, res_payload_sum=0
N-2	8 字节合法包（含 4B payload）	pkt_len=8, pkt_type=0x02, hdr_chk=0x0A, payload=0x01020304	done=1, format_ok=1, res_pkt_len=8, res_payload_sum=0x0A, res_payload_xor=0x04
N-3	最大合法包（32 bytes）	pkt_len=32, pkt_type=0x04, 28B payload	done=1, format_ok=1, res_pkt_len=32
N-4	连续两帧处理	第一帧完成（done=1）后写第二帧并 start	两帧结果独立正确，done 在两帧间有清零过程

10.2 异常场景

编号	场景描述	写入内容	期望结果
E-1	包长下溢	pkt_len=3（十进制，低于最小 4）	done=1, length_error=1, format_ok=0，M3 不卡死
E-2	包长上溢	pkt_len=33（十进制，高于最大 32）	done=1, length_error=1, format_ok=0
E-3	非法 pkt_type	pkt_type=0x03（非 one-hot）	done=1, type_error=1
E-4	type_mask 屏蔽	type_mask=4'b1110，pkt_type=0x01	done=1, type_error=1
E-5	hdr_chk 错误	hdr_chk 与 B0^B1^B2 不符，algo_mode=1	done=1, chk_error=1
E-6	algo_mode=0 旁路	同 E-5 的 packet，但 algo_mode=0	done=1, chk_error=0（校验被跳过）

10.3 边界场景

编号	场景描述	关注点
B-1	done 未清除时再次 start	done 应清零后 busy 重新置 1，结果寄存器被新帧覆盖
B-2	busy=1 期间写 PKT_MEM	PSLVERR=1，SRAM 内容不变（Lab3 选做）
B-3	中断完整路径	done_irq 置位 → irq_o=1 → 写 IRQ_STA 清除 → irq_o=0（Lab1 选做）
B-4	PKT_LEN_EXP 与 pkt_len 不符	length_error=1（M1 可选一致性检查）

11 四次实验阶段拆分与里程碑

11.1 实验 1（Lab1）：APB 3.0 从接口及时序

目标：掌握 APB 3.0 从接口时序，实现 CSR 寄存器组与 SRAM 写入路径

里程碑：
M1.1：APB 寄存器读写（单拍握手，PSLVERR 正确响应）
M1.2：CSR 所有寄存器字段功能正确（RW/W1P/RW1C/RO）
M1.3：PKT_MEM 窗口写入（busy=0 时正常写入）
M1.4：中断逻辑（done_irq / err_irq 置位与清除）

交付物：
M1 代码（apb_slave_if.v）
M1 测试平台（apb_slave_if_tb.sv）
Makefile 支持 make smoke

11.2 实验 2（Lab2）：FSM 与算法核

目标：掌握 FSM 设计，实现包头解析与格式检查算法核

里程碑：
M2.1：三态 FSM 正确（IDLE/PROCESS/DONE）
M2.2：包解析正确（pkt_len / pkt_type / hdr_chk）
M2.3：三种错误检测正确（length_error / type_error / chk_error）
M2.4：payload sum/xor 计算正确
M2.5：结果字段输出正确（res_*）

交付物：
M2 + M3 代码（packet_sram.v, packet_proc_core.v）
M2+M3 测试平台（packet_proc_tb.sv）
Makefile 支持 make smoke

11.3 实验 3（Lab3）：模块集成与端到端验证

目标：掌握多模块集成方法，完成端到端驱动与结果验证

里程碑：
M3.1：M1+M2+M3 正确连接（ppa_top）
M3.2：busy=1 期间写 PKT_MEM 返回 PSLVERR=1
M3.3：完整端到端场景通过（正常包 + 错误包）
M3.4：连续两帧处理正确

交付物：
ppa_top 顶层连线
完整系统测试平台（ppa_top_tb.sv）
Makefile 支持 make regress

11.4 实验 4（Lab4）：覆盖率收敛与签核

目标：掌握回归测试与覆盖率闭环方法，完成完整验证收尾

里程碑：
M4.1：所有 CSR 字段toggle覆盖率达到 100%
M4.2：所有错误标志触发覆盖率达到 100%
M4.3：边界场景覆盖率达到 100%
M4.4：回归测试套件通过 make regress
M4.5：覆盖率和 sign-off 文档完成

交付物：
覆盖率数据库和报告
Sign-off 检查清单
最终代码归档

12 评分标准与交付清单

12.1 评分标准

实验	评分项	分值比例
Lab1	APB 时序正确性	20%
	CSR 功能正确性	20%
	PKT_MEM 写入正确性	15%
	TB 覆盖率与自动化	15%
	现场验收表现	30%
Lab2	FSM 状态转移正确性	20%
	包解析算法正确性	20%
	错误检测完整性	15%
	TB 覆盖率与自动化	15%
	现场验收表现	30%
Lab3	模块连接正确性	20%
	端到端场景通过率	25%
	边界场景覆盖	15%
	TB 自动化程度	10%
	现场验收表现	30%
Lab4	覆盖率收敛情况	30%
	回归测试套件完整性	25%
	文档质量	15%
	现场验收表现	30%

12.2 交付清单

实验	交付物
Lab1	apb_slave_if.v, apb_slave_if_tb.sv, README_Lab1.md, Makefile
Lab2	packet_sram.v, packet_proc_core.v, packet_proc_tb.sv, README_Lab2.md, Makefile
Lab3	ppa_top.v, ppa_top_tb.sv, README_Lab3.md, Makefile
Lab4	cov_report.pdf, signoff_checklist.pdf, README_Lab4.md, regression_run.sh

附录 A：最小寄存器访问序列示例

A.1 触发一次包处理的最小序列

写 pkt_len/type/flags/hdr_chk 到 PKT_MEM (Word0)
配置 CFG (algo_mode, type_mask)
配置 PKT_LEN_EXP (可选)
enable=1
start=1
轮询 STATUS.done 或等待 irq
读 RES_* 结果寄存器

A.2 中断处理最小序列

等待 irq
读 IRQ_STA 确定中断源
清除对应中断标志（写 1）
读结果寄存器

附录 B：常见错误示例

B.1 APB 时序错误
PENABLE 提前拉高（在 SETUP 阶段之前）
PREADY 响应延迟不正确
地址/数据采样拍次错误

B.2 状态机错误
状态转移条件不完整
状态保持条件错误
输出信号未正确清零

B.3 错误标志累积
错误标志未在下一次 start 时清零
多个错误未同时检测

B.4 中断响应错误
中断置位延迟一拍
清除中断后未立即拉低 irq_o

附录 C：字段属性速查表

属性	写 1	写 0	读	PSLVERR
RW	写入新值	保持不变	返回值	-
RO	不变	不变	返回值	写返回 1
W1P	产生脉冲	无操作	返回 0	-
RW1C	清零该位	保持不变	返回值	-
