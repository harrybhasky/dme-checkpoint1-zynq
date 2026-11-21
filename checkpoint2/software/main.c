#include "dme_driver.h"
#include "dme_rx_driver.h"
#include "xil_printf.h"

/*
 * Replace these with the addresses assigned in the Vivado Address Editor.
 */
#define DME_BASE_ADDRESS    0x43C00000u
#define DME_RX_BASE_ADDRESS 0x43C10000u
#define FCLK_HZ             100000000u

int main(void)
{
    dme_device_t dme;
    dme_rx_device_t rx;
    uint32_t previous_ts = 0u;
    int have_previous = 0;

    /* Checkpoint 1 transmitter: ~30 pulse pairs/s on the 1 MHz carrier. */
    dme_init(&dme, DME_BASE_ADDRESS);
    dme_set_rate_hz(&dme, 30u);
    dme_enable_carrier(&dme, 1);

    /* Checkpoint 2 receiver, fed directly from modulated_out. */
    dme_rx_init(&rx, DME_RX_BASE_ADDRESS, FCLK_HZ);
    dme_rx_select_input(&rx, DME_RX_INPUT_LOOPBACK);
    dme_rx_enable(&rx, 1);

    dme_enable(&dme, 1);
    xil_printf("DME checkpoint 2: demodulator and pair detector\r\n");

    for (;;) {
        uint32_t ts;

        while (dme_rx_pop_pair(&rx, &ts)) {
            uint32_t width_us = dme_rx_cycles_to_us(&rx, dme_rx_read_last_width(&rx));
            uint32_t spacing_us = dme_rx_cycles_to_us(&rx, dme_rx_read_last_spacing(&rx));

            xil_printf("pair #%u  ts=%u  spacing=%u us  width=%u us",
                       (unsigned)dme_rx_read_pair_count(&rx), (unsigned)ts,
                       (unsigned)spacing_us, (unsigned)width_us);
            if (have_previous)
                xil_printf("  interval=%u us",
                           (unsigned)dme_rx_cycles_to_us(&rx, ts - previous_ts));
            xil_printf("  rejected=%u\r\n",
                       (unsigned)dme_rx_read_reject_count(&rx));

            previous_ts = ts;
            have_previous = 1;
        }

        if (dme_rx_read_status(&rx) & DME_RX_STATUS_FIFO_OVERFLOW) {
            xil_printf("pair FIFO overflow, clearing\r\n");
            dme_rx_clear(&rx);
            have_previous = 0;
        }
    }
}
