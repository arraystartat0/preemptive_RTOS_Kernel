#include "stm32f3xx.h" // dispatcher
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include "uart.h"
#include "systick.h"
#include "delay.h"

// golden variables to populate the .data and .bss sections
volatile uint32_t golden_data = 0xDEADBEEF; // This variable is initialized and should be in .data
volatile uint32_t golden_bss = 0; // explicitely initialized to zero, should be in .bss

// .data section boundary symbols defined by the linker script
extern uint32_t _sidata; // start address for the initialization values of the .data section
extern uint32_t _sdata;  // start address for the .data section
extern uint32_t _edata;  // end address for the .data section

// Standard GCC linker symbols for the .bss section boundary
extern uint8_t _sbss; // Start of .bss in RAM
extern uint8_t _ebss; // End of .bss in RAM

bool is_data_properly_initialized(void) {
    // Test 1: Fail if .data range is zero or inverted
    if (&_sdata >= &_edata) {
        return false; 
    }

    // Test 2: Axiom check (an axiom check is a logical assertion about the expected state)
    if (golden_data != 0xDEADBEEF) {
        return false; // Fail: The golden_data variable was not properly initialized
    }
    return true; // Success: The golden_data variable is properly initialized
}

bool is_bss_properly_zeroed(void) {
    if(golden_bss != 0) return false; // Fail: The golden_bss variable was not properly zeroed (non circular)

    // catches partial zero
    uint8_t *bss_ptr = &_sbss;  
    while (bss_ptr < &_ebss) {
        if (*bss_ptr++ != 0) {
            return false; // Fail: Found a non-zero byte in the .bss section
        }
    }

    return true; // Success: The entire .bss section is clean and zeroed
}

int main(void){
    // Verify that the startup code correctly cleared RAM for .bss
    if (!is_bss_properly_zeroed()) {
        while(1); 
    }

    if(!is_data_properly_initialized()) {
        while(1); 
    }

    RCC->AHBENR |= RCC_AHBENR_GPIOAEN; // Enable GPIOA clock
    /*
        MODER is one register covering all 16 pins of port A, 2 bits each.
        Read-modify-write so we touch only PA5's field. a plain assignment
        would clobber PA13/PA14 and nuke SWD.
        Two steps because |= can't turn a 1 into a 0: if the field currently
        holds 11 (analog), OR-ing 01 leaves it at 11.
    */
    GPIOA->MODER &= ~(GPIO_MODER_MODER5_Msk); // Clear mode bits for pin 5
    GPIOA->MODER |= (1 << GPIO_MODER_MODER5_Pos); // Set pin 5 to output mode
    
    uart2_init();
    systick_init();
    // todo: understand what this does: and why we couldn't just use printf earlier.
    setvbuf(stdout, NULL, _IONBF, 0);
    int counter = 0;
    printf("booted RTOS Kernel\r\n");    
    // Safely proceed with hardware init and application code
    while (1) {
        // Main loop
        counter += 1;
        printf("%d\r\n", counter);
        GPIOA->ODR ^= GPIO_ODR_5; // Toggle PA5 (LED)
        // Add a simple delay to make the LED toggle visible
        delay_ticks(MS_TO_TICKS(250)); // Delay for 250 milliseconds
    }
}
