# Checkpoint 3: DME Ground Station with Delay and Distance Model

DME test equipment ("DME Test IP"). It receives the aircraft's
interrogations, models the distance to the aircraft, and answers each one
with a reply pulse pair delayed by 50 us plus the round trip. The aircraft
side gains transmit correlation so it can turn each reply into a distance.

```text
aircraft TX ──► demodulator ─► pair detector ─► efficiency ─► reply queue ─► reply generator ──► aircraft RX
(checkpoint 1)  (checkpoint 2 cores)            gate (LFSR)   due = pulse 2   (checkpoint 1         (checkpoint 2
                                                              + 50 us         modulator, one         + TX correlation)
                                         range model ───────► + range         pair per trigger)
                                         (range, velocity, 10 to 200 NM)
```

## Algorithm

- **Interrogation receiver**: the checkpoint 2 envelope demodulator and pair
  detector, with their own copy of every threshold and window register.
- **Reply timing**: the reply delay is measured from the half-amplitude
  point of the *second* interrogation pulse to the half-amplitude point of
  the first reply pulse. First-pulse timing cannot work here. The pair is
  only known after its second pulse, 400 us after the first. At short range,
  50 us plus the round trip is less than that (below about 31 NM).
- **Range model** (`dme_range_model.sv`): the range is stored as the round
  trip in clock cycles (1 NM = 12.3552 us = 1235.52 cycles at 100 MHz),
  with 16 fractional bits. Every 1 ms it adds a signed velocity. Positive
  means flying away, negative flying towards. While motion is enabled it is
  clamped to the RANGE_MIN to RANGE_MAX window (10 to 200 NM by default).
- **Reply queue**: each accepted interrogation queues a trigger time of
  `pulse2 + REPLY_DELAY + RANGE - LATENCY_COMP - 13.5 us`. The 13.5 us is
  the generator's 1 us start-up plus the 12.5 us to half amplitude.
  LATENCY_COMP removes the station's own detection latency. The queue holds
  8 entries, so replies to several interrogations can be in flight at long
  range and high PRF. A reply that comes due while one is still being sent
  is dropped and counted, not sent late with a wrong range.
- **Reply generator**: the checkpoint 1 modulator, enabled for one pair per
  trigger. It produces the same 50 us raised-cosine pulses 400 us apart on
  the station's own carrier input. That carrier can come from a second DDS
  at a different frequency, like a real reply channel.
- **Reply efficiency**: a 16-bit LFSR maps each interrogation to 0 to 99,
  and it is answered if that is below EFFICIENCY (default 100%).

### Aircraft transmit correlation (checkpoint 2 receiver)

`dme_rx_axi4lite` has a new `tx_envelope` input, connected to
`dme_axi4lite/pulse_envelope_out`. An upward crossing of half the envelope
peak marks an interrogation, unless it is the second pulse of one. Each
detected pair is stored with its delay from the latest interrogation sent
before its first pulse. Software computes:

```text
round trip = PAIR_DELAY - 450 us - receiver latency
distance   = round trip / 12.3552 us per NM
```

`main.c` measures the receiver latency at start-up by setting the station to
zero range (about 67 cycles in simulation). The interrogation period must be
longer than 450 us plus the round trip, or a reply is matched to the wrong
interrogation. That is 2.9 ms at 200 NM, well inside the 33 ms period at 30
pairs/s.

### Accuracy

Non-coherent detection jitters with the carrier phase at the start of a
pulse. The residual 2 MHz ripple moves the threshold crossing by up to
about ±0.2 us. In simulation, every distance is within 0.025 NM of the
model, and both pairs at the same setting give identical delays. On the
board the phase changes from pulse to pulse, and the tracking filter in
`main.c` averages it out.

## Register map

Offsets 0x00 to 0x28 match the checkpoint 2 receiver.

| Offset | Name | Access | Description |
|---:|---|---|---|
| 0x00 | CONTROL | RW | bit 0 enable, bit 1 input select (0 loopback, 1 ADC), bit 2 motion enable, bit 31 clear counters and queue (write 1) |
| 0x04 | STATUS | RO | bit 0 interrogation pulse active, bit 1 reply active, bit 2 queue full, bit 3 at range limit, [11:8] queue count, [31:16] envelope |
| 0x08 | DC_OFFSET | RW | signed 16-bit, subtracted from every sample |
| 0x0C | ENV_SHIFT | RW | IIR shift, 0 to 15 (default 7) |
| 0x10 | THRESH_HIGH | RW | default 5000 |
| 0x14 | THRESH_LOW | RW | default 4000 |
| 0x18 | WIDTH_MIN | RW | cycles (default 15 us) |
| 0x1C | WIDTH_MAX | RW | cycles (default 40 us) |
| 0x20 | SPACING_MIN | RW | cycles (default 395 us) |
| 0x24 | SPACING_MAX | RW | cycles (default 405 us) |
| 0x28 | TIMESTAMP | RO | free-running cycle counter |
| 0x2C | REPLY_DELAY | RW | transponder delay, cycles (default 50 us) |
| 0x30 | LATENCY_COMP | RW | detection latency removed from the delay, cycles (default 67) |
| 0x34 | RANGE | RW | round-trip delay, cycles. A write loads the model (default 10 NM) |
| 0x38 | VELOCITY | RW | signed, Q16 cycles per ms. 1 kt is about 22.49 |
| 0x3C | RANGE_MIN | RW | cycles (default 10 NM) |
| 0x40 | RANGE_MAX | RW | cycles (default 200 NM) |
| 0x44 | EFFICIENCY | RW | percent of interrogations answered, 0 to 100 (default 100) |
| 0x48 | INTERROGATIONS | RO | valid interrogation pairs decoded |
| 0x4C | REPLIES | RO | replies sent |
| 0x50 | SKIPPED | RO | interrogations not answered because of EFFICIENCY |
| 0x54 | DROPPED | RO | replies lost to a full queue or a busy generator |
| 0x58 | REJECTED | RO | interrogation pulses with an invalid width |

