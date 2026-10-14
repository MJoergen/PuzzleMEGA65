XILINX_DIR = /opt/Xilinx/2025.1/Vivado

# The m65 tool from the mega65-tools repository
# (https://github.com/MEGA65/mega65-tools), used by the "fpga" target.
M65 = m65

# The coretool from the mega65-tools repository, used by the "cor" target. It
# is a Python script, src/tools/coretool in that repository, and is used as
# it is, e.g. "make cor CORETOOL=~/mega65-tools/src/tools/coretool".
CORETOOL = coretool

# Name of the design. Used for the Vivado script.
NAME = puzzle

# The number of threads of each Vivado run (8 is the most that Vivado uses).
# At most half of the cores of the build machine should be used, so when the
# boards are built at the same time, use fewer, e.g.
# "make -j2 mega65-r3 mega65-r6 VIVADO_THREADS=5".
VIVADO_THREADS = 8

# Target boards. Each board has its own FPGA part, top level module, source
# files, and constraint file (<board>.xdc). The make target <board> generates
# the bit-file build/<board>/<board>.bit. Vivado is run in build/<board>, so
# all its files (logs, checkpoint, .Xil, etc.) go there, and the boards can be
# built at the same time, e.g. "make -j2 mega65-r3 mega65-r6".
BOARDS = mega65-r3 mega65-r6 nexys4ddr
BITS   = $(foreach b,$(BOARDS),build/$(b)/$(b).bit)

# The MEGA65 boards, which also get a core file (build/<board>/<board>.cor)
# from the "cor" target. The name of the target in coretool is the board name
# without the dash, i.e. mega65r3 and mega65r6. The name and the version are
# shown by MEGAFLASH (at most 31 characters each). The version is the current
# commit, with "-dirty" if there are uncommitted changes.
MEGA65_BOARDS = mega65-r3 mega65-r6
CORS          = $(foreach b,$(MEGA65_BOARDS),build/$(b)/$(b).cor)
COR_NAME      = Puzzle
COR_VERSION   = $(shell git describe --always --dirty 2>/dev/null)

# Board programmed by the "fpga" target. Must be specified on the command
# line, e.g. "make fpga BOARD=mega65-r6", because the bit-file of one MEGA65
# revision must not be used on the other one.
BOARD =

# The MEGA65 board revisions R3 and R6 have the same FPGA, and the same
# design (src/mega65.vhd). Only the top level modules are different, because
# some of the pins are different. The bit-file of one revision must not be
# used on the other one. The keyboard driver and the HDMI output (both from
# the C64MEGA65 core) are only on the MEGA65. The link to the MAX10 (also
# from the C64MEGA65 core), which reads the reset button, is only on the R3.
MEGA65_SRC  = src/keyboard/kb_matrix_ram.vhd
MEGA65_SRC += src/keyboard/mega65kbd_to_matrix.vhd
MEGA65_SRC += src/keyboard/matrix_to_keynum.vhd
MEGA65_SRC += src/keyboard/m2m_keyb.vhd
MEGA65_SRC += src/hdmi/types_pkg.vhd
MEGA65_SRC += src/hdmi/sync_reg.vhd
MEGA65_SRC += src/hdmi/hdmi_tx_encoder.vhd
MEGA65_SRC += src/hdmi/vga_to_hdmi.vhd
MEGA65_SRC += src/hdmi/serialiser_10to1_selectio.vhd
MEGA65_SRC += src/keys.vhd
MEGA65_SRC += src/mega65.vhd

mega65-r3_PART = xc7a200tfbg484-2
mega65-r3_TOP  = mega65_r3
mega65-r3_SRC  = $(MEGA65_SRC) src/max10/max10.vhd src/mega65_r3.vhd

mega65-r6_PART = xc7a200tfbg484-2
mega65-r6_TOP  = mega65_r6
mega65-r6_SRC  = $(MEGA65_SRC) src/mega65_r6.vhd

# The Nexys 4 DDR has a smaller FPGA (of the speed grade -1), and its own top
# level module, with the same design as src/mega65.vhd, but with fewer
# engines.
nexys4ddr_PART = xc7a100tcsg324-1
nexys4ddr_TOP  = nexys4ddr
nexys4ddr_SRC  = src/buttons.vhd src/nexys4ddr.vhd

