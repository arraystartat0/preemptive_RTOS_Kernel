# Preemptive RTOS Kernel — STM32F302R8

## What this project is

A preemptive real-time kernel written from scratch for the STM32F302R8, targeting a
Cortex-M4. No HAL, no CubeMX, no FreeRTOS. The point is to build the scheduler, the
context switcher, and the synchronization primitives by hand, then measure them.

**This is a learning project.** See "How to work with me" below — it changes what
kind of help is useful.

---

## Hardware

| | |
|---|---|
| Board | NUCLEO-F302R8 (MB1136) |
| MCU | STM32F302R8T6 — Cortex-M4F, 72 MHz max, 64 KB flash, **16 KB SRAM** |
| Debug probe | On-board ST-LINK/V2-1, SWD |
| User LED | LD2 on **PA5** |
| User button | B1 on PC13 |
| Virtual COM port | USART2 on **PA2 (TX) / PA3 (RX)**, via ST-LINK, default 115200 |

The 16 KB SRAM is the real constraint. Budget 512 B–1 KB per task stack — comfortable
for 6–8 tasks, but there is no room to be careless.

### F3-specific gotchas

- **GPIO ports are on AHB, not APB2.** It is `RCC->AHBENR |= RCC_AHBENR_GPIOAEN`.
  Nearly every STM32 tutorial online is written for F1/F4 and will say `APB2ENR`.
  This is the single most common wasted hour on this chip.
- The M4 has an FPU. Build **`-mfloat-abi=soft`** for Phases 0–7. Floating-point
  context save (lazy stacking, S16–S31, the FP bit in EXC_RETURN) is a second hard
  problem stacked on the first. Add it deliberately, later.
- Staying on default HSI (8 MHz) for now. PLL/clock-tree configuration is a separate
  rabbit hole and is not needed until much later.

---

## Environment

- **OS: Windows.** Commands run in `cmd.exe`. User home is `C:\Users\hitar`.
  GNU Make on Windows runs recipes through `cmd`, so recipes must use `del /Q` and
  `rmdir /S /Q`, never `rm -rf`.
- **Compiler: `arm-none-eabi-gcc` 15.2.Rel1 (Build arm-15.86), GCC 15.2.1, Dec 2025.**
  This is much newer than the tutorials and videos being followed. Consequences:
  - GCC 15 defaults to `-std=gnu23`. The Makefile pins `-std=gnu11` deliberately.
    Do not remove that pin without discussing it.
  - GCC 14+ made implicit function declarations, int-to-pointer conversion, and
    incompatible pointer types **hard errors**. Old copy-pasted startup code will
    fail to build. The errors are correct; the old code was always wrong.
  - Modern binutils warns about RWX segments on bare-metal linker scripts. Harmless
    on a Cortex-M with no MMU. Silenced with `-Wl,--no-warn-rwx-segments`.
- **OpenOCD: xPack 0.12.0+dev-02228-ge5888bda3 (2025-10-04).** Installed via
  `xpm install --global @xpack-dev-tools/openocd@latest`, binary at
  `C:\Users\hitar\AppData\Roaming\xPacks\@xpack-dev-tools\openocd\0.12.0-7.1\.content\bin`,
  added to user PATH. Note the version number is in that path — a future `xpm install`
  will silently break PATH.
- **`arm-none-eabi-gdb` 16.3.90.20250906-git** (Arm GNU Toolchain 15.2.Rel1), installed
  and on PATH alongside gcc at
  `C:\Program Files (x86)\Arm\GNU Toolchain mingw-w64-i686-arm-none-eabi\bin`.
- **GNU Make 4.4.1**, installed via `winget install ezwinports.make`, on PATH at
  `C:\Users\hitar\AppData\Local\Microsoft\WinGet\Packages\ezwinports.make_*\bin`.
  MSYS2 is still the better long-term option if a Unix-shaped shell becomes worth the detour.
- **Shell note:** commands often get run in PowerShell, not `cmd.exe`. The two differ in
  ways that bite — PowerShell's `ren` is an alias for `Rename-Item`, which **refuses
  case-only renames**; `curl` is an alias for `Invoke-WebRequest`, so native curl needs
  `curl.exe`. Prefer commands that work in both, or state which shell is assumed.

---

## Status

### Done

- Board verified alive. LD2 responds to reset, so the target is powered, out of reset,
  and executing from flash.
