#ifndef DME_TRACK_H
#define DME_TRACK_H

#include <stdint.h>

/*
 * Range and speed tracker for the aircraft DME. Plain C with no hardware
 * access: main.c feeds it the reply FIFO, and test/test_track.c feeds it
 * modelled and simulated replies on a PC.
 *
 * Each block (one second on the board) it finds the delay that the most
 * replies agree on:
 *
 *   1. Histogram of the block's reply delays, 256-cycle bins. The strongest
 *      pair of adjacent bins is the reply delay. Squitter and other
 *      aircraft's replies do not move with our randomly jittered
 *      interrogations, so they spread over all bins; our replies all land
 *      in one.
 *   2. The median of that peak, then the mean of the replies within
 *      +/- gate cycles of it. That mean is the block's delay and distance.
 *
 * Speed: the course station moves the aircraft in 1 km steps
 * (distanceModel.v). When the delay changes between blocks, the replies of
 * this and the previous block are split, in time order, into "old level" and
 * "new level" at the point with the fewest misfits. That gives the time of
 * each step to within one interrogation period. Speed is the distance
 * between the first and last step of a run in the same direction divided by
 * the time between them. It is also limited to step / (time since the last
 * step), so it falls to zero when the motion stops. Before two steps are
 * seen, speed is the least-squares slope of the block distances.
 */

#define DME_TRK_BLOCK_MAX   1024u /* replies stored per block */
#define DME_TRK_BIN_SHIFT   8u    /* 256-cycle histogram bins */
#define DME_TRK_BINS        1100u /* covers 281600 cycles, beyond 389 km */
#define DME_TRK_FIT_POINTS  16u   /* block distances in the slope fit */
#define DME_TRK_STEPS       8u    /* steps kept for the speed */

typedef struct {
    uint64_t time;   /* cycles, when the reply arrived */
    uint32_t delay;  /* cycles from the interrogation */
} dme_trk_reply_t;

typedef struct {
    double   clock_hz;        /* 100e6 */
    double   meters_per_cycle;/* round-trip delay cycles to meters */
    uint32_t zero_delay;      /* K: delay at zero distance, cycles */
    uint32_t max_delay;       /* replies beyond this are ignored */
    uint32_t gate;            /* +/- cycles around the peak median */
    uint32_t min_hits;        /* fewest replies that make a peak */
    uint32_t min_fraction_pct;/* and at least this % of interrogations */
    uint32_t lost_blocks;     /* blocks without a peak before the level is dropped */
    double   max_step_m;      /* a bigger change is a new distance, not motion */
} dme_trk_config_t;

typedef struct {
    int      valid;           /* a peak was found */
    double   distance_m;
    double   delay;           /* mean delay of the peak, cycles */
    uint32_t hits;            /* replies in the peak */
    uint32_t replies;         /* replies in the block, within max_delay */
    uint32_t dropped;         /* replies not stored: block buffer full */
    int      step;            /* a step was found in this block */
    double   step_time_s;
    int      speed_valid;
    int      speed_from_steps;/* 1: step timing, 0: slope fit */
    double   speed_mps;       /* positive: flying away */
    uint32_t steps;           /* steps in the current run */
} dme_trk_result_t;

typedef struct {
    dme_trk_config_t cfg;

    dme_trk_reply_t buf[2][DME_TRK_BLOCK_MAX];
    uint32_t n[2];
    uint32_t cur;             /* index of the block being filled */
    uint32_t dropped;
    uint16_t bins[DME_TRK_BINS];

    int      have_level;
    double   level;           /* delay of the last valid block, cycles */
    uint32_t misses;

    double   fit_t[DME_TRK_FIT_POINTS];
    double   fit_d[DME_TRK_FIT_POINTS];
    uint32_t fit_n, fit_head;

    double   step_t[DME_TRK_STEPS];
    double   step_d[DME_TRK_STEPS];
    uint32_t step_n;
    int      step_dir;
} dme_trk_t;

/* Defaults for the course ground station at 100 MHz. */
void dme_trk_default_config(dme_trk_config_t *cfg);
void dme_trk_init(dme_trk_t *trk, const dme_trk_config_t *cfg);
/* Forget everything: after the distance is changed by hand. */
void dme_trk_reset(dme_trk_t *trk);
/* Forget the speed history only (speed or direction changed). */
void dme_trk_reset_speed(dme_trk_t *trk);
void dme_trk_add(dme_trk_t *trk, uint64_t time, uint32_t delay);
/* Ends the block. interrogations is the number sent during it (0 if
 * unknown). Returns res->valid. */
int dme_trk_end_block(dme_trk_t *trk, uint32_t interrogations,
                      dme_trk_result_t *res);

#endif
