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
├── src/
│   ├── clock.h                      SYSCLK/HPRE/PPRE1 inputs; HCLK/PCLK1 derived
│   ├── delay.c/.h                   delay_ticks() — spins on the tick counter
│   ├── gpio.c                       empty — Phase 1 step 3
│   ├── main.c                       .data/.bss acceptance checks, blinky, printf loop
│   ├── startup.s                    vector table, .data copy, .bss zero
│   ├── systick.c/.h                 1 kHz tick, tick counter, ms<->tick conversions
│   └── uart.c/.h                    USART2 init, putc, _write() retarget
├── build/                           gitignored
├── linker.ld
├── openocd.cfg
├── Makefile
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

`--specs=nano.specs --specs=nosys.specs` plus a hand-written `_write()` — this replaced
`-nostdlib` once `printf` was wanted. `printf` costs about 4.6 KB of text. Call
`setvbuf(stdout, NULL, _IONBF, 0)` once before any output: newlib otherwise allocates a
stdio buffer through `malloc`, and libnosys's `_sbrk` always fails.

Header dependency tracking is on (`-MMD -MP`), so editing a header rebuilds exactly what
included it.

---

## Build, flash, debug

```
make                 # -> build/firmware.elf, build/firmware.bin, size report
make flash           # program, verify, and reset via OpenOCD
make clean
```

Debug session, two terminals:

```
openocd                                    # reads ./openocd.cfg, GDB server on :3333
arm-none-eabi-gdb build/firmware.elf       # then: target extended-remote localhost:3333
```

`openocd.cfg` selects the ST-LINK interface, SWD transport, and the `stm32f3x` target,
then asks for 1 MHz on SWCLK — comfortably under the F_cpu/6 ceiling at 8 MHz HSI. The
ST-LINK only offers fixed divisors, so it clamps to 950 kHz and says so twice on every
connection. Cosmetic.

Note that OpenOCD only auto-loads `./openocd.cfg` when invoked with **neither** `-f` nor
`-c`. The `make flash` recipe passes `-c "program ..."`, so it must also pass
`-f openocd.cfg` explicitly or it has no adapter driver.

**First command of every debug session:**

```
compare-sections
```

If it does not report every section matched, the board is running a different binary
than the ELF you are reasoning about, and any fault decode you do will be internally
consistent and completely fictional. GDB's "source file is more recent than executable"
warning is the same signal, earlier.

---

## Status

**Phase 0 complete. Phase 1 steps 1–2 complete. Phase 1 step 3 in progress.**

Current image: **5824 text / 96 data / 1368 bss**. LD2 blinks at 250 ms off a real
1 kHz tick while an incrementing counter streams out the VCP.

Phase 0 — build, step, print (verified on hardware):

- Own `startup.s` — 98-word / 392-byte vector table with a self-checking assembly-time
  length assertion, `.data` copy and `.bss` zero loops that both guard the zero-length
  case, and a `HardFault_Handler` with its own body so faults break distinctly.
- Own `linker.ld` — `.isr_vector` first in FLASH, `.data` with `>RAM AT> FLASH`, `.bss`
  bracketed by `_sbss`/`_ebss`, `_estack` at the top of RAM.
- Acceptance test: `golden_data = 0xDEADBEEF` in `.data` and `golden_bss` in `.bss` both
  read correctly at a breakpoint on `main`, exercising both startup loops. The `.data`
  chain was also verified statically — `readelf -l` gave the segment LMA, and `xxd` found
  `0xDEADBEEF` physically present in the binary at that offset.
- `printf` retargeted to USART2 through a hand-written `_write()`.

Phase 1 step 1 — SysTick at 1 kHz:

- Vector proven to point at the handler (`x/a 0x0800003c`), not merely to exist.
- `LOAD = 0x1f3f`, `CTRL = 0x7`, priority byte `0xf0` (lowest — a tick handler must
  never delay a device interrupt).
