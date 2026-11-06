#include "dme_aircraft_driver.h"

uint32_t dme_ac_read(const dme_ac_device_t *device, uint32_t offset)
{
    return *(volatile uint32_t *)(device->base_address + offset);
}

void dme_ac_write(const dme_ac_device_t *device, uint32_t offset,
                  uint32_t value)
{
    *(volatile uint32_t *)(device->base_address + offset) = value;
}

void dme_ac_init(dme_ac_device_t *device, uintptr_t base_address,
                 uint32_t clock_hz)
{
    device->base_address = base_address;
    device->clock_hz = clock_hz;

    dme_ac_write(device, DME_AC_REG_CONTROL, 0u);

    /* Receiver set for the ground station's replies: 7 us half-sine pulses
     * 12 us apart. The envelope peaks near 21800, and the detected width
     * at these thresholds is about 5 us. */
    dme_ac_write(device, DME_AC_REG_ENV_SHIFT, 4u);
    dme_ac_write(device, DME_AC_REG_THRESH_HIGH, 10000u);
    dme_ac_write(device, DME_AC_REG_THRESH_LOW, 8000u);
    dme_ac_write(device, DME_AC_REG_WIDTH_MIN, 400u);
    dme_ac_write(device, DME_AC_REG_WIDTH_MAX, 650u);
    dme_ac_write(device, DME_AC_REG_SPACING_MIN, 1150u);
    dme_ac_write(device, DME_AC_REG_SPACING_MAX, 1250u);

    dme_ac_set_rate_hz(device, 30u);
    dme_ac_set_jitter_mask(device, 0u);
    dme_ac_set_max_delay(device, 270000u); /* just beyond 389 km */
    dme_ac_clear(device);
}

void dme_ac_enable(const dme_ac_device_t *device, int tx, int rx)
{
    uint32_t control = dme_ac_read(device, DME_AC_REG_CONTROL);

    control &= ~(DME_AC_CONTROL_TX_ENABLE | DME_AC_CONTROL_RX_ENABLE);
    if (tx)
        control |= DME_AC_CONTROL_TX_ENABLE;
    if (rx)
        control |= DME_AC_CONTROL_RX_ENABLE;
    dme_ac_write(device, DME_AC_REG_CONTROL, control);
}

void dme_ac_clear(const dme_ac_device_t *device)
{
    uint32_t control = dme_ac_read(device, DME_AC_REG_CONTROL);
    dme_ac_write(device, DME_AC_REG_CONTROL, control | DME_AC_CONTROL_CLEAR);
}

void dme_ac_set_rate_hz(const dme_ac_device_t *device, uint32_t pairs_per_s)
{
    if (pairs_per_s == 0u)
        pairs_per_s = 1u;
    dme_ac_write(device, DME_AC_REG_TX_PERIOD,
                 (device->clock_hz + pairs_per_s / 2u) / pairs_per_s);
}

void dme_ac_set_jitter_mask(const dme_ac_device_t *device, uint32_t jitter_mask)
{
    dme_ac_write(device, DME_AC_REG_TX_JITTER, jitter_mask);
}

void dme_ac_set_max_delay(const dme_ac_device_t *device, uint32_t max_delay)
{
    dme_ac_write(device, DME_AC_REG_MAX_DELAY, max_delay);
}

int dme_ac_pop_reply(const dme_ac_device_t *device, uint32_t *delay,
                     uint32_t *time)
{
    if (dme_ac_read(device, DME_AC_REG_STATUS) & DME_AC_STATUS_FIFO_EMPTY)
        return 0;
    *delay = dme_ac_read(device, DME_AC_REG_REPLY_DELAY);
    *time = dme_ac_read(device, DME_AC_REG_REPLY_TIME);
    return 1;
}
