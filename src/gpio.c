#include "gpio.h"
#include <stdint.h> 
#include <stdbool.h>

static uint32_t gpio_clock_mask(GPIO_TypeDef *port) {
    if (port == GPIOA) return RCC_AHBENR_GPIOAEN;
    else if (port == GPIOB) return RCC_AHBENR_GPIOBEN;
    else if (port == GPIOC) return RCC_AHBENR_GPIOCEN;
    else if (port == GPIOD) return RCC_AHBENR_GPIODEN;
    else if (port == GPIOF) return RCC_AHBENR_GPIOFEN;
    else {
        __BKPT(0); // Breakpoint for debugging if an invalid port is passed
        while(1) {
            // Infinite loop to halt execution
        }
    }
}

static bool check_valid_pin(uint32_t pin) {
    /* 
        pin 0-15 available, derived by 2 bits per pin in
        MODER register = 16 fields, indices 0-15 since each field
        is 2 bits wide.
    */
    if (pin > 15U) {
        return false; // Pin is invalid
    }
    return true; // Pin is valid
}

void gpio_init_output(GPIO_TypeDef *port, uint32_t pin) {
    
    if (!check_valid_pin(pin)) {
        // redundant BKPT check and while will be replaced with assert in another phase.
        __BKPT(0); // Breakpoint for debugging if an invalid pin number is passed
        while(1) {
            // Infinite loop to halt execution
        }
    }
    // Initializing GPIO pin as output
    RCC->AHBENR |= gpio_clock_mask(port);
    __DSB(); // Data Synchronization Barrier to ensure the clock is enabled before proceeding

    // TODO: understand these bitwise operations.
    // Clear the 2 bits for Pin
    port->MODER &= ~(3U << (pin * 2U)); 

    // Set the bits to 01 for output mode
    port->MODER |= (1U << (pin * 2U)); 

    /*
        TODO: change speed by port->OSPEEDR |= (3U << (pin * 2U)); for 
        phase 8 when using logic analyzer. 
        also understand the bit setting since different from MODER.
    */
    port->OSPEEDR &= ~(3U << (pin * 2U)); // Clear speed bits
    port->PUPDR &= ~(3U << (pin * 2U)); // Clear pull-up/pull-down bits
    port->OTYPER &= ~(1U << (pin)); // Clear output type bit (0 for push-pull)
}

void gpio_write_pin(GPIO_TypeDef *port, uint32_t pin, GPIO_state state) {
    if (!check_valid_pin(pin)) {
        __BKPT(0); // Breakpoint for debugging if an invalid pin number is passed
        while(1) {
            // Infinite loop to halt execution
        }
    }

    if (state == GPIO_HIGH) {
        port->BSRR = (1U << pin); // Set the pin high
    } else {
        port->BRR = (1U << pin); // Set the pin low
    }
}