- Clock tree is *derived*, not hand-maintained: three independent inputs in `clock.h`
  (`SYSCLK_HZ`, `HPRE_DIV`, `PPRE1_DIV`), everything else by division, with exactness
  asserted at every division node. Enabling the PLL later is a two-number edit.

Phase 1 step 2 — `delay_ticks()`:

- Spins on elapsed ticks via **subtraction** (`now - start`), never a computed deadline.
  Verified across a real rollover: `tick_count` forced to `0xFFFFFFF0` immediately before
  a 251-boundary wait read back **235** — it passed through zero mid-delay and still
  waited its full length.
- Waits **N+1** boundaries, because a call arriving mid-period only guarantees more than
  N−1 full periods otherwise.
- Traps on `__BKPT(0)` if SysTick is not running, rather than returning early — a silent
  early return would convert a visible hang into a wrong-timing bug. Verified by forcing
  `SysTick->CTRL = 0` and calling into it from GDB.

Next: the GPIO driver — a `set_pin(port, pin, state)` layer built on `BSRR` rather than
`ODR`, so set and clear are single writes with no read-modify-write window. That stops
being a style question and becomes correctness in Phase 4, when a preemption can land
mid-RMW.

See [CLAUDE.md](CLAUDE.md) for detailed working notes, including the traps hit along the
way and how each was found.

---

## Roadmap

| Phase | Content | Est. | Status |
|---|---|---|---|
| 0 | Toolchain, own startup/linker/Makefile, blinky on PA5, GDB, `printf` | weekend | ✅ done |
| 1 | SysTick at 1 kHz + tick counter, `delay_ticks()` spinning on ticks, GPIO driver | weekend | steps 1–2 ✅, step 3 ← **here** |
| 2 | **The context switch.** Two hardcoded tasks alternating on SysTick. No scheduler, no priorities. Prove a task can be left mid-execution and resumed exactly | the hard part | |
| 3 | Task Control Blocks, stack initialization, round-robin scheduler, `os_start()` | 1 wk | |
| 4 | Task states (READY/RUNNING/BLOCKED/SUSPENDED), yielding `os_delay()`, fixed-priority preemption, `os_yield()` | 1–2 wk | |
| 5 | Nestable critical sections, counting semaphore, mutex with priority inheritance — reproduce the inversion bug on a scope first, then fix it | 1–2 wk | |
| 6 | Fixed-size message queues, blocking send/receive with timeouts, ISR-safe variants using a deferred-yield flag | 1 wk | |
| 7 | Stack overflow detection (paint `0xDEADBEEF`, watermark checks at switch), fault handlers that decode CFSR/HFSR, static allocation only, `assert` | — | |
| 8 | **Prove it.** Logic-analyzer capture of task entry/exit, context switch latency in cycles via `DWT->CYCCNT`, worst-case interrupt latency published below, demo app | — | |

Public APIs take **ticks**, not milliseconds — `delay_ticks(MS_TO_TICKS(250))`, the same
shape as FreeRTOS's `pdMS_TO_TICKS`. The verbosity is the point: it keeps the
quantisation visible instead of letting callers assume 1 tick = 1 ms. `MS_TO_TICKS`
rounds **up** (a delay promises *at least* that long); `TICKS_TO_MS` truncates (a
measurement must not overstate).

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

Two rules for when these get filled in. The day-to-day build is `-O0`, and a context
switch latency measured at `-O0` is not a number worth publishing — measure at `-O2` and
say which. And use `DWT->CYCCNT`, which counts the core clock directly, rather than an
APB timer: timers on APB1 run at PCLK1 × 2 whenever `PPRE1 != 1`, which is an easy 2×
error waiting to happen.

---

## F3-specific notes

- **GPIO ports are on AHB, not APB2.** It is `RCC->AHBENR |= RCC_AHBENR_GPIOAEN`. Nearly
  every STM32 tutorial online targets F1/F4 and says `APB2ENR`. This is the single most
  common wasted hour on this chip.
