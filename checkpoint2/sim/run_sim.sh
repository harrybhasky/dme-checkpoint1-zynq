#!/bin/sh
# Builds and runs the checkpoint 2 testbench with Icarus Verilog.
# The transmitter is the checkpoint 1 modulator from the Vivado project.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
TX_RTL=${TX_RTL:-$ROOT/checkpoint1/checkpoint1.srcs/sources_1/imports/rtl/dme_pulse_pair_modulator.sv}
OUT=${OUT:-$HERE/build}

mkdir -p "$OUT"
iverilog -g2012 -Wall -o "$OUT/tb_dme_rx.vvp" -s tb_dme_rx \
    "$TX_RTL" \
    "$HERE/../rtl/dme_envelope_demodulator.sv" \
    "$HERE/../rtl/dme_pulse_pair_detector.sv" \
    "$HERE/../rtl/dme_rx_axi4lite.sv" \
    "$HERE/../rtl/tb_dme_rx.sv"
cd "$OUT" && vvp -n tb_dme_rx.vvp
