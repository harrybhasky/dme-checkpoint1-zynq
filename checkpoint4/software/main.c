/*
 * Checkpoint 4 / final project: aircraft DME against the course ground
 * station IP, in the same FPGA.
 *
 * Every second it prints the distance to the station, the station's own
 * distance, the error, how many interrogations were answered, and the
 * speed (positive: flying away). It covers all six project requirements:
 * static and moving aircraft, 60% reply efficiency, and squitter up to
 * 2500 pulse pairs per second. The tracker is in dme_track.c.
 *
 * Commands over the UART (115200 8N1), each ended with Enter:
 *
 *   d <m>  k <km>  n <NM>   station distance (stops the motion)
 *   v <m/s>                 speed, 47 to 255 (the station's limit)
 *   a / t                   fly away from / towards the station
 *   m 0|1                   motion off / on
 *   e <percent>             reply efficiency
 *   q 0|1                   squitter off / on
 *   r <pps>                 squitter rate (default 2500)
 *   j 0|1                   station reply jitter off / on (recalibrates)
 *   c                       recalibrate
 *   s                       counters
 *   1 ... 6                 set up the test case of requirement 1 to 6
 *   ?                       help
 */
#include <stdint.h>
#include <stdlib.h>

#include "dme_aircraft_driver.h"
#include "dme_gs_ctrl_driver.h"
#include "dme_track.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xuartps_hw.h"

/* Addresses from the Vivado Address Editor (build_project.tcl sets these). */
#define DME_AC_BASE_ADDRESS  0x43C00000u
#define DME_GSC_BASE_ADDRESS 0x43C10000u
#define FCLK_HZ              100000000u

#define INTERROGATION_RATE_HZ 30u
/* Up to 0.65 ms of random PRF jitter, more than a squitter period at 2500
 * pps (0.4 ms). Squitter delays are then spread evenly while our replies
 * keep one delay. The period stays above the 2.7 ms longest round trip, so
 * every reply belongs to the latest interrogation. */
#define JITTER_MASK           0xFFFFu
/* Range gate: just beyond the station's 389 km limit. */
#define MAX_DELAY_CYCLES      270000u
#define START_DISTANCE_M      100000u
#define DEFAULT_SQUITTER_PPS  2500u

/* Interrogation start to reply with no propagation delay, from simulation.
 * Calibration replaces it. */
#define DEFAULT_ZERO_RANGE_DELAY 5168u
/* Calibrate at a known non-zero distance: at zero the station's delay FIFO
 * starts 2 cycles earlier than at any other distance. */
#define CAL_DISTANCE_M        10000u

#define GATE_CYCLES           32u  /* our replies spread +/-7 cycles */
#define GATE_JITTER_CYCLES    160u /* station reply jitter adds 1..255 */

static dme_ac_device_t ac;
static dme_gsc_device_t gsc;
static dme_trk_t trk;
static uint32_t zero_range_delay = DEFAULT_ZERO_RANGE_DELAY;

/* ------------------------------------------------------------------ */
/* Time: the aircraft's 32-bit cycle counter, extended to 64 bits      */
/* ------------------------------------------------------------------ */
static uint64_t clock64;
static uint32_t clock_last;

static uint64_t now_cycles(void)
{
    uint32_t t = dme_ac_read(&ac, DME_AC_REG_TIMESTAMP);
    clock64 += (uint32_t)(t - clock_last);
    clock_last = t;
    return clock64;
}

/* A 32-bit timestamp from the last 42 s, as 64-bit cycles. */
static uint64_t extend_time(uint32_t t32)
{
    now_cycles();
    return clock64 - (uint32_t)(clock_last - t32);
}

/* Reads every reply in the FIFO into the tracker. */
static void drain_fifo(void)
{
    uint32_t delay, time;
    while (dme_ac_pop_reply(&ac, &delay, &time))
        dme_trk_add(&trk, extend_time(time), delay);
}

static void wait_ms(uint32_t ms)
{
    uint64_t until = now_cycles() + (uint64_t)ms * (FCLK_HZ / 1000u);
    while (now_cycles() < until)
        drain_fifo();
}