- **`stm32f303x8.h` is not a substitute for `stm32f302x8.h`.** It looks fine at first —
  `SysTick_IRQn` and `PendSV_IRQn` are core exceptions and identical, and `USART2_IRQn`
  happens to share a slot — but the device IRQ lists diverge. It detonates in Phase 4,
  when NVIC priorities start mattering.
- **RM0365 documents two different vector tables.** Table 40 is STM32F302x**B/C/D/E**;
  Table 41 is STM32F302x**6/8**, the Nucleo's part. Transcribing Table 40 gives you
  peripherals this silicon does not have. Verified figures for F302x8: 16 core
  exceptions + **82 device IRQ slots** (50 named, 32 reserved), last vector at position
  81, **98 words / 392 bytes** total. Invariant to check work against: *enum value ==
  table index − 16*.
- **ST omitted the row for position 66 from Table 41** — the printed table jumps 65 → 67.
  It is reserved. Copying row-by-row yields a 97-word table with everything after 65
  shifted by one: silent, and only visible once NVIC priorities matter.
- **RM acronyms are not CMSIS symbol names.** Positions are identical, labels are not
  (`TAMPER_STAMP` vs `TAMP_STAMP_IRQn`, `CAN_TX` vs `USB_HP_CAN_TX_IRQn`, …). Use the
  CMSIS names so `NVIC_EnableIRQ(USART2_IRQn)` pairs with `USART2_IRQHandler`.
- **The F3 USART is the modern one.** Status is `ISR`, not `SR`, and transmit/receive are
  separate `TDR`/`RDR`, not one `DR`. `BRR` holds USARTDIV **directly** at `OVER8 = 0` —
  no mantissa/fraction split, so F1/F4 code that shifts by 4 is wrong here. Also note
  three different buses in one file: GPIO on `AHBENR`, USART2 on `APB1ENR`, USART1 on
  `APB2ENR`.
- **Instance pointers carry the number; bit-mask macros do not.** `USART2->ISR` but
  `USART_ISR_TXE`. And `_0`/`_1` suffixes name which bit *of the field*, not the value —
  `MODER5_0` writes `01` (output), `MODER5_1` writes `10` (alternate function).
- **SysTick is ARM's, not ST's.** It lives in the System Control Space at `0xE000E010`,
  is documented in **PM0214** rather than RM0365, comes from `core_cm4.h` rather than the
  device header, and has no RCC enable bit. Period is `LOAD + 1` cycles. It also stops
  counting while the core is halted in debug — so a frozen `VAL` at a breakpoint is
  expected, and tick-based intervals measured across a halt undercount.
- **64 MHz is the PLL ceiling from HSI on this part.** `PLLSRC` is a one-bit field
  (HSI/2 or HSE/PREDIV) and `PLLMUL` maxes at ×16, so 72 MHz requires HSE — and the
  NUCLEO-64's X3 crystal footprint ships unpopulated. `HPRE` also skips 32 (…16, **64**,
  128…), so a power-of-two assert would wave an illegal divisor through.

---

## References

- **RM0365** — STM32F302 reference manual. RCC, GPIO, USART chapters. Search it, don't read it. Table 41 is this part's vector table, **not** Table 40.
- **PM0214** — STM32 Cortex-M4 programming manual. SysTick, NVIC, SCB — the things RM0365 does not document because they are ARM's, not ST's.
- **UM1724** — Nucleo-64 board user manual.
- **STM32F302R8 datasheet** — the alternate-function tables. Which AF wires which pin to which peripheral is a package fact, not in the RM. PA2 → AF7 for USART2_TX.
- **DDI 0403** — ARMv7-M Architecture Reference Manual. The authority. Search only.
- Joseph Yiu, *The Definitive Guide to ARM Cortex-M3 and Cortex-M4 Processors* — the exception model chapters.
- Miro Samek, *Modern Embedded Systems Programming* (YouTube), lessons ~22–27.
- FreeRTOS `portable/GCC/ARM_CM4F/port.c` — read **after** the Phase 2 switcher works, then diff approaches.
