# ============================================================================
# Makefile for PPA-Lite Verilog Simulation (VCS + Verdi)
# ============================================================================

# =====================================
# 【请修改以下路径为实际安装路径】
# =====================================
# 示例:
#   Windows: C:/synopsys/vcs/O-2024.03/bin/vcs.exe
#   Linux:   /opt/synopsys/vcs/O-2024.03/bin/vcs

#VCS_HOME   = /home/synopsys/vcs-mx/O-2018.09-1       # <-- 修改为 VCS 安装路径
#VERDI_HOME = /home/synopsys/verdi/Verdi_O-2018.09-SP2        # <-- 修改为 Verdi 安装路径

VCS   = /home/synopsys/vcs-mx/O-2018.09-1/bin/vcs
VERDI = /home/synopsys/verdi/Verdi_O-2018.09-SP2/bin/verdi

# VCS 编译选项
VCS_FLAGS = -full64 -sverilog -timescale=1ns/1ps
VCS_FLAGS += -debug_access+all -kdb
VCS_FLAGS += +v2k +systemverilogext+.sv
VCS_FLAGS += -Mdir=$(OUT_DIR)/csrc

# 文件路径
RTL_DIR = ..
TB_DIR = .
RTL_FILES = $(RTL_DIR)/apb_slave_if.v $(RTL_DIR)/packet_sram.v $(RTL_DIR)/ppa_top.v
TB_FILE = $(TB_DIR)/ppa_lite_tb_stage1.sv

# 输出文件
OUT_DIR = simv
FSDB_OUT = $(OUT_DIR)/ppa_lite.fsdb

# 目标
.PHONY: all compile run run_fsdb verdi verdi_rtl clean distclean help

all: compile run

# 编译: 使用 VCS
compile:
	@echo "========================================"
	@echo "Compiling with VCS..."
	@mkdir -p $(OUT_DIR)
	$(VCS) $(VCS_FLAGS) -o $(OUT_DIR)/simv $(RTL_FILES) $(TB_FILE)
	@echo "Compilation completed!"
	@echo "========================================"

# 运行仿真
run:
	@echo "Running simulation..."
	@mkdir -p $(OUT_DIR)
	./$(OUT_DIR)/simv -l sim.log
	@echo "Simulation completed!"
	@echo "========================================"

# 运行仿真并生成 FSDB 波形
run_fsdb: compile
	@echo "Running simulation with FSDB..."
	@mkdir -p $(OUT_DIR)
	./$(OUT_DIR)/simv -l sim.log -ucli -do fsdb_do.tcl
	@echo "Simulation completed!"
	@echo "FSDB waveform: $(FSDB_OUT)"
	@echo "========================================"

# 使用 Verdi 打开波形
verdi:
	@if [ -f "$(FSDB_OUT)" ]; then \
		$(VERDI) -fsm $(TB_FILE) -ssf $(FSDB_OUT) & \
		echo "Opening Verdi waveform viewer..."; \
	else \
		echo "Error: FSDB file not found. Please run 'make run_fsdb' first."; \
	fi

# 使用 Verdi 打开 RTL 代码
verdi_rtl:
	$(VERDI) -sv $(TB_FILE) $(RTL_FILES) &

# 清理
clean:
	rm -rf $(OUT_DIR) simv* *.log *.vpd *.fsdb DVEfiles *.key csrc *.conf novas.rc .*.rc

# 完全清理
distclean: clean
	rm -rf work/

# 帮助
help:
	@echo "========================================"
	@echo "  PPA-Lite Simulation Makefile Help"
	@echo "========================================"
	@echo "  make compile      - 编译 RTL 和 Testbench"
	@echo "  make run           - 运行仿真"
	@echo "  make run_fsdb      - 运行仿真并生成 FSDB 波形"
	@echo "  make verdi         - 使用 Verdi 打开波形"
	@echo "  make verdi_rtl     - 使用 Verdi 打开 RTL 代码"
	@echo "  make clean         - 清理仿真文件"
	@echo "  make distclean     - 完全清理"
	@echo "========================================"
