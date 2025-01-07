# ----------------------------------------------------------------------------
# Out-of-Tree (OOT) Makefile
# ----------------------------------------------------------------------------

#
# DIRECTORIES
#
BUILD_DIR  ?= build
K          := kernel
U          := user
MKFSDIR    := mkfs

#
# TOOLCHAIN
#
# The TOOLPREFIX logic from your original Makefile can remain as-is.
ifndef TOOLPREFIX
TOOLPREFIX := $(shell if riscv64-unknown-elf-objdump -i 2>&1 | grep 'elf64-big' >/dev/null 2>&1; \
	then echo 'riscv64-unknown-elf-'; \
	elif riscv64-linux-gnu-objdump -i 2>&1 | grep 'elf64-big' >/dev/null 2>&1; \
	then echo 'riscv64-linux-gnu-'; \
	elif riscv64-unknown-linux-gnu-objdump -i 2>&1 | grep 'elf64-big' >/dev/null 2>&1; \
	then echo 'riscv64-unknown-linux-gnu-'; \
	else echo "***" 1>&2; \
	echo "*** Error: Couldn't find a riscv64 version of GCC/binutils." 1>&2; \
	echo "*** To turn off this error, run 'gmake TOOLPREFIX= ...'." 1>&2; \
	echo "***" 1>&2; exit 1; fi)
endif

QEMU      := qemu-system-riscv64
CC        := $(TOOLPREFIX)gcc
AS        := $(TOOLPREFIX)gas
LD        := $(TOOLPREFIX)ld
OBJCOPY   := $(TOOLPREFIX)objcopy
OBJDUMP   := $(TOOLPREFIX)objdump

#
# FLAGS
#
CFLAGS  = -Wall -Werror -O -fno-omit-frame-pointer -ggdb -gdwarf-2
CFLAGS += -MD -mcmodel=medany
CFLAGS += -fno-common -nostdlib
CFLAGS += -fno-builtin-strncpy -fno-builtin-strncmp -fno-builtin-strlen -fno-builtin-memset
CFLAGS += -fno-builtin-memmove -fno-builtin-memcmp -fno-builtin-log -fno-builtin-bzero
CFLAGS += -fno-builtin-strchr -fno-builtin-exit -fno-builtin-malloc -fno-builtin-putc
CFLAGS += -fno-builtin-free
CFLAGS += -fno-builtin-memcpy -Wno-main
CFLAGS += -fno-builtin-printf -fno-builtin-fprintf -fno-builtin-vprintf
CFLAGS += -I.
CFLAGS += $(shell $(CC) -fno-stack-protector -E -x c /dev/null >/dev/null 2>&1 && echo -fno-stack-protector)

# Disable PIE when possible
ifneq ($(shell $(CC) -dumpspecs 2>/dev/null | grep -e '[^f]no-pie'),)
CFLAGS += -fno-pie -no-pie
endif
ifneq ($(shell $(CC) -dumpspecs 2>/dev/null | grep -e '[^f]nopie'),)
CFLAGS += -fno-pie -nopie
endif

LDFLAGS = -z max-page-size=4096

#
# KERNEL OBJECTS -- note that we refer to them by their "source" names;
# the actual .o files are redirected into BUILD_DIR below.
#
OBJS = \
  $(K)/entry.o \
  $(K)/start.o \
  $(K)/console.o \
  $(K)/printf.o \
  $(K)/uart.o \
  $(K)/kalloc.o \
  $(K)/spinlock.o \
  $(K)/string.o \
  $(K)/main.o \
  $(K)/vm.o \
  $(K)/proc.o \
  $(K)/swtch.o \
  $(K)/trampoline.o \
  $(K)/trap.o \
  $(K)/syscall.o \
  $(K)/sysproc.o \
  $(K)/bio.o \
  $(K)/fs.o \
  $(K)/log.o \
  $(K)/sleeplock.o \
  $(K)/file.o \
  $(K)/pipe.o \
  $(K)/exec.o \
  $(K)/sysfile.o \
  $(K)/kernelvec.o \
  $(K)/plic.o \
  $(K)/virtio_disk.o

#
# Transform the "kernel/*.o" into "build/kernel/*.o"
# So $(K)/entry.o => $(BUILD_DIR)/kernel/entry.o, etc.
#
KOBJS := $(patsubst $(K)/%.o,$(BUILD_DIR)/$(K)/%.o,$(OBJS))

#
# USER BITS
#
ULIB = \
  $(BUILD_DIR)/$(U)/ulib.o \
  $(BUILD_DIR)/$(U)/usys.o \
  $(BUILD_DIR)/$(U)/printf.o \
  $(BUILD_DIR)/$(U)/umalloc.o



INITCODE = $(BUILD_DIR)/$(U)/initcode
INITCODE_O = $(BUILD_DIR)/$(U)/initcode.o
INITCODE_OUT = $(BUILD_DIR)/$(U)/initcode.out

#
# FINAL KERNEL OUTPUT (in the build directory)
#
KERNEL_BIN = $(BUILD_DIR)/$(K)/kernel

#
# BUILD RULES
#

# Default target: build kernel + fs.img
all: $(KERNEL_BIN) fs.img

