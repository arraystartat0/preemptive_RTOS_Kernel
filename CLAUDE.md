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
after PA5 setup; `print/x USART2->CR1` should have bits 0 and 3 set. The compiler
cannot know which register you *meant* — only the silicon can tell you.

**Linker script**

- **`.isr_vector` must be the first output section in `SECTIONS`.** `.ARM.extab` and
  `.ARM` were briefly placed above it. Both were size 0, so `.isr_vector` still landed
  at `0x08000000` and everything worked — a latent landmine that detonates the moment
  unwind data appears (C++, `-funwind-tables`). Fixed; keep it first.

### In progress

**Phase 1.** Nothing written yet. Next concrete task: SysTick at 1 kHz with a tick
counter, then a GPIO driver, then `delay_ms()` spinning on ticks — which is what
finally deletes the magic `200000` from the `volatile` delay loop.

Two things to carry forward into Phase 1:

- `BRR` is currently the literal expression `8000000 / 115200`. The moment the PLL
  comes up, PCLK1 stops being 8 MHz and that divisor is wrong. Same for any SysTick
  reload value derived from an assumed clock.
- `SystemCoreClock` is *declared* by `system_stm32f3xx.h` but never *defined* —
  `system_stm32f3xx.c` was deliberately not kept. Using it compiles clean and fails at
  link. The fix is your own clock constant, **not** adding ST's file back, which does
  full PLL setup.

### Not started

Phases 2–8.

---

## Project layout (actual, as of end of Phase 0)

```
preemptive_rtos_kernel/
├── cmsis/
│   ├── Include/                     (core_cm4.h, cmsis_gcc.h, ...)
│   └── Device/ST/STM32F3xx/Include/ (stm32f302x8.h, stm32f3xx.h)
├── src/
│   ├── main.c      (checks, blinky, uart2_init/putc, _write, printf)
│   └── startup.s
├── build/          (gitignored)
├── linker.ld
├── Makefile
├── openocd.cfg
├── CLAUDE.md
├── README.md
└── .gitignore      (build/ *.o *.elf *.bin *.map)
```

`main.c` will need splitting in Phase 1 — the UART and GPIO code belongs in drivers,
not next to `main`. Watch the `$(notdir ...)` caveat in the Makefile section if that
means adding subdirectories under `src/`.

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

1. **SysTick at 1 kHz** with a `volatile` tick counter incremented in
   `SysTick_Handler`. The handler name must match the vector table exactly — a
   misspelled handler is silent, because the weak alias to `Default_Handler` just
   keeps winning. Check the `.map` if it never fires.
2. **`delay_ms()`** spinning on the tick counter. Deletes the magic `200000`.
3. **A GPIO driver** — the `set_pin(port, pin, state)` layer. Use `BSRR`, not `ODR`:
   `BSRR` does set and clear as single writes with no read-modify-write window, which
   stops mattering as style and starts mattering as correctness in Phase 4 when a
   preemption can land mid-RMW.

Do not derive the SysTick reload value from `SystemCoreClock` — see the note in
"In progress" above about why that link-errors, and why the fix is not ST's file.

---

## Phase plan

| Phase | Content | Est. | Status |
|---|---|---|---|
| **0** | Toolchain, own startup/linker/Makefile, blinky on PA5, GDB, `printf` | weekend | ✅ **done** |
| **1** | SysTick at 1 kHz + tick counter, GPIO driver, `delay_ms()` spinning on ticks | weekend | ← next |
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