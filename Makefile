K=kernel
U=user
L=include

OBJS = \
	$K/bio.o\
	$K/console.o\
	$K/exec.o\
	$K/file.o\
	$K/fs.o\
	$K/ide.o\
	$K/ioapic.o\
	$K/kalloc.o\
	$K/kbd.o\
	$K/lapic.o\
	$K/log.o\
	$K/main.o\
	$K/mp.o\
	$K/picirq.o\
	$K/pipe.o\
	$K/proc.o\
	$K/sleeplock.o\
	$K/spinlock.o\
	$K/string.o\
	$K/swtch.o\
	$K/syscall.o\
	$K/sysfile.o\
	$K/sysproc.o\
	$K/trapasm.o\
	$K/trap.o\
	$K/uart.o\
	$K/vectors.o\
	$K/vm.o\

# Cross-compiling (e.g., on Mac OS X)
# TOOLPREFIX = i386-jos-elf

# Using native tools (e.g., on X86 Linux)
#TOOLPREFIX = x86_64-linux-gnu-

# Try to infer the correct TOOLPREFIX if not set
ifndef TOOLPREFIX
TOOLPREFIX := $(shell if i386-jos-elf-objdump -i 2>&1 | grep '^elf32-i386$$' >/dev/null 2>&1; \
	then echo 'i386-jos-elf-'; \
	elif objdump -i 2>&1 | grep 'elf32-i386' >/dev/null 2>&1; \
	then echo ''; \
	else echo "***" 1>&2; \
	echo "*** Error: Couldn't find an i386-*-elf version of GCC/binutils." 1>&2; \
	echo "*** Is the directory with i386-jos-elf-gcc in your PATH?" 1>&2; \
	echo "*** If your i386-*-elf toolchain is installed with a command" 1>&2; \
	echo "*** prefix other than 'i386-jos-elf-', set your TOOLPREFIX" 1>&2; \
	echo "*** environment variable to that prefix and run 'make' again." 1>&2; \
	echo "*** To turn off this error, run 'gmake TOOLPREFIX= ...'." 1>&2; \
	echo "***" 1>&2; exit 1; fi)
endif

# If the makefile can't find QEMU, specify its path here
# QEMU = qemu-system-i386

# Try to infer the correct QEMU
ifndef QEMU
QEMU = $(shell if which qemu > /dev/null; \
	then echo qemu; exit; \
	elif which qemu-system-i386 > /dev/null; \
	then echo qemu-system-i386; exit; \
	elif which qemu-system-x86_64 > /dev/null; \
	then echo qemu-system-x86_64; exit; \
	else \
	qemu=/Applications/Q.app/Contents/MacOS/i386-softmmu.app/Contents/MacOS/i386-softmmu; \
	if test -x $$qemu; then echo $$qemu; exit; fi; fi; \
	echo "***" 1>&2; \
	echo "*** Error: Couldn't find a working QEMU executable." 1>&2; \
	echo "*** Is the directory containing the qemu binary in your PATH" 1>&2; \
	echo "*** or have you tried setting the QEMU variable in Makefile?" 1>&2; \
	echo "***" 1>&2; exit 1)
endif

CC = $(TOOLPREFIX)gcc
AS = $(TOOLPREFIX)gas
LD = $(TOOLPREFIX)ld
OBJCOPY = $(TOOLPREFIX)objcopy
OBJDUMP = $(TOOLPREFIX)objdump
CFLAGS = -fno-pic -static -fno-builtin -fno-strict-aliasing -O2 -Wall -MD -ggdb -m32 -fno-omit-frame-pointer
CFLAGS += -ffreestanding -fno-common -nostdlib -O0
CFLAGS += -I. -I./include
CFLAGS += $(shell $(CC) -fno-stack-protector -E -x c /dev/null >/dev/null 2>&1 && echo -fno-stack-protector)
ASFLAGS = -m32 -gdwarf-2 -Wa,-divide -I./include -O0
# FreeBSD ld wants ``elf_i386_fbsd''
LDFLAGS += -m $(shell $(LD) -V | grep elf_i386 2>/dev/null | head -n 1)

# Disable PIE when possible (for Ubuntu 16.10 toolchain)
ifneq ($(shell $(CC) -dumpspecs 2>/dev/null | grep -e '[^f]no-pie'),)
CFLAGS += -fno-pie -no-pie
endif
ifneq ($(shell $(CC) -dumpspecs 2>/dev/null | grep -e '[^f]nopie'),)
CFLAGS += -fno-pie -nopie
endif

xv6.img: $K/bootblock $K/kernel
	dd if=/dev/zero of=xv6.img count=10000
	dd if=$K/bootblock of=xv6.img conv=notrunc
	dd if=$K/kernel of=xv6.img seek=1 conv=notrunc

xv6memfs.img: $K/bootblock $K/kernelmemfs
	dd if=/dev/zero of=xv6memfs.img count=10000
	dd if=$K/bootblock of=xv6memfs.img conv=notrunc
	dd if=$K/kernelmemfs of=xv6memfs.img seek=1 conv=notrunc

