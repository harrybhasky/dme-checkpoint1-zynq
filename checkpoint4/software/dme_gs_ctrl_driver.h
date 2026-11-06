#ifndef DME_GS_CTRL_DRIVER_H
#define DME_GS_CTRL_DRIVER_H

#include <stdint.h>

/* Driver for dme_gs_ctrl_axi4lite, which drives the inputs of the course
 * ground station IP (groundStation). */

typedef struct {
    uintptr_t base_address;
} dme_gsc_device_t;

enum {
    DME_GSC_REG_CONTROL = 0x00,
    DME_GSC_REG_DISTANCE = 0x04,     /* meters, 20 bits */
    DME_GSC_REG_SPEED = 0x08,        /* m/s, 8 bits */
    DME_GSC_REG_EFFICIENCY = 0x0C,   /* percent */
    DME_GSC_REG_PULSE_RATE = 0x10,   /* squitter, pulse pairs per second */
    DME_GSC_REG_DISTANCE_NOW = 0x14, /* station's current distance, meters */
    DME_GSC_REG_ERRORS = 0x18,
    DME_GSC_REG_PW_ERR_COUNT = 0x1C,
    DME_GSC_REG_PD_ERR_COUNT = 0x20
};

enum {
    DME_GSC_MOTION = 1u << 0,    /* i_var_distance */
    DME_GSC_AWAY = 1u << 1,      /* i_direction: 0 towards, 1 away */
    DME_GSC_SQUITTER = 1u << 2,  /* i_squitter_en */
    DME_GSC_JITTER = 1u << 3,    /* i_jitter_en */
    DME_GSC_IDENT = 1u << 4,     /* i_ident */
    DME_GSC_PULSE_EN = 1u << 5,  /* i_pulse_en */
    DME_GSC_CLEAR = 1u << 31     /* clear the error counters */
};

/* The station's one-way delay is floor(d * 334 * 33 / 32768) cycles for d
 * meters (delayModel.v), and its delay FIFO holds 131072 cycles. The
 * product also overflows 32 bits beyond this distance. */
#define DME_GSC_MAX_DISTANCE_M 389000u

void dme_gsc_init(dme_gsc_device_t *device, uintptr_t base_address);
void dme_gsc_set_flags(const dme_gsc_device_t *device, uint32_t flags);
uint32_t dme_gsc_get_flags(const dme_gsc_device_t *device);
void dme_gsc_set_distance_m(const dme_gsc_device_t *device, uint32_t meters);
uint32_t dme_gsc_distance_now_m(const dme_gsc_device_t *device);
void dme_gsc_set_speed_mps(const dme_gsc_device_t *device, uint32_t mps);
void dme_gsc_set_efficiency(const dme_gsc_device_t *device, uint32_t percent);
void dme_gsc_set_pulse_rate(const dme_gsc_device_t *device, uint32_t pps);
uint32_t dme_gsc_pw_errors(const dme_gsc_device_t *device);
uint32_t dme_gsc_pd_errors(const dme_gsc_device_t *device);

/* The station's one-way delay for a distance, in clock cycles. */
static inline uint32_t dme_gsc_one_way_cycles(uint32_t meters)
{
    return (uint32_t)(meters * 334u * 33u) / 32768u;
}

#endif
