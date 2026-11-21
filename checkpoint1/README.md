# Checkpoint 1: DME Pulse-Pair Generator, Driver, and Modulator

Pulse-pair generator IP for the Zynq (ZedBoard, `xc7z020clg484-1`, Vivado
2020.1), packaged as the custom IP `xilinx.com:user:dme_axi4lite:1.0` and
run on the board with an ILA.

- FPGA clock: 100 MHz (`FCLK_CLK0`)
- Pulse width: 50 us
- Delay between the two pulses: 350 us (400 us rising edge to rising edge)
- Pair rate: set from software; default 33333 us period = 30 pairs/s
- Pulse shape: raised cosine (1024-entry LUT, peak 32767), so the spectrum
  stays narrow
- Carrier: 1 MHz sine from the Xilinx **DDS Compiler** (28-bit phase,
  PINC 2684354, 15-bit sine output), into the IP over AXI-Stream
- Output: 16-bit signed `modulated_out` = envelope x carrier / 2^15, and the
  16-bit envelope `pulse_envelope_out`. With the carrier disabled the output
  is the bare envelope.
- Processor interface: AXI4-Lite from the Zynq PS (M_AXI_GP0), base
  address 0x43C00000

## Register map

| Offset | Name | Access | Description |
|---:|---|---|---|
| 0x00 | CONTROL | RW | bit 0 enable generator, bit 1 enable carrier (reset: 0b10) |
| 0x04 | PERIOD_US | RW | start-to-start period of the pulse pairs in us (reset 33333). Writes below 450 are ignored |
| 0x08 | STATUS | RO | [15:0] current envelope amplitude (0 between pulses) |
| 0x0C | ELAPSED_US | RO | microseconds into the current pair period |

Any other address returns SLVERR. The minimum period is 450 us = 50 + 350
+ 50 us.

## Files

```text
rtl/dme_pulse_pair_modulator.sv   timing state machine, raised-cosine LUT, carrier multiplier
rtl/dme_axi4lite.sv               AXI4-Lite registers around the core (the packaged IP top)
rtl/tb_dme_ckpt1.sv               self-checking testbench (with a DDS model)
sim/run_sim.sh                    Icarus Verilog runner
software/dme_driver.c/.h          bare-metal driver
software/main.c                   example: 30 pairs/s, carrier on
checkpoint1.xpr                   Vivado 2020.1 project
checkpoint1.srcs/sources_1/bd/    block design design_1
checkpoint1.srcs/sources_1/imports/   the packaged IP (component.xml, xgui, rtl)
checkpoint1.xsa, final_xsa.xsa     hardware platform with the bitstream (Vitis used final_xsa.xsa)
checkpoint1.hw/backup/            ILA capture from the board (hw_ila_data_1.ila)
```

`rtl/` and `checkpoint1.srcs/sources_1/imports/rtl/` hold the same two
RTL files. The second copy is what the packaged IP and the bitstream were
built from; `sim/run_sim.sh` simulates that copy.

## Block design (`design_1`)

```text
ZYNQ7 PS ── M_AXI_GP0 ── AXI interconnect ── dme_axi4lite_0 (s_axi, 0x43C00000)
dds_compiler_0 (1 MHz sine) ── M_AXIS_DATA ──► dme_axi4lite_0 (s_axis_carrier)
dme_axi4lite_0: modulated_out ──► ila_0 probe0,  pulse_envelope_out ──► ila_0 probe1
FCLK_CLK0 100 MHz to everything, proc_sys_reset
```

Open `checkpoint1.xpr` in Vivado 2020.1. The generated output products
(`.cache`, `.runs`, `.gen`, IP netlists) are not in the repository: Vivado
regenerates them (Generate Block Design, then Generate Bitstream). The
`.xsa` is ready for Vitis as it is.

## Software

Create a standalone application on `checkpoint1.xsa` in Vitis and add the
three files in `software/`. `main.c` starts 30 pairs/s with the carrier on.
Watch `modulated_out` and the envelope in the ILA (trigger on probe1 > 0).

## Simulation

```sh
./checkpoint1/sim/run_sim.sh      # Icarus Verilog 12, about 30 s
```

The testbench drives the IP over AXI4-Lite, with a behavioural model of the
DDS (same phase increment), and checks:

1. Reset values, read/write, SLVERR, periods below 450 us rejected.
2. Six pulses: 5000 cycles (50 us) wide, 35000 cycles (350 us) gap,
   40000 cycles (400 us) rising to rising, envelope peak 32767.
3. Carrier: 80 zero crossings in 40 us (1 MHz) in every pulse.
4. Periods of 1000 us, 2000 us and the default 33333 us, exact to the cycle.
5. Carrier off: output equals the envelope. Envelope 0 between pulses.
6. Disable: generator idles and the outputs go to 0.

Known behaviour: the first period after enabling is 1 us short (999 us for
1000 us), because leaving the idle state the period counter has already
stepped to 1 when the first pulse starts. Every period after that is exact.
The RTL is left as it is because it is what the board bitstream was built
from.

## Implementation results (Vivado 2020.1, from the board build)

| | LUT | FF | DSP48 | BRAM36 |
|---|---:|---:|---:|---:|
| `dme_axi4lite` IP (out-of-context synthesis) | 525 | 259 | 1 | 0 |
| Whole design incl. ILA (131072 samples), placed | 2519 | 2996 | 1 | 121 |

Timing at 100 MHz: met, worst setup slack +0.417 ns (Fmax about 104 MHz).
The critical path is `env_phase` → envelope LUT → DSP multiplier →
`modulated_out`. The 121 BRAMs are all the ILA's capture buffer.

The DAC/ADC loopback of the project slides is milestone 4; in the final
project (checkpoint 4) the aircraft is connected to the course ground
station IP directly in the FPGA.
