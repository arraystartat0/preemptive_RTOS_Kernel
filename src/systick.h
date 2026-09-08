#pragma once
#include <stdint.h>
// This file contains the declarations for the SysTick timer functions and variables.
// SysTick is a system timer that can be used for generating periodic interrupts, measuring time intervals, and implementing delays.
// The tick rate of this kernel is 1000Hz, which means that the SysTick timer will generate an interrupt every 1 millisecond.

#define TICK_RATE_HZ 1000U // 1000Hz tick rate/ 1ms per tick

#define MS_PER_SECOND 1000U // Number of milliseconds in one second

/*
    Overflow: the multiply happens first, so (ms * TICK_RATE_HZ) + 999 must
    fit in 32 bits. That caps ms at (0xFFFFFFFF - 999) / 1000 = 4294966 ms,
    approx. 49.7 days. Cannot be checked at runtime: an overflow
    has already wrapped by the time you could look at the result.

    We use 999 instead of 1000 because it is a ceiling division,
    because for a ceiling division, we add D-1 to numerator before dividing 
    by D. Our D is 1000 in this case so it becomes 999. This works because
    we are using integer division, which truncates the result. By adding 999 to
    the numerator, we ensure that the result is rounded up to the nearest integer.

    For example at 100Hz, 10ms * 100 ticks/s = 1000, +999 -> 1999/1000 = 1 Tick 
    but +1000 -> 2000 / 1000 = 2 Ticks, which is incorrect.
*/
#define MS_TO_TICKS(ms) ((((ms) * TICK_RATE_HZ) + (MS_PER_SECOND - 1)) / MS_PER_SECOND) // Convert milliseconds to ticks
#define TICKS_TO_MS(ticks) (((ticks) * MS_PER_SECOND) / TICK_RATE_HZ) // Convert ticks to milliseconds

void systick_init(void);
uint32_t get_tick_count(void);
