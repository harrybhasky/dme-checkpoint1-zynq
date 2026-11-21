#ifndef DME_RANGE_H
#define DME_RANGE_H

#include <stdint.h>

/*
 * Range conversions shared by the aircraft and the ground station.
 *
 * Distances are in milli-nautical miles (mNM). Ranges in hardware are
 * round-trip propagation delays in clock cycles: one nautical mile is
 * 2 * 1852 m / c = 12.355214 us there and back.
 */
#define DME_RT_PS_PER_NM 12355214ull

/* Interrogation pulse 1 to pulse 2 (400 us) plus the 50 us reply delay,
 * which is timed from the second interrogation pulse. */
#define DME_FIXED_DELAY_US 450u

static inline uint32_t dme_mnm_to_cycles(uint32_t clocks_per_us, uint32_t mnm)
{
    return (uint32_t)(((uint64_t)mnm * clocks_per_us * DME_RT_PS_PER_NM +
                       500000000ull) / 1000000000ull);
}

static inline uint32_t dme_cycles_to_mnm(uint32_t clocks_per_us, uint32_t cycles)
{
    uint64_t divisor = (uint64_t)clocks_per_us * DME_RT_PS_PER_NM;
    return (uint32_t)(((uint64_t)cycles * 1000000000ull + divisor / 2u) / divisor);
}

/* Range rate in Q16 round-trip cycles per millisecond. Positive knots are
 * flying away from the station. */
static inline int32_t dme_knots_to_velocity(uint32_t clocks_per_us, int32_t knots)
{
    int64_t scaled = (int64_t)knots * clocks_per_us * (int64_t)DME_RT_PS_PER_NM * 65536;
    int64_t divisor = 3600ll * 1000000000ll;
    return (int32_t)((scaled + (scaled < 0 ? -divisor / 2 : divisor / 2)) / divisor);
}

#endif
