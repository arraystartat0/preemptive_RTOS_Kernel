# preemptive RTOS kernel

A preemptive real-time kernel written from scratch for the STM32F302R8 (Cortex-M4).

No HAL, no CubeMX, no FreeRTOS. The scheduler, the context switcher, and the
synchronization primitives are all hand-written against the ARMv7-M architecture and
CMSIS register definitions — then measured on hardware.

This is a learning project. The deliverable is a *correct* kernel with a small feature
set and real timing numbers, not a general-purpose RTOS.

---

## Hardware

| | |
|---|---|
| Board | NUCLEO-F302R8 (MB1136) |
| MCU | STM32F302R8T6 — Cortex-M4F, 72 MHz max, 64 KB flash, 16 KB SRAM |
| Clock | Default HSI, 8 MHz (no PLL configuration yet) |
| Debug probe | On-board ST-LINK/V2-1 over SWD |
| User LED | LD2 on PA5 |
| User button | B1 on PC13 |
| Virtual COM port | USART2 on PA2 (TX) / PA3 (RX), through ST-LINK, 115200 8N1 |

16 KB of SRAM is the binding constraint. At 512 B–1 KB per task stack that is a
comfortable 6–8 tasks, with no room to be careless.

Debug resources: 6 hardware breakpoints, 4 watchpoints.

---

## Layout

```
preemptive_rtos_kernel/
├── cmsis/
│   ├── Include/                     core_cm4.h, cmsis_gcc.h, ...
│   └── Device/ST/STM32F3xx/Include/ stm32f302x8.h, stm32f3xx.h, system_stm32f3xx.h
├── src/                             main.c, startup.s  (not written yet)
├── build/                           gitignored
├── linker.ld
├── openocd.cfg
├── Makefile                         (not written yet)
├── CLAUDE.md                        working notes, phase plan, detailed status
└── README.md
```

