#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT

iverilog -g2012 -DSIMULATION \
    -s spk286_debug_overlay_tb \
    -o "$build_dir/spk286_debug_overlay_tb" \
    "$repo_root/rtl/common/jtframe_ram.v" \
    "$repo_root/rtl/common/spk286_debug_overlay.sv" \
    "$repo_root/sim/spk286_integration/spk286_debug_overlay_tb.sv"

(
    cd "$repo_root/rtl/common"
    vvp "$build_dir/spk286_debug_overlay_tb"
)

verilator --binary --timing -DSIMULATION -Wno-fatal \
    --top-module spk286_debug_overlay_tb \
    --Mdir "$build_dir/verilator-at" \
    "$repo_root/rtl/common/jtframe_ram.v" \
    "$repo_root/rtl/common/spk286_debug_overlay.sv" \
    "$repo_root/sim/spk286_integration/spk286_debug_overlay_tb.sv"

(
    cd "$repo_root/rtl/common"
    "$build_dir/verilator-at/Vspk286_debug_overlay_tb"
)
