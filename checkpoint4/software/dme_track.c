#include "dme_track.h"

#include <string.h>

/* The course station's delay model: floor(d * 334 * 33 / 32768) cycles one
 * way for d meters, so a round-trip cycle is 32768 / (334 * 33) / 2 m. */
#define GS_METERS_PER_RT_CYCLE (32768.0 / (334.0 * 33.0) / 2.0)

static double fabs_d(double x) { return x < 0.0 ? -x : x; }

void dme_trk_default_config(dme_trk_config_t *cfg)
{
    cfg->clock_hz = 100e6;
    cfg->meters_per_cycle = GS_METERS_PER_RT_CYCLE;
    cfg->zero_delay = 5168u;
    cfg->max_delay = 270000u;
    /* Our replies spread by +/-7 cycles (carrier phase). 32 keeps squitter
     * out. With the station's reply jitter (1 to 255 cycles) use 160. */
    cfg->gate = 32u;
    cfg->min_hits = 3u;
    cfg->min_fraction_pct = 15u;
    cfg->lost_blocks = 3u;
    cfg->max_step_m = 1500.0;
}

void dme_trk_reset_speed(dme_trk_t *trk)
{
    trk->fit_n = 0u;
    trk->fit_head = 0u;
    trk->step_n = 0u;
    trk->step_dir = 0;
}

void dme_trk_reset(dme_trk_t *trk)
{
    trk->n[0] = trk->n[1] = 0u;
    trk->cur = 0u;
    trk->dropped = 0u;
    trk->have_level = 0;
    trk->misses = 0u;
    dme_trk_reset_speed(trk);
}

void dme_trk_init(dme_trk_t *trk, const dme_trk_config_t *cfg)
{
    trk->cfg = *cfg;
    dme_trk_reset(trk);
}

void dme_trk_add(dme_trk_t *trk, uint64_t time, uint32_t delay)
{
    uint32_t c = trk->cur;

    if (delay > trk->cfg.max_delay)
        return;
    if (trk->n[c] >= DME_TRK_BLOCK_MAX) {
        trk->dropped++;
        return;
    }
    trk->buf[c][trk->n[c]].time = time;
    trk->buf[c][trk->n[c]].delay = delay;
    trk->n[c]++;
}

static void sort_u32(uint32_t *a, uint32_t n)
{
    uint32_t i, j;
    for (i = 1u; i < n; i++) {
        uint32_t v = a[i];
        for (j = i; j > 0u && a[j - 1u] > v; j--)
            a[j] = a[j - 1u];
        a[j] = v;
    }
}

/* Strongest delay in the current block. Returns the number of replies in it
 * and their mean delay and time. */
static uint32_t find_peak(dme_trk_t *trk, double *delay, double *time)
{
    static uint32_t peak[DME_TRK_BLOCK_MAX];
    const dme_trk_reply_t *r = trk->buf[trk->cur];
    uint32_t n = trk->n[trk->cur];
    uint32_t i, best = 0u, best_sum = 0u, np = 0u, hits = 0u, lo, hi, median;
    double sum_d = 0.0, sum_t = 0.0;

    memset(trk->bins, 0, sizeof(trk->bins));
    for (i = 0; i < n; i++) {
        uint32_t b = r[i].delay >> DME_TRK_BIN_SHIFT;
        if (b < DME_TRK_BINS && trk->bins[b] != 0xFFFFu)
            trk->bins[b]++;
    }
    for (i = 0; i + 1u < DME_TRK_BINS; i++) {
        uint32_t s = (uint32_t)trk->bins[i] + trk->bins[i + 1u];
        if (s > best_sum) {
            best_sum = s;
            best = i;
        }
    }
    if (best_sum == 0u)
        return 0u;

    lo = best << DME_TRK_BIN_SHIFT;
    hi = (best + 2u) << DME_TRK_BIN_SHIFT;
    for (i = 0; i < n; i++)
        if (r[i].delay >= lo && r[i].delay < hi)
            peak[np++] = r[i].delay;
    sort_u32(peak, np);
    median = peak[np / 2u];

    for (i = 0; i < n; i++) {
        uint32_t d = r[i].delay;
        uint32_t diff = d > median ? d - median : median - d;
        if (diff <= trk->cfg.gate) {
            sum_d += d;
            sum_t += (double)r[i].time;
            hits++;
        }
    }
    *delay = sum_d / hits;
    *time = sum_t / hits;
    return hits;
}

/* Time of the change from delay `from` to delay `to`, using the previous
 * and the current block: the split of the replies near either level, in
 * time order, with the fewest replies on the wrong side. */
static double step_time(const dme_trk_t *trk, double from, double to)
{
    const dme_trk_reply_t *blocks[2];
    uint32_t counts[2];
    uint32_t b, i, total_old = 0u, new_before = 0u, old_after;
    uint32_t best_cost = 0xFFFFFFFFu;
    double gate = trk->cfg.gate;
    double t_prev = -1.0, best_t = -1.0;

    blocks[0] = trk->buf[trk->cur ^ 1u];
    counts[0] = trk->n[trk->cur ^ 1u];
    blocks[1] = trk->buf[trk->cur];
    counts[1] = trk->n[trk->cur];

    for (b = 0; b < 2u; b++)
        for (i = 0; i < counts[b]; i++)
            if (fabs_d(blocks[b][i].delay - from) <= gate)
                total_old++;

    /* Split before each "new" reply: cost = new replies before it plus old
     * replies after it. */
    old_after = total_old;
    for (b = 0; b < 2u; b++) {
        for (i = 0; i < counts[b]; i++) {
            double d = blocks[b][i].delay;
            double t = (double)blocks[b][i].time;
            if (fabs_d(d - from) <= gate) {
                old_after--;
                t_prev = t;
            } else if (fabs_d(d - to) <= gate) {
                uint32_t cost = new_before + old_after;
                if (cost < best_cost) {
                    best_cost = cost;
                    best_t = t_prev < 0.0 ? t : (t_prev + t) / 2.0;
                }
                new_before++;
            }
        }
    }
    return best_t;
}

