# DME for Aircraft and its Test Equipment: Project Report

EEE G626 project on the Zynq-7020 (ZedBoard). This report covers the
architecture of the IPs, the algorithms, and performance (resources,
throughput, Fmax). Each checkpoint folder has a README with full register
maps and test details.

> **Status of the numbers.** Checkpoint 1 figures are from the real Vivado
> 2020.1 board build. Checkpoints 2 to 4 figures marked *(est.)* are Yosys
> `synth_xilinx` estimates for the same 7-series device; for checkpoint 1
> Yosys gives 563 LUT / 260 FF / 1 DSP against Vivado's 525 / 259 / 1, so
> they are close. Checkpoint 4 Vivado figures (`TODO`) come from
> `checkpoint4/vivado/output/utilization.txt` and `timing.txt` after the
> board build (see `HANDOFF.md`).

## 1. Deliverables

| Project deliverable | Where |
|---|---|
| Pulse-pair generator IP, 50 us / 350 us, rate set from software | `checkpoint1` (packaged IP `dme_axi4lite`) |
| 1 MHz internal carrier (DDS IP) | `checkpoint1` (Xilinx DDS Compiler, AXI-Stream into the IP) |
| Demodulate received pulses, identify valid pairs | `checkpoint2` (envelope demodulator + pair detector, in hardware) |
| Correlate TX with RX pairs, calculate distance | `checkpoint3`, `checkpoint4` (reply-delay FIFO in hardware, tracker in software) |
| Test equipment: efficiency 40-100%, 50 us delay, pulse rate + squitter on/off, 10-200 NM, towards/away | `checkpoint3` (own ground station), `checkpoint4` (course `groundStation` IP, all inputs under AXI control) |
| DAC/ADC loopback (milestone 4) | Not done on hardware: the final project connects the aircraft to the course ground station inside the FPGA, with no DAC/ADC |
| IP package + Vivado project | `checkpoint1` (`.xpr`, block design, packaged IP, `.xsa`); `checkpoint4/vivado/build_project.tcl` builds the final project |
| Drivers + C main | `checkpointN/software` |
| Report | this file |

## 2. Architecture

### Checkpoint 1: pulse-pair generator (`dme_axi4lite`)

```text
PS ── AXI4-Lite ──► registers (CONTROL, PERIOD_US) ──► timing FSM (us ticks)
                                                          │ IDLE→PULSE1→GAP→PULSE2→WAIT
DDS Compiler (1 MHz sine) ── AXI-Stream ──┐               ▼
                                          └──► x ◄── raised-cosine LUT (1024 x 16)
                                               ▼
                                   modulated_out (16-bit) , pulse_envelope_out → ILA
```

A 1 us tick drives a five-state FSM. The envelope phase steps through a
1024-entry raised-cosine table across each 50 us pulse. The output is
envelope x carrier / 2^15 (one DSP48).

### Checkpoint 2: demodulator and detector (`dme_rx_axi4lite`)

Non-coherent envelope detection: DC removal, rectification, IIR low-pass
(configurable shift) and hysteresis thresholds produce a pulse signal. The
pair detector checks each pulse width against a window, keeps a short
history of pulse start times, and declares a pair when two valid pulses are
the set spacing apart. Pairs go into a timestamp FIFO with counters for
software.

### Checkpoint 3: own ground station (`dme_gs_axi4lite`)

The checkpoint 2 receiver decodes interrogations. A reply queue schedules
each reply at 50 us + 2 x range delay. The range model covers 10 to 200 NM,
moving towards or away at a set speed. An LFSR implements reply efficiency.

### Checkpoint 4: final system (aircraft vs course ground station)

```text
PS ─ AXI ─► dme_aircraft_axi4lite: interrogator TX (7 us half-sine, 12 us, 10 MHz, PRF jitter)
                │ tx_sample (12-bit)                 ▲ rx_sample (12-bit)
                ▼                                    │
            groundStation (course IP, unmodified) ───┘   envelope demod → pair detector
PS ─ AXI ─► dme_gs_ctrl_axi4lite: distance, speed, direction, efficiency, squitter, jitter
                                         reply FIFO (delay, timestamp) ─► software tracker
```

