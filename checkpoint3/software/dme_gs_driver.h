#ifndef DME_GS_DRIVER_H
#define DME_GS_DRIVER_H

#include <stdint.h>

typedef struct {
    uintptr_t base_address;
    uint32_t clocks_per_us;
} dme_gs_device_t;

enum {
    DME_GS_REG_CONTROL = 0x00,
    DME_GS_REG_STATUS = 0x04,
    DME_GS_REG_DC_OFFSET = 0x08,
    DME_GS_REG_ENV_SHIFT = 0x0C,
    DME_GS_REG_THRESH_HIGH = 0x10,
    DME_GS_REG_THRESH_LOW = 0x14,
    DME_GS_REG_WIDTH_MIN = 0x18,
    DME_GS_REG_WIDTH_MAX = 0x1C,
    DME_GS_REG_SPACING_MIN = 0x20,
    DME_GS_REG_SPACING_MAX = 0x24,
    DME_GS_REG_TIMESTAMP = 0x28,
    DME_GS_REG_REPLY_DELAY = 0x2C,
    DME_GS_REG_LATENCY_COMP = 0x30,
    DME_GS_REG_RANGE = 0x34,
    DME_GS_REG_VELOCITY = 0x38,
    DME_GS_REG_RANGE_MIN = 0x3C,
    DME_GS_REG_RANGE_MAX = 0x40,
    DME_GS_REG_EFFICIENCY = 0x44,
    DME_GS_REG_INTERROGATIONS = 0x48,
    DME_GS_REG_REPLIES = 0x4C,
    DME_GS_REG_SKIPPED = 0x50,
    DME_GS_REG_DROPPED = 0x54,
    DME_GS_REG_REJECTED = 0x58
};

enum {
    DME_GS_CONTROL_ENABLE = 1u << 0,
    DME_GS_CONTROL_ADC_SELECT = 1u << 1,
    DME_GS_CONTROL_MOTION_ENABLE = 1u << 2,
    DME_GS_CONTROL_CLEAR = 1u << 31,
    DME_GS_STATUS_PULSE_ACTIVE = 1u << 0,
    DME_GS_STATUS_REPLY_ACTIVE = 1u << 1,
    DME_GS_STATUS_QUEUE_FULL = 1u << 2,
    DME_GS_STATUS_AT_LIMIT = 1u << 3
};

#define DME_GS_STATUS_QUEUE_COUNT(status) (((status) >> 8) & 0xFu)
#define DME_GS_STATUS_ENVELOPE(status)    ((status) >> 16)

#define DME_GS_DEFAULT_LATENCY_COMP 67u

typedef enum {
    DME_GS_INPUT_LOOPBACK = 0,
    DME_GS_INPUT_ADC = 1
} dme_gs_input_t;

void dme_gs_init(dme_gs_device_t *device, uintptr_t base_address,
                 uint32_t clock_hz);
void dme_gs_enable(const dme_gs_device_t *device, int enable);
void dme_gs_select_input(const dme_gs_device_t *device, dme_gs_input_t input);
void dme_gs_enable_motion(const dme_gs_device_t *device, int enable);
void dme_gs_clear(const dme_gs_device_t *device);

/* Interrogation receiver, same meaning as the dme_rx_* settings. */
void dme_gs_set_dc_offset(const dme_gs_device_t *device, int16_t offset);
void dme_gs_set_env_shift(const dme_gs_device_t *device, uint32_t shift);
void dme_gs_set_thresholds(const dme_gs_device_t *device,
                           uint16_t high, uint16_t low);
void dme_gs_set_width_window_us(const dme_gs_device_t *device,
                                uint32_t min_us, uint32_t max_us);
void dme_gs_set_spacing_window_us(const dme_gs_device_t *device,
                                  uint32_t min_us, uint32_t max_us);

/* Transponder timing */
void dme_gs_set_reply_delay_us(const dme_gs_device_t *device, uint32_t delay_us);
void dme_gs_set_latency_comp(const dme_gs_device_t *device, uint32_t cycles);
void dme_gs_set_efficiency(const dme_gs_device_t *device, uint32_t percent);

/* Distance model */
void dme_gs_set_range_mnm(const dme_gs_device_t *device, uint32_t mnm);
uint32_t dme_gs_read_range_mnm(const dme_gs_device_t *device);
void dme_gs_set_range_cycles(const dme_gs_device_t *device, uint32_t cycles);
uint32_t dme_gs_read_range_cycles(const dme_gs_device_t *device);
void dme_gs_set_range_limits_mnm(const dme_gs_device_t *device,
                                 uint32_t min_mnm, uint32_t max_mnm);
void dme_gs_set_velocity_knots(const dme_gs_device_t *device, int32_t knots);

uint32_t dme_gs_read_status(const dme_gs_device_t *device);
uint32_t dme_gs_read_interrogations(const dme_gs_device_t *device);
uint32_t dme_gs_read_replies(const dme_gs_device_t *device);
uint32_t dme_gs_read_skipped(const dme_gs_device_t *device);
uint32_t dme_gs_read_dropped(const dme_gs_device_t *device);
uint32_t dme_gs_read_rejected(const dme_gs_device_t *device);

#endif