# List of source files common to all boards. This is the only list: it is
# also given to the Vivado script (puzzle.tcl), followed by the source files
# of the board.
SRC  = src/util_pkg.vhd
SRC += src/main/puzzle_pkg.vhd
SRC += src/ctrl_pkg.vhd
SRC += src/main/engine.vhd
SRC += src/main/solver.vhd
SRC += src/main/control.vhd
SRC += src/main/stats.vhd
SRC += src/main/snapshot.vhd
SRC += src/main/main.vhd
SRC += src/vga/video_pkg.vhd
SRC += src/vga/palette_pkg.vhd
SRC += src/vga/font_pkg.vhd
SRC += src/vga/pix.vhd
SRC += src/vga/board.vhd
SRC += src/vga/bcd.vhd
SRC += src/vga/status.vhd
SRC += src/vga/text.vhd
SRC += src/vga/vga.vhd
SRC += src/cdc_data.vhd
SRC += src/board_mem.vhd
SRC += src/core.vhd
SRC += src/clk_rst.vhd

# The generated files: the puzzles (from puzzles/*.txt and tools/puzzles.py),
# the colours of the pieces (from tools/render.py), and the data of the
# testbenches (from the model, not committed).
PUZZLE_PKG  = src/main/puzzle_pkg.vhd
PALETTE_PKG = src/vga/palette_pkg.vhd
MODEL_PKG   = build/model/model_pkg.vhd

# Testbenches, i.e. sim/<name>_tb.vhd. The slowest are listed first, so that
# they are started first by "make sim".
TBS = core board engine status bcd cdc_data keys buttons

# Testbench simulated by the "run" and "check" targets. Must be specified on
# the command line, e.g. "make run TB=engine".
TB =

# Generics of the testbench, as a list of <name>=<value>, e.g.
# GENERICS="G_COUNTED=true".
GENERICS =

# Maximum simulation time. This must be longer than the slowest testbench.
# The testbenches stop by themselves. "make sim" counts a testbench that is
# still running at this time as failed.
STOP_TIME = 1000ms

TB_EXE = $(TB)_tb
# The clock module and the board top levels use Xilinx primitives, and are
# not simulated. keys.vhd and buttons.vhd are board files, but have
# testbenches.
TB_SRC = $(filter-out src/clk_rst.vhd,$(SRC)) src/keys.vhd src/buttons.vhd $(MODEL_PKG) sim/$(TB)_tb.vhd
WAVE = sim/$(TB).ghw
SAVE = sim/$(TB).gtkw

# Each testbench has its own GHDL work directory, so that several testbenches
# can be analyzed and simulated at the same time (see "make sim").
WORKDIR = build/$(TB)

GHDL = ghdl

GHDL_OPTS = --std=08 -frelaxed-rules --workdir=$(WORKDIR)

# The number of jobs of "make sim": at most half of the cores
SIM_JOBS ?= $(shell echo $$(( ($$(nproc 2>/dev/null || echo 2) + 1) / 2 )))


#####################################
# Help (default target)
#####################################

.PHONY: help
help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  help            Show this help text (default)"
	@echo "  mega65-r3       Synthesize and implement the design for the MEGA65 R3 using Vivado (build/mega65-r3/)"
	@echo "  mega65-r6       Synthesize and implement the design for the MEGA65 R6 using Vivado (build/mega65-r6/)"
	@echo "  nexys4ddr       Synthesize and implement the design for the Nexys 4 DDR using Vivado (build/nexys4ddr/)"
	@echo "  cor             Make the core files of the MEGA65 boards using coretool"
	@echo "  fpga            Program the FPGA of a board (BOARD=<board>) with its bit-file using m65"
	@echo "  sim             Simulate all testbenches in parallel using ghdl (logs in build/)"
	@echo "  run             Simulate a single testbench (TB=<name>) using ghdl, without writing a waveform"
	@echo "  check           Simulate a single testbench (TB=<name>) using ghdl, write the waveform, and show it in gtkwave"
	@echo "  formal          Run the formal verification using SymbiYosys (in formal/)"
	@echo "  model           Check the model against the counts of the C++ program (about 3 minutes)"
	@echo "  pictures        Simulate the whole design and save pictures of the screen (doc/*.png)"
	@echo "  puzzles         Generate $(PUZZLE_PKG) from puzzles/*.txt"
	@echo "  palette         Generate $(PALETTE_PKG) from tools/render.py"
	@echo "  tbdata          Generate the data of the testbenches from the model (build/model/)"
	@echo "  clean           Remove generated files"
	@echo ""
	@echo "Testbench is selected by TB=<name>, e.g. 'make run TB=engine'."
	@echo "Available testbenches: $(TBS)"
	@echo ""
	@echo "Board is selected by BOARD=<board>, e.g. 'make fpga BOARD=mega65-r6'."
	@echo "Available boards: $(BOARDS)"