/* ------------------------------------------------------------------ */
/* Printing (xil_printf has no %f)                                     */
/* ------------------------------------------------------------------ */
static void print_fixed(double value, unsigned decimals)
{
    uint32_t scale = 1u;
    uint64_t scaled;
    unsigned i;

    for (i = 0; i < decimals; i++)
        scale *= 10u;
    if (value < 0.0) {
        xil_printf("-");
        value = -value;
    }
    scaled = (uint64_t)(value * scale + 0.5);
    xil_printf("%u", (unsigned)(scaled / scale));
    if (decimals > 0u) {
        uint32_t frac = (uint32_t)(scaled % scale);
        uint32_t digit = scale / 10u;
        xil_printf(".");
        while (digit > 0u) {
            xil_printf("%u", (unsigned)(frac / digit));
            frac %= digit;
            digit /= 10u;
        }
    }
}

/* ------------------------------------------------------------------ */
/* Tracker set-up and calibration                                      */
/* ------------------------------------------------------------------ */
static void tracker_setup(void)
{
    dme_trk_config_t cfg;
    int jitter = (dme_gsc_get_flags(&gsc) & DME_GSC_JITTER) != 0;

    dme_trk_default_config(&cfg);
    cfg.clock_hz = FCLK_HZ;
    cfg.zero_delay = zero_range_delay;
    cfg.max_delay = MAX_DELAY_CYCLES;
    cfg.gate = jitter ? GATE_JITTER_CYCLES : GATE_CYCLES;
    dme_trk_init(&trk, &cfg);
}

/* Restart measurements after the station changes: its delay lines are
 * flushed, and replies in flight carry the old distance. */
static void restart_measurement(void)
{
    wait_ms(100u);
    dme_ac_clear(&ac);
    tracker_setup();
}

/* Measures the zero-range delay with the station at CAL_DISTANCE_M. Works
 * with squitter and low efficiency: it uses the tracker's histogram peak. */
static void calibrate(void)
{
    uint32_t flags = dme_gsc_get_flags(&gsc);
    uint32_t restore_m = dme_gsc_distance_now_m(&gsc);
    dme_trk_result_t res;
    uint32_t tries;

    dme_gsc_set_flags(&gsc, flags & ~DME_GSC_MOTION);
    dme_gsc_set_distance_m(&gsc, CAL_DISTANCE_M);
    zero_range_delay = 0u; /* the tracker reports raw delays */
    restart_measurement();

    res.valid = 0;
    for (tries = 0; tries < 3u && !res.valid; tries++) {
        wait_ms(1000u);
        dme_trk_end_block(&trk, INTERROGATION_RATE_HZ, &res);
    }

    if (!res.valid) {
        zero_range_delay = DEFAULT_ZERO_RANGE_DELAY;
        xil_printf("calibration: no reply peak in 3 s, using %u cycles\r\n",
                   (unsigned)zero_range_delay);
    } else {
        zero_range_delay = (uint32_t)(res.delay + 0.5) -
                           2u * dme_gsc_one_way_cycles(CAL_DISTANCE_M);
        xil_printf("calibration at %u m: zero-range delay %u cycles (",
                   (unsigned)CAL_DISTANCE_M, (unsigned)zero_range_delay);
        print_fixed(zero_range_delay / 100.0, 2);
        xil_printf(" us), %u replies\r\n", (unsigned)res.hits);
    }

    dme_gsc_set_distance_m(&gsc, restore_m);
    dme_gsc_set_flags(&gsc, flags);
    restart_measurement();
}

/* ------------------------------------------------------------------ */
/* UART commands                                                       */
/* ------------------------------------------------------------------ */
static void print_help(void)
{
    xil_printf("commands: d <m> | k <km> | n <NM>  distance;  v <m/s>  speed (47-255);\r\n"
               "          a | t  away/towards;  m 0|1  motion;  e <pct>  efficiency;\r\n"
               "          q 0|1  squitter;  r <pps>  squitter rate;  j 0|1  station jitter;\r\n"
               "          c  calibrate;  s  counters;  1..6  requirement test case;  ?  help\r\n");
}

static void print_counters(void)
{
    uint32_t status = dme_ac_read(&ac, DME_AC_REG_STATUS);

    xil_printf("aircraft: %u interrogations, %u pairs decoded (%u beyond range gate), "
               "%u pulses, %u rejected, FIFO overflow %u\r\n",
               (unsigned)dme_ac_read(&ac, DME_AC_REG_TX_COUNT),
               (unsigned)dme_ac_read(&ac, DME_AC_REG_REPLY_COUNT),
               (unsigned)dme_ac_read(&ac, DME_AC_REG_GATED_COUNT),
               (unsigned)dme_ac_read(&ac, DME_AC_REG_PULSE_COUNT),
               (unsigned)dme_ac_read(&ac, DME_AC_REG_REJECT_COUNT),
               (unsigned)((status & DME_AC_STATUS_FIFO_OVERFLOW) != 0u));
    xil_printf("station: distance %u m, flags 0x%x, pulse width errors %u, "
               "pulse delay errors %u, zero-range delay %u cycles\r\n",
               (unsigned)dme_gsc_distance_now_m(&gsc),
               (unsigned)dme_gsc_get_flags(&gsc),
               (unsigned)dme_gsc_pw_errors(&gsc),
               (unsigned)dme_gsc_pd_errors(&gsc),
               (unsigned)zero_range_delay);
}

