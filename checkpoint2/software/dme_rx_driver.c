#include "dme_rx_driver.h"

static inline void dme_rx_write(const dme_rx_device_t *device,
                                uint32_t offset, uint32_t value)
{
    *(volatile uint32_t *)(device->base_address + offset) = value;
}

static inline uint32_t dme_rx_read(const dme_rx_device_t *device,
                                   uint32_t offset)
{
    return *(volatile uint32_t *)(device->base_address + offset);
}

static void dme_rx_update_control(const dme_rx_device_t *device,
                                  uint32_t mask, int set)
{
    uint32_t control = dme_rx_read(device, DME_RX_REG_CONTROL);
    if (set)
        control |= mask;
    else
        control &= ~mask;
    dme_rx_write(device, DME_RX_REG_CONTROL, control);
}

void dme_rx_init(dme_rx_device_t *device, uintptr_t base_address,
                 uint32_t clock_hz)
{
    device->base_address = base_address;
    device->clocks_per_us = (clock_hz + 500000u) / 1000000u;

    dme_rx_write(device, DME_RX_REG_CONTROL, 0u);
    dme_rx_set_dc_offset(device, 0);
    dme_rx_set_env_shift(device, 7u);
    dme_rx_set_thresholds(device, 5000u, 4000u);
    dme_rx_set_width_window_us(device, 15u, 40u);
    dme_rx_set_spacing_window_us(device, 395u, 405u);
    dme_rx_clear(device);
}

void dme_rx_enable(const dme_rx_device_t *device, int enable)
{
    dme_rx_update_control(device, DME_RX_CONTROL_ENABLE, enable);
}

void dme_rx_enable_irq(const dme_rx_device_t *device, int enable)
{
    dme_rx_update_control(device, DME_RX_CONTROL_IRQ_ENABLE, enable);
}

void dme_rx_select_input(const dme_rx_device_t *device, dme_rx_input_t input)
{
    dme_rx_update_control(device, DME_RX_CONTROL_ADC_SELECT,
                          input == DME_RX_INPUT_ADC);
}

void dme_rx_clear(const dme_rx_device_t *device)
{
    uint32_t control = dme_rx_read(device, DME_RX_REG_CONTROL);
    dme_rx_write(device, DME_RX_REG_CONTROL, control | DME_RX_CONTROL_CLEAR);
}

void dme_rx_set_dc_offset(const dme_rx_device_t *device, int16_t offset)
{
    dme_rx_write(device, DME_RX_REG_DC_OFFSET, (uint16_t)offset);
}

void dme_rx_set_env_shift(const dme_rx_device_t *device, uint32_t shift)
{
    if (shift > 15u)
        shift = 15u;
    dme_rx_write(device, DME_RX_REG_ENV_SHIFT, shift);
}

void dme_rx_set_thresholds(const dme_rx_device_t *device,
                           uint16_t high, uint16_t low)
{
    if (low > high)
        low = high;
    dme_rx_write(device, DME_RX_REG_THRESH_HIGH, high);
    dme_rx_write(device, DME_RX_REG_THRESH_LOW, low);
}

void dme_rx_set_width_window_us(const dme_rx_device_t *device,
                                uint32_t min_us, uint32_t max_us)
{
    dme_rx_write(device, DME_RX_REG_WIDTH_MIN, min_us * device->clocks_per_us);
    dme_rx_write(device, DME_RX_REG_WIDTH_MAX, max_us * device->clocks_per_us);
}

void dme_rx_set_spacing_window_us(const dme_rx_device_t *device,
                                  uint32_t min_us, uint32_t max_us)
{
    dme_rx_write(device, DME_RX_REG_SPACING_MIN, min_us * device->clocks_per_us);
    dme_rx_write(device, DME_RX_REG_SPACING_MAX, max_us * device->clocks_per_us);
}

uint32_t dme_rx_read_status(const dme_rx_device_t *device)
{
    return dme_rx_read(device, DME_RX_REG_STATUS);
}

uint32_t dme_rx_read_timestamp(const dme_rx_device_t *device)
{
    return dme_rx_read(device, DME_RX_REG_TIMESTAMP);
}

/* Returns 1 and the first-pulse timestamp of the oldest detected pair, or 0
 * if no pair is waiting. */
int dme_rx_pop_pair(const dme_rx_device_t *device, uint32_t *timestamp)
{
    if (dme_rx_read_status(device) & DME_RX_STATUS_FIFO_EMPTY)
        return 0;
    *timestamp = dme_rx_read(device, DME_RX_REG_PAIR_FIFO);
    return 1;
}

uint32_t dme_rx_read_pair_count(const dme_rx_device_t *device)
{
    return dme_rx_read(device, DME_RX_REG_PAIR_COUNT);
}

uint32_t dme_rx_read_pulse_count(const dme_rx_device_t *device)
{
    return dme_rx_read(device, DME_RX_REG_PULSE_COUNT);
}

uint32_t dme_rx_read_reject_count(const dme_rx_device_t *device)
{
    return dme_rx_read(device, DME_RX_REG_REJECT_COUNT);
}

uint32_t dme_rx_read_last_width(const dme_rx_device_t *device)
{
    return dme_rx_read(device, DME_RX_REG_LAST_WIDTH);
}

uint32_t dme_rx_read_last_spacing(const dme_rx_device_t *device)
{
    return dme_rx_read(device, DME_RX_REG_LAST_SPACING);
}

uint32_t dme_rx_cycles_to_us(const dme_rx_device_t *device, uint32_t cycles)
{
    return (cycles + device->clocks_per_us / 2u) / device->clocks_per_us;
}
