/*
 * PC tests for dme_track.c, the range and speed tracker that runs on the
 * Zynq. Build and run:  ./checkpoint4/software/test/run_tests.sh
 *
 * Model mode (no arguments): a model of the course ground station's
 * behaviour generates the reply FIFO the aircraft would see, for each
 * project requirement, and checks the tracker's distance and speed:
 *
 *   - delay  = K + 2 * floor(d * 334 * 33 / 32768) +/- 7 cycles (delayModel.v)
 *   - motion = 1 km steps every floor(1000 / v) s (distanceModel.v)
 *   - efficiency: each interrogation answered with probability e
 *   - squitter: one pair every 1e8 / rate + 1 cycles (squitterGen.v), at a
 *     fixed phase. The station's output mux (pulseMux.v) sends one source at
 *     a time: a reply due while a squitter is being sent is lost, and after a
 *     reply nothing else is sent for 1e8 / rate cycles (replyGen.v DELAY).
 *   - station reply jitter: 1 to 255 extra cycles (replyGen.v)
 *
 * Replay mode: test_track replay <file> <block_cycles> <zero_delay>
 *   <max_delay> <expected_m> [<expected_speed_mps> <clock_hz>]
 * runs the tracker on "time delay" lines dumped by the Verilog testbench.
 */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../dme_track.h"

#define CLK 100e6
#define K   5168u

static int failures;
static uint64_t rng = 0x9E3779B97F4A7C15ull;

static uint32_t rnd(void)
{
    rng ^= rng << 13;
    rng ^= rng >> 7;
    rng ^= rng << 17;
    return (uint32_t)(rng >> 16);
}


static uint32_t one_way(uint32_t m) { return (uint32_t)(m * 334u * 33u) / 32768u; }

static void check(const char *what, double got, double lo, double hi)
{
    int ok = got >= lo && got <= hi;
    printf("%s  %s = %.2f (%.2f to %.2f)\n", ok ? "PASS" : "FAIL", what, got, lo, hi);
    if (!ok)
        failures++;
}

typedef struct {
    const char *name;
    uint32_t start_m;
    int      speed;        /* m/s, 0 static; sign: + away */
    uint32_t efficiency;   /* percent */
    uint32_t squitter_pps; /* 0 off */
    int      gs_jitter;
    uint32_t seconds;
    int      stop_at;      /* motion stops at this second (0 never) */
} scenario_t;

/* Station distance at time t (s): 1 km steps every floor(1000/|v|) s. */
static uint32_t station_distance(const scenario_t *s, double t)
{
    double moving_t = (s->stop_at && t > s->stop_at) ? s->stop_at : t;
    uint32_t k, steps;
    if (s->speed == 0)
        return s->start_m;
    k = 1000u / (uint32_t)abs(s->speed);
    steps = (uint32_t)(moving_t / k);
    return s->speed > 0 ? s->start_m + 1000u * steps : s->start_m - 1000u * steps;
}

