#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GEN3_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
RESULT_DIR="$GEN3_DIR/results"
RAW_FILE="$RESULT_DIR/ipc_raw.csv"

mkdir -p "$RESULT_DIR"
printf '%s\n' 'config,decode_width,issue_alu,issue_slow,slow_latency,workload,instructions,cycles,ipc' > "$RAW_FILE"

run_config() {
    config_name=$1
    decode_width=$2
    issue_alu=$3
    issue_slow=$4
    slow_latency=$5
    build_dir="$RESULT_DIR/build_$config_name"
    log_file="$RESULT_DIR/$config_name.log"

    printf 'Building %-22s decode=%s issue=%s+%s slow_latency=%s\n' \
        "$config_name" "$decode_width" "$issue_alu" "$issue_slow" "$slow_latency"

    verilator --binary --timing --build-jobs 0 -Wall -Wno-fatal \
        -Wno-BLKSEQ -Wno-MULTIDRIVEN -Wno-WIDTHEXPAND \
        -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-UNOPTFLAT -Wno-SYNCASYNCNET \
        --top-module tb_eulsukdo_ipc \
        -GP_DECODE_WIDTH="$decode_width" \
        -GP_ISSUE_ALU="$issue_alu" \
        -GP_ISSUE_SLOW="$issue_slow" \
        -GP_SLOW_LATENCY="$slow_latency" \
        -Mdir "$build_dir" \
        -f "$GEN3_DIR/rtl.f" "$GEN3_DIR/src/TB/tb_eulsukdo_ipc.sv" \
        > "$log_file" 2>&1

    "$build_dir/Vtb_eulsukdo_ipc" >> "$log_file" 2>&1
    awk -F, -v cfg="$config_name" -v lat="$slow_latency" '
        /^IPC_RESULT/ {
            printf "%s,%s,%s,%s,%s,%s,%s,%s,%s\n", cfg, $2, $3, $4, lat, $5, $6, $7, $8
        }
    ' "$log_file" >> "$RAW_FILE"
}

cd "$GEN3_DIR"
run_config decode1_dualpath      1 1 1 4
run_config decode1_dualpath_lat2 1 1 1 2
run_config decode1_dualpath_lat8 1 1 1 8
run_config balanced_2wide       2 1 1 4
run_config balanced_4wide       4 2 2 4
run_config alu_heavy_4wide      4 3 1 4
run_config balanced_2wide_lat2  2 1 1 2
run_config balanced_2wide_lat8  2 1 1 8

python3 "$SCRIPT_DIR/summarize_ipc.py" "$RAW_FILE" "$RESULT_DIR/ipc_summary.csv" "$RESULT_DIR/ipc_table.md"
printf 'Wrote %s\n' "$RAW_FILE"
printf 'Wrote %s\n' "$RESULT_DIR/ipc_summary.csv"
printf 'Wrote %s\n' "$RESULT_DIR/ipc_table.md"
