#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT
verilator --binary --timing --trace -DGEN_TRACE -j 4 --Mdir "$build_dir/obj" \
  --top-module tb_eulsukdo_scheduler src/RTL/*.sv src/TB_UVM/tb_eulsukdo_scheduler.sv \
  > "$build_dir/build.log" 2>&1 || { cat "$build_dir/build.log"; exit 1; }
(cd "$build_dir" && ./obj/Vtb_eulsukdo_scheduler)
cp "$build_dir/gen_sample.vcd" sim_visualizer/public/gen_sample.vcd
