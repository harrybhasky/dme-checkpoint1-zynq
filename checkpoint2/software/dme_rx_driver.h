#ifndef DME_RX_DRIVER_H
#define DME_RX_DRIVER_H

#include <stdint.h>

typedef struct {
    uintptr_t base_address;
    uint32_t clocks_per_us;
} dme_rx_device_t;

enum {
    DME_RX_REG_CONTROL = 0x00,
    DME_RX_REG_STATUS = 0x04,
    DME_RX_REG_DC_OFFSET = 0x08,
    DME_RX_REG_ENV_SHIFT = 0x0C,
    DME_RX_REG_THRESH_HIGH = 0x10,
    DME_RX_REG_THRESH_LOW = 0x14,
    DME_RX_REG_WIDTH_MIN = 0x18,
    DME_RX_REG_WIDTH_MAX = 0x1C,
    DME_RX_REG_SPACING_MIN = 0x20,
    DME_RX_REG_SPACING_MAX = 0x24,
    DME_RX_REG_TIMESTAMP = 0x28,
    DME_RX_REG_PAIR_FIFO = 0x2C,
    DME_RX_REG_PAIR_COUNT = 0x30,
    DME_RX_REG_PULSE_COUNT = 0x34,
    DME_RX_REG_REJECT_COUNT = 0x38,
    DME_RX_REG_LAST_WIDTH = 0x3C,
    DME_RX_REG_LAST_SPACING = 0x40
};

enum {
    DME_RX_CONTROL_ENABLE = 1u << 0,
    DME_RX_CONTROL_ADC_SELECT = 1u << 1,
    DME_RX_CONTROL_IRQ_ENABLE = 1u << 2,
    DME_RX_CONTROL_CLEAR = 1u << 31,
    DME_RX_STATUS_PULSE_ACTIVE = 1u << 0,
    DME_RX_STATUS_FIFO_EMPTY = 1u << 1,
    DME_RX_STATUS_FIFO_FULL = 1u << 2,
    DME_RX_STATUS_FIFO_OVERFLOW = 1u << 3
};

#define DME_RX_STATUS_FIFO_COUNT(status) (((status) >> 8) & 0x1Fu)
#define DME_RX_STATUS_ENVELOPE(status)   ((status) >> 16)

typedef enum {
    DME_RX_INPUT_LOOPBACK = 0,
    DME_RX_INPUT_ADC = 1
} dme_rx_input_t;

void dme_rx_init(dme_rx_device_t *device, uintptr_t base_address,
                 uint32_t clock_hz);
void dme_rx_enable(const dme_rx_device_t *device, int enable);
void dme_rx_enable_irq(const dme_rx_device_t *device, int enable);
void dme_rx_select_input(const dme_rx_device_t *device, dme_rx_input_t input);
void dme_rx_clear(const dme_rx_device_t *device);

void dme_rx_set_dc_offset(const dme_rx_device_t *device, int16_t offset);
void dme_rx_set_env_shift(const dme_rx_device_t *device, uint32_t shift);
void dme_rx_set_thresholds(const dme_rx_device_t *device,
                           uint16_t high, uint16_t low);
void dme_rx_set_width_window_us(const dme_rx_device_t *device,
                                uint32_t min_us, uint32_t max_us);
void dme_rx_set_spacing_window_us(const dme_rx_device_t *device,
                                  uint32_t min_us, uint32_t max_us);

uint32_t dme_rx_read_status(const dme_rx_device_t *device);
uint32_t dme_rx_read_timestamp(const dme_rx_device_t *device);
int dme_rx_pop_pair(const dme_rx_device_t *device, uint32_t *timestamp);
uint32_t dme_rx_read_pair_count(const dme_rx_device_t *device);
uint32_t dme_rx_read_pulse_count(const dme_rx_device_t *device);
uint32_t dme_rx_read_reject_count(const dme_rx_device_t *device);
uint32_t dme_rx_read_last_width(const dme_rx_device_t *device);
uint32_t dme_rx_read_last_spacing(const dme_rx_device_t *device);
uint32_t dme_rx_cycles_to_us(const dme_rx_device_t *device, uint32_t cycles);

#endif
