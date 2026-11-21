#include "dme_gs_ctrl_driver.h"

static inline void dme_gsc_write(const dme_gsc_device_t *device,
                                 uint32_t offset, uint32_t value)
{
    *(volatile uint32_t *)(device->base_address + offset) = value;
}

static inline uint32_t dme_gsc_read(const dme_gsc_device_t *device,
                                    uint32_t offset)
{
    return *(volatile uint32_t *)(device->base_address + offset);
}

void dme_gsc_init(dme_gsc_device_t *device, uintptr_t base_address)
{
    device->base_address = base_address;

    /* Static aircraft, every interrogation answered, no squitter. */
    dme_gsc_set_flags(device, DME_GSC_PULSE_EN | DME_GSC_CLEAR);
    dme_gsc_set_speed_mps(device, 0u);
    dme_gsc_set_efficiency(device, 100u);
    dme_gsc_set_pulse_rate(device, 2500u);
    dme_gsc_set_distance_m(device, 0u);
}

void dme_gsc_set_flags(const dme_gsc_device_t *device, uint32_t flags)
{
    dme_gsc_write(device, DME_GSC_REG_CONTROL, flags);
}

uint32_t dme_gsc_get_flags(const dme_gsc_device_t *device)
{
    return dme_gsc_read(device, DME_GSC_REG_CONTROL);
}

void dme_gsc_set_distance_m(const dme_gsc_device_t *device, uint32_t meters)
{
    if (meters > DME_GSC_MAX_DISTANCE_M)
        meters = DME_GSC_MAX_DISTANCE_M;
    dme_gsc_write(device, DME_GSC_REG_DISTANCE, meters);
}

uint32_t dme_gsc_distance_now_m(const dme_gsc_device_t *device)
{
    return dme_gsc_read(device, DME_GSC_REG_DISTANCE_NOW);
}

void dme_gsc_set_speed_mps(const dme_gsc_device_t *device, uint32_t mps)
{
    dme_gsc_write(device, DME_GSC_REG_SPEED, mps > 255u ? 255u : mps);
}

void dme_gsc_set_efficiency(const dme_gsc_device_t *device, uint32_t percent)
{
    dme_gsc_write(device, DME_GSC_REG_EFFICIENCY, percent);
}

void dme_gsc_set_pulse_rate(const dme_gsc_device_t *device, uint32_t pps)
{
    dme_gsc_write(device, DME_GSC_REG_PULSE_RATE, pps);
}

uint32_t dme_gsc_pw_errors(const dme_gsc_device_t *device)
{
    return dme_gsc_read(device, DME_GSC_REG_PW_ERR_COUNT);
}

uint32_t dme_gsc_pd_errors(const dme_gsc_device_t *device)
{
    return dme_gsc_read(device, DME_GSC_REG_PD_ERR_COUNT);
}
