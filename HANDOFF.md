# Handoff: finish the project on a machine with Vivado and Vitis

Written for a person or a Claude Code session picking this up. Everything
that does not need Xilinx tools is done and verified. What is left needs
Vivado/Vitis and a ZedBoard.

Start Claude Code in the repository root and say:
"Read HANDOFF.md and do the remaining steps."

## Done and verified (macOS, no Xilinx tools)

Run twice, all passing:

| Check | Command | Result |
|---|---|---|
| CP1 sim (new self-checking testbench) | `sh checkpoint1/sim/run_sim.sh` | PASS, 0 fail |
| CP2 sim | `sh checkpoint2/sim/run_sim.sh` | PASS |
| CP3 sim | `sh checkpoint3/sim/run_sim.sh` | PASS |
| CP4 RTL sim vs course IP + tracker replay (~7 min) | `sh checkpoint4/sim/run_sim.sh` | ALL TESTS PASSED, 105 checks |
| CP4 tracker PC tests | `sh checkpoint4/software/test/run_tests.sh` | ALL TRACKER TESTS PASSED |
| Board C cross-compile (Cortex-A9, real Zynq BSP headers, `-Wall -Wextra`) | clang `--target=armv7a-none-eabi` | 0 warnings, all 4 checkpoints |
| Verilator `-Wall` lint, all RTL tops | | no errors; only width/style warnings |

Changes in this round:

- **Checkpoint 1** restored: `rtl/` now holds the board version of the IP
  (DDS carrier over AXI-Stream, raised cosine), the same files as the
  packaged IP in `checkpoint1.srcs/sources_1/imports`. The essential Vivado
  2020.1 project (`.xpr`, block design, `.xci`, packaged IP, `.xsa`, ILA
  capture) is committed; caches/runs/Vitis output are ignored. New
  self-checking testbench `rtl/tb_dme_ckpt1.sv` + `sim/run_sim.sh`. README
  rewritten with the real register map and the board's Vivado results.
- CP2/CP3 sim scripts point at `checkpoint1/rtl` (they pointed at an
  uncommitted path).
- `REPORT.md`: the required report. Checkpoint 4 Vivado numbers are `TODO`.

## Remaining (needs Vivado/Vitis 2020.1+ and the ZedBoard)

Follow `checkpoint4/BUILD.md`. In short, from the repository root:

1. **Build hardware.**
   `vivado -mode batch -source checkpoint4/vivado/build_project.tcl`
   The script has never been run (it was written without Vivado), so
   expect to fix Tcl errors. Check in the log: four
   `CHECK: <ip> settings match the course IP` lines, the two addresses
   (0x43C00000, 0x43C10000), and `Worst setup slack`.
2. **Fill in `REPORT.md`.** From `checkpoint4/vivado/output/utilization.txt`
   (LUT, FF, DSP, BRAM of the whole design) and `timing.txt` (WNS →
   Fmax = 1000 / (10 − WNS) MHz). Replace every `TODO`. Optionally get
   per-module numbers with `report_utilization -hierarchical`.
3. **Build software.** `xsct checkpoint4/vitis/build_app.tcl` → `dme_app.elf`.
4. **Run on the board.** Serial terminal 115200 8N1, then
   `xsct checkpoint4/vitis/run_on_board.tcl`. Expect calibration about 5168
   cycles, then type `1` to `6` for each requirement (table in BUILD.md §4).
   Record the terminal output for the report/demo.
5. **Optional, CP1 on the board:** open `checkpoint1/checkpoint1.xpr` in
   Vivado 2020.1 (upgrade IP if a newer version), regenerate, check the
   ILA. Already done once (capture in `checkpoint1.hw/backup`).
6. Re-run the simulations above if any RTL changed, commit, push the
   `checkpoint4` branch; the PR checkpoint4 → main updates itself.

## Known limits

- No DAC/ADC loopback (milestone 4): the final project connects the
  aircraft to the course ground station IP directly inside the FPGA.
- CP1: the first period after enable is 1 us short; later periods exact.
- Course IP: speeds below 47 m/s overflow in its `distanceModel.v`;
  distance limit about 389 km.
