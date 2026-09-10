#include "delay.h"
#include "systick.h" // for tick count and SysTick timer functions
#include "stm32f3xx.h" // dispatcher

void delay_ticks(uint32_t ticks) {
    if (ticks == 0) {
        return; // No delay needed for zero ticks
    }
    if (!is_systick_initialized()) {
        // If SysTick is not initialized, we cannot perform a delay
        __BKPT(0); // Trigger a breakpoint for debugging purposes
        while(1) {
            // Infinite loop to halt execution
        }
    }
    uint32_t start_tick = systick_get_tick_count(); // Get the current value of the SysTick timer
    uint32_t elapsed_ticks = 0; // Initialize elapsed ticks to zero

    while (elapsed_ticks < (ticks + 1)) {
        uint32_t current_tick = systick_get_tick_count(); // Get the current value of the SysTick timer
        elapsed_ticks = current_tick - start_tick; // Calculate the number of ticks that have elapsed

    }
}