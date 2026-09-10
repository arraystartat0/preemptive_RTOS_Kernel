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
    `USART2_IRQn` happens to share a slot. The device IRQ lists diverge, though, so
    it would have detonated in Phase 4 when NVIC priorities start mattering.
    (Earlier versions of this note claimed "59 IRQ entries" and that slot 18 is
    `ADC1_IRQn` not `ADC1_2_IRQn` — both wrong, see the vector table facts below.)
  - **`system_stm32f3xx.h` is required even though `SystemInit` is never called.**
    `stm32f302x8.h` includes it unconditionally; without it the first compile dies.
    The *header* is all that's needed — ST's `system_stm32f3xx.c` from
    `Source/Templates/` was deliberately **not** kept, since it does full PLL setup
    and this project stays on default HSI until much later.
  - **RM0365 documents two different vector tables.** Table 40 is
    STM32F302x**B/C/D/E**; Table 41 is STM32F302x**6/8** — the Nucleo's part.
    Transcribing Table 40 would give TIM3/TIM4 at 29/30, SPI1 at 35, FMC at 48,
    UART4/5 at 52/53, DMA2 at 56–60 and `COMP1_2_` at 64, none of which exist on
    this chip. Same failure mode as the F303 header, from a different direction.

### Vector table facts (verified: RM0365 Table 41 vs `IRQn_Type` in `stm32f302x8.h`)

Positions agree exactly between the two sources.

| | |
|---|---|
| Core exceptions | 16 (indices 0–15) |
| Device IRQ slots | 82 (positions 0–81) |
| Named IRQs | 50 |
| Reserved slots | 32 |
| Last vector | position 81 (`FPU`) at offset `0x184` |
| **Full table** | **98 words = 392 bytes = `0x188`** |

Reserved (need `.word 0`): **29–30, 35, 43–50, 52–53, 55–63, 66–71, 77–80**.

Invariant to check work against: **enum value == table index − 16**. Spot checks:
`USART2_IRQn` = 38 lands at index 54; `FPU_IRQn` = 81 at index 97, the last entry.

Two transcription traps in Table 41 itself:

- **ST omitted the row for position 66.** The printed table jumps 65 → 67. It is
  reserved (CMSIS agrees). Copying row-by-row yields a 97-word table with
  everything after 65 shifted by one — silent, and only visible in Phase 4.
- **RM acronyms are not CMSIS symbol names.** Positions identical, labels differ:
  pos 2 `TAMPER_STAMP`/`TAMP_STAMP_IRQn`, 8 `EXTI2_TS`/`EXTI2_TSC_IRQn`,
  18 `ADC1_2`/`ADC1_IRQn`, 19 `CAN_TX`/`USB_HP_CAN_TX_IRQn`,
  20 `CAN_RX0`/`USB_LP_CAN_RX0_IRQn`. Use the **CMSIS** names, so that
  `NVIC_EnableIRQ(USART2_IRQn)` pairs with `USART2_IRQHandler`.

### Phase 0 — COMPLETE (verified on hardware, 2026-09-01)

Build, step, and print all work. `firmware.elf` is **5552 text / 96 data / 1368 bss**,
flashed and `** Verified OK **`.

| Criterion | Evidence |
|---|---|
| **Build** | `make` works; incremental; `-MMD` header tracking rebuilds only what changed; `make clean` idempotent; `make flash` programs and verifies |
| **Step** | GDB over OpenOCD: `break main`, `print/x golden_data` → `0xdeadbeef`, `print golden_bss` → `0` |
| **Print** | `printf("%d\r\n", counter)` streaming to COM3 at 115200 8N1 via the ST-LINK VCP |

The board blinks LD2 on PA5 at ~1.8 Hz (200,000-iteration `volatile` delay loop) while
printing an incrementing counter.

What `startup.s` contains and why, so it doesn't have to be re-derived:

- Vector table `g_pfnVectors`: **98 words / 392 bytes**, verified by `readelf`.
  Full 82-slot IRQ range with reserved slots as `.word 0`; each entry carries its
  position as a trailing comment. Generated from the `IRQn_Type` enum in
  `stm32f302x8.h` and then audited back against that enum entry-by-entry — all 98
  match. Position 66 (the row ST omitted from RM0365 Table 41) is reserved.
- **Self-checking length assertion** after the table: `.if .-g_pfnVectors != 392` /
  `.error` / `.endif`. `.` is the location counter, so `.-g_pfnVectors` is an
  assembly-time constant. Watched to both fire and pass. Reuse this technique for
  TCB size and stack alignment in Phases 3 and 7.
  Note it only checks *length* — a shifted-by-one table of the right size passes.
- `.data` copy and `.bss` zero loops both guard the zero-length case. The `.data`
  loop branches to its test (`b LoopCopyDataInit`); the `.bss` loop uses the other
  idiom — a `cmp`/`bcs BSSDone` guard ahead of the body. `bcs`/`bcc` are unsigned
  (`hs`/`lo`) because these are address comparisons; `blt` would be a latent bug.
- `HardFault_Handler` has its **own** weak body in its own section (`hardfault_loop`),
  not aliased to `Default_Handler`, so faults breakpoint distinctly. Its
  `.thumb_set` line is deleted — a symbol cannot be both label-defined and equated.
- MemManage/BusFault/UsageFault stay aliased on purpose: they are disabled in
  `SHCSR` at reset, so those faults escalate to HardFault. Split them in Phase 7
  when they get enabled.

**Naming rule, which differs across the table:** device IRQs (index ≥ 16) derive
their handler name from the enum — strip `_IRQn`, append `_IRQHandler`. Core
exceptions do **not**; those names are conventional and four of nine don't
correspond (`NonMaskableInt_IRQn`→`NMI_Handler`, `MemoryManagement_IRQn`→
`MemManage_Handler`, `SVCall_IRQn`→`SVC_Handler`, `DebugMonitor_IRQn`→
`DebugMon_Handler`). A misspelled handler in C is silent — the weak alias just
keeps winning. Check the `.map` if a handler never fires.

**Acceptance test for the startup code: PASSED.** Two globals in `main.c` —
`golden_data = 0xDEADBEEF` (lands in `.data`, exercises the copy loop) and
`golden_bss = 0` (lands in `.bss`, exercises the zero loop). Both read correctly in
GDB at a breakpoint on `main`.

The whole `.data` chain was also verified statically, without hardware, and that
technique is worth reusing: `readelf -l` showed the segment's **PhysAddr (LMA)
`0x0800028c`** matching `_sidata` exactly, and `xxd` on `firmware.bin` at offset
`0x28c` showed `efbeadde` — `0xDEADBEEF` physically present at the address the copy
loop reads from. Vector table decoded from `objdump -s -j .isr_vector`: word 0 =
`0x20004000` (`_estack`), word 1 = `0x08000239` (`Reset_Handler`, thumb bit set),
HardFault at a *different* address from the three aliased handlers, exactly as designed.

