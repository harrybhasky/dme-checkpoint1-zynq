#include "dme_driver.h"

/*
 * Replace this address with the address assigned to the custom IP
 * in the Vivado Address Editor.
 */
#define DME_BASE_ADDRESS 0x43C00000u

int main(void)
{
    dme_device_t dme;

    dme_init(&dme, DME_BASE_ADDRESS);
    dme_set_rate_hz(&dme, 30u);
    dme_enable_carrier(&dme, 1);
    dme_enable(&dme, 1);

    for (;;) {
        /*
         * Read these in the debugger or print them using the board's
         * UART support while validating the design.
         */
        volatile uint32_t status = dme_read_status(&dme);
        volatile uint32_t elapsed = dme_read_elapsed_us(&dme);
        (void)status;
        (void)elapsed;
    }
}
