/* 
    This file has 4 jobs
    - Lay down the vector table: word 0 = _estack, word 1 = Reset_Handler
    - Copy .data from _sidata to _sdata to e_data
    - Zero out .bss from _sbss to _ebss
    - Branch to main() after initialization
*/

/* 
    Syntax and CPU settings: specifies the syntax to be unified,
    sets the CPU to CORTEX-M4, and enables thumb mode instructions.
 */
    .syntax unified
    .cpu cortex-m4
    .thumb

/* 
    Section and type: Defines a new section .text.Reset_Handler
    with exectuable and allocated attributes, and declares 
    Reset_Handler as a function.
 */

    /* 
        two flags: 
        - "a" -> allocatable (it occupies address space at runtime) 
        without this the linked won't place it in a memory region at all. 
        - %progbits -> says it contains actual bytes in the file. 
        this is as opposed to %nobits which is what .bss is. 
    */
    .section .text.Reset_Handler,"ax",%progbits 
    .type Reset_Handler, %function

    .global Reset_Handler

    Reset_Handler:
        /* 
            Copy the data segment initializers from flash to SRAM
            _sidata is the start of the initialized data in flash
            _sdata is the start of the .data section in SRAM
            _edata is the end of the .data section in SRAM
        */
        
        /* loads the stack pointer with the add. of _estack */
        ldr sp,= _estack /* Set the stack pointer */

        ldr r0, =_sidata
        ldr r1, =_sdata
        ldr r2, =_edata

        movs r3, #0
        b LoopCopyDataInit

        /* 
            1. Load a word from source base + index into a scratch register
            2. Store that scratch register to destination base + index
            3. Add 4 to index to move to the next word
         */

    CopyDataInit:
        ldr r4, [r0, r3]
        str r4, [r1, r3]
        adds r3, r3, #4 

    LoopCopyDataInit:
        adds r4, r1, r3 /* adds rD, rN, rM: rD -> where result lands, rN, rM -> two values being added. */
        cmp r4, r2
        bcc CopyDataInit

        /* 
            Zero fill the .bss segment. The .bss segment is used for 
            uninitialized global and static variables. It is important 
            to zero it out before using it.
        */
        ldr r2, =_sbss
        ldr r3, =_ebss
        ldr r4, = 0

    /* Zero fill the .bss segment */

        /* Guard for the zero-length case: if _sbss == _ebss there is
           nothing to zero. Without this the store below would run once
           before the first test and write one word past _ebss. */
        cmp r2, r3
        bcs BSSDone /* TODO: need to understand how bcs works */

    ZeroFillBSS:
        str r4, [r2]
        adds r2, r2, #4
        cmp r2, r3
        bcc ZeroFillBSS

    BSSDone:
        bl main
        b MainReturned

    MainReturned:
            b MainReturned
    .size Reset_Handler, .-Reset_Handler

    /*
        Section and type: Defines a new section .text.Default_Handler
        and allocated attributes, and declares Default_Handler as a function.
     */

    .section .text.Default_Handler,"ax",%progbits
    .type Default_Handler, %function
    
    Default_Handler:
        Infinite_Loop:
            b Infinite_Loop
            .size Default_Handler, .-Default_Handler

    /* 
        Weak symbol declarations for exception handlers
     */
    .weak NMI_Handler
    .weak HardFault_Handler
    .weak MemManage_Handler
    .weak BusFault_Handler
    .weak UsageFault_Handler
    .weak SVC_Handler
    .weak DebugMon_Handler
    .weak PendSV_Handler
    .weak SysTick_Handler
    .weak WWDG_IRQHandler
    .weak PVD_IRQHandler
    .weak TAMP_STAMP_IRQHandler
    .weak RTC_WKUP_IRQHandler
    .weak FLASH_IRQHandler
    .weak RCC_IRQHandler
    .weak EXTI0_IRQHandler
    .weak EXTI1_IRQHandler
    .weak EXTI2_TSC_IRQHandler
    .weak EXTI3_IRQHandler
    .weak EXTI4_IRQHandler
    .weak DMA1_Channel1_IRQHandler
    .weak DMA1_Channel2_IRQHandler
    .weak DMA1_Channel3_IRQHandler
    .weak DMA1_Channel4_IRQHandler
    .weak DMA1_Channel5_IRQHandler
    .weak DMA1_Channel6_IRQHandler
    .weak DMA1_Channel7_IRQHandler
    .weak ADC1_IRQHandler
    .weak USB_HP_CAN_TX_IRQHandler
    .weak USB_LP_CAN_RX0_IRQHandler
    .weak CAN_RX1_IRQHandler
    .weak CAN_SCE_IRQHandler
    .weak EXTI9_5_IRQHandler
    .weak TIM1_BRK_TIM15_IRQHandler
    .weak TIM1_UP_TIM16_IRQHandler
    .weak TIM1_TRG_COM_TIM17_IRQHandler
    .weak TIM1_CC_IRQHandler
    .weak TIM2_IRQHandler
    .weak I2C1_EV_IRQHandler
    .weak I2C1_ER_IRQHandler
    .weak I2C2_EV_IRQHandler
    .weak I2C2_ER_IRQHandler
    .weak SPI2_IRQHandler
    .weak USART1_IRQHandler
    .weak USART2_IRQHandler
    .weak USART3_IRQHandler
    .weak EXTI15_10_IRQHandler
    .weak RTC_Alarm_IRQHandler
    .weak USBWakeUp_IRQHandler
    .weak SPI3_IRQHandler
    .weak TIM6_DAC_IRQHandler
    .weak COMP2_IRQHandler
    .weak COMP4_6_IRQHandler
    .weak I2C3_EV_IRQHandler
    .weak I2C3_ER_IRQHandler
    .weak USB_HP_IRQHandler
    .weak USB_LP_IRQHandler
    .weak USBWakeUp_RMP_IRQHandler
    .weak FPU_IRQHandler

    /* 
        Set the weak symbols to the default handler
     */
    .thumb_set NMI_Handler, Default_Handler
    .thumb_set MemManage_Handler, Default_Handler
    .thumb_set BusFault_Handler, Default_Handler
    .thumb_set UsageFault_Handler, Default_Handler
    .thumb_set SVC_Handler, Default_Handler
    .thumb_set DebugMon_Handler, Default_Handler
    .thumb_set PendSV_Handler, Default_Handler
    .thumb_set SysTick_Handler, Default_Handler
    .thumb_set WWDG_IRQHandler, Default_Handler
    .thumb_set PVD_IRQHandler, Default_Handler
    .thumb_set TAMP_STAMP_IRQHandler, Default_Handler
    .thumb_set RTC_WKUP_IRQHandler, Default_Handler
    .thumb_set FLASH_IRQHandler, Default_Handler
    .thumb_set RCC_IRQHandler, Default_Handler
    .thumb_set EXTI0_IRQHandler, Default_Handler
    .thumb_set EXTI1_IRQHandler, Default_Handler
    .thumb_set EXTI2_TSC_IRQHandler, Default_Handler
    .thumb_set EXTI3_IRQHandler, Default_Handler
    .thumb_set EXTI4_IRQHandler, Default_Handler
    .thumb_set DMA1_Channel1_IRQHandler, Default_Handler
    .thumb_set DMA1_Channel2_IRQHandler, Default_Handler
    .thumb_set DMA1_Channel3_IRQHandler, Default_Handler
    .thumb_set DMA1_Channel4_IRQHandler, Default_Handler
    .thumb_set DMA1_Channel5_IRQHandler, Default_Handler
    .thumb_set DMA1_Channel6_IRQHandler, Default_Handler
    .thumb_set DMA1_Channel7_IRQHandler, Default_Handler
    .thumb_set ADC1_IRQHandler, Default_Handler
    .thumb_set USB_HP_CAN_TX_IRQHandler, Default_Handler
    .thumb_set USB_LP_CAN_RX0_IRQHandler, Default_Handler
    .thumb_set CAN_RX1_IRQHandler, Default_Handler
    .thumb_set CAN_SCE_IRQHandler, Default_Handler
    .thumb_set EXTI9_5_IRQHandler, Default_Handler
    .thumb_set TIM1_BRK_TIM15_IRQHandler, Default_Handler
    .thumb_set TIM1_UP_TIM16_IRQHandler, Default_Handler
    .thumb_set TIM1_TRG_COM_TIM17_IRQHandler, Default_Handler
    .thumb_set TIM1_CC_IRQHandler, Default_Handler
    .thumb_set TIM2_IRQHandler, Default_Handler
    .thumb_set I2C1_EV_IRQHandler, Default_Handler
    .thumb_set I2C1_ER_IRQHandler, Default_Handler
    .thumb_set I2C2_EV_IRQHandler, Default_Handler
    .thumb_set I2C2_ER_IRQHandler, Default_Handler
    .thumb_set SPI2_IRQHandler, Default_Handler
    .thumb_set USART1_IRQHandler, Default_Handler
    .thumb_set USART2_IRQHandler, Default_Handler
    .thumb_set USART3_IRQHandler, Default_Handler
    .thumb_set EXTI15_10_IRQHandler, Default_Handler
    .thumb_set RTC_Alarm_IRQHandler, Default_Handler
    .thumb_set USBWakeUp_IRQHandler, Default_Handler
    .thumb_set SPI3_IRQHandler, Default_Handler
    .thumb_set TIM6_DAC_IRQHandler, Default_Handler
    .thumb_set COMP2_IRQHandler, Default_Handler
    .thumb_set COMP4_6_IRQHandler, Default_Handler
    .thumb_set I2C3_EV_IRQHandler, Default_Handler
    .thumb_set I2C3_ER_IRQHandler, Default_Handler
    .thumb_set USB_HP_IRQHandler, Default_Handler
    .thumb_set USB_LP_IRQHandler, Default_Handler
    .thumb_set USBWakeUp_RMP_IRQHandler, Default_Handler
    .thumb_set FPU_IRQHandler, Default_Handler

    /*
        Section and type: Defines a new section .text.HardFault_Handler
        and allocated attributes, and declares HardFault_Handler as a function.
     */

    .section .text.HardFault_Handler,"ax",%progbits
    .type HardFault_Handler, %function
    
    HardFault_Handler:
        hardfault_loop:
            b hardfault_loop
            .size HardFault_Handler, .-HardFault_Handler

    /* 
        The vector table gets its own section so linker.ld can force it to the
        very start of FLASH. "a" = allocatable, it occupies address space at
        runtime. %progbits = it contains real bytes in the image, %nobits = no bytes. 
        No "x" flag this is data, not code. Nothing ever branches into it.

        Why linker.ld wraps this in KEEP():
        LDFLAGS carries --gc-sections, so the linker discards any section that
        nothing reachable references. The roots of that reachability walk are
        ENTRY(Reset_Handler) and anything KEEP()'d. Nothing in this program
        references g_pfnVectors -- not one instruction. The table is read by the
        *hardware*, from a fixed physical address, and the linker has no model of
        that whatsoever. Without KEEP the table is collected as dead weight and
        the image ships with something other than _estack at 0x08000000.

        Note which way the dependency runs: KEEPing this section is also what
        transitively keeps Reset_Handler, and everything main() calls, alive.
     */
    .section .isr_vector,"a",%progbits
    .type g_pfnVectors, %object

    /* 
        The vector table is an array of pointers to the exception handlers.
        The first entry is the initial stack pointer, which is set to _estack.
        The second entry is the address of the Reset_Handler function.
        The rest of the entries are addresses of other exception handlers.
    */

    g_pfnVectors:
        .word _estack
        .word Reset_Handler
        .word NMI_Handler
        .word HardFault_Handler
        .word MemManage_Handler
        .word BusFault_Handler
        .word UsageFault_Handler
        .word 0
        .word 0 
        .word 0
        .word 0
        .word SVC_Handler
        .word DebugMon_Handler
        .word 0
        .word PendSV_Handler
        .word SysTick_Handler
        .word WWDG_IRQHandler
        .word PVD_IRQHandler               /*  1 */
        .word TAMP_STAMP_IRQHandler        /*  2 */
        .word RTC_WKUP_IRQHandler          /*  3 */
        .word FLASH_IRQHandler             /*  4 */
        .word RCC_IRQHandler               /*  5 */
        .word EXTI0_IRQHandler             /*  6 */
        .word EXTI1_IRQHandler             /*  7 */
        .word EXTI2_TSC_IRQHandler         /*  8 */
        .word EXTI3_IRQHandler             /*  9 */
        .word EXTI4_IRQHandler             /* 10 */
        .word DMA1_Channel1_IRQHandler     /* 11 */
        .word DMA1_Channel2_IRQHandler     /* 12 */
        .word DMA1_Channel3_IRQHandler     /* 13 */
        .word DMA1_Channel4_IRQHandler     /* 14 */
        .word DMA1_Channel5_IRQHandler     /* 15 */
        .word DMA1_Channel6_IRQHandler     /* 16 */
        .word DMA1_Channel7_IRQHandler     /* 17 */
        .word ADC1_IRQHandler              /* 18 */
        .word USB_HP_CAN_TX_IRQHandler     /* 19 */
        .word USB_LP_CAN_RX0_IRQHandler    /* 20 */
        .word CAN_RX1_IRQHandler           /* 21 */
        .word CAN_SCE_IRQHandler           /* 22 */
        .word EXTI9_5_IRQHandler           /* 23 */
        .word TIM1_BRK_TIM15_IRQHandler    /* 24 */
        .word TIM1_UP_TIM16_IRQHandler     /* 25 */
        .word TIM1_TRG_COM_TIM17_IRQHandler /* 26 */
        .word TIM1_CC_IRQHandler           /* 27 */
        .word TIM2_IRQHandler              /* 28 */
        .word 0                            /* 29 reserved */
        .word 0                            /* 30 reserved */
        .word I2C1_EV_IRQHandler           /* 31 */
        .word I2C1_ER_IRQHandler           /* 32 */
        .word I2C2_EV_IRQHandler           /* 33 */
        .word I2C2_ER_IRQHandler           /* 34 */
        .word 0                            /* 35 reserved */
        .word SPI2_IRQHandler              /* 36 */
        .word USART1_IRQHandler            /* 37 */
        .word USART2_IRQHandler            /* 38 */
        .word USART3_IRQHandler            /* 39 */
        .word EXTI15_10_IRQHandler         /* 40 */
        .word RTC_Alarm_IRQHandler         /* 41 */
        .word USBWakeUp_IRQHandler         /* 42 */
        .word 0                            /* 43 reserved */
        .word 0                            /* 44 reserved */
        .word 0                            /* 45 reserved */
        .word 0                            /* 46 reserved */
        .word 0                            /* 47 reserved */
        .word 0                            /* 48 reserved */
        .word 0                            /* 49 reserved */
        .word 0                            /* 50 reserved */
        .word SPI3_IRQHandler              /* 51 */
        .word 0                            /* 52 reserved */
        .word 0                            /* 53 reserved */
        .word TIM6_DAC_IRQHandler          /* 54 */
        .word 0                            /* 55 reserved */
        .word 0                            /* 56 reserved */
        .word 0                            /* 57 reserved */
        .word 0                            /* 58 reserved */
        .word 0                            /* 59 reserved */
        .word 0                            /* 60 reserved */
        .word 0                            /* 61 reserved */
        .word 0                            /* 62 reserved */
        .word 0                            /* 63 reserved */
        .word COMP2_IRQHandler             /* 64 */
        .word COMP4_6_IRQHandler           /* 65 */
        .word 0                            /* 66 reserved */
        .word 0                            /* 67 reserved */
        .word 0                            /* 68 reserved */
        .word 0                            /* 69 reserved */
        .word 0                            /* 70 reserved */
        .word 0                            /* 71 reserved */
        .word I2C3_EV_IRQHandler           /* 72 */
        .word I2C3_ER_IRQHandler           /* 73 */
        .word USB_HP_IRQHandler            /* 74 */
        .word USB_LP_IRQHandler            /* 75 */
        .word USBWakeUp_RMP_IRQHandler     /* 76 */
        .word 0                            /* 77 reserved */
        .word 0                            /* 78 reserved */
        .word 0                            /* 79 reserved */
        .word 0                            /* 80 reserved */
        .word FPU_IRQHandler               /* 81 */
    .size g_pfnVectors, .-g_pfnVectors
    /* self assert table if table not 392 bytes long */
    .if .-g_pfnVectors != 392
        .error "Vector table is not 392 bytes long" 
    .endif
