TARGET  = firmware
BUILD   = build

CC      = arm-none-eabi-gcc
OBJCOPY = arm-none-eabi-objcopy
SIZE    = arm-none-eabi-size

# Architecture flags must be identical on compile AND link. With -nostdlib it
# does not matter yet, but as soon as printf pulls in a multilib, the driver
# uses these to pick which build of the library to link.
ARCH    = -mcpu=cortex-m4 -mthumb -mfloat-abi=soft

CFLAGS  = $(ARCH)
CFLAGS += -std=gnu11 -O0 -g3
CFLAGS += -Wall -Wextra -Werror
CFLAGS += -ffunction-sections -fdata-sections
CFLAGS += -MMD -MP
CFLAGS += -Icmsis/Include -Icmsis/Device/ST/STM32F3xx/Include
CFLAGS += -DSTM32F302x8

LDFLAGS  = $(ARCH)
LDFLAGS += -T linker.ld -nostdlib -Wl,--gc-sections
LDFLAGS += -Wl,-Map=$(BUILD)/$(TARGET).map -Wl,--no-warn-rwx-segments

SRCS = src/main.c src/startup.s
OBJS = $(addprefix $(BUILD)/,$(notdir $(SRCS:.c=.o)))
OBJS := $(OBJS:.s=.o)
DEPS = $(OBJS:.o=.d)

all: $(BUILD)/$(TARGET).elf

$(BUILD)/%.o: src/%.c | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/%.o: src/%.s | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/$(TARGET).elf: $(OBJS)
	$(CC) $(OBJS) $(LDFLAGS) -o $@
	$(OBJCOPY) -O binary $@ $(BUILD)/$(TARGET).bin
	$(SIZE) $@

# Order-only prerequisite: build/ must exist, but its timestamp is ignored.
# Without the |, writing any object into build/ bumps the directory mtime and
# every target rebuilds forever. Also, cmd's mkdir errors if the dir exists,
# so this recipe must run exactly once.
$(BUILD):
	mkdir $(BUILD)

# -f openocd.cfg is NOT optional here. OpenOCD only falls back to reading
# openocd.cfg from the cwd when no -f AND no -c are given; passing -c for the
# program command suppresses that default and leaves it with no adapter driver.
flash: $(BUILD)/$(TARGET).elf
	openocd -f openocd.cfg -c "program $< verify reset exit"

# Leading '-' tells make to ignore the exit status. cmd's rmdir errors when
# the directory is already gone, so a second `make clean` would otherwise fail.
clean:
	-rmdir /S /Q $(BUILD)

# Pull in the per-object header dependency files GCC wrote via -MMD.
# Leading '-' because they do not exist on the very first build.
-include $(DEPS)

.PHONY: all clean flash