$K/bootblock: $K/bootasm.S $K/bootmain.c
	$(CC) $(CFLAGS) -fno-pic -O -nostdinc -I. -Ikernel -c $K/bootmain.c -o $K/bootmain.o
	$(CC) $(CFLAGS) -fno-pic -nostdinc -I. -Ikernel -c $K/bootasm.S -o $K/bootasm.o
	$(LD) $(LDFLAGS) -N -e start -Ttext 0x7C00 -o $K/bootblock.o $K/bootasm.o $K/bootmain.o
	$(OBJDUMP) -S $K/bootblock.o > $K/bootblock.asm
	$(OBJCOPY) -S -O binary -j .text $K/bootblock.o $K/bootblock
	$K/sign.pl $K/bootblock

$K/entryother: $K/entryother.S
	$(CC) $(CFLAGS) -fno-pic -nostdinc -I. -Ikernel -c $K/entryother.S -o $K/entryother.o
	$(LD) $(LDFLAGS) -N -e start -Ttext 0x7000 -o $K/bootblockother.o $K/entryother.o
	$(OBJCOPY) -S -O binary -j .text $K/bootblockother.o $K/entryother
	$(OBJDUMP) -S $K/bootblockother.o > $K/entryother.asm

$K/%.o: $K/%.c
	$(CC) $(CFLAGS) -c -o $@ $<

$U/initcode: $U/initcode.S
	$(CC) $(CFLAGS) -nostdinc -I. -Ikernel -c $U/initcode.S -o $U/initcode.o
	$(LD) $(LDFLAGS) -N -e start -Ttext 0 -o $U/initcode.out $U/initcode.o
	$(OBJCOPY) -S -O binary $U/initcode.out $U/initcode
	$(OBJDUMP) -S $U/initcode.o > $U/initcode.asm

$U/usys: $U/usys.S
	$(CC) -I. -I./include -nostdinc -c $U/usys.S -o $U/usys.o
	$(LD) $(LDFLAGS) -N -e start -Ttext 0 -o $U/usys.out $U/usys.o
	$(OBJCOPY) -S -O binary $U/usys.out $U/usys
	$(OBJDUMP) -S $U/usys.o > $U/usys.asm

$K/kernel: $(OBJS) $K/entry.o $K/entryother $U/initcode $K/kernel.ld
	$(LD) $(LDFLAGS) -T $K/kernel.ld -o $K/kernel $K/entry.o $(OBJS) -b binary $U/initcode $K/entryother
	$(OBJDUMP) -S $K/kernel > $K/kernel.asm
	$(OBJDUMP) -t $K/kernel | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > $K/kernel.sym

# kernelmemfs is a copy of kernel that maintains the
# disk image in memory instead of writing to a disk.
# This is not so useful for testing persistent storage or
# exploring disk buffering implementations, but it is
# great for testing the kernel on real hardware without
# needing a scratch disk.
MEMFSOBJS = $(filter-out $K/ide.o,$(OBJS)) $K/memide.o
$K/kernelmemfs: $(MEMFSOBJS) $K/entry.o $K/entryother $U/initcode $K/kernel.ld fs.img
	$(LD) $(LDFLAGS) -T $K/kernel.ld -o $K/kernelmemfs $K/entry.o  $(MEMFSOBJS) -b binary $U/initcode $K/entryother fs.img
	$(OBJDUMP) -S $K/kernelmemfs > $K/kernelmemfs.asm
	$(OBJDUMP) -t $K/kernelmemfs | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > $K/kernelmemfs.sym

tags: $(OBJS) $K/entryother.S _init
	etags *.S *.c

$K/vectors.S: $K/vectors.pl
	$K/vectors.pl > $K/vectors.S

#ULIB = $U/libc.o $U/usys.o $U/printf.o $U/umalloc.o 
CLIB = $U/curses.o $U/sl.o
ULIB = $U/libc.o $U/usys.o $U/printf.o

_%: %.o $(ULIB)
	$(LD) $(LDFLAGS) -N -e main -Ttext 0 -o $@ $^
	$(OBJDUMP) -S $@ > $*.asm
	$(OBJDUMP) -t $@ | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > $*.sym

$U/sl: $U/sl.o $U/curses.o
	$(LD) $(LDFLAGS) -N -e  0 -o $@ $< $(ULIB) -f __UCC_HEAP_START
	$(OBJDUMP) -S $@ > $*.asm
	$(OBJDUMP) -t $@ | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > $*.sym

$U/_forktest: $U/forktest.o $(ULIB)
	# forktest has less library code linked in - needs to be small
	# in order to be able to max out the proc table.
	$(LD) $(LDFLAGS) -N -e main -Ttext 0 -o $U/_forktest $U/forktest.o $U/libc.o $U/usys.o $U/printf.o
	$(OBJDUMP) -S $U/_forktest > $U/forktest.asm