#
# Kernel linking
#
$(KERNEL_BIN): $(KOBJS) $(K)/kernel.ld $(INITCODE)
	@mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -T $(K)/kernel.ld -o $@ $(KOBJS)
	$(OBJDUMP) -S $@ > $(BUILD_DIR)/$(K)/kernel.asm
	$(OBJDUMP) -t $@ | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > $(BUILD_DIR)/$(K)/kernel.sym

#
# Pattern rules for kernel object files
#   e.g.  build/kernel/foo.o <- kernel/foo.c
#         build/kernel/foo.o <- kernel/foo.S
#
$(BUILD_DIR)/$(K)/%.o: $(K)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -march=rv64g -c -o $@ $<

$(BUILD_DIR)/$(K)/%.o: $(K)/%.S
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -march=rv64g -c -o $@ $<

#
# initcode (build/user/initcode)
#
$(INITCODE): $(INITCODE_OUT)
	@# Convert ELF to raw binary
	$(OBJCOPY) -S -O binary $(INITCODE_OUT) $@
	@# Dump asm for debugging
	$(OBJDUMP) -S $(INITCODE_O) > $(BUILD_DIR)/$(U)/initcode.asm

$(INITCODE_OUT): $(INITCODE_O)
	$(LD) $(LDFLAGS) -N -e start -Ttext 0 -o $@ $(INITCODE_O)

$(INITCODE_O): $(U)/initcode.S
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -march=rv64g -nostdinc -I. -I$(K) -c $< -o $@

#
# Pattern rules for user object files (common library code, etc.)
#
$(BUILD_DIR)/$(U)/%.o: $(U)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILD_DIR)/$(U)/%.o: $(BUILD_DIR)/$(U)/%.S
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

#
# usys.S from usys.pl
#
$(BUILD_DIR)/$(U)/usys.S: $(U)/usys.pl
	@mkdir -p $(dir $@)
	perl $(U)/usys.pl > $@

#
# Example user program link rule: create a user binary from .o’s + ULIB
# If you have many user programs, you can do pattern rules or explicit lines.
#
$(BUILD_DIR)/$(U)/_%: $(BUILD_DIR)/$(U)/%.o $(ULIB)
	@mkdir -p $(dir $@)
	$(LD) $(LDFLAGS) -T $(U)/user.ld -o $@ $^
	$(OBJDUMP) -S $@ > $(BUILD_DIR)/$(U)/cat.asm
	$(OBJDUMP) -t $@ | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > $@.sym

#
# Example user programs we want to put in the file system
# (You’ll need to define build rules for each)
#

UPROGS=\
	$(BUILD_DIR)/$(U)/_cat\
	$(BUILD_DIR)/$(U)/_echo\
	$(BUILD_DIR)/$(U)/_forktest\
	$(BUILD_DIR)/$(U)/_grep\
	$(BUILD_DIR)/$(U)/_init\
	$(BUILD_DIR)/$(U)/_kill\
	$(BUILD_DIR)/$(U)/_ln\
	$(BUILD_DIR)/$(U)/_ls\
	$(BUILD_DIR)/$(U)/_mkdir\
	$(BUILD_DIR)/$(U)/_rm\
	$(BUILD_DIR)/$(U)/_sh\
	$(BUILD_DIR)/$(U)/_stressfs\
	$(BUILD_DIR)/$(U)/_usertests\
	$(BUILD_DIR)/$(U)/_grind\
	$(BUILD_DIR)/$(U)/_wc\
	$(BUILD_DIR)/$(U)/_zombie\

#
# Build mkfs and produce fs.img
#
MKFS_BIN = $(BUILD_DIR)/mkfs/mkfs
fs.img: $(MKFS_BIN) README $(UPROGS)
	@mkdir -p $(dir $@)
	$(MKFS_BIN) fs.img README $(UPROGS)

$(MKFS_BIN): $(MKFSDIR)/mkfs.c $(K)/fs.h $(K)/param.h
	@mkdir -p $(dir $@)
	gcc -Werror -Wall -I. -o $@ $<

#
# Clean up all build artifacts
#
clean:
	rm -rf $(BUILD_DIR) fs.img

#
# QEMU convenience
#
CPUS     ?= 3
GDBPORT  = $(shell expr `id -u` % 5000 + 25000)
QEMUGDB  = $(shell if $(QEMU) -help | grep -q '^-gdb'; \
	       then echo "-gdb tcp::$(GDBPORT)"; \
	       else echo "-s -p $(GDBPORT)"; fi)
QEMUOPTS = -machine virt -bios none -kernel $(KERNEL_BIN) -m 128M -smp $(CPUS) -nographic
QEMUOPTS += -global virtio-mmio.force-legacy=false
QEMUOPTS += -drive file=fs.img,if=none,format=raw,id=x0
QEMUOPTS += -device virtio-blk-device,drive=x0,bus=virtio-mmio-bus.0

qemu: $(KERNEL_BIN) fs.img
	$(QEMU) $(QEMUOPTS)

qemu-gdb: $(KERNEL_BIN) fs.img
	@echo "*** Now run 'gdb' in another window."
	$(QEMU) $(QEMUOPTS) -S $(QEMUGDB)

#
# Include automatically generated .d files (dependencies)
# They live in build/kernel/*.d, build/user/*.d, etc.
#
-include $(KOBJS:.o=.d)
-include $(ULIB:.o=.d)
-include $(BUILD_DIR)/$(U)/initcode.d
# (And so on for any other object files)
