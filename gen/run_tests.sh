#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

run_test() {
    local test_name="$1"
    local top_name="$2"
    local parameter="${3:-}"
    local output_dir="/tmp/gen_${test_name}_obj"
    local build_log="/tmp/gen_${test_name}_build.log"
    local sources=(src/RTL/*.sv "src/TB_UVM/${top_name}.sv")
    local args=(--binary --timing -j 4 --Mdir "$output_dir" --top-module "$top_name")
    if [[ -n "$parameter" ]]; then args+=("$parameter"); fi
    if ! verilator "${args[@]}" "${sources[@]}" > "$build_log" 2>&1; then
        cat "$build_log"
        return 1
    fi
    "$output_dir/V${top_name}"
}

run_test fifo_rf tb_gen2_fifo_order
run_test fifo_bram tb_gen2_fifo_order -GUSE_BRAM=1
run_test allocator_init tb_gen2_allocator_init
run_test allocator_full tb_gen2_allocator_full
run_test allocator_sparse tb_allocator_sparse
run_test prm_fanout tb_prm_fanout
run_test ready_station tb_ready_station_paths
run_test flow_control tb_flow_control_logic
run_test flow_pressure tb_flow_window_pressure
run_test scheduler tb_eulsukdo_scheduler
run_test scheduler_two_lane tb_scheduler_two_lane
run_test scheduler_stream tb_scheduler_stream

verilator --lint-only --top-module eulsukdo_scheduler src/RTL/*.sv
verilator --lint-only --top-module eulsukdo_scheduler \
    -GSTRUCT_DECODE_NEW_INST=1 -GSTRUCT_FLOW_WINDOWS=2 \
    -GSTRUCT_FLOW_PC_MAX_RANGE=4 src/RTL/*.sv
echo 'gen: 12 simulations and 2 lint configurations passed'
