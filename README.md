# argOS — a small OSdev project

A minimal 32-bit x86 kernel, booted through Multiboot, that serves as the foundation for the
rest of the project: a cross-compilation toolchain, text output drivers (VGA and serial port),
a hand-written `kprintf`, automated tests, and debugging with QEMU + GDB.

argOS is a learning project in operating system development.

```
serial: ok
multiboot magic ok, info struct at 9500
[selftest] begin
[selftest] char=Z str=ok pct=%
[selftest] dec=42 neg=-42 zero=0
[selftest] u=7 max=4294967295
[selftest] hex=deadbeef HEX=CAFE ptr=0x1000
[selftest] min=-2147483648
[selftest] seq=12 i=-3 null=(null)
[selftest] end
press any key for echo mode
halting.
```

## Features

- **Multiboot boot**: header, 16 KiB stack and call to `kernel_main` in assembly (`boot.s`); the kernel is loaded at 1 MiB.
- **I/O port access**: `inb` / `outb` / `inw` / `outw` written in GCC inline assembly.
- **VGA text driver** (80×25, memory at `0xB8000`): colors, `\n` `\r` `\t` `\b`, automatic line wrapping, scrolling, hardware cursor through the CRTC registers.
- **16550 UART serial driver** (COM1): 38400 baud 8N1, FIFO, loopback self-test at initialization, polled transmit and receive.
- **`kprintf`**: `%c %s %d %i %u %x %X %p %%`, written to both outputs at once. Handles `0`, `INT32_MIN`, `%s` with `NULL`, and back-to-back specifiers.
- **Echo mode**: if a key is pressed during boot, the kernel echoes every character received on the serial port, until Ctrl-D.
- **QEMU shutdown** from the kernel through the `isa-debug-exit` device (exit code 33).

## Layout
```
argOS/
├── Makefile
├── linker.ld          memory layout (loaded at 1 MiB, .multiboot first)
├── src/
│   ├── boot.s         Multiboot header, stack, _start entry point
│   ├── kernel.c       kernel_main, self-test, echo mode, QEMU exit
│   ├── io.h           in/out instructions (inline asm)
│   ├── vga.c/h        VGA text driver
│   ├── serial.c/h     16550 UART driver
│   ├── kprintf.c/h    formatting and output
│   └── string.c/h     strlen, memset, memcpy, memcmp, strcmp
├── tests/
│   ├── expected.txt   lines expected on the serial port
│   └── run.sh         compares the serial log with expected.txt
└── tools/
    ├── install-toolchain.sh   builds the i686-elf cross-toolchain from local archives
    ├── check-env.sh           checks that every required tool is installed
    ├── check-multiboot.py     validates the Multiboot header (make check)
    ├── emu-smoke.py           runs the kernel under Unicorn, without QEMU (make smoke)
    └── gdbinit                GDB setup for make debug (remote target, breakpoints)
```
## Requirements

| Tool | Purpose |
|---|---|
| `i686-elf-gcc`, `i686-elf-binutils` | cross-compilation (falls back to `gcc -m32` if missing) |
| `qemu-system-i386` | running and testing |
| `gdb` | debugging (`make debug`) |
| `grub-mkrescue`, `xorriso`, `mtools` | optional: bootable ISO image |

The `debug`, `check` and `smoke` targets rely on the scripts in the `tools/` directory.

## Building and running

### Cross-toolchain

The install script does not download anything: fetch the binutils and GCC source archives
yourself, then build the toolchain.

```sh
#   https://ftp.gnu.org/gnu/binutils/         binutils-X.YY.tar.xz
#   https://ftp.gnu.org/gnu/gcc/gcc-X.Y.Z/    gcc-X.Y.Z.tar.xz
./tools/install-toolchain.sh --check   # checks that the archives are found
./tools/install-toolchain.sh           # builds and installs i686-elf-gcc / binutils
./tools/check-env.sh                   # verifies the whole environment
```

### Kernel

```sh
make            # build/kernel.elf
make run        # QEMU with a VGA window; serial port on the terminal
make run-nox    # no window, serial port only
make test       # headless boot and serial output check
make debug      # QEMU frozen (-s -S) with GDB attached, stopped at kernel_main
make iso        # GRUB ISO image (build/os.iso), then make run-iso
make clean
```

Useful variables: `OPT=-O2` (default `-O0`, for debugging), `QEMUFLAGS="-d int"`, `EXTRA_CFLAGS=...`.

**Echo mode**: with `make run-nox`, press a key at the boot prompt, type some text, then press
Ctrl-D. QEMU exits with code 33 (`echo $?`).

## Tests

`make test` boots the kernel without a display, captures the serial port into
`build/serial.log`, then checks that every line of `tests/expected.txt` appears in it, in order,
as a line prefix. The kernel shuts QEMU down itself through `isa-debug-exit`; `make` reports
that exit code 33, which is ignored.

```
12 réussi(s), 0 échec(s)   (log complet : build/serial.log)
```

## Technical notes

**Boot.** The Multiboot loader leaves the CPU in 32-bit protected mode, with paging and
interrupts disabled, `eax = 0x2BADB002` and `ebx` pointing to the information structure.
`_start` sets up the stack, writes an "OK" marker straight into VGA memory, then calls
`kernel_main(magic, mbi_addr)` using the cdecl convention.

**Exiting QEMU.** `-device isa-debug-exit,iobase=0xf4,iosize=0x04` adds a virtual device on
port `0xF4`. Writing `val` to it terminates QEMU with exit code `(val << 1) | 1`, which is
always odd and therefore distinguishable from a normal exit. On real hardware the write has
no effect.

**Negating `INT32_MIN`.** `-2147483648` has no representable opposite in an `int32_t`, so
`kprintf` computes the absolute value in unsigned arithmetic (`-(uint32_t)n`), where the
result is well defined.

**Known limitations.**
- No field width or precision in `kprintf` (`%08x`, `%5d`).
- 32-bit integers only (64-bit division requires libgcc).
- The echo-mode timeout is a count of `io_wait` iterations rather than a real clock, so its
  duration depends on the host machine. A proper timer comes with the PIT (module 04).

## References

- [OSDev Wiki](https://wiki.osdev.org): *Bare Bones*, *Printing To Screen*, *Text Mode Cursor*, *Serial Ports*, *Inline Assembly*
- Intel® 64 and IA-32 Architectures Software Developer's Manual, Vol. 2 (`IN`, `OUT`, `HLT` instructions)
- Multiboot Specification 0.6.96
- Texas Instruments, *PC16550D UART* datasheet
- GCC manual, *Extended Asm* and *Machine Constraints*