CMSIS headers are vendored as individual files from
[STMicroelectronics/cmsis-device-f3](https://github.com/STMicroelectronics/cmsis-device-f3)
(`Include/`, branch `master`) plus ARM's CMSIS Core. Only the headers — ST's
`system_stm32f3xx.c` is deliberately **not** included, since it performs full PLL setup
and this project stays on HSI until much later. `system_stm32f3xx.h` is still required:
`stm32f302x8.h` includes it unconditionally.

Using CMSIS headers for register definitions is not a shortcut being taken. Everything
above the register map — startup, linker script, scheduler, switcher — is written by hand.

---

## Toolchain

Everything below is on PATH and verified working.

| Tool | Version | Notes |
|---|---|---|
| `arm-none-eabi-gcc` | 15.2.Rel1 (GCC 15.2.1) | Arm GNU Toolchain, Dec 2025 |
| `arm-none-eabi-gdb` | 16.3.90.20250906-git | ships alongside gcc |
| OpenOCD | xPack 0.12.0+dev-02228-ge5888bda3 | installed via `xpm install --global @xpack-dev-tools/openocd@latest` |
| GNU Make | 4.4.1 | `winget install ezwinports.make` |

Host is Windows. Make runs its recipes through `cmd.exe`, so recipes use `del /Q` and
`rmdir /S /Q` rather than `rm -rf`.

### Toolchain gotchas worth knowing

- **GCC 15 defaults to `-std=gnu23`.** The build pins `-std=gnu11` on purpose.
- **GCC 14+ turned implicit function declarations, int-to-pointer conversion, and
  incompatible pointer types into hard errors.** Copy-pasted startup code from older
  tutorials will not build. The errors are correct; that code was always wrong.
- **Modern binutils warns about RWX segments.** Harmless on a Cortex-M with no MMU,
  silenced with `-Wl,--no-warn-rwx-segments`.
- **The OpenOCD install path contains its version number.** A future `xpm install` will
  silently break PATH.

### Build flags, and why

`-O0 -g3` — at higher optimization levels GDB lies about variable values, and this
project lives in GDB.

`-Werror` from day one — an ignored warning in a context switcher is a hard fault three
weeks later.

`-mfloat-abi=soft` — the M4 has an FPU, but floating-point context save (lazy stacking,
S16–S31, the FP bit in `EXC_RETURN`) is a second hard problem stacked on the first. It
gets added deliberately, after Phase 7.

`-nostdlib` — holds until `printf` is wanted, at which point it becomes
`--specs=nano.specs --specs=nosys.specs` plus a hand-written `_write()`.

---

## Build, flash, debug

```
make                 # -> build/firmware.elf, build/firmware.bin, size report
make flash           # program and reset via OpenOCD
make clean
```

Debug session, two terminals:

```
openocd                                    # reads ./openocd.cfg, GDB server on :3333
arm-none-eabi-gdb build/firmware.elf       # then: target extended-remote localhost:3333
```

`openocd.cfg` selects the ST-LINK interface, SWD transport, and the `stm32f3x` target,
then clocks SWCLK at 1 MHz — comfortably under the F_cpu/6 ceiling at 8 MHz HSI.

---

## Status

**Phase 0, in progress.**

Working:

- Board alive, SWD link confirmed — `STLINK V2J36M26 (API v2)`, target voltage 3.26 V,
  `SWD DPIDR 0x2ba01477`, `Cortex-M4 r0p1 processor detected`, GDB server up on 3333.
- Full toolchain installed and verified.
- CMSIS headers vendored and verified by compiling a throwaway translation unit against
  the real CFLAGS — resolved `stm32f3xx.h`, dispatched on `-DSTM32F302x8`, accepted
  `RCC->AHBENR |= RCC_AHBENR_GPIOAEN` and `GPIOA->MODER`, resolved `USB_LP_IRQn`,
  confirmed `__FPU_USED == 0`.
- `openocd.cfg` written.
- `linker.ld` written — memory regions, `.isr_vector` first in FLASH, `.data` with
  `>RAM AT> FLASH`, `.bss` bracketed by `_sbss`/`_ebss`, `_estack` at the top of RAM.

Next: `src/startup.s`, `src/main.c`, the `Makefile`, then blinky on PA5 and a GDB
single-step through `main`. Phase 0 is not done until build, step, and `printf` over the
VCP are all frictionless.

See [CLAUDE.md](CLAUDE.md) for detailed working notes.

---

## Roadmap

| Phase | Content | Est. |
|---|---|---|
| 0 | Toolchain, own startup/linker/Makefile, blinky on PA5, GDB, `printf` | weekend |
| 1 | SysTick at 1 kHz + tick counter, GPIO driver, `delay_ms()` spinning on ticks | weekend |
| 2 | **The context switch.** Two hardcoded tasks alternating on SysTick. No scheduler, no priorities. Prove a task can be left mid-execution and resumed exactly | the hard part |
| 3 | Task Control Blocks, stack initialization, round-robin scheduler, `os_start()` | 1 wk |
| 4 | Task states (READY/RUNNING/BLOCKED/SUSPENDED), yielding `os_delay()`, fixed-priority preemption, `os_yield()` | 1–2 wk |
| 5 | Nestable critical sections, counting semaphore, mutex with priority inheritance — reproduce the inversion bug on a scope first, then fix it | 1–2 wk |
| 6 | Fixed-size message queues, blocking send/receive with timeouts, ISR-safe variants using a deferred-yield flag | 1 wk |
| 7 | Stack overflow detection (paint `0xDEADBEEF`, watermark checks at switch), fault handlers that decode CFSR/HFSR, static allocation only, `assert` | — |
| 8 | **Prove it.** Logic-analyzer capture of task entry/exit, context switch latency in cycles via `DWT->CYCCNT`, worst-case interrupt latency published below, demo app | — |

Realistic timeline: 8–12 weeks part-time, with most of the pain concentrated in Phase 2.

---

## Measurements

Phase 8 deliverable. Nothing measured yet — this table is a placeholder and every row is
currently unfilled by design.

| Metric | Value | Method |
|---|---|---|
| Context switch latency | — | `DWT->CYCCNT` around PendSV |
| Worst-case interrupt latency | — | GPIO toggle, logic analyzer |
| Tick handler cost | — | `DWT->CYCCNT` |
| Per-task RAM overhead | — | `.map` file + TCB sizeof |

---

## F3-specific notes

- **GPIO ports are on AHB, not APB2.** It is `RCC->AHBENR |= RCC_AHBENR_GPIOAEN`. Nearly
  every STM32 tutorial online targets F1/F4 and says `APB2ENR`. This is the single most
  common wasted hour on this chip.
- **`stm32f303x8.h` is not a substitute for `stm32f302x8.h`.** It looks fine at first —
  `SysTick_IRQn` and `PendSV_IRQn` are core exceptions and identical, and `USART2_IRQn`
  happens to share a slot — but F302x8 has 59 IRQ entries to F303x8's 52, slot 18 is
  `ADC1_IRQn` not `ADC1_2_IRQn`, and 19/20 are the USB-shared CAN vectors. It detonates
  in Phase 4 when NVIC priorities start mattering.

---

## References

- **RM0365** — STM32F302 reference manual. RCC, GPIO, USART chapters. Search it, don't read it.
- **UM1724** — Nucleo-64 board user manual.
- **DDI 0403** — ARMv7-M Architecture Reference Manual. The authority. Search only.
- Joseph Yiu, *The Definitive Guide to ARM Cortex-M3 and Cortex-M4 Processors* — the exception model chapters.
- Miro Samek, *Modern Embedded Systems Programming* (YouTube), lessons ~22–27.
- FreeRTOS `portable/GCC/ARM_CM4F/port.c` — read **after** the Phase 2 switcher works, then diff approaches.
