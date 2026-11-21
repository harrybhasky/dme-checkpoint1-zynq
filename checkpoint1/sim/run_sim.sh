#!/bin/sh
# Builds and runs the checkpoint 1 testbench with Icarus Verilog 12.
# Simulates the pulse-pair generator IP exactly as packaged in the Vivado
# project (checkpoint1.srcs/sources_1/imports/rtl), with a model of the DDS.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
RTL=$HERE/../rtl
IP_RTL=$HERE/../checkpoint1.srcs/sources_1/imports/rtl
OUT=${OUT:-$HERE/build}

# rtl/ and the packaged IP's copy must be the same.
for f in dme_pulse_pair_modulator.sv dme_axi4lite.sv; do
    cmp -s "$RTL/$f" "$IP_RTL/$f" || { echo "ERROR: rtl/$f differs from the packaged IP copy"; exit 1; }
done

mkdir -p "$OUT"
iverilog -g2012 -o "$OUT/tb_dme_ckpt1.vvp" -s tb_dme_ckpt1 \
    "$IP_RTL/dme_pulse_pair_modulator.sv" \
    "$IP_RTL/dme_axi4lite.sv" \
    "$RTL/tb_dme_ckpt1.sv"
cd "$OUT"
vvp -n tb_dme_ckpt1.vvp | tee sim.log
grep -q "simulation PASSED" sim.log
