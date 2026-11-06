#!/bin/sh
# Builds and runs the checkpoint 4 testbench with Icarus Verilog: the
# aircraft DME against the unmodified course ground station IP, with
# behavioural models of the station's Xilinx cores. Then runs the board
# software's tracker (software/dme_track.c) on the replies it recorded.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
RTL=$HERE/../rtl
RX_RTL=${RX_RTL:-$ROOT/checkpoint2/rtl}
GS=$HERE/../ip/groundStation/project_1.srcs/sources_1/new
OUT=${OUT:-$HERE/build}
export OUT

mkdir -p "$OUT"
# -Wall is left off: the course IP's own files warn about port widths.
iverilog -g2012 -o "$OUT/tb_dme_ckpt4.vvp" -s tb_dme_ckpt4 \
    "$HERE/models/xilinx_ip_models.v" \
    "$GS/groundStation.v" "$GS/delayModel.v" "$GS/demodulator.v" \
    "$GS/distanceModel.v" "$GS/mixer.v" "$GS/ppGen.v" "$GS/pp_to_squit.v" \
    "$GS/pulseBRAM.v" "$GS/pulseEfficiency.v" "$GS/pulseMux.v" \
    "$GS/replyGen.v" "$GS/squitterGen.v" "$GS/stationIDGen.v" "$GS/pulseGen.v" \
    "$RX_RTL/dme_envelope_demodulator.sv" \
    "$RX_RTL/dme_pulse_pair_detector.sv" \
    "$RTL/dme_halfsine_rom.sv" \
    "$RTL/dme_interrogator_tx.sv" \
    "$RTL/dme_aircraft_axi4lite.sv" \
    "$RTL/dme_gs_ctrl_axi4lite.sv" \
    "$RTL/tb_dme_ckpt4.sv"
cd "$OUT"
vvp -n tb_dme_ckpt4.vvp | tee sim.log
grep -q "ALL TESTS PASSED" sim.log

# Run the board software's tracker on the replies the testbench dumped.
"$HERE/../software/test/run_tests.sh" replay $(cat squitter_static.args)
"$OUT/test_track" replay $(cat squitter_moving.args)
echo "SIMULATION AND TRACKER REPLAY PASSED"