**A note on `= 0`:** a global explicitly initialized to zero lands in `.bss`, not
`.data` — the linker won't waste flash storing zeros. Getting this backwards voids
the acceptance test, because both variables end up in `.bss` and the copy loop is
never exercised.

### Phase 0 traps, so they aren't rediscovered

**Toolchain / build**

- **OpenOCD only auto-loads `openocd.cfg` when neither `-f` nor `-c` is given.** The
  `flash` recipe passes `-c "program ..."`, which suppresses that default. Without an
  explicit `-f openocd.cfg` you get `Error: Debug Adapter has to be specified`.
- **Make's recipe shell on Windows depends on PATH.** From PowerShell/cmd it uses
  `cmd.exe` and `rmdir /S /Q` works. From Git Bash it finds a Unix `rmdir`, `/S` and
  `/Q` become path arguments, the command fails, and the `-` prefix **silently
  swallows the error** — `make clean` appears to succeed and deletes nothing. Run
  `make` from PowerShell. (The `-` that makes a second `clean` safe is the same `-`
  that hides real failures. That's the trade.)
- `--specs=nano.specs --specs=nosys.specs` links fine **without** `-nostartfiles`. It
  emits ~5 linker warnings (`_close`/`_fstat`/`_isatty`/`_lseek`/`_read` "is not
  implemented and will always fail"). Harmless — libnosys stubs for syscalls nothing
  calls. `-Werror` lives in `CFLAGS`, not `LDFLAGS`, so they don't fail the build.
- `printf` costs **~4.6 KB**: 932 → 5552 bytes of text.

**C and compiler**

- `int(expr)` is C++ syntax. C spells a cast `(int)expr` — and `8000000 / 115200` is
  already integer division, constant-folded to `movs r2, #69`. No float, no runtime
  division. Note it *truncates*; for baud dividers where the fraction exceeds .5,
  round with `(num + den/2) / den`.
- **`printf` with no `%` conversion is rewritten by GCC into `puts`, even at `-O0`.**
  Verified in the disassembly. A literal-only `printf` therefore does not test the
  formatting engine at all.
- newlib's `printf` allocates a stdio buffer via `malloc`, and `nosys.specs`'s
  `_sbrk` always fails (`malloc`, `_malloc_r`, and `_sbrk` are all genuinely linked
  into the image). **`setvbuf(stdout, NULL, _IONBF, 0)` before any output** skips the
  allocation. Call it once, before any I/O on the stream — the C standard makes a
  later call undefined, so it must not live inside the loop.

**F3 register traps**

- **Three different buses in one file:** GPIO on `AHBENR`, USART2 on `APB1ENR`,
  USART1 on `APB2ENR`. Copying a USART1 example gets the clock line wrong.
- The F3 USART is the modern one: status is **`ISR`** (not `SR`), and transmit/receive
  are **separate `TDR`/`RDR`** (not one `DR`). F1/F4 tutorial code won't compile —
  which is the header telling the truth.
- **`BRR` holds USARTDIV directly** at OVER8=0 — no mantissa/fraction split. F1/F4
  code shifting by 4 is wrong here. 8 MHz / 115200 = **69** (`0x45`), actual 115942
  baud, +0.64%, well inside the ±2.5% a UART tolerates.
- The F302x8 has **no `USART2SW`** clock selector — `RCC_CFGR3` only has
  `USART1SW`. USART2/3 are hardwired to PCLK1. Larger F3 parts (302xC/xE) do have it,
  so tutorials may show a selector this silicon lacks.
- **AF numbers come from the datasheet's alternate-function table, not RM0365.** The
  RM documents the GPIO peripheral; the datasheet says which AF wires which pin to
  which peripheral on this package. PA2 → **AF7** for USART2_TX.
- Confirm the clock rather than inheriting it: `RCC->CFGR` reads `0x00000000`, so
  `SWS`=HSI, `HPRE`=÷1, `PPRE1`=÷1 → **PCLK1 = 8 MHz**. Read it with
  `print/x RCC->CFGR` in GDB or `mdw 0x40021004` from OpenOCD.

**CMSIS naming, two rules that caused real bugs**

- **Instance pointers carry the number; bit-mask macros do not.** `USART2->ISR` but
  `USART_ISR_TXE`; `GPIOA->MODER` but `GPIO_MODER_MODER5_Msk`. Register layouts are
  per-peripheral-*type*, so the masks are defined once for all instances.
- **`_0` / `_1` suffixes name which bit *of the field*, not the value.**
  `MODER5_0` is the field's low bit → writes `01` (output). `MODER5_1` is the high bit
  → writes `10` (alternate function). Four modes: `00` input, `01` output, `10`
  alternate function, `11` analog.
- `MODER`/`OSPEEDR`/`PUPDR` are 2 bits per pin (position = pin × 2); `OTYPER`/`IDR`/`ODR`
  are 1 bit; `AFR[]` is 4 bits (position = pin × 4), split `AFR[0]` = pins 0–7,
  `AFR[1]` = pins 8–15.

**The bug class `-Werror` cannot catch**

Two real ones happened, both valid C that compiled silently:

- `GPIOA->MODER /= (1 << Pos)` instead of `|=` — divides the register. Would have
  wiped bits 31:26, dropping PA13/PA14 (SWDIO/SWCLK) from alternate function to
  input, killing the debug port a few instructions into `main`.
- `USART2->CR2 |= USART_CR1_UE` — right bit, wrong register. `UE` never gets set, the
  USART stays off, and every other register looks perfect.

**Countermeasure: after configuring a peripheral, read the registers back in GDB and
compare against what you intended.** `print/x GPIOA->MODER` should be `0xa8000400`
after PA5 setup alone, `0xa8000420` once `uart2_init()` has also put PA2 in AF mode; `print/x USART2->CR1` should have bits 0 and 3 set. The compiler
cannot know which register you *meant* — only the silicon can tell you.

**Linker script**

- **`.isr_vector` must be the first output section in `SECTIONS`.** `.ARM.extab` and
  `.ARM` were briefly placed above it. Both were size 0, so `.isr_vector` still landed
  at `0x08000000` and everything worked — a latent landmine that detonates the moment
  unwind data appears (C++, `-funwind-tables`). Fixed; keep it first.

### Phase 1 step 1 - COMPLETE (verified on hardware, 2026-09-07)

SysTick at 1 kHz with a tick counter. `firmware.elf` is **5704 text / 96 data / 1368 bss**.

| Criterion | Evidence |
|---|---|
| Vector wired | `x/a 0x0800003c` -> `0x8000531 <SysTick_Handler>` - the weak alias lost |
| Reload correct | `objdump -d` on `systick_init` shows `movw r2, #7999` (`0x1f3f`) stored to `LOAD` |
| Registers | `LOAD` = `0x1f3f`, `CTRL` = `0x7`, priority byte at `0xE000ED23` = `0xf0` |
| Handler runs | `tick_count` advanced **60620** over a stopwatched 60 s |
| No faults | `CFSR` (`0xE000ED28`) = 0, `$sp` = `0x20003ff0` (16 B below `_estack`) |

**The clock tree is now derived, not hand-maintained.** `constants.h` is gone, replaced
by `clock.h`. Three *independent* inputs - `SYSCLK_HZ`, `HPRE_DIV`, `PPRE1_DIV` - and
everything else (`HCLK_HZ`, `PCLK1_HZ`, the SysTick reload, the UART `BRR`) derives by
division. Enabling the PLL later becomes a two-number edit instead of an archaeology
exercise. Ceilings are asserted (SYSCLK/HCLK <= 72 MHz, PCLK1 <= 36 MHz) and so is
exactness at **every** division node - if `SYSCLK % HPRE` truncates, `HCLK_HZ` is
already a lie and the tick assert below it validates that lie.

`PCLK2_HZ` was written first and deleted: it referenced an undefined `PPRE2_DIV` and
compiled cleanly **because nothing used it**. Macros are not evaluated until expanded,
so a broken one with zero consumers is invisible - same failure shape as the
`.isr_vector` ordering landmine. Either define it or delete it; never leave it
half-built. There is no APB2 consumer on this project yet.

### Phase 1 step 2 - COMPLETE (verified on hardware, 2026-09-08)

`delay_ticks()` in its own module (`delay.c` / `delay.h`). The magic `200000` is gone
from `main.c`; the blink is now `delay_ticks(MS_TO_TICKS(250))`.
`firmware.elf` is **5824 text / 96 data / 1368 bss**.

| Criterion | Evidence |
|---|---|
| In the image | `nm` -> `08000574 T delay_ticks`; text moved 5704 -> 5824 |
| Right instructions | `objdump -d`: `subs r3, r2, r3` (elapsed = now - start), `adds r3, #1` (boundary), `bcc` (unsigned), `bkpt 0x0000` |
| Wrap-safe | `set var 'systick.c'::tick_count = 0xFFFFFFF0` immediately before a 251-boundary wait; read back **235**. `0xFFFFFFF0 + 251 = 0x1000000EB`, mod 2^32 = `0xEB` = 235 - it rolled through zero *mid-delay* and still waited the full length |
| Guard fires | `set var SysTick->CTRL = 0` -> `is_systick_initialized()` returns `false` -> `call delay_ticks(10)` stops with `SIGTRAP` on the `__BKPT` |
| Live frame | Ctrl+C mid-delay: `ticks`=250, target=251, `start`=15563, `current`=15584, `elapsed`=21 |

Shape that survived review:

- Lives in **`delay.c`, not `systick.c`**. SysTick is the timer *driver*; a spin-delay
  is a *consumer* of the tick counter. `delay.c` knows only `systick_get_tick_count()` and
  `is_systick_initialized()` - never the reload value.
- **`delay_ticks` does not call `systick_init`.** An early version did, "in case it
  wasn't initialised yet". It re-ran init on *every* call, and `SysTick->VAL = 0`
  resets the *phase* of the global timebase each time, jittering every other consumer.
  It also **masked the missing boundary `+1`**, because a freshly-reset counter always
  puts the next tick a full period away. In Phase 3, a task calling that would reset
  SysTick out from under the scheduler.
- `ticks == 0` returns immediately, deliberately. `ticks == UINT32_MAX` still makes
  `ticks + 1` wrap to 0 and return instantly - known, unguarded, written down here.
- The init check reads **the hardware**, not a flag:
  `(CTRL & (ENABLE|TICKINT)) == (ENABLE|TICKINT)`. No RAM, no second source of truth,
  cannot be defeated by a linkage mistake. It answers "is SysTick *running*", which is
  weaker than "did `systick_init` run" - fine for now; note the gap.
- On failure it **traps** (`__BKPT(0)`), it does not return. A silent early return
  converts a visible hang into a wrong-timing bug, the hardest class to diagnose here.
  With no debugger attached, `BKPT` escalates to HardFault - which already has its own
  distinct handler from Phase 0, so it is loud either way.

### Phase 1 step 2 traps

**The one that cost the most time: a stale flash image.**

A `printf` HardFault was decoded end to end. `HFSR = 0x40000000` (FORCED),
`CFSR = 0x8200` (BusFault: `PRECISERR` + `BFARVALID`), `BFAR = 0x40480611`, stacked PC
`0x0800075a` inside `iprintf`, which does `ldr r0, [r1]` from `0x20000010`
(`_impure_ptr`) and then `ldr r1, [r0, #8]`. `_impure_ptr` read `0x40480609`; BFAR was
exactly that + 8. Airtight - and **entirely fictional**. The board was running the
*previous* binary while the analysis ran against the new ELF. After `make && make
flash`, `compare-sections` matched, `HFSR` and `CFSR` both read `0`, and the fault
never recurred. A watchpoint on `0x20000010` never tripped, which was the first real
clue that the story was wrong.

GDB had been saying so the whole time: **"Source file is more recent than executable."**

> **Rule: `compare-sections` clean before decoding anything.** A fault decode against a
> mismatched image is not weaker evidence, it is *fabricated* evidence - internally
> self-consistent, which is exactly why it convinces.

The flash-side check that proved the build was fine is worth reusing: `readelf -l` gave
the `.data` LMA (`PhysAddr 0x080016c0`), and
`od -A x -t x4 -j 0x16c0 -N 0x60 build/firmware.bin` showed `20000014` at LMA+0x10 -
the correct `_impure_ptr` value physically present in flash. Same family as the Phase 0
`0xDEADBEEF` LMA check.

**`static` in a header - both failure modes, one after the other.**

- `static bool systick_initialized = false;` in `systick.h` gives **every including TU
  its own private copy**. `systick.c` set its copy; `delay.c` read its own, forever
  false. No linker error. It surfaced only as `-Werror=unused-variable` in `main.c` -
  a *symptom*, not the disease. Silence that warning and it builds clean and is
  silently broken.
- The "fix" was `volatile uint32_t tick_count = 0;` in `systick.h` - a *definition*
  with external linkage in a header, so three TUs each defined it:
  `multiple definition of 'tick_count'`. The linker catches this one.

**Only one of the two is detectable**, from the same root cause: a header must
*declare*, never *define*. The correct shape was already in the file - object `static`
in the `.c`, accessor in the `.h`, exactly like `tick_count` / `systick_get_tick_count`.

**`_Static_assert` is compile-time and cannot see runtime state.**

`if (!initialized) { _Static_assert(false, "..."); }` fails the build unconditionally.
The `if` is irrelevant - the compiler never "reaches" anything, it evaluates the assert
while parsing. `_Static_assert` takes a *constant expression*; a variable's value never
is one. The names are the trap: `_Static_assert` is compile-time, `assert()` from
`<assert.h>` is **runtime**. Newlib's `assert` is unusable here anyway - it calls
`abort()`, a nosys stub. Runtime traps use `__BKPT` until Phase 7 builds a real one.

**Test for which phase a check belongs to:** could the answer differ between two runs
of the same binary? `HCLK_HZ % TICK_RATE_HZ` - no, compile time. "Has `systick_init`
been called?" - yes, runtime.

**`&&` where `&` was meant, plus C's precedence wart.**

`return (CTRL && (MASK) == (MASK));` - `==` binds tighter than `&&`, so it parses as
`CTRL && (MASK == MASK)`, i.e. `CTRL != 0`. The mask comparison is a tautology and
vanishes. It *worked by accident* (`CTRL` is 0 at reset, 7 after init) and would have
failed the day `CTRL` held ENABLE without TICKINT - precisely the case the check exists
to catch. No warning: `-Wall -Wextra` does not flag comparing two identical constant
macro expansions.

Changing `&&` to `&` then tripped `-Werror=parentheses`, because **`&` has *lower*
precedence than `==`** in C. `CTRL & MASK == MASK` is `CTRL & (MASK == MASK)` =
`CTRL & 1`. It must be `(CTRL & MASK) == MASK`. Note the asymmetry: with `&&` the bug
was invisible; with `&` GCC has a dedicated warning for it. Third entry in the
precedence family, after `+ 999U / 1000U`.

**Time was spent debugging a file no compiler had ever seen.** `delay.c` (then
`time.c`) was not in `SRCS`. Later it *was* in `SRCS` and compiled, but `main.c` never
called it, so `-ffunction-sections -Wl,--gc-sections` stripped it and the text size
stayed byte-identical at 5704. **`nm` the ELF for the symbol, and watch the size move.**
A green `make` still proves nothing.

**`time.c` was renamed to `delay.c`** before it could bite. `<time.h>` is a standard
header; a `src/time.h` collides the moment `-Isrc` is added - which is exactly what
Phase 3's `src/kernel/` will require. Harmless now, silent, detonates later: the same
shape as the `.isr_vector` ordering landmine.

### PLL: investigated, deliberately deferred until after Phase 2

- On the F302x8, `PLLSRC` is a **one-bit** field - HSI/2 or HSE/PREDIV. There is no way
  to feed HSI to the PLL undivided. `PLLMUL` maxes at x16, so **8 / 2 x 16 = 64 MHz is
  the ceiling reachable from HSI**; 72 MHz requires HSE. Larger F3 parts have a 2-bit
  `PLLSRC` with an `HSI/PREDIV` option this silicon lacks - same trap shape as the
  missing `USART2SW`.
- **`HPRE` skips 32.** Legal divisors are 1, 2, 4, 8, 16, **64**, 128, 256, 512
  (`RCC_CFGR_HPRE_DIV16` = `0xB0` jumps straight to `DIV64` = `0xC0`). A power-of-two
  assert would wave 32 through. `PPRE1`/`PPRE2` stop at 16.
- **APB1 maxes at 36 MHz**, so a 64 MHz SYSCLK forces `PPRE1 = /2` and PCLK1 becomes
  32 MHz. `BRR` derives from **PCLK1**, not SYSCLK - this is the classic "UART prints
  garbage after enabling the PLL" bug.
- **Timers on APB1 are clocked at PCLK1 x 2 whenever `PPRE1 != 1`.** An easy 2x error
  if a general-purpose timer is ever used for measurement. `DWT->CYCCNT` counts the
  core clock and sidesteps it - the right instrument for Phase 8 latency numbers.
- Order is mandatory: flash latency (0 WS <=24 MHz, 1 WS <=48, 2 WS <=72) -> `PLLON` ->
  poll `PLLRDY` -> switch `SW` -> poll `SWS` to confirm.
- **Deferred on purpose.** Nothing in Phases 1-3 is clock-bound (a 1 ms tick is 8000
  cycles; a context switch is low hundreds). Changing the clock risks the UART, which
  is the primary observability channel, immediately before the hardest debugging in
  the project. The switcher is clock-independent, so there is no rework penalty for
  waiting. Do it as a standalone task **between Phase 2 and Phase 3**.
- **NUCLEO-64 HSE caveat:** the X3 crystal footprint ships **unpopulated**; HSE is fed
  from the ST-LINK's MCO by default. Check UM1724 6.7 before planning around it.

### ms <-> ticks: option B (public APIs take ticks)

Chosen shape: `MS_TO_TICKS` is public and applied **at the call site** -
`delay_ticks(MS_TO_TICKS(250))`. Same as FreeRTOS's `pdMS_TO_TICKS`, which matters
because the Phase 5 plan is to diff against their port. The verbosity is the feature:
it keeps the quantisation visible instead of letting callers assume 1 tick = 1 ms.

- **`MS_TO_TICKS` rounds UP; `TICKS_TO_MS` truncates.** A delay promises "*at least*
  this long" - truncation at 100 Hz turns a 5 ms delay into 0 ticks, i.e. a task that
  never yields. A *measurement* must not round up, or it systematically overstates.
- Ceiling idiom: add **D - 1** to the numerator before dividing by D. Written as
  `MS_PER_SECOND - 1U`, not a literal `999U`, so it tracks the divisor. It is the
  largest addend that cannot carry a zero remainder and the smallest that carries
  every nonzero one - `+1000` breaks exact multiples, `+0` truncates sub-tick delays.
- **`MS_PER_SECOND` is named separately from `TICK_RATE_HZ`.** Both are 1000 today and
  mean entirely unrelated things (ms/s, an SI fact, vs ticks/s, a policy choice that
  will change). Units: `[ms] x [ticks/s] / [ms/s] = [ticks]`.
- Overflow: the multiply happens first, capping `ms` at `(0xFFFFFFFF - 999) / 1000` =
  **4294966**. Not runtime-checkable - an overflow has already wrapped by the time you
  could inspect the result.
- Reasons `TICK_RATE_HZ` will actually change: tick overhead (a 200-cycle scheduler
  pass is 2.5% of the CPU at 8 MHz), or finer resolution for the Phase 8 demo.

### The bug class `-Werror` cannot catch - macro arithmetic (Phase 1 additions)

**Three** silently-wrong values in one file, all valid C:

- **`%` typed where `/` was meant** in the reload value. `8000000 % 1000` is 0, then
  unsigned `0 - 1` wraps to `0xFFFFFFFF`. `LOAD` keeps 24 bits -> `0xFFFFFF` -> a
  **2.097 s** tick period, 2097x too slow. Confirmed via `objdump`:
  `mov.w r2, #4294967295`.
- **The assert that would have caught it had been disarmed** in the same edit -
  swapped from `<= 0xFFFFFF` to `!= 0`, which passes on `0xFFFFFFFF`, while its
  message still read `"exceeds 24 bits"`.
- **Precedence.** `(((ms) * TICK_RATE_HZ) + 999U / 1000U)` - `/` binds tighter than
  `+`, so it parses as `(ms * RATE) + 0`. The unit conversion vanished entirely and
  **`make` still passed**, because nothing in `src/` calls the macro.

Rules that came out of it:

- **An assert and the value it guards must be edited independently.** Change both in
  one motion and you have written one thing twice, not two things that cross-check.
- **An assert whose condition and message disagree is worse than no assert** - it
  reads like coverage. Believe neither half when they drift.
- **Failure modes are additive, not alternatives.** The reload needs `!= 0` *and*
  `<= 0xFFFFFF` *and* exactness. Trading one for another was done twice.
- Parenthesize every macro body **as a whole**, and every operand. The preprocessor
  pastes text; C's precedence rules then apply to the result, not to what you meant.
- **A green `make` proves nothing about code with no callers.**

### Verification techniques worth reusing

- **`objdump -d` the linked function and read the constant that actually reaches the
  register.** Caught the `0xFFFFFFFF` and confirmed `movw r2, #7999`. Works with no
  board attached. Same family as the Phase 0 `.data` LMA check.
- **To test compile-time logic whose real configuration makes it degenerate:** include
  the real header, `#undef` the constant, redefine it, then `_Static_assert` the
  results. Macro bodies expand at *use* time, so this re-points the shipped macro at a
  new configuration rather than testing a copy. At 1 kHz `MS_TO_TICKS` is the identity
  function and untestable in-project; at 100 Hz and 300 Hz it is not. **Test truncation
  cases *and* exact-multiple cases** - they catch opposite bugs (`+0` vs `+D`). Reuse
  for TCB size and stack alignment in Phases 3 and 7.
- **`compare-sections` in GDB** verifies flash matches the ELF. Run it before trusting
  any register readback - "source file is more recent than executable" is a real
  warning.

### SysTick facts (ARM's peripheral, not ST's)

- SysTick lives in the **System Control Space at `0xE000E010`** - it is ARM's, defined
  by the ARMv7-M ARM and documented in **PM0214**, not RM0365 (which only mentions
  that the external reference clock is HCLK/8). Definitions come from `core_cm4.h`,
  **not** the device header. There is no RCC enable bit for it.
- It runs *nothing*. Peripherals are clocked by the RCC tree; SysTick is a consumer of
  HCLK sitting alongside the CPU.
- Registers: `CTRL` (bit 0 ENABLE, 1 TICKINT, 2 CLKSOURCE, 16 COUNTFLAG), `LOAD`,
  `VAL`, `CALIB`.
- **Period is `LOAD + 1` cycles** - the counter includes 0. Hence `HCLK/rate - 1`.
- **`CLKSOURCE` and the reload value are one decision in two places.** Cleared means
  HCLK/8, and the reload would be 8x wrong with no error anywhere.
- Writing `VAL` clears the counter to 0 *and* clears COUNTFLAG - it does not load what
  you wrote. Writing `LOAD` while running takes effect at the next wrap. Order must be
  `LOAD` -> `VAL` -> `CTRL`.
- **COUNTFLAG is read-clear, and a GDB read clears it.** Do not poll it if you use the
  interrupt. Seeing `0x10007` then `0x7` on two reads is the flag doing its job.
- `SysTick_IRQn` is **-1**, so `NVIC_SetPriority` dispatches to `SCB->SHP`, not
  `NVIC->IP`. The byte is at `0xE000ED23`; with `__NVIC_PRIO_BITS` = 4 the value is
  shifted into the high nibble, so priority 15 reads as **`0xf0`**.
- Lowest priority is deliberate - a tick handler must never delay a device interrupt.
  Same reasoning puts PendSV at the bottom in Phase 2.

### Debug-session facts learned the hard way

- **SysTick stops counting while the core is halted in debug.** `VAL` frozen at a
  breakpoint is *expected*, not a fault. Any tick-based interval measured across a
  halt undercounts. This makes "stopwatch + breakpoint" self-contradictory for rate
  measurement, and makes breakpoint-to-breakpoint deltas the *right* way to measure
  execution time.
- **The `200000` spin loop actually takes 274 ms, not the predicted 250** - about 11
  cycles/iteration rather than 10. The remainder is the unbuffered `printf`, roughly
  87 us per character at 115200.
- **Stopwatch-vs-tick cannot resolve better than ~1%.** Reaction time is +/-0.83% over
  60 s and HSI is +/-1%. The 60620/60 s reading is *consistent with* 1 kHz and proves
  nothing finer. A real number needs a better reference - an argument for HSE.
- In gdb, a `static` file-scope variable needs the file qualifier:
  `print 'systick.c'::tick_count`. `tick_count` is at `0x20000064`.
- **`(gdb)` and `>` in notes are prompts, not part of the command.** For a one-shot
  from PowerShell: `arm-none-eabi-gdb -batch -ex "x/a 0x0800003c" build/firmware.elf`.
- **A watchpoint halts the target by itself** - no Ctrl+C. `watch *(uint32_t *)ADDR`,
  then `continue`; it stops on the write and prints old/new values. Check the word
  **"Hardware"** in GDB's confirmation: this chip has 4 DWT comparators, so it runs at
  full speed. A plain "Watchpoint" means GDB fell back to software single-stepping.
  A watchpoint that *never trips* while the symptom still occurs is real evidence -
  it is what killed the `_impure_ptr` corruption theory above.
- **`BFAR` / `MMFAR` are only meaningful when `BFARVALID` / `MMARVALID` is set** in
  CFSR. Read otherwise, they hold stale garbage (`0xe000edf8` was observed on a run
  with `CFSR == 0`). Check the valid bit before believing the address.
- **CFSR and HFSR bits are sticky** (write-1-to-clear) and accumulate across faults.
  `monitor reset halt` before reading, or you may be decoding a previous run's fault.
- **`call f()` from GDB that hits a `BKPT`** leaves a dummy frame on the target stack
  ("GDB remains in the frame where the signal was received"). Do not unwind it by
  hand - `monitor reset halt` and start clean.
- **Faulting-PC lookup without a board:** `arm-none-eabi-objdump -d --start-address=
  <pc-0x20> --stop-address=<pc+0x20> build/firmware.elf`, or `nm -n` and find the last
  symbol below the PC. The hardware-stacked frame is `R0, R1, R2, R3, R12, LR, PC,
  xPSR`, so `x/8wx $sp` in a handler that pushes nothing puts the **7th word** at the
  faulting instruction.

### Phase 1 step 3 - COMPLETE (verified on hardware, 2026-09-10) -> **Phase 1 is done**

GPIO driver in `gpio.c` / `gpio.h`. `main.c` no longer touches `MODER` or `ODR` at all
(grep is clean) - PA5 goes through `gpio_init_output(GPIOA, 5)` and
`gpio_write_pin(GPIOA, 5, GPIO_HIGH | GPIO_LOW)`. LD2 blinks through the driver.
`firmware.elf` is **6200 text / 96 data / 1368 bss**.

Shape that shipped:

- Two public functions, `gpio_init_output(port, pin)` and
  `gpio_write_pin(port, pin, state)`. **`pin` is an index 0-15, not a mask** - the
  header says so twice, because it is the obvious call-site mistake. `state` is a
  `GPIO_state` enum (`GPIO_HIGH` / `GPIO_LOW`), not a bare int.
- **Writes are single stores: `BSRR` to set, `BRR` to clear.** No read-modify-write
  window. The F3 GPIO has a dedicated 16-bit `BRR`; F4 does not (it clears via
  `BSRR[31:16]`). Either works here - the property that matters is that *neither reads
  the register first*. This is what Phase 4 leans on.
- **Init is still RMW** on `MODER` / `OSPEEDR` / `PUPDR` / `OTYPER` (clear the field,
  then set it). Fine at boot, **not** preemption-safe: two tasks initialising pins on
  the same port concurrently is a real race. Known, unguarded, written down - Phase 5's
  critical section is the fix, not a rewrite.
- Port -> `AHBENR` bit mapping is a `static` lookup (`gpio_clock_mask`) over the ports
  this package actually has (A, B, C, D, F - no E on the F302x8). Unknown port and
  out-of-range pin both hit `__BKPT(0)` + spin, same trap-don't-return policy as
  `delay_ticks`. The pin check runs in *both* public functions.
- `__DSB()` after the clock enable, before the first register write to the port.
  Cheap insurance against the enable not having landed by the next store.
- `gpio_init_output(GPIOA, 5)` runs **before** `uart2_init()`; there is an ordering
  comment in `main.c`. `uart2_init` still does its own PA2 setup - that has not moved
  behind the driver, deliberately: the driver has no "alternate function" mode yet and
  Phase 2 does not need one.

Two `TODO`s left in `gpio.c` on purpose: one to re-derive the `MODER` clear/set
arithmetic (answered under "CMSIS naming" in the Phase 0 traps - `_0`/`_1` name bits of
the field, 2 bits per pin, position = pin x 2), and one to bump `OSPEEDR` for PA5
before the Phase 8 logic-analyser capture.

Open, not blocking (carried from step 2, status updated):

- **`uart.c` baud.** ~~`115200` is a bare literal~~ - now `BAUD_RATE` in `uart.c`.
  Still open: the division **truncates** instead of rounding (`(num + den/2) / den`),
  and the three asserts beside it are not written - `BRR` fits 16 bits, `BRR >= 16`
  (required at `OVER8 = 0`; confirm the wording in RM0365's USART chapter), and
  **achieved baud within ~2% of requested**. That last one turns "enabling the PLL
  broke the UART" into a build error naming the file. State the bound without
  subtracting unsigned values - compare scaled products; `115200 * 102` is nowhere near
  32-bit overflow. At 8 MHz the value stays 69 either way, which is exactly why to do
  it *before* the PLL lands and the fraction crosses .5.
- ~~**`get_tick_count` breaks the module-prefix pattern.**~~ Renamed to
  `systick_get_tick_count`. Done.
- **Stale `todo:` comments**, now five: `main.c` on `setvbuf`; `uart.c` on `_write` and
  on the `BRR` derivation; the two in `gpio.c` above. All but the `OSPEEDR` one are
  answered in this file. Delete them or don't - they are not blocking anything.

Carried forward, still true:

- `SystemCoreClock` is *declared* by `system_stm32f3xx.h` but never *defined* -
  `system_stm32f3xx.c` was deliberately not kept. Using it compiles clean and fails at
  link. The fix is `clock.h`, **not** adding ST's file back.

### In progress

**Phase 2 - the context switch.** See "Phase 2, the plan" under "Immediate next
steps" for the brief. Nothing written yet.

### Not started

Phases 3-8. The PLL task is still slotted **between Phase 2 and Phase 3** (see the PLL
section above for why not before).

---

## Project layout (actual, as of Phase 1 complete)

```
preemptive_rtos_kernel/
├── cmsis/
│   ├── Include/                     (core_cm4.h, cmsis_gcc.h, ...)
│   └── Device/ST/STM32F3xx/Include/ (stm32f302x8.h, stm32f3xx.h)
├── src/
│   ├── clock.h     (SYSCLK/HPRE/PPRE1 inputs; HCLK_HZ + PCLK1_HZ derived; asserts)
│   ├── delay.c     (delay_ticks - spin on the tick counter, __BKPT if SysTick is off)
│   ├── delay.h     (delay_ticks decl only)
│   ├── gpio.c      (gpio_init_output, gpio_write_pin via BSRR/BRR; static port->AHBENR
│   │                lookup; __BKPT on bad port or pin)
│   ├── gpio.h      (GPIO_state enum, the two decls; pin is an index, not a mask)
│   ├── main.c      (.data/.bss acceptance checks, blinky through the driver, printf loop)
│   ├── startup.s
│   ├── systick.c   (reload value + its 3 asserts, init, handler, systick_get_tick_count,
│   │                is_systick_initialized; tick_count is static here)
│   ├── systick.h   (TICK_RATE_HZ, MS_PER_SECOND, MS_TO_TICKS, TICKS_TO_MS, decls)
│   ├── uart.c      (uart2_init, uart2_putc, _write)
│   └── uart.h
├── build/          (gitignored)
├── linker.ld
├── Makefile
├── openocd.cfg
├── CLAUDE.md
├── README.md
└── .gitignore      (build/ *.o *.elf *.bin *.map)
```

`constants.h` was deleted; `clock.h` replaces it. Still a flat `src/`, so the
`$(notdir ...)` caveat in the Makefile section has not bitten yet - it will if
Phase 3 adds `src/kernel/`.

**The .h/.c split rule being applied here:** C has no access control. `#include` is
literal text substitution, and a macro defined in a `.c` has no linkage and never
reaches the object file. So "private" is enforced *only* by which file you type it in.
Test: does anything outside this module need it? `TICK_RATE_HZ` and the conversions
are public contract -> header. `SYSTICK_RELOAD_VALUE` is the arithmetic that happens to
satisfy that contract, and only `systick.c` programs `LOAD` -> `.c`. **An assert lives
with the thing it guards**, which is why the clock-tree exactness asserts sit in
`clock.h` and the reload asserts sit in `systick.c`. Once the reload moved out,
`systick.h` needed nothing from `clock.h` and the include went with it.

### openocd.cfg

```tcl
source [find interface/stlink.cfg]
transport select swd
source [find target/stm32f3x.cfg]
adapter speed 1000
```

The ST-LINK only offers fixed divisors, so 1000 gets clamped and every connection
prints `Unable to match requested speed 1000 kHz, using 950 kHz` twice. Purely
cosmetic — it clocks at 950 either way. Setting it to 950 silences the noise.

**This file is only loaded automatically when OpenOCD is invoked with neither `-f`
nor `-c`.** The Makefile's `flash` recipe passes `-c`, so it must also pass
`-f openocd.cfg` explicitly.

### Makefile

The real file is at `Makefile` in the repo root — no copy is kept here, so it can't go
stale. **Written by Claude at my explicit request**, unlike every other file in this
project; the standing no-code rule below still applies to everything else.

Five things it does beyond the original hand-sketched draft, each for a reason:

1. **`ARCH` as a shared variable** spliced into *both* `CFLAGS` and `LDFLAGS`. The
   draft had the arch flags on compile only. That works under `-nostdlib` because no
   libraries get linked — but the moment `printf` pulls in a multilib, the driver uses
   `-mcpu`/`-mthumb`/`-mfloat-abi` to choose which build of libc to link. Without them
   on the link line you get float-ABI errors that read like nonsense.
2. **`-MMD -MP` plus `-include $(DEPS)`.** The draft had no header dependency tracking
   at all — editing a header rebuilt nothing and you'd link a stale object. GCC writes
   a `.d` per object listing every header it consumed; make reads them back as extra
   rules. `-MP` adds phony targets so deleting a header doesn't break the build. (`.s`
   files produce no `.d` — lowercase `.s` skips the preprocessor — and the leading `-`
   on `-include` handles the absence silently.)
3. **`| $(BUILD)` order-only prerequisite.** Two problems in one: cmd's `mkdir` errors
   if the directory exists, and writing objects into `build/` bumps its mtime so
   everything would rebuild forever. Order-only means "ensure it exists, ignore its
   timestamp," so `mkdir` runs exactly once.
4. **Leading `-` on the `clean` recipe** so a second `make clean` doesn't abort. See
   the shell-sensitivity trap above for what this also hides.
5. **`-f openocd.cfg` in the `flash` recipe** — mandatory, see the OpenOCD trap above.

`-O0 -g3` is deliberate: at higher optimization levels GDB lies about variables, and
this project lives in GDB. Note for Phase 8 — a context-switch latency measured at
`-O0` is not a number worth publishing; measure at `-O2` and say which. `-Werror` from
day one is deliberate too: an ignored warning in a context switcher is a hard fault
three weeks later.

`-nostdlib` held until Phase 0 step 8 and is now
`--specs=nano.specs --specs=nosys.specs` plus a hand-written `_write()`.

Known simplification: `OBJS` uses `$(notdir ...)`, which flattens paths. Fine for a
flat `src/`; it breaks the day `src/kernel/sched.c` and `src/sched.c` both exist.
Phase 3 is when that becomes likely.

---

## Immediate next steps

~~1. Finish extracting CMSIS headers; move the Cube clone out; `git init`.~~ Done.
~~2. Read ST's `startup_stm32f302x8.s` and a reference `.ld`.~~ Done.
~~3. Write `linker.ld`.~~ Done — details below kept for reference:
   - `MEMORY`: FLASH `0x08000000` len 64K, RAM `0x20000000` len 16K
   - `.isr_vector` **first** in FLASH — the chip fetches its initial SP from
     `0x08000000` and its reset vector from `0x08000004` before executing anything
   - `.text`, `.rodata` in FLASH
   - `.data` with `>RAM AT >FLASH` — two addresses for one section, the concept that
     makes linker scripts click. Export `_sidata`, `_sdata`, `_edata`
   - `.bss` bracketed by `_sbss`, `_ebss`
   - `_estack` at `0x20004000` (top of RAM)
   - `. = ALIGN(4);` around `.data` and `.bss` — startup copies word-at-a-time
~~4. Write `src/startup.s`.~~ Done — see the Phase 0 section above for what it
   contains. Now at `src/startup.s`. No `SystemInit` call; clock setup comes later.
~~5. Write `src/main.c`: GPIOA clock on **AHBENR**, PA5 output via `MODER`, toggle
   `ODR` in a `volatile`-counter delay loop.~~ Done.
~~6. `make`, then `make flash`.~~ Done — ST's demo firmware is gone.
~~7. Connect GDB through OpenOCD, step through `main`.~~ Done — acceptance test passed.
~~8. Retarget `_write()` to USART2, get `printf` out the VCP.~~ Done.

**Steps 6–8 (build, step, print) were Phase 0. All three work. → Phase 1.**

### Phase 1, in order

~~1. **SysTick at 1 kHz** with a `volatile` tick counter.~~ **Done - verified on
   hardware.** Note the `.map` alone only proves the symbol *exists*; to prove the
   table *points at it*, read slot 15 (exception number 15 -> byte offset `0x3C`) with
   `x/a 0x0800003c`. Expect an **odd** address - bit 0 is the T-bit, and an even
   vector entry takes a UsageFault/`INVSTATE` that escalates to HardFault.
~~2. **`delay_ticks()`** spinning on the tick counter. Deletes the magic `200000`.
   Named for its unit, not `delay_ms` - under option B it takes ticks.~~ **Done -
   verified on hardware.** Kept its unit suffix deliberately: the name is the only
   place the unit is recorded, and Phase 4 adds a *blocking* `os_delay` that must stay
   visibly different at every call site. Once the scheduler exists, a spin-delay in
   task code is a bug but stays legal in boot code and ISRs - so the distinct name is
   what makes the audit greppable.
~~3. **A GPIO driver** — the `set_pin(port, pin, state)` layer. Use `BSRR`, not `ODR`:
   `BSRR` does set and clear as single writes with no read-modify-write window, which
   stops mattering as style and starts mattering as correctness in Phase 4 when a
   preemption can land mid-RMW.~~ **Done - verified on hardware.** Shipped as
   `gpio_write_pin`, writing `BSRR` / `BRR`. See the Phase 1 step 3 section.

Do not derive the SysTick reload value from `SystemCoreClock` — see the note in
"Phase 1 step 3" above about why that link-errors, and why the fix is not ST's file.

**Phase 1 complete (2026-09-10). → Phase 2.**

### Phase 2, the plan

**Goal, stated precisely:** two tasks, each an infinite loop with its own stack, each
doing something *visibly distinct* (different LED pattern, or a private counter
inspectable in GDB). SysTick decides to switch every N ticks; PendSV performs the
switch. No TCB struct, no scheduler, no priorities, no blocking - a hardcoded pair and
a "which one is running" pointer. **Pass criterion: a task interrupted mid-loop resumes
with every register and its local variables exactly as it left them**, and the other
task's state is untouched. Everything after Phase 2 is bookkeeping around this
mechanism.

**The mechanism has two halves, and the boundary between them is the whole trick.**

1. *Hardware half.* On exception entry the core pushes 8 words - `xPSR, PC, LR, R12,
   R3, R2, R1, R0` (that order, top of stack downward) - onto the stack that was active
   in thread mode, then loads a magic value into `LR` (**EXC_RETURN**). On `bx lr` with
   that magic value, it pops the same 8 words from whichever stack the EXC_RETURN bits
   name and resumes at the popped `PC`. Everything the AAPCS calls caller-saved is
   handled here for free.
2. *Software half.* `R4-R11` are callee-saved: the hardware does **not** stack them,
   because a normal handler is a function and functions preserve those. A context
   switch is the one "function" that returns to a *different* caller, so the handler
   itself must push `R4-R11` onto the outgoing task's stack, swap the stack pointer,
   and pop `R4-R11` from the incoming task's stack, *then* `bx lr`. 8 + 8 = **16 words =
   64 bytes per task frame** with the FPU off (`-mfloat-abi=soft`; this is why).

**Six things the hardware requires, each a Phase 2 sub-step:**

- **Two stack pointers.** Handlers run on `MSP`; tasks run on `PSP`. Selected by
  `CONTROL.SPSEL` (bit 1), and by the EXC_RETURN value on exception return:
  `0xFFFFFFF9` = return to thread mode on MSP, `0xFFFFFFFD` = return to thread mode on
  PSP. The switcher reads/writes `PSP` explicitly (`MRS`/`MSR` with the special
  register name) - `SP` inside the handler *is* `MSP`, so pushing to "the stack" there
  saves onto the wrong one. This is the first bug everyone writes.
- **Why PendSV, not SysTick directly.** SysTick can fire while a device ISR is running.
  If SysTick did the switch, it would "return" into a task while that ISR is still
  half-finished on the MSP. PendSV at the *lowest* priority (same 15 as SysTick) is
  guaranteed to run only when no other handler is active, and tail-chains straight
  after SysTick with no extra thread-mode round trip. SysTick's job is to *decide* and
  set `SCB->ICSR` `PENDSVSET`; PendSV's job is to *do*. Set both priorities
  explicitly; the SysTick one is already 15 from Phase 1.
- **A fabricated first frame.** A task that has never run must look, to the restore
  path, exactly like a task that was interrupted at its entry point. So its stack is
  pre-painted with a 16-word frame: `xPSR` with **bit 24 (T) set** - `0x01000000` -
  or the first return takes `INVSTATE`; `PC` = the task function; `LR` = somewhere
  safe to land if the task ever returns (a trap, not garbage); `R0-R3, R12, R4-R11` =
  anything, and recognisable patterns (`0x04040404` in R4, etc.) make a wrong-order
  frame obvious in `x/16wx`. The saved `PSP` for that task points at the *bottom* of
  this frame (lowest address), because the restore pops upward.
- **Alignment.** The stacks are `static` arrays in `.bss`, 8-byte aligned
  (`aligned(8)`), size a multiple of 8. The frame is 64 bytes so alignment survives a
  switch, but a task that calls `printf` needs several hundred bytes of headroom -
  budget 512 B each for Phase 2, or keep `printf` out of the tasks and observe via
  GDB. Reuse the `.if`/`.error` trick from `startup.s` (or `_Static_assert` in C) for
  the size and alignment.
- **The handler must be `naked`.** A normal C function gets a compiler prologue that
  pushes registers and may move `SP`. In the switcher that prologue lands on the MSP
  between exception entry and your code, corrupting the frame arithmetic. `naked`
  means the body is *only* what you write, in inline assembly, and must end with its
  own `bx lr`. Block moves (`STMDB`/`LDMIA` with writeback) save/restore `R4-R11` in
  one instruction each; look up what the `!` writeback does before using it.
- **Bootstrapping the first task.** `main` runs on the MSP. The first task must start
  on the PSP with `CONTROL.SPSEL` set, and there is no "previous task" to save. Two
  honest options: (a) set `PSP` to task 1's pre-painted frame, set `CONTROL`, `ISB`,
  and make the switcher's save path skip when "current" is null; or (b) trigger the
  very first switch via `SVC` so the hardware performs a real exception return into
  the fake frame. Pick one and say why - both are defensible, and Phase 3's `os_start`
  is exactly this decision made permanent. Whatever is chosen, `ISB` after any write to
  `CONTROL` is mandatory (ARMv7-M ARM B1.4.4).

**Verification plan (decide it before writing the handler):**

- Watchpoint on the current-task pointer - the single most useful tool in the project.
  It halts on every switch at full speed; `bt` and `x/16wx $psp` from there.
- Break inside PendSV: `print/x $lr` must be `0xfffffffd`; `print/x $control` must
  show SPSEL. `x/8wx $psp` should decode as the hardware frame with an odd `PC` and
  `0x01000000` in `xPSR`.
- Each task keeps a `volatile` local counter *and* a distinct `R4-R11` footprint
  (e.g. a `register` variable or just a nested call chain). After a few hundred
  switches, both counters advance monotonically and neither has skipped or repeated -
  that is the "resumed exactly" proof.
- Measure nothing yet. `DWT->CYCCNT` and `-O2` numbers are Phase 8.

**Faults to expect, in the order they usually appear:**
`INVSTATE` UsageFault (T bit clear in the fake `xPSR`, or a vector/PC with bit 0
clear) -> HardFault from a garbage `PC` (frame word order wrong; count from the
*low* address: `R0` first, `xPSR` last) -> `INVPC` (EXC_RETURN clobbered, usually
by a non-naked handler or by using `LR` as scratch) -> silent corruption (saved
`R4-R11` on the MSP instead of the PSP - the *worst* one, because it works until it
doesn't). `compare-sections` clean before decoding any of them.

**Reading order:** Yiu ch. 8 (exceptions) and ch. 10 (the switch, "OS support
features") first; Samek lessons 22-23 (two-thread hand switch, then PendSV); the
ARMv7-M ARM B1.5 for the stacking rules when Yiu is ambiguous. **FreeRTOS `port.c`
only after the switch works.**

**Prep before touching the switcher:** none required. `printf` inside tasks is a
stack-budget decision, not a blocker; the `uart.c` rounding/asserts and the PLL are
explicitly after Phase 2.

---

## Phase plan

| Phase | Content | Est. | Status |
|---|---|---|---|
| **0** | Toolchain, own startup/linker/Makefile, blinky on PA5, GDB, `printf` | weekend | ✅ **done** |
| **1** | SysTick at 1 kHz + tick counter, GPIO driver, `delay_ticks()` spinning on ticks | weekend | ✅ **done** (2026-09-10) |
| **2** | **The context switch.** Two hardcoded tasks alternating on SysTick. No scheduler, no priorities. Prove a task can be left mid-execution and resumed exactly | the hard part | ← **here** |
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
  chapters. Search it, don't read it. Obtained. Table 41 is the vector table for
  this part — **not** Table 40.
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