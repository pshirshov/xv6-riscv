MAKEFLAGS += --no-builtin-rules

include Makefile.inc

B          ?= build
K		   := kernel
U          := user

S_OBJS = \
  $K/entry.o \
  $K/start.o \
  $K/console.o \
  $K/printf.o \
  $K/uart.o \
  $K/kalloc.o \
  $K/spinlock.o \
  $K/string.o \
  $K/main.o \
  $K/vm.o \
  $K/proc.o \
  $K/swtch.o \
  $K/trampoline.o \
  $K/trap.o \
  $K/syscall.o \
  $K/sysproc.o \
  $K/bio.o \
  $K/fs.o \
  $K/log.o \
  $K/sleeplock.o \
  $K/file.o \
  $K/pipe.o \
  $K/exec.o \
  $K/sysfile.o \
  $K/kernelvec.o \
  $K/plic.o \
  $K/virtio_disk.o

OBJS := $(patsubst $(K)/%.o,$(B)/$(K)/%.o,$(S_OBJS))

LDFLAGS = -z max-page-size=4096

$(B)/$(K)/%.o: $(K)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -march=rv64g -c -o $@ $<

$(B)/$(K)/%.o: $(K)/%.S
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -march=rv64g -c -o $@ $<

$(B)/$(U)/%.o: $(U)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -march=rv64g -c -o $@ $<

$B/$K/kernel: $(OBJS) $K/kernel.ld $B/$U/initcode
	$(LD) $(LDFLAGS) -T $K/kernel.ld -o $B/$K/kernel $(OBJS)
	$(OBJDUMP) -S $B/$K/kernel > $B/$K/kernel.asm
	$(OBJDUMP) -t $B/$K/kernel | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > $B/$K/kernel.sym

$B/$U/initcode: $U/initcode.S
	$(CC) $(CFLAGS) -march=rv64g -nostdinc -I. -Ikernel -c $U/initcode.S -o $B/$U/initcode.o
	$(LD) $(LDFLAGS) -N -e start -Ttext 0 -o $B/$U/initcode.out $B/$U/initcode.o
	$(OBJCOPY) -S -O binary $B/$U/initcode.out $B/$U/initcode
	$(OBJDUMP) -S $B/$U/initcode.o > $B/$U/initcode.asm

tags: $(OBJS) _init
	etags *.S *.c

S_ULIB = $U/ulib.o $U/usys.o $U/printf.o $U/umalloc.o
ULIB := $(patsubst $(U)/%.o,$(B)/$(U)/%.o,$(S_ULIB))

$B/$U/_%: $B/$U/%.o $(ULIB)
	$(LD) $(LDFLAGS) -T $U/user.ld -o $@ $^
	$(OBJDUMP) -S $@ > $B/$U/$*.asm
	$(OBJDUMP) -t $@ | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > $B/$U/$*.sym

$B/$U/usys.S : $U/usys.pl
	perl $U/usys.pl > $B/$U/usys.S

$B/$U/usys.o : $B/$U/usys.S
	$(CC) $(CFLAGS) -c -o $B/$U/usys.o $B/$U/usys.S

$B/$U/_forktest: $B/$U/forktest.o $(ULIB)
	# forktest has less library code linked in - needs to be small
	# in order to be able to max out the proc table.
	$(LD) $(LDFLAGS) -N -e main -Ttext 0 -o $B/$U/_forktest $B/$U/forktest.o $B/$U/ulib.o $B/$U/usys.o
	$(OBJDUMP) -S $B/$U/_forktest > $B/$U/forktest.asm

$B/mkfs: mkfs/mkfs.c $K/fs.h $K/param.h
	gcc -Werror -Wall -I. -o $B/mkfs mkfs/mkfs.c

# Prevent deletion of intermediate files, e.g. cat.o, after first build, so
# that disk image changes after first build are persistent until clean.  More
# details:
# http://www.gnu.org/software/make/manual/html_node/Chained-Rules.html
.PRECIOUS: %.o

S_UPROGS=\
	$U/_cat\
	$U/_echo\
	$U/_forktest\
	$U/_grep\
	$U/_init\
	$U/_kill\
	$U/_ln\
	$U/_ls\
	$U/_mkdir\
	$U/_rm\
	$U/_sh\
	$U/_stressfs\
	$U/_usertests\
	$U/_grind\
	$U/_wc\
	$U/_zombie\

UPROGS := $(patsubst $(U)/_%,$(B)/$(U)/_%,$(S_UPROGS))

$B/fs.img: $B/mkfs README $(UPROGS)
	$B/mkfs $B/fs.img README $(UPROGS)

-include $B/kernel/*.d $B/user/*.d

clean:
	rm -f *.tex *.dvi *.idx *.aux *.log *.ind *.ilg \
	*/*.o */*.d */*.asm */*.sym \
	$U/initcode $U/initcode.out $K/kernel fs.img \
	mkfs/mkfs .gdbinit \
        $U/usys.S \
	$(UPROGS)

bins: $B/$K/kernel $B/fs.img

all: bins

qemu: bins
	$(QEMU) $(QEMUOPTS)

.gdbinit: .gdbinit.tmpl-riscv
	sed "s/:1234/:$(GDBPORT)/" < $^ > $@

qemu-gdb: all .gdbinit
	@echo "*** Now run 'gdb' in another window." 1>&2
	$(QEMU) $(QEMUOPTS) -S $(QEMUGDB)

