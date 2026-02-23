# ============================================================
# Boreal Neuro-Core v3.1 — Optimized Build System
# Supports: Linting, Parallel Simulation, Synthesis, Reporting
# ============================================================

# Toolchain
IVERILOG  = iverilog
VVP       = vvp
YOSYS     = yosys
PYTHON    = python3

# Build output directory
BUILD     = build

# ── Source Files ─────────────────────────────────────────────
SRCS = src/boreal_top.v \
       src/boreal_apex_core.v \
       src/boreal_spi_chain.v \
       src/boreal_spi_fifo.v \
       src/boreal_learning.v \
       src/boreal_memory.v \
       src/boreal_pwm_gen.v \
       src/boreal_vns_control.v \
       src/boreal_cordic_ik.v \
       src/boreal_ad_guard.v \
       src/boreal_watchdog.v \
       src/boreal_status_regs.v

# ── Testbenches ──────────────────────────────────────────────
TB_CORE_SRC = tb/tb_boreal_apex_core.v
TB_VNS_SRC  = tb/tb_boreal_vns.v

# ── LUT Generation ───────────────────────────────────────────
LUT_SCRIPT  = scripts/lut_gen.py
LUT_FILE    = sigmoid_lut.mem

# ── Build Outputs ────────────────────────────────────────────
LINT_OUT    = $(BUILD)/boreal_lint.vvp
TB_CORE_OUT = $(BUILD)/tb_core.vvp
TB_VNS_OUT  = $(BUILD)/tb_vns.vvp
SYNTH_OUT   = $(BUILD)/boreal_synth.v
SYNTH_LOG   = $(BUILD)/yosys_synth.log

# ── Phony Targets ────────────────────────────────────────────
.PHONY: all lint sim sim_core sim_vns synth lut report clean help

# Default: lint, then synthesize, then simulate
all: lint synth sim
	@echo ""
	@echo "=========================================="
	@echo " BUILD COMPLETE — All checks passed."
	@echo "=========================================="

# ── Help ─────────────────────────────────────────────────────
help:
	@echo "Boreal Neuro-Core v3.1 Build System"
	@echo ""
	@echo "  make all        Full pipeline: lint → synth → sim"
	@echo "  make lint       Structural lint (iverilog -Wall)"
	@echo "  make sim        Run all testbenches (parallel with -j2)"
	@echo "  make sim_core   Run Apex Core testbench only"
	@echo "  make sim_vns    Run VNS Control testbench only"
	@echo "  make synth      Yosys synthesis (Xilinx target)"
	@echo "  make report     Print synthesis resource utilization"
	@echo "  make lut        Generate sigmoid LUT"
	@echo "  make clean      Remove all build artifacts"

# ── Build Directory ──────────────────────────────────────────
$(BUILD):
	@mkdir -p $(BUILD)

# ── LUT Generation (incremental) ────────────────────────────
lut: $(LUT_FILE)

$(LUT_FILE): $(LUT_SCRIPT)
	@echo "[LUT] Generating sigmoid and acos look-up tables..."
	@$(PYTHON) $(LUT_SCRIPT)
	@$(PYTHON) scripts/acos_lut_gen.py
	@echo "[LUT] Done."

# ── Lint ─────────────────────────────────────────────────────
lint: $(LINT_OUT)

$(LINT_OUT): $(SRCS) $(LUT_FILE) | $(BUILD)
	@echo "[LINT] Checking Verilog sources..."
	@$(IVERILOG) -Wall -o $(LINT_OUT) $(SRCS)
	@echo "[LINT] Passed. No errors."

# ── Simulation (parallel-safe) ───────────────────────────────
sim: sim_core sim_vns
	@echo ""
	@echo "[SIM] All simulations passed. VCD waveforms in $(BUILD)/."

sim_core: $(TB_CORE_OUT)
	@$(VVP) $(TB_CORE_OUT)

$(TB_CORE_OUT): $(SRCS) $(TB_CORE_SRC) $(LUT_FILE) | $(BUILD)
	@echo "[SIM] Compiling Apex Core testbench..."
	@cp sigmoid_lut.mem $(BUILD)/
	@cp acos_lut.mem $(BUILD)/
	@$(IVERILOG) -o $(TB_CORE_OUT) $(SRCS) $(TB_CORE_SRC)

sim_vns: $(TB_VNS_OUT)
	@$(VVP) $(TB_VNS_OUT)

$(TB_VNS_OUT): $(SRCS) $(TB_VNS_SRC) $(LUT_FILE) | $(BUILD)
	@echo "[SIM] Compiling VNS Control testbench..."
	@$(IVERILOG) -o $(TB_VNS_OUT) $(SRCS) $(TB_VNS_SRC)

# ── Synthesis ────────────────────────────────────────────────
synth: $(SYNTH_OUT)

$(SYNTH_OUT): $(SRCS) $(LUT_FILE) | $(BUILD)
	@echo "[SYNTH] Running Yosys → Xilinx Artix-7..."
	@$(YOSYS) -p "\
		read_verilog $(SRCS); \
		synth_xilinx -top boreal_top; \
		write_verilog $(SYNTH_OUT)" > $(SYNTH_LOG) 2>&1
	@echo "[SYNTH] Done. Log → $(SYNTH_LOG)"
	@$(MAKE) --no-print-directory report

# ── Resource Utilization Report ──────────────────────────────
report:
	@echo ""
	@echo "╔══════════════════════════════════════════╗"
	@echo "║   SYNTHESIS RESOURCE UTILIZATION REPORT  ║"
	@echo "╠══════════════════════════════════════════╣"
	@if [ -f $(SYNTH_LOG) ]; then \
		echo "║"; \
		echo "║ Cell Breakdown (post-map):"; \
		grep -E "^\s+[0-9]+" $(SYNTH_LOG) | grep -E "(DSP48|LUT[0-9]|FDCE|FDRE|CARRY4|MUXF|BUFG|IBUF|OBUF|RAM)" | tail -20 | sed 's/^/║   /'; \
		echo "║"; \
		echo "║ Warnings:"; \
		WARNS=$$(grep -ci "warning" $(SYNTH_LOG) 2>/dev/null || echo 0); \
		echo "║   Total: $$WARNS"; \
	else \
		echo "║   No synthesis log found. Run 'make synth' first."; \
	fi
	@echo "╚══════════════════════════════════════════╝"
	@echo ""

# ── Clean ────────────────────────────────────────────────────
clean:
	@echo "[CLEAN] Removing build artifacts..."
	@rm -rf $(BUILD)
	@rm -f $(LUT_FILE) *.vcd
	@echo "[CLEAN] Done."
