VERILATOR ?= verilator
LINT_FLAGS := --lint-only -Wall -Wno-fatal \
	-Wno-BLKSEQ -Wno-MULTIDRIVEN -Wno-WIDTHEXPAND \
	-Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM

.PHONY: lint lint-parameters test test-wave ipc-sweep clean

lint:
	$(VERILATOR) $(LINT_FLAGS) --top-module eulsukdo_gen3 -f rtl.f

lint-parameters:
	$(VERILATOR) $(LINT_FLAGS) -Wno-PINMISSING --top-module eulsukdo_parameter_lint \
		-f rtl.f src/TB/eulsukdo_parameter_lint.sv

test:
	$(VERILATOR) --binary --timing -Wall -Wno-fatal \
		-Wno-BLKSEQ -Wno-MULTIDRIVEN -Wno-WIDTHEXPAND \
		-Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
		--top-module tb_eulsukdo_sequence -f rtl.f src/TB/tb_eulsukdo_sequence.sv
	./obj_dir/Vtb_eulsukdo_sequence

test-wave:
	$(VERILATOR) --binary --timing --trace -DTRACE -Wall -Wno-fatal \
		-Wno-BLKSEQ -Wno-MULTIDRIVEN -Wno-WIDTHEXPAND \
		-Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
		--top-module tb_eulsukdo_sequence -f rtl.f src/TB/tb_eulsukdo_sequence.sv
	./obj_dir/Vtb_eulsukdo_sequence

ipc-sweep:
	./scripts/run_ipc_sweep.sh

clean:
	rm -rf obj_dir obj_ipc_test eulsukdo_sequence.vcd results/build_*
