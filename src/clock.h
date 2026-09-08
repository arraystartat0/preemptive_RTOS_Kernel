#pragma once

#define SYSCLK_HZ 8000000U // System clock frequency in Hz
#define HPRE_DIV 1U // AHB prescaler divisor
#define PPRE1_DIV 1U // APB1 prescaler divisor // becomes 2 after PLL change (APB1 <= 36MHz)

#define HCLK_HZ (SYSCLK_HZ / HPRE_DIV) // 8 MHz clock constant for SysTick timer
#define PCLK1_HZ (HCLK_HZ / PPRE1_DIV) // Peripheral clock 1 frequency

/* 
    safety asserts to ensure that the clock configuration is valid and within 
    the limits of the STM32F3 series microcontroller. 
    These assertions will trigger a compile-time error if the conditions are 
    not met, helping to catch configuration issues early in the development 
    process.
*/ 
_Static_assert(SYSCLK_HZ <= 72000000U, "SYSCLK_HZ exceeds 72 MHz");
_Static_assert(HCLK_HZ <= 72000000U, "HCLK_HZ exceeds 72 MHz");
_Static_assert(PCLK1_HZ <= 36000000U, "PCLK1_HZ exceeds 36 MHz");
_Static_assert(SYSCLK_HZ % HPRE_DIV == 0, "SYSCLK_HZ must be divisible by HPRE_DIV for proper HCLK operation");
_Static_assert(HCLK_HZ % PPRE1_DIV == 0, "HCLK_HZ must be divisible by PPRE1_DIV for proper PCLK1 operation");
