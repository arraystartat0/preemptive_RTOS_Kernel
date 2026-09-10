#pragma once
#include <stdint.h>
#include "stm32f3xx.h" //dispatcher

typedef enum {
    GPIO_HIGH = 1,
    GPIO_LOW = 0,
} GPIO_state;

/*
    initialize a GPIO pin as output
    @param port: pointer to the GPIO port
    @param pin: the pin number. This is an index 0-15, not a bitmask. For example, to initialize pin 5, pass 5 as the pin parameter.
*/
void gpio_init_output(GPIO_TypeDef *port, uint32_t pin);

/*
    write a value to a GPIO pin
    @param port: pointer to the GPIO port
    @param pin: the pin number. This is an index 0-15, not a bitmask. For example, to write to pin 5, pass 5 as the pin parameter.
    @param state: the state to write, High is 1, Low is 0
*/
void gpio_write_pin(GPIO_TypeDef *port, uint32_t pin, GPIO_state state);