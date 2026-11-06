# DME Checkpoints - Zynq FPGA

Implementation of the aircraft Distance Measuring Equipment (DME) project on
the Zynq FPGA platform.

## Checkpoints

### Checkpoint 1: Pulse-pair transmitter

- 50 us pulse width
- 350 us delay between the two pulses
- Software-configurable pulse-pair period/rate
- 1 MHz DDS-style internal carrier
- Zynq PS-to-PL AXI4-Lite register interface
- Simulation testbench and bare-metal C driver

See [`checkpoint1/README.md`](checkpoint1/README.md) for the transmitter
register map,
Vivado integration steps, and validation procedure.

### Checkpoint 2: Pulse demodulator and detector

- Non-coherent envelope demodulation with configurable DC removal, filtering,
  and hysteresis thresholds
- Pulse-width validation and 400 us pulse-pair spacing detection
- Timestamp FIFO and counters exposed through a second AXI4-Lite peripheral
- Digital loopback and ADC sample-stream input paths
- Self-checking simulation covering loopback, noise, invalid pulses, and
  interfering pulses

See [`checkpoint2/README.md`](checkpoint2/README.md) for the receiver
algorithm, register map, Vivado integration steps, and simulation procedure.

### Checkpoint 3: Ground station with delay and distance model

- DME test equipment IP: decodes interrogations with the checkpoint 2
  receiver and replies with a 50 us transponder delay plus the round trip
- Distance model from 10 to 200 NM, with aircraft velocity towards or away
  from the station
- Reply queue for several replies in flight, and configurable reply
  efficiency
- Aircraft-side TX correlation, zero-range calibration and range tracking
  in software
- Self-checking end-to-end simulation (aircraft TX → ground station →
  aircraft RX)

See [`checkpoint3/README.md`](checkpoint3/README.md) for the timing
algorithm, register map, Vivado integration steps, and simulation procedure.

### Checkpoint 4: Final project with the course ground station IP

All six project requirements: distance and speed, static and flying
towards/away, at 60% reply efficiency, with squitter up to 2500 pps.

- Aircraft DME connected directly to the course `groundStation` IP in the
  same FPGA
- New interrogator: 7 us half-sine pulses, 12 us apart, 10 MHz carrier,
  12-bit samples, random PRF jitter
- Checkpoint 2 receiver cores retuned for the station's replies, a
  reply-delay FIFO with a range gate
- AXI control of every ground station input (distance, speed, direction,
  efficiency, squitter, jitter)
- Software: delay-histogram tracker that rejects squitter, speed from the
  station's 1 km steps, calibration, UART commands and one-key test cases
  for each requirement
- Self-checking simulation against the unmodified course IP (including
  squitter and motion), plus PC tests of the tracker for every requirement
- One-command Vivado build (any version from 2020.1) and XSCT scripts to
  build and run the software

**Building it on the board: [`checkpoint4/BUILD.md`](checkpoint4/BUILD.md).**
Design details: [`checkpoint4/README.md`](checkpoint4/README.md).

## Layout

```text
checkpoint1/
├── rtl/       Transmitter SystemVerilog core, AXI4-Lite wrapper, and testbench
└── software/  Transmitter bare-metal C driver and example application
checkpoint2/
├── rtl/       Receiver/detector SystemVerilog cores and testbench
├── sim/       Icarus Verilog simulation runner
└── software/  Receiver bare-metal C driver and example application
checkpoint3/
├── rtl/       Ground station core, range model and end-to-end testbench
├── sim/       Icarus Verilog simulation runner
└── software/  Ground station driver, range conversions and demo application
checkpoint4/
├── ip/        Course ground station IP (as provided, Vivado 2022.2)
├── rtl/       Interrogator TX, aircraft and station-control AXI IPs, PL system, testbench
├── sim/       Icarus runner, Xilinx core models, pulse ROM generator
├── software/  Drivers, tracker (dme_track.c), application; test/ PC tests
├── vivado/    build_project.tcl: project, block design, bitstream, .xsa
└── vitis/     build_app.tcl and run_on_board.tcl (XSCT)
```
