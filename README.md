# DME Checkpoint 1 - Zynq FPGA

Implementation for Checkpoint 1 of the aircraft Distance Measuring Equipment
(DME) project.

## Scope

- 50 us pulse width
- 350 us delay between the two pulses
- Software-configurable pulse-pair period/rate
- 1 MHz DDS-style internal carrier
- Zynq PS-to-PL AXI4-Lite register interface
- Simulation testbench and bare-metal C driver

See [`checkpoint1/README.md`](checkpoint1/README.md) for the register map,
Vivado integration steps, and validation procedure.

## Layout

```text
checkpoint1/
├── rtl/       SystemVerilog core, AXI4-Lite wrapper, and testbench
└── software/  Bare-metal C driver and example application
```