New receiver registers (`checkpoint2/rtl/dme_rx_axi4lite.sv`):

| Offset | Name | Access | Description |
|---:|---|---|---|
| 0x44 | TX_TIMESTAMP | RO | timestamp of the latest interrogation sent |
| 0x48 | PAIR_DELAY | RO | delay from interrogation to the oldest FIFO pair, cycles. Read it before popping PAIR_FIFO |
| 0x4C | TX_COUNT | RO | interrogations sent |

## Simulation

```sh
./checkpoint3/sim/run_sim.sh
```

This needs Icarus Verilog 12 and takes about 90 seconds. The testbench
(`rtl/tb_dme_gs.sv`) chains the checkpoint 1 modulator (1 MHz), the ground
station (1.25 MHz reply carrier) and the checkpoint 2 receiver. It times the
half-amplitude points itself, independent of the station's registers. It
checks:

1. Zero range: 3 replies at 50 us, and aircraft receiver calibration.
2. 10, 100 and 200 NM: station delay of 50 us + round trip, and aircraft
   distance, both within 0.3 us (0.024 NM).
3. 200 NM at a 600 us period: 8 replies with about 5 in flight, none
   dropped, all on time.
4. Motion: range changes by exactly 5 ticks of velocity in 5 ms, successive
   reply delays shrink by the expected step, and the model clamps at
   RANGE_MIN with the at-limit flag set.
5. Efficiency: 0% answers nothing. 50% answers 10 ± 5 of 20, and replies
   plus skips add up to 20.

`./checkpoint2/sim/run_sim.sh` still passes and now also checks the TX tap
and the loopback TX-to-RX delay.

## Vivado block design

1. Re-add the updated `checkpoint2/rtl` files and package
   `dme_rx_axi4lite` (it now has the `tx_envelope` port).
2. Package `dme_gs_axi4lite` with `checkpoint3/rtl/dme_gs_axi4lite.sv`,
   `dme_range_model.sv`, `checkpoint2/rtl/dme_envelope_demodulator.sv`,
   `dme_pulse_pair_detector.sv` and the checkpoint 1
   `dme_pulse_pair_modulator.sv`. Leave out the testbenches.
3. Add both to `design_1`, raise `NUM_MI` on `ps7_0_axi_periph` to 3, and
   connect `s_axi`, `s_axi_aclk` (`FCLK_CLK0`) and `s_axi_aresetn`
   (`peripheral_aresetn`) as before.
4. Connect:
   - `dme_axi4lite_0/modulated_out` → `dme_gs_axi4lite_0/loopback_sample`
   - `dme_gs_axi4lite_0/reply_out` → `dme_rx_axi4lite_0/loopback_sample`
   - `dme_axi4lite_0/pulse_envelope_out` → `dme_rx_axi4lite_0/tx_envelope`
   - Reply carrier: a second DDS Compiler (for example 1.25 MHz, 16-bit
     output) → `dme_gs_axi4lite_0/s_axis_carrier`. You can also fan out the
     existing DDS `m_axis_data_tdata`.
   - Tie `adc_sample` and `adc_sample_valid` on both IPs to 0 until
     milestone 4.
5. Assign addresses: TX 0x43C00000, RX 0x43C10000, ground station
   0x43C20000. Then regenerate the bitstream and export the XSA.
6. Optional ILA probes: `modulated_out`, `reply_out`,
   `interrogation_detected`, `reply_active` and the receiver's
   `pair_detected`.

## Software

Build `software/main.c` with `dme_gs_driver.c/.h` and `dme_range.h`, plus
`checkpoint2/software/dme_rx_driver.c/.h` and the checkpoint 1
`dme_driver.c/.h`. Over UART it:

1. Calibrates the aircraft receiver at zero range.
2. Puts the aircraft at 120 NM, flying towards the station at 3600 kt
   (1 NM/s, sped up so the change shows).
3. Prints the measured, tracked and modelled distance for every reply.
   Replies outside a 1 NM gate around the track are ignored, which is what
   will reject squitters and other aircraft.
4. Turns the aircraft around at 10 NM and 200 NM. Every 30 replies it
   prints the station's counters.

## Not yet done

- Squitters (random pulse pairs at a configurable rate, enable or disable).
  These complete the test-equipment feature list for the final demo.
- ADC and DAC in the loop (milestone 4). Both IPs already take
  `adc_sample` and `adc_sample_valid`. With a real channel, recalibrate
  LATENCY_COMP and the aircraft latency.
- Resource use and Fmax. These need a Vivado implementation run, which has
  not been done.