static void set_flag(uint32_t flag, int on)
{
    uint32_t flags = dme_gsc_get_flags(&gsc) & ~DME_GSC_CLEAR;
    dme_gsc_set_flags(&gsc, on ? (flags | flag) : (flags & ~flag));
}

static void set_distance(uint32_t meters)
{
    set_flag(DME_GSC_MOTION, 0);
    dme_gsc_set_distance_m(&gsc, meters);
    restart_measurement();
}

/* Requirement test cases. Speeds below 47 m/s do not work in the station
 * (distanceModel.v overflows), and it moves in 1 km steps every
 * floor(1000 / v) s, so 200 m/s is exact. */
static void test_case(int n)
{
    int moving = n == 2 || n == 3 || n == 5 || n == 6;
    int low_eff = n == 3 || n == 6;
    int squitter = n >= 4;

    set_distance(moving ? 150000u : START_DISTANCE_M);
    dme_gsc_set_efficiency(&gsc, low_eff ? 60u : 100u);
    dme_gsc_set_pulse_rate(&gsc, DEFAULT_SQUITTER_PPS);
    dme_gsc_set_speed_mps(&gsc, 200u);
    set_flag(DME_GSC_SQUITTER, squitter);
    set_flag(DME_GSC_AWAY, 0);
    set_flag(DME_GSC_MOTION, moving);
    dme_trk_reset(&trk);
    xil_printf("requirement %d: %s, efficiency %u percent, squitter %s\r\n", n,
               moving ? "150 km, towards at 200 m/s (a: away)" : "static at 100 km",
               low_eff ? 60u : 100u, squitter ? "2500 pps" : "off");
}

static void run_command(char *line)
{
    char cmd = line[0];
    long arg = strtol(line + 1, NULL, 10);

    switch (cmd) {
    case 'd': case 'k': case 'n': {
        long meters = cmd == 'd' ? arg : cmd == 'k' ? arg * 1000 : arg * 1852;
        if (meters < 0 || meters > (long)DME_GSC_MAX_DISTANCE_M) {
            xil_printf("distance must be 0 to %u m\r\n", (unsigned)DME_GSC_MAX_DISTANCE_M);
            return;
        }
        set_distance((uint32_t)meters);
        xil_printf("station distance set to %u m, motion off\r\n", (unsigned)meters);
        break;
    }
    case 'e':
        if (arg < 0 || arg > 100) {
            xil_printf("efficiency must be 0 to 100\r\n");
            return;
        }
        dme_gsc_set_efficiency(&gsc, (uint32_t)arg);
        xil_printf("reply efficiency %u percent\r\n", (unsigned)arg);
        break;
    case 'v':
        if (arg < 1 || arg > 255) {
            xil_printf("speed must be 1 to 255 m/s\r\n");
            return;
        }
        dme_gsc_set_speed_mps(&gsc, (uint32_t)arg);
        dme_trk_reset_speed(&trk);
        xil_printf("station speed %u m/s: it moves 1 km every %u s (%u m/s)\r\n",
                   (unsigned)arg, (unsigned)(1000 / arg), (unsigned)(1000 / (1000 / arg)));
        if (arg < 47)
            xil_printf("warning: the station's distanceModel overflows below 47 m/s\r\n");
        break;
    case 'a': case 't':
        set_flag(DME_GSC_AWAY, cmd == 'a');
        dme_trk_reset_speed(&trk);
        xil_printf("flying %s the station\r\n", cmd == 'a' ? "away from" : "towards");
        break;
    case 'm':
        set_flag(DME_GSC_MOTION, arg != 0);
        dme_trk_reset_speed(&trk);
        xil_printf("motion %s\r\n", arg ? "on" : "off");
        break;
    case 'q':
        set_flag(DME_GSC_SQUITTER, arg != 0);
        xil_printf("squitter %s\r\n", arg ? "on" : "off");
        break;
    case 'r':
        if (arg < 1 || arg > 4095) {
            xil_printf("squitter rate must be 1 to 4095 pps\r\n");
            return;
        }
        dme_gsc_set_pulse_rate(&gsc, (uint32_t)arg);
        xil_printf("squitter rate %u pps\r\n", (unsigned)arg);
        break;
    case 'j':
        set_flag(DME_GSC_JITTER, arg != 0);
        xil_printf("station reply jitter %s, recalibrating\r\n", arg ? "on" : "off");
        calibrate();
        break;
    case 'c':
        calibrate();
        break;
    case 's':
        print_counters();
        break;
    case '1': case '2': case '3': case '4': case '5': case '6':
        test_case(cmd - '0');
        break;
    default:
        print_help();
        break;
    }
}