static void run_scenario(const scenario_t *s)
{
    static dme_trk_t trk;
    dme_trk_config_t cfg;
    dme_trk_result_t res;
    const double period = CLK / 30.0;
    const uint32_t jitter_mask = 0xFFFF;
    const uint64_t sq_period = s->squitter_pps ? (uint64_t)(CLK / s->squitter_pps) + 1u : 0u;
    const uint64_t sq_busy = 701 + 501 + 701 + 501;          /* squitterGen valid */
    const uint64_t rp_busy = 701 + 501 + 701 + (s->squitter_pps ? (uint64_t)(CLK / s->squitter_pps) : 0u);
    uint64_t sq_phase = rnd() % 40001u;
    uint64_t t_tx = 1000, block_end = (uint64_t)CLK;
    uint64_t reply_busy_until = 0;
    uint32_t tx_in_block = 0, valid_blocks = 0, blocks = 0;
    double worst = 0.0, last_speed = 0.0;
    int last_speed_valid = 0, last_from_steps = 0;
    double expect_v = 0.0;

    printf("-- %s\n", s->name);
    dme_trk_default_config(&cfg);
    if (s->gs_jitter)
        cfg.gate = 160u;
    dme_trk_init(&trk, &cfg);

    while (block_end <= (uint64_t)(s->seconds * CLK)) {
        uint64_t next_tx = t_tx + (uint64_t)period + (rnd() & jitter_mask);
        double t_s = t_tx / CLK;
        uint32_t d = station_distance(s, t_s);
        uint32_t one = one_way(d);
        /* The station's reply leaves its mux at t_tx + K + one way - (the
         * downlink delay). The window up to the next interrogation is what
         * the aircraft records against this one. */
        uint64_t reply_out = t_tx + K - 168u + one; /* mux time (approx.) */
        int answered = (rnd() % 100u) < s->efficiency;

        /* A step during the round trip flushes the delay lines. */
        if (station_distance(s, (t_tx + K + 2.0 * one) / CLK) != d)
            answered = 0;

        if (answered && sq_period) {
            /* Lost if a squitter pair is being sent, or the station is
             * still in its post-reply hold-off. */
            uint64_t since = (reply_out + sq_period - sq_phase % sq_period) % sq_period;
            if (since < sq_busy || reply_out < reply_busy_until)
                answered = 0;
        }
        if (answered) {
            uint32_t delay = K + 2u * one + (rnd() % 15u) - 7u;
            if (s->gs_jitter)
                delay += 1u + rnd() % 255u - 128u; /* mean removed by calibration */
            reply_busy_until = reply_out + rp_busy;
            dme_trk_add(&trk, t_tx + delay, delay);
        }

        if (sq_period) {
            /* Squitter pairs sent from the mux in [t_tx, next_tx), arriving
             * one way later, recorded against this interrogation. */
            uint64_t first = t_tx > one ? t_tx - one : 0u;
            uint64_t j = (first > sq_phase) ? (first - sq_phase + sq_period - 1u) / sq_period : 0u;
            for (;; j++) {
                uint64_t sent = sq_phase + j * sq_period;
                uint64_t arrive = sent + one + 168u;
                if (arrive >= next_tx)
                    break;
                if (arrive < t_tx)
                    continue;
                if (sent >= reply_busy_until - rp_busy && sent < reply_busy_until)
                    continue; /* blocked by our reply */
                dme_trk_add(&trk, arrive, (uint32_t)(arrive - t_tx));
            }
        }

        tx_in_block++;
        t_tx = next_tx;
        if (t_tx >= block_end) {
            blocks++;
            if (dme_trk_end_block(&trk, tx_in_block, &res)) {
                double ref_t = 0.0;
                uint32_t ref;
                valid_blocks++;
                /* Compare with the station distance in the middle of the
                 * replies that made the peak. */
                ref_t = (block_end / CLK) - 0.5;
                ref = station_distance(s, ref_t);
                if (fabs(res.distance_m - ref) > 900.0)
                    ref = station_distance(s, ref_t + 0.5); /* step inside the block */
                if (fabs(res.distance_m - ref) > 900.0)
                    ref = station_distance(s, ref_t - 0.5);
                if (fabs(res.distance_m - ref) > worst)
                    worst = fabs(res.distance_m - ref);
            }
            last_speed_valid = res.speed_valid;
            last_speed = res.speed_mps;
            last_from_steps = res.speed_from_steps;
            if (s->seconds - block_end / CLK < 0.5 || (blocks % 10u) == 0u)
                printf("INFO  t=%2us %s %9.1f m  hits %2u/%2u of %3u  speed %s%.1f m/s (%s, %u steps)\n",
                       blocks, res.valid ? "dist" : "LOST",
                       res.distance_m, res.hits, tx_in_block, res.replies,
                       res.speed_valid ? "" : "n/a ", res.speed_mps,
                       res.speed_from_steps ? "steps" : "fit", res.steps);
            tx_in_block = 0;
            block_end += (uint64_t)CLK;
        }
    }

    check("blocks with a distance (%)", 100.0 * valid_blocks / blocks, 95.0, 100.0);
    check("worst distance error (m)", worst, 0.0, s->gs_jitter ? 120.0 : 8.0);
    if (s->speed != 0 && !s->stop_at) {
        expect_v = 1000.0 / (1000u / (uint32_t)abs(s->speed));
        if (s->speed < 0)
            expect_v = -expect_v;
        check("speed from step timing", last_speed_valid && last_from_steps, 1, 1);
        check("speed (m/s, + away)", last_speed, expect_v - fabs(expect_v) * 0.03,
              expect_v + fabs(expect_v) * 0.03);
    } else {
        check("speed (m/s)", last_speed_valid ? last_speed : 999.0, -2.0, 2.0);
    }
}

