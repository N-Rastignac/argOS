# Makefile — module 01-environnement
#
# Cibles :
#   make            → build/kernel.elf
#   make run        → QEMU : écran VGA dans une fenêtre, port série sur ce terminal
#   make run-nox    → QEMU sans fenêtre (série seulement), pratique en SSH
#   make debug      → QEMU gelé (-s -S) + GDB attaché avec tools/gdbinit
#   make test       → boote en headless, compare la sortie série à tests/expected.txt
#   make check      → vérifie l'en-tête Multiboot sans GRUB (tools/check-multiboot.py)
#   make smoke      → exécute le noyau dans Unicorn, sans QEMU (pip install unicorn pyelftools)
#   make iso        → build/os.iso avec GRUB (grub-mkrescue requis)
#   make run-iso    → boote l'ISO
#   make clean
#
# Variables : OPT=-O0 (défaut, pour GDB) ou -O2 ; QEMUFLAGS="-d int" ;
#             EXTRA_CFLAGS=... (options de compilation supplémentaires)
#
# check, smoke et debug utilisent les scripts de $(ROOT)/tools.

MODULE   := 01-environnement
ROOT     := .
BUILD    := build
KERNEL   := $(BUILD)/kernel.elf

# ---------------------------------------------------------------------------
# Toolchain : cross-compilateur i686-elf si présent, sinon gcc hôte en -m32.
# ---------------------------------------------------------------------------
CROSS    ?= i686-elf-
ifneq (,$(shell command -v $(CROSS)gcc 2>/dev/null))
  CC      := $(CROSS)gcc
  ARCHFLAGS :=
  LIBS    := -lgcc
else
  $(warning [Makefile] $(CROSS)gcc introuvable : repli sur "gcc -m32" (voir tools/install-toolchain.sh).)
  CC      := gcc
  # gcc hôte : désactiver ce qui suppose un OS sous-jacent (PIE/PIC).
  ARCHFLAGS := -m32 -fno-pie -fno-pic -no-pie
  LIBS    :=
endif

OPT         ?= -O0
EXTRA_CFLAGS ?=
CFLAGS   := $(ARCHFLAGS) $(OPT) -g -std=gnu11 -ffreestanding -Wall -Wextra \
            -fno-stack-protector -fno-asynchronous-unwind-tables \
            -mgeneral-regs-only -iquote src $(EXTRA_CFLAGS)
ASFLAGS  := $(ARCHFLAGS) -g
LDFLAGS  := $(ARCHFLAGS) -ffreestanding -nostdlib -T linker.ld -Wl,--build-id=none

SRC_C    := $(wildcard src/*.c)
SRC_S    := $(wildcard src/*.s)
OBJ      := $(patsubst src/%.c,$(BUILD)/%.o,$(SRC_C)) \
            $(patsubst src/%.s,$(BUILD)/%.o,$(SRC_S))

# ---------------------------------------------------------------------------
# QEMU
# ---------------------------------------------------------------------------
QEMU      ?= qemu-system-i386
QEMUFLAGS ?=
QEMU_BASE := -m 64M -no-reboot $(QEMUFLAGS)

.PHONY: all run run-nox debug test check smoke iso run-iso clean

all: $(KERNEL)

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/%.o: src/%.c | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/%.o: src/%.s | $(BUILD)
	$(CC) $(ASFLAGS) -c $< -o $@

$(KERNEL): $(OBJ) linker.ld
	$(CC) $(LDFLAGS) -o $@ $(OBJ) $(LIBS)
	@echo "==> $@ ($$(stat -c %s $@) octets)"

check: $(KERNEL)
	python3 $(ROOT)/tools/check-multiboot.py $(KERNEL)

smoke: $(KERNEL)
	python3 $(ROOT)/tools/emu-smoke.py $(KERNEL)

run: $(KERNEL)
	$(QEMU) $(QEMU_BASE) -kernel $(KERNEL) -serial stdio \
		-device isa-debug-exit,iobase=0xf4,iosize=0x04

run-nox: $(KERNEL)
	$(QEMU) $(QEMU_BASE) -kernel $(KERNEL) -display none -serial stdio \
		-device isa-debug-exit,iobase=0xf4,iosize=0x04

# GDB : QEMU attend sur :1234 avec le CPU gelé ; gdb charge les symboles du
# noyau et exécute tools/gdbinit (target remote + break kernel_main).
# La sortie série va dans build/serial.log (QEMU tourne en arrière-plan et ne
# peut pas partager le terminal avec GDB) : `tail -f build/serial.log` à côté.
debug: $(KERNEL)
	$(QEMU) $(QEMU_BASE) -kernel $(KERNEL) -serial file:$(BUILD)/serial.log -s -S &
	sleep 0.5
	gdb -q $(KERNEL) -x $(ROOT)/tools/gdbinit
	-pkill -f "$(QEMU) .*-s -S" 2>/dev/null

# Test automatisé : la sortie série est capturée dans build/serial.log puis
# comparée à tests/expected.txt. Le noyau termine QEMU via isa-debug-exit
# (code 33, ignoré) ; timeout est un garde-fou en cas de blocage.
test: $(KERNEL)
	@rm -f $(BUILD)/serial.log
	-timeout --foreground 8 $(QEMU) $(QEMU_BASE) -kernel $(KERNEL) \
	    -display none -serial file:$(BUILD)/serial.log \
	    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
	@bash tests/run.sh $(BUILD)/serial.log tests/expected.txt

iso: $(KERNEL)
	mkdir -p $(BUILD)/isodir/boot/grub
	cp $(KERNEL) $(BUILD)/isodir/boot/kernel.elf
	printf 'set timeout=0\nset default=0\nmenuentry "osdev-sandbox $(MODULE)" {\n  multiboot /boot/kernel.elf\n  boot\n}\n' \
	    > $(BUILD)/isodir/boot/grub/grub.cfg
	grub-mkrescue -o $(BUILD)/os.iso $(BUILD)/isodir 2>/dev/null
	@echo "==> $(BUILD)/os.iso"

run-iso: iso
	$(QEMU) $(QEMU_BASE) -cdrom $(BUILD)/os.iso -serial stdio

clean:
	rm -rf $(BUILD)
