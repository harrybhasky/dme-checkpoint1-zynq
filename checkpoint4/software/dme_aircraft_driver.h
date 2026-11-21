#ifndef DME_AIRCRAFT_DRIVER_H
#define DME_AIRCRAFT_DRIVER_H

#include <stdint.h>

/* Driver for dme_aircraft_axi4lite: interrogator TX, reply receiver and the
 * reply-delay FIFO. All times are 100 MHz clock cycles. */

typedef struct {
    uintptr_t base_address;
    uint32_t clock_hz;
} dme_ac_device_t;

enum {
    DME_AC_REG_CONTROL = 0x00,
    DME_AC_REG_STATUS = 0x04,
    DME_AC_REG_TX_PERIOD = 0x08,
    DME_AC_REG_TX_JITTER = 0x0C,
    DME_AC_REG_ENV_SHIFT = 0x10,
    DME_AC_REG_THRESH_HIGH = 0x14,
    DME_AC_REG_THRESH_LOW = 0x18,
    DME_AC_REG_WIDTH_MIN = 0x1C,
    DME_AC_REG_WIDTH_MAX = 0x20,
    DME_AC_REG_SPACING_MIN = 0x24,
    DME_AC_REG_SPACING_MAX = 0x28,
    DME_AC_REG_TIMESTAMP = 0x2C,
    DME_AC_REG_TX_TIMESTAMP = 0x30,
    DME_AC_REG_TX_COUNT = 0x34,
    DME_AC_REG_REPLY_DELAY = 0x38,
    DME_AC_REG_REPLY_TIME = 0x3C, /* reading it pops the FIFO */
    DME_AC_REG_REPLY_COUNT = 0x40,
    DME_AC_REG_PULSE_COUNT = 0x44,
    DME_AC_REG_REJECT_COUNT = 0x48,
    DME_AC_REG_LAST_WIDTH = 0x4C,
    DME_AC_REG_LAST_SPACING = 0x50,
    DME_AC_REG_MAX_DELAY = 0x54,   /* range gate, cycles */
    DME_AC_REG_GATED_COUNT = 0x58  /* pairs beyond the range gate */
};

enum {
    DME_AC_CONTROL_TX_ENABLE = 1u << 0,
    DME_AC_CONTROL_RX_ENABLE = 1u << 1,
    DME_AC_CONTROL_IRQ_ENABLE = 1u << 2,
    DME_AC_CONTROL_CLEAR = 1u << 31,
    DME_AC_STATUS_RX_PULSE = 1u << 0,
    DME_AC_STATUS_FIFO_EMPTY = 1u << 1,
    DME_AC_STATUS_FIFO_FULL = 1u << 2,
    DME_AC_STATUS_FIFO_OVERFLOW = 1u << 3
};

void dme_ac_init(dme_ac_device_t *device, uintptr_t base_address,
                 uint32_t clock_hz);
void dme_ac_enable(const dme_ac_device_t *device, int tx, int rx);
/* Clears the counters, the reply FIFO and the interrogation history. */
void dme_ac_clear(const dme_ac_device_t *device);
void dme_ac_set_rate_hz(const dme_ac_device_t *device, uint32_t pairs_per_s);
/* Random extra delay of 0 to jitter_mask cycles before each interrogation. */
void dme_ac_set_jitter_mask(const dme_ac_device_t *device, uint32_t jitter_mask);

/* Pairs later than max_delay cycles after the interrogation are not stored
 * in the reply FIFO (squitter between interrogations). */
void dme_ac_set_max_delay(const dme_ac_device_t *device, uint32_t max_delay);

/* Pops the oldest reply. delay is in cycles from the start of the
 * interrogation it answers, time is when its first pulse arrived. Returns 0
 * when the FIFO is empty. */
int dme_ac_pop_reply(const dme_ac_device_t *device, uint32_t *delay,
                     uint32_t *time);

uint32_t dme_ac_read(const dme_ac_device_t *device, uint32_t offset);
void dme_ac_write(const dme_ac_device_t *device, uint32_t offset,
                  uint32_t value);

#endif