#####################################
# Generate bit-file and program FPGA
#####################################

.SECONDEXPANSION:

.PHONY: $(BOARDS)
$(BOARDS): %: build/$$*/$$*.bit

# The arguments of the Vivado script are the board name, the FPGA part, the
# top level module, the number of threads, and the source files. The stem
# ($*) is <board>/<board>, so the board name is $(notdir $*). The source files
# are given with absolute paths, because Vivado is run in build/<board>.
$(BITS): build/%.bit: $(NAME).tcl $$(notdir $$*).xdc $(SRC) $$($$(notdir $$*)_SRC)
	@mkdir -p $(@D)
	cd $(@D) && bash -c "source $(XILINX_DIR)/settings64.sh ; vivado -mode tcl -nojournal -source $(abspath $<) -tclargs $(notdir $*) $($(notdir $*)_PART) $($(notdir $*)_TOP) $(VIVADO_THREADS) $(abspath $(SRC) $($(notdir $*)_SRC))"

# Make the core files of the MEGA65 boards, which are flashed into a slot with
# MEGAFLASH. Each bit-file is built first, if needed. As with the bit-files,
# the core file of one MEGA65 revision must not be used on the other one.
.PHONY: cor
cor: $(CORS)

$(CORS): build/%.cor: build/%.bit
	$(CORETOOL) --quiet --force --build $@ --bit $< --target $(subst -,,$(notdir $*)) \
	   --bit-name "$(COR_NAME)" --bit-version "$(COR_VERSION)"

# Program the FPGA of the board BOARD with its bit-file, which is built first
# if needed. m65 works for all the boards, i.e. also for the Nexys 4 DDR.
.PHONY: fpga
ifeq ($(BOARD),)

# No board specified, so list the possible ones
fpga:
	@echo "Please specify a board using BOARD=<board>, e.g. 'make fpga BOARD=mega65-r6'."
	@echo "Available boards:"
	@for b in $(BOARDS); do echo "  $$b"; done

else ifeq ($(filter $(BOARD),$(BOARDS)),)

fpga:
	@echo "Unknown board '$(BOARD)'. Available boards: $(BOARDS)"
	@exit 1

else

fpga: build/$(BOARD)/$(BOARD).bit
	$(M65) -q $<

endif


#####################################
# Generated files
#####################################

.PHONY: puzzles palette tbdata
puzzles:
	python3 tools/gen_puzzle_pkg.py > $(PUZZLE_PKG).new
	mv $(PUZZLE_PKG).new $(PUZZLE_PKG)

palette:
	python3 tools/render.py palette > $(PALETTE_PKG).new
	mv $(PALETTE_PKG).new $(PALETTE_PKG)

# The data of the testbenches: the model package and the traces, and the
# pictures of the board for board_tb.
tbdata: $(MODEL_PKG)

