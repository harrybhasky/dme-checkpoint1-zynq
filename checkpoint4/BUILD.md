# Building and running the final project on the ZedBoard

Step-by-step instructions to go from this repository to the aircraft DME
running against the course ground station on a ZedBoard. Written to be
followed by a person or by a coding agent. Every step is a script; the
manual (GUI) way is given as a fallback.

## 0. What you need

- Vivado and Vitis (classic, with `xsct`) **2020.1 or newer**, same version
  for both. Any version works: the scripts re-create the course IP's Xilinx
  cores instead of using its 2022.2 `.xci` files.
- ZedBoard board files (Vivado usually has them; if not, the script falls
  back to the bare part `xc7z020clg484-1` with the PS7 `ZedBoard` preset).
- ZedBoard, both micro-USB cables (PROG J17 for JTAG, UART J14 for the
  console), boot jumpers JP7 to JP11 all on GND (JTAG boot).
- A serial terminal (PuTTY, Tera Term, the Vitis serial terminal) at
  **115200 8N1**.

Run every command from the **repository root** (the folder that contains
`checkpoint2/` and `checkpoint4/`). On Windows, use the "Vivado 2020.1 Tcl
Shell" / "Vitis 2020.1 Command Prompt" (or add `<Xilinx>/Vivado/<ver>/bin`
and `<Xilinx>/Vitis/<ver>/bin` to `PATH`). Use a path **without spaces**.

```text
git clone -b checkpoint4 https://github.com/harrybhasky/dme-checkpoint1-zynq.git
cd dme-checkpoint1-zynq
```

## 1. Hardware: bitstream and .xsa (about 10 to 20 minutes)

```sh
vivado -mode batch -source checkpoint4/vivado/build_project.tcl
```

Optional: `-tclargs 8` for 8 parallel jobs; `-tclargs 4 1` only creates the
project (open `checkpoint4/vivado/dme_final/dme_final.xpr` in the GUI).

What it does:

1. Creates `checkpoint4/vivado/dme_final` for the ZedBoard.
2. Adds the RTL: `checkpoint2/rtl` (receiver), `checkpoint4/rtl` (aircraft,
   ground station control, `dme_system.sv`) and the **unmodified** course
   ground station sources from `checkpoint4/ip/groundStation`.
3. Re-creates the ground station's four Xilinx cores with the original
   settings: `dds_compiler_0` (10 MHz carrier), `div_gen_0`, `div_gen_1`,
   `fifo_generator_0` (131072 x 1 delay line).
4. Block design `design_1`: Zynq PS (board preset, 100 MHz FCLK_CLK0),
   AXI interconnect, two AXI4-Lite master ports to the PL.
5. Generates `system_top.v` (block design + `dme_system`), synthesises,
   implements and writes the bitstream.

**Success** is the end of the log:

```text
========== Done ==========
Bitstream: .../checkpoint4/vivado/output/dme_final.bit
Platform:  .../checkpoint4/vivado/output/dme_final.xsa
Worst setup slack: <n> ns (timing met)
```

Check these lines in the log too:

- `CHECK: <ip> settings match the course IP` for all four cores. A
  `CHECK: ... is 'x', expected 'y'` line means that setting did not apply in
  this Vivado version: open the core (Sources > IP Sources, double-click) and
  set it by hand, then re-run synthesis. Latency mismatches matter less,
  but report them.
- `Address: M_AXI_AC at 0x43C00000` and `M_AXI_GSC at 0x43C10000`. If the
  addresses ever differ, change `DME_AC_BASE_ADDRESS` and
  `DME_GSC_BASE_ADDRESS` at the top of `checkpoint4/software/main.c`.

If timing is not met (negative slack), the design will probably still work
at 100 MHz on the bench, but report the worst path from
`checkpoint4/vivado/output/timing.txt`.

### Manual fallback (GUI)

If the script fails at the block design step, everything before it is in the
project already. Open `dme_final.xpr` and in IP Integrator create
`design_1`. Add the ZYNQ7 Processing System, run block automation (board
preset), enable M_AXI_GP0, FCLK_CLK0 = 100 MHz. Add an AXI Interconnect
(1 slave, 2 masters) and a Processor System Reset. Make the two interconnect
master ports external as `M_AXI_AC` and `M_AXI_GSC` (protocol AXI4LITE), and
make `FCLK_CLK0` and `peripheral_aresetn` external with those names. Set the
addresses to 0x43C00000 and 0x43C10000 (64K each). Then re-run the script
from the "Top level" section, or create `system_top.v` by hand: it
instantiates `design_1_wrapper` and `dme_system` and connects
`M_AXI_AC_<signal>` to `.ac_<signal>`, `M_AXI_GSC_<signal>` to
`.gsc_<signal>`, `FCLK_CLK0` to `.clk` and `peripheral_aresetn` to `.rstn`.
DDR and FIXED_IO are top-level ports.

