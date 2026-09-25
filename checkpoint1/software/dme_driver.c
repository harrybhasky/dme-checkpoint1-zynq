#include "dme_driver.h"

#define DME_MIN_PERIOD_US 450u

static inline void dme_write(const dme_device_t *device,
                             uint32_t offset, uint32_t value)
{
    *(volatile uint32_t *)(device->base_address + offset) = value;
}

static inline uint32_t dme_read(const dme_device_t *device, uint32_t offset)
{
    return *(volatile uint32_t *)(device->base_address + offset);
}

void dme_init(dme_device_t *device, uintptr_t base_address)
{
    device->base_address = base_address;
    dme_write(device, DME_REG_CONTROL, DME_CONTROL_CARRIER_ENABLE);
    dme_set_period_us(device, 33333u); /* approximately 30 pulse pairs/s */
}

void dme_set_period_us(const dme_device_t *device, uint32_t period_us)
{
    if (period_us < DME_MIN_PERIOD_US)
        period_us = DME_MIN_PERIOD_US;
    dme_write(device, DME_REG_PERIOD_US, period_us);
}

void dme_set_rate_hz(const dme_device_t *device, uint32_t rate_hz)
{
    uint32_t period_us;

    if (rate_hz == 0u)
        return;
    period_us = (1000000u + rate_hz / 2u) / rate_hz;
    dme_set_period_us(device, period_us);
}

void dme_enable(const dme_device_t *device, int enable)
{
    uint32_t control = dme_read(device, DME_REG_CONTROL);
    if (enable)
        control |= DME_CONTROL_ENABLE;
    else
        control &= ~DME_CONTROL_ENABLE;
    dme_write(device, DME_REG_CONTROL, control);
}

void dme_enable_carrier(const dme_device_t *device, int enable)
{
    uint32_t control = dme_read(device, DME_REG_CONTROL);
    if (enable)
        control |= DME_CONTROL_CARRIER_ENABLE;
    else
        control &= ~DME_CONTROL_CARRIER_ENABLE;
    dme_write(device, DME_REG_CONTROL, control);
}

uint32_t dme_read_status(const dme_device_t *device)
{
    return dme_read(device, DME_REG_STATUS);
}

uint32_t dme_read_elapsed_us(const dme_device_t *device)
{
    return dme_read(device, DME_REG_ELAPSED_US);
}
