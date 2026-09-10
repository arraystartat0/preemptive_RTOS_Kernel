#include "gpio.h"
#include <stdint.h> 

static uint32_t gpio_clock_mask(GPIO_TypeDef *port) {
    if (port == GPIOA) return RCC_AHBENR_GPIOAEN;
    else if (port == GPIOB) return RCC_AHBENR_GPIOBEN;
    else if (port == GPIOC) return RCC_AHBENR_GPIOCEN;
    else if (port == GPIOD) return RCC_AHBENR_GPIODEN;
    else if (port == GPIOF) return RCC_AHBENR_GPIOFEN;
    else {
        __BKPT(0); // Breakpoint for debugging if an invalid port is passed
    }
    return 0; // Return 0 for invalid port, though this should never be reached due to the breakpoint above
}

void gpio_init_output(GPIO_TypeDef *port, uint32_t pin) {
    // Implementation for initializing GPIO pin as output
    RCC->AHBENR |= gpio_clock_mask(port); // Enable clock for the GPIO port
    // TODO: understand these bitwise operations.
    // Clear the 2 bits for Pin
    port->MODER &= ~(3U << (pin * 2U)); 

    // Set the bits to 01 for output mode
    port->MODER |= (1U << (pin * 2U)); 
}

void gpio_write_pin(GPIO_TypeDef *port, uint32_t pin, GPIO_state state) {
    if (state == GPIO_HIGH) {
        port->BSRR = (1U << pin); // Set the pin high
    } else {
        port->BRR = (1U << pin); // Set the pin low
    }
}