static void poll_uart(void)
{
    static char line[32];
    static unsigned len;

    while (XUartPs_IsReceiveData(STDIN_BASEADDRESS)) {
        char c = (char)XUartPs_ReadReg(STDIN_BASEADDRESS, XUARTPS_FIFO_OFFSET);
        if (c == '\r' || c == '\n') {
            xil_printf("\r\n");
            line[len] = '\0';
            if (len > 0u)
                run_command(line);
            len = 0u;
        } else if (len < sizeof(line) - 1u) {
            line[len++] = c;
            xil_printf("%c", c);
        }
    }
}

/* ------------------------------------------------------------------ */
/* Report                                                              */
/* ------------------------------------------------------------------ */
static void report(uint32_t t_s, uint32_t interrogations)
{
    dme_trk_result_t res;
    uint32_t set_m = dme_gsc_distance_now_m(&gsc);

    dme_trk_end_block(&trk, interrogations, &res);

    xil_printf("t=%us  ", (unsigned)t_s);
    if (!res.valid) {
        xil_printf("searching  (station %u m, %u pairs received, %u interrogations)\r\n",
                   (unsigned)set_m, (unsigned)res.replies, (unsigned)interrogations);
        return;
    }

    xil_printf("distance ");
    print_fixed(res.distance_m, 1);
    xil_printf(" m = ");
    print_fixed(res.distance_m / 1852.0, 3);
    xil_printf(" NM  station %u m  error ", (unsigned)set_m);
    print_fixed(res.distance_m - set_m, 1);
    xil_printf(" m  replies %u/%u  other pairs %u", (unsigned)res.hits,
               (unsigned)interrogations, (unsigned)(res.replies - res.hits));

    if (res.speed_valid) {
        double v = res.speed_mps;
        xil_printf("  speed ");
        print_fixed(v < 0 ? -v : v, 1);
        xil_printf(" m/s %s", v < -0.5 ? "towards" : v > 0.5 ? "away" : "");
        xil_printf(res.speed_from_steps ? " (%u steps)" : " (fit)", (unsigned)res.steps);
    }
    if (res.dropped)
        xil_printf("  [%u replies dropped]", (unsigned)res.dropped);
    xil_printf("\r\n");
}

int main(void)
{
    uint64_t next_report, start;
    uint32_t tx_last;

    dme_gsc_init(&gsc, DME_GSC_BASE_ADDRESS);
    dme_gsc_set_pulse_rate(&gsc, DEFAULT_SQUITTER_PPS);
    dme_ac_init(&ac, DME_AC_BASE_ADDRESS, FCLK_HZ);
    dme_ac_set_rate_hz(&ac, INTERROGATION_RATE_HZ);
    dme_ac_set_jitter_mask(&ac, JITTER_MASK);
    dme_ac_set_max_delay(&ac, MAX_DELAY_CYCLES);
    clock_last = dme_ac_read(&ac, DME_AC_REG_TIMESTAMP);
    dme_ac_enable(&ac, 1, 1);
    tracker_setup();

    xil_printf("\r\nDME final project: aircraft vs course ground station\r\n");
    calibrate();
    set_distance(START_DISTANCE_M);
    print_help();

    start = now_cycles();
    next_report = start + FCLK_HZ;
    tx_last = dme_ac_read(&ac, DME_AC_REG_TX_COUNT);

    for (;;) {
        drain_fifo();
        poll_uart();

        if (now_cycles() >= next_report) {
            uint32_t tx = dme_ac_read(&ac, DME_AC_REG_TX_COUNT);
            drain_fifo();
            /* TX_COUNT restarts from 0 when the measurement restarts. */
            report((uint32_t)((next_report - start) / FCLK_HZ),
                   tx >= tx_last ? tx - tx_last : tx);
            tx_last = tx;
            next_report += FCLK_HZ;
            /* A command (calibration) can take seconds: do not catch up. */
            if (next_report <= now_cycles())
                next_report = now_cycles() + FCLK_HZ;
        }
    }
}
