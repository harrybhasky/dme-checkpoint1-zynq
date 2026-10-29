#!/bin/sh
# Builds and runs the checkpoint 3 testbench with Icarus Verilog.
# Uses the checkpoint 1 modulator (aircraft TX and ground station reply
# generator) and the checkpoint 2 receive path.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
TX_RTL=${TX_RTL:-$ROOT/checkpoint1/checkpoint1.srcs/sources_1/imports/rtl/dme_pulse_pair_modulator.sv}
RX_RTL=${RX_RTL:-$ROOT/checkpoint2/rtl}
OUT=${OUT:-$HERE/build}

mkdir -p "$OUT"
iverilog -g2012 -Wall -o "$OUT/tb_dme_gs.vvp" -s tb_dme_gs \
    "$TX_RTL" \
    "$RX_RTL/dme_envelope_demodulator.sv" \
    "$RX_RTL/dme_pulse_pair_detector.sv" \
    "$RX_RTL/dme_rx_axi4lite.sv" \
    "$HERE/../rtl/dme_range_model.sv" \
    "$HERE/../rtl/dme_gs_axi4lite.sv" \
    "$HERE/../rtl/tb_dme_gs.sv"
cd "$OUT" && vvp -n tb_dme_gs.vvp