static void fit_add(dme_trk_t *trk, double t_s, double d_m)
{
    trk->fit_t[trk->fit_head] = t_s;
    trk->fit_d[trk->fit_head] = d_m;
    trk->fit_head = (trk->fit_head + 1u) % DME_TRK_FIT_POINTS;
    if (trk->fit_n < DME_TRK_FIT_POINTS)
        trk->fit_n++;
}

/* Least-squares slope of distance over time. */
static int fit_slope(const dme_trk_t *trk, double *mps)
{
    double st = 0.0, sd = 0.0, stt = 0.0, std = 0.0, t0, denom;
    uint32_t i, n = trk->fit_n;

    if (n < 3u)
        return 0;
    t0 = trk->fit_t[0];
    for (i = 0; i < n; i++) {
        double t = trk->fit_t[i] - t0;
        st += t;
        sd += trk->fit_d[i];
        stt += t * t;
        std += t * trk->fit_d[i];
    }
    denom = n * stt - st * st;
    if (denom <= 0.0)
        return 0;
    *mps = (n * std - st * sd) / denom;
    return 1;
}

static void step_add(dme_trk_t *trk, double t_s, double d_m, int dir)
{
    if (dir != trk->step_dir) {
        trk->step_n = 0u;
        trk->step_dir = dir;
    }
    if (trk->step_n == DME_TRK_STEPS) {
        memmove(&trk->step_t[0], &trk->step_t[1], (DME_TRK_STEPS - 1u) * sizeof(double));
        memmove(&trk->step_d[0], &trk->step_d[1], (DME_TRK_STEPS - 1u) * sizeof(double));
        trk->step_n--;
    }
    trk->step_t[trk->step_n] = t_s;
    trk->step_d[trk->step_n] = d_m;
    trk->step_n++;
}

static void speed(dme_trk_t *trk, double now_s, dme_trk_result_t *res)
{
    uint32_t n = trk->step_n;

    if (n >= 2u) {
        double span_t = trk->step_t[n - 1u] - trk->step_t[0];
        double span_d = trk->step_d[n - 1u] - trk->step_d[0];
        double interval = span_t / (n - 1u);
        double since = now_s - trk->step_t[n - 1u];

        if (since > 2.0 * interval + 2.0) {
            /* No step for over two intervals: the motion stopped or
             * slowed down. Start again from the slope fit. */
            trk->step_n = 0u;
        } else if (span_t > 0.0) {
            double v = span_d / span_t;
            double step = fabs_d(span_d) / (n - 1u);
            /* The next step has not come yet, so the speed is at most one
             * step over the time since the last one. */
            if (since > interval && step / since < fabs_d(v))
                v = v < 0.0 ? -step / since : step / since;
            res->speed_valid = 1;
            res->speed_from_steps = 1;
            res->speed_mps = v;
            res->steps = n;
            return;
        }
    }
    res->steps = trk->step_n;
    res->speed_from_steps = 0;
    res->speed_valid = fit_slope(trk, &res->speed_mps);
}

int dme_trk_end_block(dme_trk_t *trk, uint32_t interrogations,
                      dme_trk_result_t *res)
{
    const dme_trk_config_t *c = &trk->cfg;
    uint32_t n = trk->n[trk->cur], i, need;
    double delay = 0.0, time = 0.0, now_s = 0.0;
    uint32_t hits = find_peak(trk, &delay, &time);

    memset(res, 0, sizeof(*res));
    res->replies = n;
    res->dropped = trk->dropped;
    for (i = 0; i < n; i++)
        if ((double)trk->buf[trk->cur][i].time / c->clock_hz > now_s)
            now_s = (double)trk->buf[trk->cur][i].time / c->clock_hz;

    need = interrogations * c->min_fraction_pct / 100u;
    if (need < c->min_hits)
        need = c->min_hits;

    if (hits < need) {
        if (++trk->misses >= c->lost_blocks) {
            trk->have_level = 0;
            dme_trk_reset_speed(trk);
        }
        speed(trk, now_s, res);
        res->speed_valid = 0;
    } else {
        double meters = (delay - (double)c->zero_delay) * c->meters_per_cycle;

        res->valid = 1;
        res->hits = hits;
        res->delay = delay;
        res->distance_m = meters;
        trk->misses = 0u;

        if (trk->have_level) {
            double change = delay - trk->level;
            double change_m = change * c->meters_per_cycle;
            double step_min = 3.0 * c->gate < 200.0 ? 200.0 : 3.0 * c->gate;

            if (fabs_d(change_m) > c->max_step_m) {
                /* A new distance, not motion. */
                dme_trk_reset_speed(trk);
            } else if (fabs_d(change) > step_min) {
                double t = step_time(trk, trk->level, delay);
                if (t >= 0.0) {
                    res->step = 1;
                    res->step_time_s = t / c->clock_hz;
                    step_add(trk, res->step_time_s, meters, change > 0.0 ? 1 : -1);
                }
            }
        }
        trk->have_level = 1;
        trk->level = delay;
        fit_add(trk, time / c->clock_hz, meters);
        speed(trk, now_s, res);
    }

    trk->dropped = 0u;
    trk->cur ^= 1u;
    trk->n[trk->cur] = 0u;
    return res->valid;
}