## 3. Algorithms

- **Distance.** Delay from interrogation start to the reply's first pulse,
  in 10 ns cycles. distance = (delay − K) x 1.48648 m, where K (the 50 us
  fixed delay plus pipeline latency, 5168 cycles in simulation) is measured
  at start-up with the station at 10 km.
- **Correlation and squitter rejection.** Each interrogation period gets a
  random extra 0 to 0.65 ms (PRF jitter). Every second the software builds
  a histogram of reply delays (256-cycle bins). Our replies all land in one
  bin; squitter and replies to others spread across about 1050 bins. The
  strongest pair of adjacent bins is the reply; its refined mean gives the
  distance.
- **Reply efficiency.** Only about 15% of interrogations need to be answered
  for the peak to stand out, so 60% (and the required 40%) works.
- **Speed.** The course IP moves in 1 km steps. The tracker times each step
  to one interrogation period and fits distance over up to 8 steps; before
  two steps it uses a least-squares slope of the last 16 seconds.

## 4. Performance

### Resources

| Block | LUT | FF | DSP48 | BRAM36 | Source |
|---|---:|---:|---:|---:|---|
| CP1 `dme_axi4lite` | 525 | 259 | 1 | 0 | Vivado 2020.1 OOC |
| CP1 whole design incl. ILA | 2519 | 2996 | 1 | 121 (ILA) | Vivado 2020.1 placed |
| CP2 `dme_rx_axi4lite` | 1572 | 819 | 0 | 0 | est. |
| CP3 `dme_gs_axi4lite` | 2486 | 1227 | 2 | 0 | est. |
| CP4 `dme_aircraft_axi4lite` | 2135 | 1066 | 1 | 0 | est. |
| CP4 `dme_gs_ctrl_axi4lite` | 108 | 202 | 0 | 0 | est. |
| CP4 whole design (incl. course IP) | TODO | TODO | TODO | TODO | Vivado |

The Zynq-7020 has 53200 LUT, 106400 FF, 220 DSP and 140 BRAM36.

### Fmax

| Design | WNS at 100 MHz | Fmax |
|---|---:|---:|
| CP1 (board build) | +0.417 ns | about 104 MHz |
| CP4 | TODO | TODO |

Fmax = 1 / (10 ns − WNS). CP1's critical path is `env_phase` → LUT → DSP →
`modulated_out`.

### Throughput

- One sample per clock everywhere: 100 MS/s through TX, demodulator and
  detector.
- Interrogation rate: 30 pairs/s by default (project spec 25 to 30), any
  period down to 20 us in hardware.
- Reply FIFO: 64 entries. At 30 interrogations/s with squitter at 2500 pps,
  the software drains it many times per second.
- Distance resolution 1.49 m per cycle; simulated accuracy within ±12 m
  per reply, about ±1 m on the one-second average.

## 5. Verification

| Test | Command | Result |
|---|---|---|
| CP1 IP (AXI, 50/350 us, period, 1 MHz carrier) | `checkpoint1/sim/run_sim.sh` | pass |
| CP2 receiver (loopback, noise, invalid pulses) | `checkpoint2/sim/run_sim.sh` | pass |
| CP3 end-to-end with own ground station | `checkpoint3/sim/run_sim.sh` | pass |
| CP4 RTL vs unmodified course IP, + tracker replay | `checkpoint4/sim/run_sim.sh` | pass (105 checks) |
| CP4 tracker, all six requirements, 14 scenarios | `checkpoint4/software/test/run_tests.sh` | pass |
| All board C, Cortex-A9 cross-compile against the Zynq BSP | see `HANDOFF.md` | 0 warnings |

Known: on CP1, the first period after enable is 1 us short (later periods
exact), left as is because it matches the board bitstream.
