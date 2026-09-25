# Checkpoint 1: DME Pulse-Pair Generator, Driver, and Modulator

## Checkpoint 1 implementation for Zynq

- FPGA clock: 100 MHz by default
- Pulse width: 50 us
- Delay between the two pulses: 350 us
- Pair rate: configurable in software; default is approximately 30 pairs/s
- Internal carrier: 1 MHz
- The output is a carrier gated by the pulse-pair signal
- The processor interface is AXI4-Lite for a Zynq PS-to-PL connection
- The carrier is generated with a DDS-style 32-bit phase accumulator

## Register map

| Offset | Name | Description |
|---:|---|---|
| 0x00 | CONTROL | Bit 0 enables the generator; bit 1 enables the carrier |
| 0x04 | PERIOD_US | Start-to-start period of pulse pairs |
| 0x08 | STATUS | Bit 0 pulse active; bit 1 generator active |
| 0x0C | ELAPSED_US | Elapsed microseconds in the current pair period |

The minimum period is 450 us, equal to 50 + 350 + 50 us. A normal DME
configuration is 33,333 us for approximately 30 pulse pairs per second.

## Vivado block design

Add `dme_axi4lite.sv` and `dme_pulse_pair_modulator.sv` as RTL sources, then
package `dme_axi4lite` as a custom AXI4-Lite peripheral. Connect its
`S_AXI` interface to the Zynq Processing System through the AXI interconnect.
Connect `s_axi_aclk` and `s_axi_aresetn` to the Zynq AXI clock/reset. Route
`modulated_out` to an FPGA output or an ILA for checkpoint 1.

The AXI register offsets are 0x00, 0x04, 0x08, and 0x0C as listed above.
The later ADC/DAC loopback in the PPT is not part of this first checkpoint.
