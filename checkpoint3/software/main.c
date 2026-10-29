#include "dme_driver.h"
#include "dme_rx_driver.h"
#include "dme_gs_driver.h"
#include "dme_range.h"
#include "xil_printf.h"

/*
 * Replace these with the addresses assigned in the Vivado Address Editor.
 */
#define DME_BASE_ADDRESS    0x43C00000u
#define DME_RX_BASE_ADDRESS 0x43C10000u
#define DME_GS_BASE_ADDRESS 0x43C20000u
#define FCLK_HZ             100000000u

#define START_RANGE_MNM     120000u
/* 3600 kt is 1 NM/s: much faster than an aircraft, so that the range
 * visibly changes on the UART. Use 300 for a realistic approach. */
#define SPEED_KNOTS         3600
#define CALIBRATION_PAIRS   16u
/* A reply within this distance of the track belongs to our aircraft. */
#define TRACK_GATE_MNM      1000
#define TRACK_LOST_MISSES   5u

/* Replies already queued in the station when its range changes still carry
 * the old range. Drop the next n pairs after any change. */
static void discard_pairs(const dme_rx_device_t *rx, uint32_t n)
{
    uint32_t ts, delay;

    dme_rx_clear(rx);
    while (n > 0u)
        if (dme_rx_pop_pair_delay(rx, &ts, &delay))
            n--;
}

static void print_nm(const char *label, uint32_t mnm)
{
    xil_printf("%s%u.%03u NM", label, (unsigned)(mnm / 1000u),
               (unsigned)(mnm % 1000u));
}

/* Average TX-to-RX delay over 450 us with the station at zero range: the
 * aircraft receiver's own latency, removed from every later measurement. */
static uint32_t calibrate(const dme_rx_device_t *rx, const dme_gs_device_t *gs)
{
    uint32_t fixed = DME_FIXED_DELAY_US * rx->clocks_per_us;
    uint32_t sum = 0u;
    uint32_t n = 0u;

    dme_gs_enable_motion(gs, 0);
    dme_gs_set_range_cycles(gs, 0u);
    discard_pairs(rx, 2u);
    while (n < CALIBRATION_PAIRS) {
        uint32_t ts, delay;
        if (dme_rx_pop_pair_delay(rx, &ts, &delay)) {
            sum += delay - fixed;
            n++;
        }
    }
    return (sum + n / 2u) / n;
}

int main(void)
{
    dme_device_t dme;
    dme_rx_device_t rx;
    dme_gs_device_t gs;
    uint32_t latency;
    uint32_t track_mnm = 0u;
    uint32_t misses = 0u;
    uint32_t replies = 0u;
    int locked = 0;
    int32_t speed = -SPEED_KNOTS;

    /* Aircraft transmitter (checkpoint 1): 30 interrogations/s. */
    dme_init(&dme, DME_BASE_ADDRESS);
    dme_set_rate_hz(&dme, 30u);
    dme_enable_carrier(&dme, 1);

    /* Ground station, fed by the aircraft's modulated_out. */
    dme_gs_init(&gs, DME_GS_BASE_ADDRESS, FCLK_HZ);
    dme_gs_select_input(&gs, DME_GS_INPUT_LOOPBACK);
    dme_gs_enable(&gs, 1);

    /* Aircraft receiver (checkpoint 2), fed by the ground station reply. */
    dme_rx_init(&rx, DME_RX_BASE_ADDRESS, FCLK_HZ);
    dme_rx_select_input(&rx, DME_RX_INPUT_LOOPBACK);
    dme_rx_enable(&rx, 1);

    dme_enable(&dme, 1);
    xil_printf("DME checkpoint 3: ground station delay and distance model\r\n");

    latency = calibrate(&rx, &gs);
    xil_printf("receiver latency %u cycles\r\n", (unsigned)latency);

    dme_gs_set_range_limits_mnm(&gs, 10000u, 200000u);
    dme_gs_set_range_mnm(&gs, START_RANGE_MNM);
    dme_gs_set_velocity_knots(&gs, speed);
    dme_gs_enable_motion(&gs, 1);
    discard_pairs(&rx, 2u);

    for (;;) {
        uint32_t ts, delay, offset, mnm;
        int32_t error;

        if (!dme_rx_pop_pair_delay(&rx, &ts, &delay))
            continue;

        offset = DME_FIXED_DELAY_US * rx.clocks_per_us + latency;
        if (delay < offset)
            continue;
        mnm = dme_cycles_to_mnm(rx.clocks_per_us, delay - offset);

        /* Track the range: replies far from it are another aircraft's or
         * squitters. Lock again after several misses in a row. */
        error = (int32_t)(mnm - track_mnm);
        if (!locked || error > TRACK_GATE_MNM || error < -TRACK_GATE_MNM) {
            if (!locked || ++misses >= TRACK_LOST_MISSES) {
                track_mnm = mnm;
                locked = 1;
                misses = 0u;
            }
            continue;
        }
        misses = 0u;
        track_mnm = (uint32_t)((int32_t)track_mnm + error / 4);

        print_nm("measured ", mnm);
        print_nm("  track ", track_mnm);
        print_nm("  model ", dme_gs_read_range_mnm(&gs));
        xil_printf("\r\n");

        /* Turn around at the model's range limits. */
        if (dme_gs_read_status(&gs) & DME_GS_STATUS_AT_LIMIT) {
            speed = -speed;
            dme_gs_set_velocity_knots(&gs, speed);
            xil_printf("range limit reached, now flying %s\r\n",
                       speed > 0 ? "away" : "towards the station");
        }

        if (++replies % 30u == 0u)
            xil_printf("station: %u interrogations, %u replies, %u dropped\r\n",
                       (unsigned)dme_gs_read_interrogations(&gs),
                       (unsigned)dme_gs_read_replies(&gs),
                       (unsigned)dme_gs_read_dropped(&gs));
    }
}
