#ifndef DME_DRIVER_H
#define DME_DRIVER_H

#include <stdint.h>

typedef struct {
    uintptr_t base_address;
} dme_device_t;

enum {
    DME_REG_CONTROL = 0x00,
    DME_REG_PERIOD_US = 0x04,
    DME_REG_STATUS = 0x08,
    DME_REG_ELAPSED_US = 0x0C
};

enum {
    DME_CONTROL_ENABLE = 1u << 0,
    DME_CONTROL_CARRIER_ENABLE = 1u << 1,
    DME_STATUS_PULSE_ACTIVE = 1u << 0,
    DME_STATUS_GENERATOR_ACTIVE = 1u << 1
};

void dme_init(dme_device_t *device, uintptr_t base_address);
void dme_set_period_us(const dme_device_t *device, uint32_t period_us);
void dme_set_rate_hz(const dme_device_t *device, uint32_t rate_hz);
void dme_enable(const dme_device_t *device, int enable);
void dme_enable_carrier(const dme_device_t *device, int enable);
uint32_t dme_read_status(const dme_device_t *device);
uint32_t dme_read_elapsed_us(const dme_device_t *device);

#endif