## 2. Software: the .elf (about 2 minutes)

```sh
xsct checkpoint4/vitis/build_app.tcl
```

It creates `checkpoint4/vitis/workspace` (platform + application `dme_app`)
from `dme_final.xsa` and the seven files in `checkpoint4/software` (not the
`test/` folder: that is a PC test with its own `main`). **Success**:
`Application: .../dme_app/Debug/dme_app.elf`.

### Manual fallback (Vitis GUI)

New Platform Project from `checkpoint4/vivado/output/dme_final.xsa`,
standalone, ps7_cortexa9_0. New Application Project `dme_app` on it, Empty
Application (C). Import `main.c`, `dme_track.c/.h`,
`dme_aircraft_driver.c/.h` and `dme_gs_ctrl_driver.c/.h` from
`checkpoint4/software` into `src`. Build.

## 3. Run on the board

1. Power the ZedBoard, connect both USB cables, open the serial terminal on
   the UART's COM port at 115200 8N1.
2. Program and run:

   ```sh
   xsct checkpoint4/vitis/run_on_board.tcl
   ```

   (or in Vitis: right-click `dme_app` > Run As > Launch Hardware).

Expected terminal output:

```text
DME final project: aircraft vs course ground station
calibration at 10000 m: zero-range delay 5168 cycles (51.68 us), 30 replies
commands: d <m> | k <km> | n <NM>  distance;  v <m/s>  speed (47-255);
          ...
t=1s  distance 100000.4 m = 53.996 NM  station 100000 m  error 0.4 m  replies 30/30  other pairs 0  speed 0.0 m/s  (fit)
t=2s  ...
```

The zero-range delay should be about 5168 cycles (simulation value). A very
different value, `searching` lines, or `replies 0/30` mean something is
wrong. See section 5.

## 4. Demo for the evaluation

Type a command and press Enter. The digits `1` to `6` set up each project
requirement's test case:

| Type | Requirement | What to look for |
|---|---|---|
| `1` | 1. Static | distance 100000 m, error a few m, `replies 30/30` |
| `2` | 2. Moving, 200 m/s towards | distance drops 1 km every 5 s; after 2 steps `speed 200.0 m/s towards (n steps)`. Type `a` for away |
| `3` | 3. Moving, 60% efficiency | about `replies 17/30`, same distance and speed |
| `4` | 4. Static, squitter 2500 pps | `other pairs` about 170, distance still exact |
| `5` | 5. Moving, squitter | as 2, with squitter |
| `6` | 6. Moving, 60%, squitter | as 3, with squitter |

Other commands: `d 50000` / `k 50` / `n 27` (distance in m / km / NM),
`v 150` (speed; the station moves 1 km every floor(1000/v) s, so 150 gives
166.7 m/s, which is what the DME reports), `a` / `t` (away / towards),
`m 0|1` (motion), `e 60` (efficiency), `q 0|1` (squitter), `r 2500`
(squitter rate), `j 1` (station reply jitter: recalibrates; the distance
then varies by about +/-30 m), `c` (recalibrate), `s` (counters, including
the station's pulse width and delay errors, which must stay 0).

Speeds below 47 m/s do not work in the course IP: its `distanceModel.v`
overflows a 32-bit integer.

## 5. If something does not work

| Symptom | Check |
|---|---|
| Nothing on the terminal | Right COM port (the UART cable, J14), 115200 8N1, open before running. |
| `calibration: no reply peak` / `searching` | `s`: are interrogations counted? Are the station's pulse width / delay errors 0? If `pulses` is 0, the RX path is not seeing the station: check `system_top.v` connects `dme_system`, and that the four cores' settings match (build log `CHECK` lines). |
| Station pulse width/delay errors > 0 | The station is rejecting our interrogations. Check `dds_compiler_0` (10 MHz cosine, 12-bit, PINC 0x1999999A). |
| Bus error / hang on the first register access | Address map: compare `main.c` addresses with the Address Editor. |
| Distance off by a constant | `c` to recalibrate. |
| ILA wanted | Signals between the aircraft and the station are marked `mark_debug`: after synthesis, Tools > Set Up Debug, then re-implement. |

## 6. Simulation and PC tests (no Vivado needed)

```sh
./checkpoint4/software/test/run_tests.sh   # tracker vs a model of the station, all 6 requirements (1 s)
./checkpoint4/sim/run_sim.sh               # RTL testbench with the course IP + tracker replay (about 7 min, Icarus Verilog 12)
```
