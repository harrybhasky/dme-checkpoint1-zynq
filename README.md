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
```
