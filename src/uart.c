#include "uart.h"
#include "stm32f3xx.h" // dispatcher
#include <sys/types.h>
#include "constants.h"

void uart2_init(void){
    RCC->APB1ENR |= RCC_APB1ENR_USART2EN; // Set bit 17 of RCC->APB1ENR
    GPIOA->MODER &= ~(GPIO_MODER_MODER2_Msk); // clear mode bits for pin 2
    GPIOA->MODER |= (2 << GPIO_MODER_MODER2_Pos); // set pin 2 to alternate function enable
    GPIOA->AFR[0] &= ~GPIO_AFRL_AFRL2_Msk; // clear bits 11:8
    GPIOA->AFR[0] |=  (7 << GPIO_AFRL_AFRL2_Pos); // AF7 = USART2
    USART2->BRR = clock_const / 115200; // baud rate register TODO: understand this derivation again.
    USART2->CR1 |= USART_CR1_TE; // enable transmitter
    USART2->CR1 |= USART_CR1_UE; // enable peripheral
}

void uart2_putc(char c){
    while(!(USART2->ISR & USART_ISR_TXE));
    USART2->TDR = c;
}

// todo: Understand what this does
int _write(int fd, const void *buf, __ssize_t size_t){
    for(int i = 0; i < size_t; i++){
        uart2_putc(((const char *)buf)[i]);
    }
    (void)fd;
    return size_t;
}