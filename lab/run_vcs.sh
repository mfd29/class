#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
RUN="$ROOT/lab_runs/vcs_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$ROOT/lab_runs"
mkdir "$RUN"
cp "$ROOT/tests/default/input.hex" "$ROOT/tests/default/expected.hex" "$RUN/"
cd "$RUN"
vcs -full64 -sverilog -timescale=1ns/1ps -top tb \
    "$ROOT/rtl/pe_array.v" "$ROOT/rtl/exp_lut.v" \
    "$ROOT/rtl/softmax_unit.v" "$ROOT/rtl/transformer_top.v" \
    "$ROOT/tests/default/tb.sv" -o simv -l compile.log
./simv +wave -l simulation.log
if ! grep -q 'ALL_PASS' simulation.log; then
    echo "ERROR: no ALL_PASS marker; inspect $RUN/simulation.log"
    exit 1
fi
echo "OUTPUT_DIRECTORY=$RUN"
