# Checkpoint 2: DME Pulse Demodulator and Detector

Receive path for the DME. It demodulates the 1 MHz pulse-pair signal from
checkpoint 1, validates pulse widths, pairs pulses by their 400 us
leading-edge spacing, and queues a timestamp for every detected pair so
software can later match received pairs to transmitted ones.

```text
sample ─► DC removal ─► |x| ─► IIR low-pass ─► hysteresis ─► width check ─► pair match ─► FIFO ─► AXI
(loopback                                       comparator     (min/max)     (spacing     (16 x
 or ADC)                                                                      min/max)     32-bit)
```

## Algorithm

- **Envelope demodulator** (`dme_envelope_demodulator.sv`): non-coherent AM
  detection. It subtracts a programmable DC offset, rectifies, then smooths
  with `acc += (|x| - acc) >> ENV_SHIFT`, a time constant of about
  2^ENV_SHIFT samples. A comparator with separate high and low thresholds
  turns the envelope into a clean digital pulse.
- **Pulse-pair detector** (`dme_pulse_pair_detector.sv`): times each pulse
  from rising to falling edge against a 32-bit cycle counter. A pulse whose
  width is outside `[WIDTH_MIN, WIDTH_MAX]` is rejected. The rising edges of
  the last 4 unpaired valid pulses are kept. A new valid pulse that is
  `[SPACING_MIN, SPACING_MAX]` after any of them completes a pair. Because
  several candidates are kept, an interfering pulse from another aircraft or
  a squitter between the two pulses of a real pair does not break that pair.
- **AXI wrapper** (`dme_rx_axi4lite.sv`): registers, counters, the pair FIFO,
  an input mux (loopback or ADC), and an `irq` output that is high while the
  FIFO is not empty.

The checkpoint 1 pulses have a raised-cosine envelope over the full 50 us.
The width measured at the comparator is therefore about 27 us, not 50 us.
The default width window is 15 to 40 us. Spacing is measured between
matching points on identical pulses, so it stays at exactly 400 us.

## Register map

| Offset | Name | Access | Description |
|---:|---|---|---|
| 0x00 | CONTROL | RW | bit 0 enable, bit 1 input select (0 loopback, 1 ADC), bit 2 IRQ enable, bit 31 clear counters, FIFO and detector (write 1) |
| 0x04 | STATUS | RO | bit 0 pulse active, bit 1 FIFO empty, bit 2 FIFO full, bit 3 FIFO overflow (sticky), [12:8] FIFO count, [31:16] envelope |
| 0x08 | DC_OFFSET | RW | signed 16-bit, subtracted from every sample |
| 0x0C | ENV_SHIFT | RW | IIR shift, 0 to 15 (default 7 = 1.28 us at 100 MSPS) |
| 0x10 | THRESH_HIGH | RW | envelope level that starts a pulse (default 5000) |
| 0x14 | THRESH_LOW | RW | envelope level that ends a pulse (default 4000) |
| 0x18 | WIDTH_MIN | RW | cycles (default 15 us) |
| 0x1C | WIDTH_MAX | RW | cycles (default 40 us) |
| 0x20 | SPACING_MIN | RW | cycles (default 395 us) |
| 0x24 | SPACING_MAX | RW | cycles (default 405 us) |
| 0x28 | TIMESTAMP | RO | free-running 100 MHz cycle counter |
| 0x2C | PAIR_FIFO | RO, pop | first-pulse timestamp of the oldest detected pair (0 if empty) |
| 0x30 | PAIR_COUNT | RO | pairs detected |
| 0x34 | PULSE_COUNT | RO | pulses with a valid width |
| 0x38 | REJECT_COUNT | RO | pulses with an invalid width |
| 0x3C | LAST_WIDTH | RO | width of the last pulse, cycles |
| 0x40 | LAST_SPACING | RO | spacing of the last pair, cycles |
| 0x44 | TX_TIMESTAMP | RO | timestamp of the latest interrogation sent (checkpoint 3) |
| 0x48 | PAIR_DELAY | RO | delay from interrogation to the oldest FIFO pair, cycles; read before popping PAIR_FIFO (checkpoint 3) |
| 0x4C | TX_COUNT | RO | interrogations sent (checkpoint 3) |

Checkpoint 3 added the last three registers and a `tx_envelope` input
(connect `dme_axi4lite/pulse_envelope_out`, or tie to 0). See
[`../checkpoint3/README.md`](../checkpoint3/README.md).

The default thresholds suit the loopback signal. The DDS sine is 15-bit
(±16383), so the mean rectified envelope at the pulse peak is about 10,400.
For the ADC, set DC_OFFSET to the ADC mid-scale and scale the thresholds to
about 50% and 40% of the received envelope.

## Simulation

```sh
./checkpoint2/sim/run_sim.sh
```

This needs Icarus Verilog 12. The testbench (`rtl/tb_dme_rx.sv`) uses the
real checkpoint 1 modulator from
`checkpoint1/checkpoint1.srcs/sources_1/imports/rtl/` (override with
`TX_RTL=...`) and a behavioural 1 MHz DDS. It checks:

- Loopback: 6 pairs in 5.5 ms at a 1000 us period, 0 rejects, spacing of
  40,000 cycles, and a pair-to-pair interval of 100,000 cycles.
- ADC path (10 MSPS, DC offset, ±1500 noise): a valid pair is detected; a
  lone pulse, 300 us spacing and 80 us wide pulses are not; a pair with an
  interfering pulse in the middle is still detected.

The first interval after the transmitter is enabled is 999 us: the
checkpoint 1 FSM spends one microsecond in `S_IDLE`. The test skips that
interval.

## Vivado block design

1. Add the three `rtl/dme_*.sv` files (not the testbench) and package
   `dme_rx_axi4lite` as a custom AXI4-Lite peripheral, the same way as
   `dme_axi4lite`.
2. Add it to `design_1`. Raise `NUM_MI` on `ps7_0_axi_periph` to 2 and
   connect `s_axi`. Connect `s_axi_aclk` to `FCLK_CLK0` and `s_axi_aresetn`
   to `peripheral_aresetn`.
3. Connect `dme_axi4lite_0/modulated_out` to `loopback_sample`. Tie
   `adc_sample` and `adc_sample_valid` to 0 with a Constant block until
   milestone 4.
4. Optional: probe `envelope_out`, `pulse_detected` and `pair_detected` on
   the ILA alongside the existing probes. To use `irq`, enable `IRQ_F2P` on
   the Zynq PS.
5. Assign an address in the Address Editor (the example uses 0x43C10000),
   regenerate the bitstream, and export the XSA.

## Software

In the Vitis application, use `software/main.c` together with
`dme_rx_driver.c/.h` and the checkpoint 1 `dme_driver.c/.h`. Over UART it
prints each detected pair with its spacing (about 400 us), its width (about
27 us) and the interval to the previous pair (about 33,333 us at 30 pairs/s).

## Notes for later milestones

- Each pair timestamp is the first pulse's rising edge on the receiver's
  cycle counter. Correlating against transmitted pairs (milestone 3) needs a
  TX timestamp on the same timebase. The demodulator adds a fixed latency of
  about 1 to 2 us that should be calibrated out of range measurements.
- Pmod ADCs such as the AD1 sample at up to 1 MSPS, which cannot represent a
  1 MHz carrier. Use an analog envelope detector in front of the ADC, a
  faster ADC, or a lower test carrier. The demodulator works on any of these
  through `adc_sample_valid` and the configurable DC offset, thresholds and
  ENV_SHIFT.