- **SWD link confirmed working.** OpenOCD output:
  `STLINK V2J36M26 (API v2)`, target voltage 3.26 V, `SWD DPIDR 0x2ba01477`,
  `Cortex-M4 r0p1 processor detected`, GDB server on port 3333.
- Hardware debug resources: **6 breakpoints, 4 watchpoints.** This ceiling gets hit
  in Phase 2. A watchpoint on the current-task pointer is the most valuable debugging
  tool in this whole project.
- Read UM1724 (Nucleo-64 board user manual) end to end.
- Project folder `preemptive_rtos_kernel` created; `git init` done.
- Full toolchain (gcc, gdb, make, OpenOCD) installed and verified on PATH.
- **CMSIS headers extracted and verified.** Final layout:

  ```
  cmsis/Include/core_cm4.h                             (+ cmsis_gcc.h, others)
  cmsis/Device/ST/STM32F3xx/Include/stm32f302x8.h
  cmsis/Device/ST/STM32F3xx/Include/stm32f3xx.h
  cmsis/Device/ST/STM32F3xx/Include/system_stm32f3xx.h
  ```

  Pulled as individual files from `STMicroelectronics/cmsis-device-f3` (branch
  `master`, `Include/`) rather than via the Cube submodule dance. The Cube clone is
  no longer in the project directory.

  Verified by compiling a throwaway TU against the real CFLAGS — not by eyeballing
  the tree. It resolved `stm32f3xx.h`, dispatched on `-DSTM32F302x8`, accepted
  `RCC->AHBENR |= RCC_AHBENR_GPIOAEN` and `GPIOA->MODER`, resolved `USB_LP_IRQn`,
  and confirmed `__FPU_USED == 0`.

  Two traps hit on the way, worth not repeating:

  - **Grabbed `stm32f303x8.h` first.** Wrong chip, and it would have *seemed* fine
    for a while: `SysTick_IRQn`/`PendSV_IRQn` are core exceptions and identical, and
    `USART2_IRQn` happens to share a slot. But F302x8 has 59 IRQ entries to F303x8's
    52, slot 18 is `ADC1_IRQn` not `ADC1_2_IRQn`, and 19/20 are the USB-shared CAN
    vectors. Would have detonated in Phase 4 when NVIC priorities start mattering.
  - **`system_stm32f3xx.h` is required even though `SystemInit` is never called.**
    `stm32f302x8.h` includes it unconditionally; without it the first compile dies.
    The *header* is all that's needed — ST's `system_stm32f3xx.c` from
    `Source/Templates/` was deliberately **not** kept, since it does full PLL setup
    and this project stays on default HSI until much later.

### In progress

**Phase 0 build plumbing.** Nothing written yet: `linker.ld` exists but is empty,
`src/` is empty, no `Makefile`, no `openocd.cfg`.

### Not started

Everything below. Next concrete task is **`openocd.cfg`, then `linker.ld`.**

---

## Target project layout

```
preemptive_rtos_kernel/
├── cmsis/
│   ├── Include/                     (core_cm4.h, cmsis_gcc.h, ...)
│   └── Device/ST/STM32F3xx/Include/ (stm32f302x8.h, stm32f3xx.h)
├── src/
│   ├── main.c
│   └── startup.s
├── build/          (gitignored)
├── linker.ld
├── Makefile
├── openocd.cfg
└── .gitignore      (build/ *.o *.elf *.bin *.map)
```

### openocd.cfg

```tcl
source [find interface/stlink.cfg]
transport select swd
source [find target/stm32f3x.cfg]
adapter speed 950
```

### Makefile (agreed starting point)

```make
TARGET  = firmware
BUILD   = build

CC      = arm-none-eabi-gcc
OBJCOPY = arm-none-eabi-objcopy
SIZE    = arm-none-eabi-size

CFLAGS  = -mcpu=cortex-m4 -mthumb -mfloat-abi=soft
CFLAGS += -std=gnu11 -O0 -g3
CFLAGS += -Wall -Wextra -Werror
CFLAGS += -ffunction-sections -fdata-sections
CFLAGS += -Icmsis/Include -Icmsis/Device/ST/STM32F3xx/Include
CFLAGS += -DSTM32F302x8

LDFLAGS  = -T linker.ld -nostdlib -Wl,--gc-sections
LDFLAGS += -Wl,-Map=$(BUILD)/$(TARGET).map -Wl,--no-warn-rwx-segments

SRCS = src/main.c src/startup.s
OBJS = $(addprefix $(BUILD)/,$(notdir $(SRCS:.c=.o)))
OBJS := $(OBJS:.s=.o)

all: $(BUILD)/$(TARGET).elf

$(BUILD)/%.o: src/%.c | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/%.o: src/%.s | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/$(TARGET).elf: $(OBJS)
	$(CC) $(OBJS) $(LDFLAGS) -o $@
	$(OBJCOPY) -O binary $@ $(BUILD)/$(TARGET).bin
	$(SIZE) $@

$(BUILD):
	mkdir $(BUILD)

flash: $(BUILD)/$(TARGET).elf
	openocd -c "program $< verify reset exit"

clean:
	rmdir /S /Q $(BUILD)
```

