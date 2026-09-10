#include "systick.h"
#include "stm32f3xx.h" // dispatcher
#include "clock.h"

// reload value for SysTick timer
#define SYSTICK_RELOAD_VALUE ((HCLK_HZ / TICK_RATE_HZ) - 1)

_Static_assert(SYSTICK_RELOAD_VALUE <= 0xFFFFFF, "SysTick reload value exceeds 24 bits");
_Static_assert(SYSTICK_RELOAD_VALUE != 0, "SysTick reload value must be greater than zero");
_Static_assert(HCLK_HZ % TICK_RATE_HZ == 0, "HCLK_HZ must be divisible by TICK_RATE_HZ for proper SysTick operation");

static volatile uint32_t tick_count = 0;

void systick_init(void) {
    // Set the reload value for the SysTick timer
    SysTick->LOAD = SYSTICK_RELOAD_VALUE;
    // Reset the current value of the SysTick timer
    SysTick->VAL = 0;
    // NVIC priority for SysTick interrupt
    NVIC_SetPriority(SysTick_IRQn, (1UL << __NVIC_PRIO_BITS) - 1); // Set to lowest priority
    // Enable SysTick timer, its interrupt, and select processor clock (HCLK)
    SysTick->CTRL = SysTick_CTRL_ENABLE_Msk | SysTick_CTRL_TICKINT_Msk | SysTick_CTRL_CLKSOURCE_Msk;
}

void SysTick_Handler(void) {
    tick_count++; // Increment the global tick count on each SysTick interrupt
}

uint32_t systick_get_tick_count(void) {
    return tick_count;
}

bool is_systick_initialized(void) {
    return ((SysTick->CTRL & (SysTick_CTRL_ENABLE_Msk | SysTick_CTRL_TICKINT_Msk)) == (SysTick_CTRL_ENABLE_Msk | SysTick_CTRL_TICKINT_Msk)); // Check if SysTick timer is enabled
}