static int replay(int argc, char **argv)
{
    static dme_trk_t trk;
    dme_trk_config_t cfg;
    dme_trk_result_t res;
    FILE *f = fopen(argv[2], "r");
    uint64_t block = strtoull(argv[3], NULL, 10), block_end, t;
    double expect_m = atof(argv[6]), expect_v = 0.0, last_d = 0.0, last_v = 0.0;
    unsigned long long tt;
    unsigned d;
    uint32_t blocks = 0, valid = 0;
    int have_v = 0, v_valid = 0, steps = 0;

    if (!f) {
        perror(argv[2]);
        return 2;
    }
    dme_trk_default_config(&cfg);
    cfg.zero_delay = (uint32_t)strtoul(argv[4], NULL, 10);
    cfg.max_delay = (uint32_t)strtoul(argv[5], NULL, 10);
    if (argc > 8) {
        have_v = 1;
        expect_v = atof(argv[7]);
        cfg.clock_hz = atof(argv[8]);
    }
    dme_trk_init(&trk, &cfg);

    if (fscanf(f, "%llu %u", &tt, &d) != 2) {
        printf("FAIL  %s is empty\n", argv[2]);
        return 1;
    }
    block_end = (tt / block + 1u) * block;
    do {
        t = tt;
        while (t >= block_end) {
            dme_trk_end_block(&trk, 0, &res);
            blocks++;
            if (res.valid) {
                valid++;
                last_d = res.distance_m;
            }
            if (res.speed_valid) {
                v_valid = 1;
                last_v = res.speed_mps;
                steps = res.speed_from_steps;
            }
            printf("INFO  block %2u: %s %9.1f m  hits %2u of %3u  speed %s%.0f (%s)\n",
                   blocks, res.valid ? "dist" : "LOST", res.distance_m, res.hits,
                   res.replies, res.speed_valid ? "" : "n/a ", res.speed_mps,
                   res.speed_from_steps ? "steps" : "fit");
            block_end += block;
        }
        dme_trk_add(&trk, t, d);
    } while (fscanf(f, "%llu %u", &tt, &d) == 2);
    dme_trk_end_block(&trk, 0, &res);
    blocks++;
    if (res.valid) {
        valid++;
        last_d = res.distance_m;
    }
    fclose(f);

    /* Simulated time is compressed: blocks are 10 interrogations, so the
     * first one and one split by a step may have too few replies. */
    check("replay: blocks with a distance", valid, blocks - 2, blocks);
    check("replay: final distance (m)", last_d, expect_m - 12.0, expect_m + 12.0);
    if (have_v) {
        check("replay: speed from step timing", v_valid && steps, 1, 1);
        check("replay: speed", last_v, expect_v - fabs(expect_v) * 0.05,
              expect_v + fabs(expect_v) * 0.05);
    }
    return failures ? 1 : 0;
}

int main(int argc, char **argv)
{
    static const scenario_t scenarios[] = {
        /* name                                             start   v    eff sq    jit  s   stop */
        {"Req 1: static 100 km",                            100000,   0, 100,    0, 0, 20, 0},
        {"Req 1: static 389 km (station limit)",            389000,   0, 100,    0, 0, 10, 0},
        {"Req 2: towards at 200 m/s",                       150000,-200, 100,    0, 0, 40, 0},
        {"Req 2: away at 150 m/s (station: 166.7)",          50000, 150, 100,    0, 0, 40, 0},
        {"Req 3: towards at 100 m/s, 60% efficiency",       120000,-100,  60,    0, 0, 60, 0},
        {"Req 3: away at 250 m/s, 60% efficiency",           80000, 250,  60,    0, 0, 40, 0},
        {"Req 4: static, squitter 2500 pps",                100000,   0, 100, 2500, 0, 20, 0},
        {"Req 5: towards at 200 m/s, squitter 2500",        150000,-200, 100, 2500, 0, 40, 0},
        {"Req 5: away at 100 m/s, squitter 2500",            30000, 100, 100, 2500, 0, 60, 0},
        {"Req 6: towards 200 m/s, 60%, squitter 2500",      200000,-200,  60, 2500, 0, 40, 0},
        {"Req 6: away 250 m/s, 60%, squitter 2500",          20000, 250,  60, 2500, 0, 40, 0},
        {"Req 6: static, 60%, squitter 2500",               300000,   0,  60, 2500, 0, 20, 0},
        {"Station reply jitter, 60%, squitter, towards",    100000,-200,  60, 2500, 1, 40, 0},
        {"Motion stops: speed returns to 0",                100000, 200, 100, 2500, 0, 60, 20},
    };
    unsigned i;

    if (argc > 1 && strcmp(argv[1], "replay") == 0) {
        if (argc < 7) {
            fprintf(stderr, "usage: %s replay file block zero_delay max_delay expected_m "
                            "[expected_mps clock_hz]\n", argv[0]);
            return 2;
        }
        return replay(argc, argv);
    }

    for (i = 0; i < sizeof(scenarios) / sizeof(scenarios[0]); i++)
        run_scenario(&scenarios[i]);
    printf(failures ? "%d CHECK(S) FAILED\n" : "ALL TRACKER TESTS PASSED\n", failures);
    return failures ? 1 : 0;
}