mkfs/mkfs: mkfs/mkfs.c $L/fs.h 
	gcc  -Werror -Wall -I. -o mkfs/mkfs mkfs/mkfs.c 

# Prevent deletion of intermediate files, e.g. cat.o, after first build, so
# that disk image changes after first build are persistent until clean.  More
# details:
# http://www.gnu.org/software/make/manual/html_node/Chained-Rules.html
.PRECIOUS: %.o

UPROGS=\
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
	$U/_wc\
	$U/_zombie\
	$U/_minesweeper\
    $U/_vi\
    $U/_2048\
    

	

fs.img: mkfs/mkfs README $(UPROGS)
	mkfs/mkfs fs.img README $(UPROGS)

-include kernel/*.d user/*.d

clean: 
	rm -f *.tex *.dvi *.idx *.aux *.log *.ind *.ilg \
	$K/*.o $K/*.d $U/*.o $U/*.d *.o *.d $K/*.asm $K/*.sym $U/*.asm $U/*.sym $K/vectors.S $K/bootblock $K/entryother \
	$U/initcode $U/initcode.out $K/kernel xv6.img fs.img $K/kernelmemfs \
	xv6memfs.img mkfs/mkfs .gdbinit \
	$(UPROGS)

# make a printout
FILES = $(shell grep -v '^\#' runoff.list)
PRINT = runoff.list runoff.spec README toc.hdr toc.ftr $(FILES)

xv6.pdf: $(PRINT)
	./runoff
	ls -l xv6.pdf

print: xv6.pdf

# run in emulators

bochs : fs.img xv6.img
	if [ ! -e .bochsrc ]; then ln -s dot-bochsrc .bochsrc; fi
	bochs -q

# try to generate a unique GDB port
GDBPORT = $(shell expr `id -u` % 5000 + 25000)
# QEMU's gdb stub command line changed in 0.11
QEMUGDB = $(shell if $(QEMU) -help | grep -q '^-gdb'; \
	then echo "-gdb tcp::$(GDBPORT)"; \
	else echo "-s -p $(GDBPORT)"; fi)
ifndef CPUS
CPUS := 2
endif
QEMUOPTS = -drive file=fs.img,index=1,media=disk,format=raw -drive file=xv6.img,index=0,media=disk,format=raw -smp $(CPUS) -m 512 $(QEMUEXTRA)

qemu: fs.img xv6.img
	$(QEMU) -serial mon:stdio $(QEMUOPTS)

qemu-memfs: xv6memfs.img
	$(QEMU) -drive file=xv6memfs.img,index=0,media=disk,format=raw -smp $(CPUS) -m 256

qemu-nox: fs.img xv6.img
	$(QEMU) -nographic $(QEMUOPTS)

.gdbinit: .gdbinit.tmpl
	sed "s/localhost:1234/localhost:$(GDBPORT)/" < $^ > $@

qemu-gdb: fs.img xv6.img .gdbinit
	@echo "*** Now run 'gdb'." 1>&2
	$(QEMU) -serial mon:stdio $(QEMUOPTS) -S $(QEMUGDB)

qemu-nox-gdb: fs.img xv6.img .gdbinit
	@echo "*** Now run 'gdb'." 1>&2
	$(QEMU) -nographic $(QEMUOPTS) -S $(QEMUGDB)

# CUT HERE
# prepare dist for students
# after running make dist, probably want to
# rename it to rev0 or rev1 or so on and then
# check in that version.

EXTRA=\
	mkfs/mkfs.c $U/libc.c $U/user.h $U/cat.c $U/echo.c $U/forktest.c $U/grep.c $U/kill.c\
	$U/ln.c $U/ls.c $U/mkdir.c $U/rm.c $U/stressfs.c $U/usertests.c $U/wc.c $U/zombie.c\
	README dot-bochsrc $K/*.pl toc.* runoff runoff1 runoff.list\
	.gdbinit.tmpl gdbutil\

dist:
	rm -rf dist
	mkdir dist
	for i in $(FILES); \
	do \
		grep -v PAGEBREAK $$i >dist/$$i; \
	done
	sed '/CUT HERE/,$$d' Makefile >dist/Makefile
	echo >dist/runoff.spec
	cp $(EXTRA) dist

dist-test:
	rm -rf dist
	make dist
	rm -rf dist-test
	mkdir dist-test
	cp dist/* dist-test
	cd dist-test; $(MAKE) print
	cd dist-test; $(MAKE) bochs || true
	cd dist-test; $(MAKE) qemu

# update this rule (change rev#) when it is time to
# make a new revision.
tar:
	rm -rf /tmp/xv6
	mkdir -p /tmp/xv6
	cp dist/* dist/.gdbinit.tmpl /tmp/xv6
	(cd /tmp; tar cf - xv6) | gzip >xv6-rev10.tar.gz  # the next one will be 10 (9/17)

.PHONY: dist-test dist