`-O0 -g3` is deliberate: at higher optimization levels GDB lies about variables, and
this project lives in GDB. `-Werror` from day one is deliberate too — an ignored
warning in a context switcher is a hard fault three weeks later.

`-nostdlib` holds until `printf` is wanted, at which point it becomes
`--specs=nano.specs --specs=nosys.specs` plus a hand-written `_write()`.

---

## Immediate next steps

1. Finish extracting CMSIS headers; move the Cube clone out; `git init`.
2. Read ST's `startup_stm32f302x8.s` and a reference `.ld` from the Cube package —
   **read, then close them.** Write originals.
3. Write `linker.ld`:
   - `MEMORY`: FLASH `0x08000000` len 64K, RAM `0x20000000` len 16K
   - `.isr_vector` **first** in FLASH — the chip fetches its initial SP from
     `0x08000000` and its reset vector from `0x08000004` before executing anything
   - `.text`, `.rodata` in FLASH
   - `.data` with `>RAM AT >FLASH` — two addresses for one section, the concept that
     makes linker scripts click. Export `_sidata`, `_sdata`, `_edata`
   - `.bss` bracketed by `_sbss`, `_ebss`
   - `_estack` at `0x20004000` (top of RAM)
   - `. = ALIGN(4);` around `.data` and `.bss` — startup copies word-at-a-time
4. Write `src/startup.s`: vector table (word 0 = `_estack`, word 1 = `Reset_Handler`),
   `.data` copy loop, `.bss` zero loop, branch to `main`. All other vectors `.weak`
   aliased to an infinite loop — but give `HardFault_Handler` its **own** loop so it
   can be breakpointed distinctly. It will be visited often.
   No `SystemInit` call; clock setup comes later.
5. Write `src/main.c`: enable GPIOA clock on **AHBENR**, PA5 to output via `MODER`,
   toggle `ODR` in a `volatile`-counter delay loop.
6. `make`, then `make flash`. This erases ST's demo firmware, which is disposable.
7. Connect GDB through OpenOCD, step through `main`.
8. Retarget `_write()` to USART2, get `printf` out the VCP.

Steps 6–8 (build, step, print) are Phase 0. Do not move to SysTick until all three
are frictionless.

---

## Phase plan

| Phase | Content | Est. |
|---|---|---|
| **0** | Toolchain, own startup/linker/Makefile, blinky on PA5, GDB, `printf` | weekend |
| **1** | SysTick at 1 kHz + tick counter, GPIO driver, `delay_ms()` spinning on ticks | weekend |
| **2** | **The context switch.** Two hardcoded tasks alternating on SysTick. No scheduler, no priorities. Prove a task can be left mid-execution and resumed exactly | the hard part |
| **3** | Task Control Blocks, stack initialization, a real round-robin scheduler, `os_start()` | 1 wk |
| **4** | Task states (READY/RUNNING/BLOCKED/SUSPENDED), `os_delay()` that yields instead of spinning, fixed-priority preemption, `os_yield()` | 1–2 wk |
| **5** | Critical sections (nestable), counting semaphore, mutex with **priority inheritance** — implement the inversion bug first, observe it on a scope, then fix it | 1–2 wk |
| **6** | Fixed-size message queues, blocking send/receive with timeouts, ISR-safe variants using a deferred-yield flag | 1 wk |
| **7** | Stack overflow detection (paint `0xDEADBEEF`, check watermarks at switch), fault handlers that decode CFSR/HFSR, static allocation only, `assert` | — |
| **8** | **Prove it.** GPIO toggle on task entry/exit captured on a logic analyzer; context switch latency in cycles via `DWT->CYCCNT`; worst-case interrupt latency published in the README; demo app: sensor task → queue → processing task → UART task with a mutex-protected resource | — |

