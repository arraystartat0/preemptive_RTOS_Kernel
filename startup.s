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

        bl main
        b MainReturned
    .size Reset_Handler, .-Reset_Handler

    MainReturned:
            b MainReturned

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
        Section and type: Defines a new section .text.Rese
        with exectuable and allocated attributes, and declares 
        isr_handler as a function.
    */
    /* 
        The important thing here is that "isr_handler" is correctly spelled
        and that it is declared as a function. If you don't do this, the linker
        will not be able to find it and you will get an empty vector table with
        no exit code 0. KEEP protects a section from garbage collection; it does 
        not assert the section exists.
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
    .size g_pfnVectors, .-g_pfnVectors

