#include "dme_gs_driver.h"
#include "dme_range.h"

static inline void dme_gs_write(const dme_gs_device_t *device,
                                uint32_t offset, uint32_t value)
{
    *(volatile uint32_t *)(device->base_address + offset) = value;
}

static inline uint32_t dme_gs_read(const dme_gs_device_t *device,
                                   uint32_t offset)
{
    return *(volatile uint32_t *)(device->base_address + offset);
}

static void dme_gs_update_control(const dme_gs_device_t *device,
                                  uint32_t mask, int set)
{
    uint32_t control = dme_gs_read(device, DME_GS_REG_CONTROL);
    if (set)
        control |= mask;
    else
        control &= ~mask;
    dme_gs_write(device, DME_GS_REG_CONTROL, control);
}

void dme_gs_init(dme_gs_device_t *device, uintptr_t base_address,
                 uint32_t clock_hz)
{
    device->base_address = base_address;
    device->clocks_per_us = (clock_hz + 500000u) / 1000000u;

    dme_gs_write(device, DME_GS_REG_CONTROL, 0u);
    dme_gs_set_dc_offset(device, 0);
    dme_gs_set_env_shift(device, 7u);
    dme_gs_set_thresholds(device, 5000u, 4000u);
    dme_gs_set_width_window_us(device, 15u, 40u);
    dme_gs_set_spacing_window_us(device, 395u, 405u);
    dme_gs_set_reply_delay_us(device, 50u);
    dme_gs_set_latency_comp(device, DME_GS_DEFAULT_LATENCY_COMP);
    dme_gs_set_efficiency(device, 100u);
    dme_gs_set_velocity_knots(device, 0);
    dme_gs_set_range_limits_mnm(device, 10000u, 200000u);
    dme_gs_set_range_mnm(device, 10000u);
    dme_gs_clear(device);
}

void dme_gs_enable(const dme_gs_device_t *device, int enable)
{
    dme_gs_update_control(device, DME_GS_CONTROL_ENABLE, enable);
}

void dme_gs_select_input(const dme_gs_device_t *device, dme_gs_input_t input)
{
    dme_gs_update_control(device, DME_GS_CONTROL_ADC_SELECT,
                          input == DME_GS_INPUT_ADC);
}

void dme_gs_enable_motion(const dme_gs_device_t *device, int enable)
{
    dme_gs_update_control(device, DME_GS_CONTROL_MOTION_ENABLE, enable);
}

void dme_gs_clear(const dme_gs_device_t *device)
{
    uint32_t control = dme_gs_read(device, DME_GS_REG_CONTROL);
    dme_gs_write(device, DME_GS_REG_CONTROL, control | DME_GS_CONTROL_CLEAR);
}

void dme_gs_set_dc_offset(const dme_gs_device_t *device, int16_t offset)
{
    dme_gs_write(device, DME_GS_REG_DC_OFFSET, (uint16_t)offset);
}

void dme_gs_set_env_shift(const dme_gs_device_t *device, uint32_t shift)
{
    if (shift > 15u)
        shift = 15u;
    dme_gs_write(device, DME_GS_REG_ENV_SHIFT, shift);
}

void dme_gs_set_thresholds(const dme_gs_device_t *device,
                           uint16_t high, uint16_t low)
{
    if (low > high)
        low = high;
    dme_gs_write(device, DME_GS_REG_THRESH_HIGH, high);
    dme_gs_write(device, DME_GS_REG_THRESH_LOW, low);
}

void dme_gs_set_width_window_us(const dme_gs_device_t *device,
                                uint32_t min_us, uint32_t max_us)
{
    dme_gs_write(device, DME_GS_REG_WIDTH_MIN, min_us * device->clocks_per_us);
    dme_gs_write(device, DME_GS_REG_WIDTH_MAX, max_us * device->clocks_per_us);
}

void dme_gs_set_spacing_window_us(const dme_gs_device_t *device,
                                  uint32_t min_us, uint32_t max_us)
{
    dme_gs_write(device, DME_GS_REG_SPACING_MIN, min_us * device->clocks_per_us);
    dme_gs_write(device, DME_GS_REG_SPACING_MAX, max_us * device->clocks_per_us);
}

void dme_gs_set_reply_delay_us(const dme_gs_device_t *device, uint32_t delay_us)
{
    dme_gs_write(device, DME_GS_REG_REPLY_DELAY, delay_us * device->clocks_per_us);
}

void dme_gs_set_latency_comp(const dme_gs_device_t *device, uint32_t cycles)
{
    dme_gs_write(device, DME_GS_REG_LATENCY_COMP, cycles);
}

/* Percentage of decoded interrogations that are answered, 0 to 100. */
void dme_gs_set_efficiency(const dme_gs_device_t *device, uint32_t percent)
{
    if (percent > 100u)
        percent = 100u;
    dme_gs_write(device, DME_GS_REG_EFFICIENCY, percent);
}

void dme_gs_set_range_mnm(const dme_gs_device_t *device, uint32_t mnm)
{
    dme_gs_set_range_cycles(device, dme_mnm_to_cycles(device->clocks_per_us, mnm));
}

uint32_t dme_gs_read_range_mnm(const dme_gs_device_t *device)
{
    return dme_cycles_to_mnm(device->clocks_per_us, dme_gs_read_range_cycles(device));
}

void dme_gs_set_range_cycles(const dme_gs_device_t *device, uint32_t cycles)
{
    dme_gs_write(device, DME_GS_REG_RANGE, cycles);
}

uint32_t dme_gs_read_range_cycles(const dme_gs_device_t *device)
{
    return dme_gs_read(device, DME_GS_REG_RANGE);
}

/* The model stops at these limits while motion is enabled. */
void dme_gs_set_range_limits_mnm(const dme_gs_device_t *device,
                                 uint32_t min_mnm, uint32_t max_mnm)
{
    dme_gs_write(device, DME_GS_REG_RANGE_MIN,
                 dme_mnm_to_cycles(device->clocks_per_us, min_mnm));
    dme_gs_write(device, DME_GS_REG_RANGE_MAX,
                 dme_mnm_to_cycles(device->clocks_per_us, max_mnm));
}

/* Positive is flying away from the station, negative towards it. */
void dme_gs_set_velocity_knots(const dme_gs_device_t *device, int32_t knots)
{
    dme_gs_write(device, DME_GS_REG_VELOCITY,
                 (uint32_t)dme_knots_to_velocity(device->clocks_per_us, knots));
}

uint32_t dme_gs_read_status(const dme_gs_device_t *device)
{
    return dme_gs_read(device, DME_GS_REG_STATUS);
}

uint32_t dme_gs_read_interrogations(const dme_gs_device_t *device)
{
    return dme_gs_read(device, DME_GS_REG_INTERROGATIONS);
}

uint32_t dme_gs_read_replies(const dme_gs_device_t *device)
{
    return dme_gs_read(device, DME_GS_REG_REPLIES);
}

uint32_t dme_gs_read_skipped(const dme_gs_device_t *device)
{
    return dme_gs_read(device, DME_GS_REG_SKIPPED);
}

uint32_t dme_gs_read_dropped(const dme_gs_device_t *device)
{
    return dme_gs_read(device, DME_GS_REG_DROPPED);
}

uint32_t dme_gs_read_rejected(const dme_gs_device_t *device)
{
    return dme_gs_read(device, DME_GS_REG_REJECTED);
}