Realistic timeline: 8–12 weeks part-time, most of the pain concentrated in Phase 2.
Several days staring at a hard fault before the first switch works is normal.

**Scope discipline:** this is not a general-purpose RTOS. It is a *correct* one with a
small feature set and measured timing numbers. Four primitives plus a latency table
beats twenty half-tested APIs.

---

## Prerequisites being learned alongside

- **ARMv7-M programmer's model** — register set, MSP vs PSP, CONTROL register
  (nPRIV bit 0, SPSEL bit 1, FPCA bit 2), thread vs handler mode, privileged vs not
- **Exception model** — hardware auto-stacking of 8 words
  (`xPSR, PC, LR, R12, R3, R2, R1, R0`), EXC_RETURN values (`0xFFFFFFF9` = thread/MSP,
  `0xFFFFFFFD` = thread/PSP), tail-chaining, why PendSV exists
- **AAPCS** — R0–R3/R12 caller-saved (hardware handles), **R4–R11 callee-saved (the
  switcher handles)**, 8-byte stack alignment
- **NVIC and critical sections** — priority grouping, why SysTick and PendSV sit at
  *lowest* priority, `PRIMASK` (`cpsid i`/`cpsie i`) before `BASEPRI`, `DSB`/`ISB`
  placement
- **Toolchain** — linker scripts, `.data`/`.bss` init, vector table placement,
  `__attribute__((naked))`, inline asm, `volatile`
- **Concepts** — race conditions, priority inversion and inheritance, deadlock,
  reentrancy

### Reference documents

- **UM1724** — Nucleo-64 board user manual. Already read.
- **RM0365** — STM32F302 reference manual. The one to live in: RCC, GPIO, USART
  chapters. Search it, don't read it. **Still needs downloading.**
- **Joseph Yiu, _The Definitive Guide to ARM Cortex-M3 and Cortex-M4 Processors_** —
  the exception model chapters.
- **ARMv7-M Architecture Reference Manual (DDI 0403)** — the authority when Yiu is
  ambiguous. Search only.
- **Miro Samek, "Modern Embedded Systems Programming" (YouTube)** — lessons ~22–27
  build essentially this kernel in public. Closest match to this project.
- **FreeRTOS `portable/GCC/ARM_CM4F/port.c` and `portmacro.h`** — read **after** the
  Phase 2 switcher works, not before, then diff approaches.

---

## How to work with me

The deliverable here is understanding, not a repository. A working kernel that I
didn't write teaches me nothing and is worthless in an interview.

**Write no code for me. This is a hard rule and it covers everything**, including what
an earlier version of this file exempted as "build plumbing":

- `linker.ld`
- `startup.s`
- `Makefile`, `openocd.cfg`, GDB configs, scripts
- The context switcher (PendSV handler, stack frame setup)
- The scheduler
- The synchronization primitives

The deliverable is understanding, not a repo. **Use the Socratic method.** Explain the
concept, tell me what the hardware requires and why, ask me what I think is happening,
review what I wrote, point at the bug. If I'm stuck, give me the next question to ask —
not the next line to type. I will type every line myself.

Explaining a directive's *semantics* (what `AT >FLASH` means, what `adapter speed`
controls) is the help I want. Emitting the finished file — even a "starting point" or
a snippet I'd only have to paste — is not, however boilerplate-ish it looks.

Still fine: throwaway test harnesses and verification scratch code that lives outside
the project tree and that I'm not meant to learn from, plus edits to this file.

**Fine to write for me:** build plumbing (Makefile, OpenOCD/GDB configs, scripts),
throwaway test harnesses, anything that isn't the pedagogical point.

Other standing preferences:

- **Never suggest STM32 HAL, CubeMX, or CubeIDE.** Using CMSIS headers for register
  definitions is not cheating; hand-writing peripheral offsets teaches nothing and
  introduces bugs. Writing my own startup, linker script, and scheduler *is* the
  project.
- Don't lower `-Werror`, `-O0`, or `-g3` to make something build. Fix the cause.
- When I paste a hard fault, walk me through decoding CFSR/HFSR and the stacked frame
  rather than guessing at the fix.
- Tell me when something I wrote is wrong, directly. Don't soften it.
- I'm on Windows/cmd — check shell assumptions before handing me a command.