$(MODEL_PKG): tools/gen_tb_data.py tools/model.py tools/model.cpp tools/puzzles.py tools/render.py $(wildcard puzzles/*.txt)
	python3 tools/gen_tb_data.py
	python3 tools/render.py ref 1 0 build/model/board_1
	python3 tools/render.py ref 9 7 build/model/board_9
	python3 tools/render.py ref 8 4 build/model/board_8

.PHONY: model
model:
	python3 tools/model.py check


#####################################
# Simulation
#####################################

# Simulate all testbenches (without opening the waveform viewer). The
# testbenches are run in parallel, each by its own target sim-<name>, using
# SIM_JOBS jobs. If make itself is run with -j, that is used instead. The
# output of each testbench goes to build/<name>.log, and a summary is shown at
# the end. The exit status is non-zero if any testbench fails.
SIM_TARGETS = $(addprefix sim-,$(TBS))

.PHONY: sim
sim: $(MODEL_PKG)
	@rm -f $(addprefix build/,$(addsuffix .status,$(TBS)))
	@$(MAKE) --no-print-directory -k $(if $(findstring jobserver,$(MAKEFLAGS)),,-j$(SIM_JOBS)) $(SIM_TARGETS) || true
	@echo ""
	@echo "=== Summary ==="
	@fail=0; \
	for tb in $(TBS); do \
	   status=`cat build/$$tb.status 2>/dev/null || echo "FAIL (not run)"`; \
	   printf "  %-15s %s\n" $$tb "$$status"; \
	   case "$$status" in PASS*) ;; *) fail=1 ;; esac; \
	done; \
	if [ $$fail -ne 0 ]; then echo "Some testbenches FAILED"; exit 1; fi; \
	echo "All testbenches passed"

# Simulate a single testbench as part of "make sim", with the output going to
# build/<name>.log. A testbench only passes if it has also reported
# "<name>_tb: finished": a testbench that hangs (e.g. waiting for a done flag
# that never comes) runs until STOP_TIME, and then GHDL exits with status 0.
.PHONY: $(SIM_TARGETS)
$(SIM_TARGETS): sim-%: $(MODEL_PKG)
	@mkdir -p build
	@echo "=== Simulating $* ==="
	@start=`date +%s`; \
	note=""; \
	if ! $(MAKE) --no-print-directory run TB=$* > build/$*.log 2>&1; then \
	   result="FAIL"; \
	elif ! grep -q "$*_tb: finished" build/$*.log; then \
	   result="FAIL"; \
	   note=", not finished by $(STOP_TIME)"; \
	else \
	   result="PASS"; \
	fi; \
	secs=$$((`date +%s` - start)); \
	echo "$$result ($${secs}s$$note)" > build/$*.status; \
	echo "=== $*: $$result ($${secs}s$$note), log in build/$*.log ==="; \
	[ $$result = PASS ]

ifeq ($(TB),)

# No testbench specified, so list the possible ones
.PHONY: run check
run check:
	@echo "Please specify a testbench using TB=<name>, e.g. 'make $@ TB=engine'."
	@echo "Available testbenches:"
	@for tb in $(TBS); do echo "  $$tb"; done

else

# Analyze, elaborate, and simulate the testbench TB. The argument is extra
# options to the simulation, e.g. --wave=<file>.
define SIMULATE
@mkdir -p $(WORKDIR)
$(GHDL) -i $(GHDL_OPTS) --work=work $(TB_SRC)
$(GHDL) -m $(GHDL_OPTS) $(TB_EXE)
$(GHDL) -r $(GHDL_OPTS) $(TB_EXE) --assert-level=error --stop-time=$(STOP_TIME) $(addprefix -g,$(GENERICS)) $(1)
endef

# Simulate a single testbench (TB=<name>) without writing a waveform, because
# that slows down the simulation considerably.
.PHONY: run
run: $(TB_SRC)
	$(call SIMULATE)

# Simulate a single testbench (TB=<name>), write the waveform to sim/<name>.ghw
# and show it. Not all testbenches have a GTKWave save file (sim/<name>.gtkw).
.PHONY: check
check: $(TB_SRC)
	$(call SIMULATE,--wave=$(WAVE))
	gtkwave $(WAVE) $(wildcard $(SAVE))

endif

# Simulate the whole design (core_tb with G_PICTURES) and save the pictures
# of the screen for the README (doc/*.png), see sim/core_tb.vhd.
.PHONY: pictures
pictures: $(MODEL_PKG)
	$(MAKE) --no-print-directory run TB=core GENERICS="G_PICTURES=true" STOP_TIME=10000ms
	for f in build/core/*.ppm; do convert $$f doc/`basename $$f .ppm`.png; done


#####################################
# Formal verification
#####################################

.PHONY: formal
formal:
	$(MAKE) -C formal


.PHONY: clean
clean:
	rm -rf build
	rm -rf work-obj08.cf
	rm -rf */*.ghw
	$(MAKE) -C formal clean
