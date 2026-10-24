#!/usr/bin/env python3
"""emu-smoke.py kernel.elf [--serial-in "text"] [--initrd fichier] [--append "cmdline"]

Test de fumée SANS QEMU : émule le CPU avec Unicorn, charge les segments de
l'ELF, place eax/ebx comme le ferait un bootloader Multiboot, exécute depuis
_start, capture les `out` vers COM1 (0x3F8) et affiche l'écran VGA (0xB8000).
Simule un UART minimal (LSR toujours "prêt", loopback), le CRTC, isa-debug-exit,
et construit une struct multiboot_info réaliste (mémoire 64 Mo, carte E820 type
QEMU, cmdline, nom de bootloader, module optionnel) comme le ferait GRUB.
Utile en CI ou sur une machine sans QEMU ; ce n'est PAS un remplacement de QEMU.
"""
import sys, struct
from elftools.elf.elffile import ELFFile
from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_INSN, UC_HOOK_CODE, UcError
from unicorn.x86_const import (UC_X86_REG_EAX, UC_X86_REG_EBX, UC_X86_REG_ESP,
                               UC_X86_REG_EIP, UC_X86_INS_IN, UC_X86_INS_OUT)

path = sys.argv[1]
opts = {"--serial-in": "", "--initrd": None, "--append": ""}
args = sys.argv[2:]
while args:
    k = args.pop(0)
    if k in opts and args:
        opts[k] = args.pop(0)
serial_in = list(opts["--serial-in"].encode().decode("unicode_escape").encode("latin-1"))

mu = Uc(UC_ARCH_X86, UC_MODE_32)
mu.mem_map(0, 16 * 1024 * 1024)                      # 16 Mo de RAM plate

with open(path, "rb") as f:
    elf = ELFFile(f)
    for seg in elf.iter_segments():
        if seg["p_type"] == "PT_LOAD":
            mu.mem_write(seg["p_paddr"], seg.data())  # .bss déjà à zéro (mem_map)
    entry = elf["e_entry"]
    symtab = elf.get_section_by_name(".symtab")
    start = [s for s in symtab.iter_symbols() if s.name == "_start"][0]["st_value"]

serial_out = bytearray()
uart = {"dlab": 0, "mcr": 0, "loop": None}
crtc = {"idx": 0, "cursor": [0, 0]}
exit_code = {"v": None}
COM1, LSR = 0x3F8, 0x3FD

def hook_in(uc, port, size, user):
    if port == LSR:
        return 0x20 | (1 if (serial_in or uart["loop"] is not None) else 0)
    if port == COM1:
        if uart["loop"] is not None:
            v, uart["loop"] = uart["loop"], None
            return v
        return serial_in.pop(0) if serial_in else 0
    return 0

def hook_out(uc, port, size, value, user):
    if port == COM1:
        if uart["dlab"]:
            return
        if uart["mcr"] & 0x10:          # loopback
            uart["loop"] = value & 0xFF
        else:
            serial_out.append(value & 0xFF)
    elif port == COM1 + 3:
        uart["dlab"] = value & 0x80
    elif port == COM1 + 4:
        uart["mcr"] = value
    elif port == 0x3D4:
        crtc["idx"] = value
    elif port == 0x3D5:
        crtc["cursor"][crtc["idx"] - 0x0E] = value & 0xFF
    elif port == 0xF4:
        exit_code["v"] = (value << 1) | 1
        uc.emu_stop()

mu.hook_add(UC_HOOK_INSN, hook_in, None, 1, 0, UC_X86_INS_IN)
mu.hook_add(UC_HOOK_INSN, hook_out, None, 1, 0, UC_X86_INS_OUT)

def hook_code(uc, addr, size, user):    # hlt → stop (cli+hlt = fin)
    if uc.mem_read(addr, 1) == b"\xf4":
        uc.emu_stop()
mu.hook_add(UC_HOOK_CODE, hook_code)

# --- Structure d'information Multiboot (spec §3.3), en mémoire basse ---
MBI, CMDLINE, LOADER, MMAP, MODS, MODDATA = 0x9000, 0x9100, 0x9200, 0x9300, 0x9400, 0x200000
mem_kb = 64 * 1024
e820 = [(0x0, 0x9FC00, 1), (0x9FC00, 0x400, 2), (0xF0000, 0x10000, 2),
        (0x100000, mem_kb * 1024 - 0x100000 - 0x20000, 1),
        (mem_kb * 1024 - 0x20000, 0x20000, 2), (0xFFFC0000, 0x40000, 2)]
mmap = b"".join(struct.pack("<IQQI", 20, a, l, t) for a, l, t in e820)
mu.mem_write(MMAP, mmap)
cmdline = ("build/kernel.elf " + opts["--append"]).strip().encode() + b"\0"
mu.mem_write(CMDLINE, cmdline)
mu.mem_write(LOADER, b"emu-smoke\0")
flags = (1 << 0) | (1 << 2) | (1 << 6) | (1 << 9)
mods_count = 0
if opts["--initrd"]:
    data = open(opts["--initrd"], "rb").read()
    mu.mem_write(MODDATA, data)
    mu.mem_write(MODS + 16, opts["--initrd"].encode() + b"\0")
    mu.mem_write(MODS, struct.pack("<IIII", MODDATA, MODDATA + len(data), MODS + 16, 0))
    mods_count, flags = 1, flags | (1 << 3)
mbi = struct.pack("<IIIIIII16sIIIIIIIII", flags, 639, mem_kb - 1024 - 128, 0, CMDLINE,
                  mods_count, MODS, b"", len(mmap), MMAP, 0, 0, 0, LOADER, 0, 0, 0)
mu.mem_write(MBI, mbi + b"\0" * (88 - len(mbi)))

mu.reg_write(UC_X86_REG_EAX, 0x2BADB002)
mu.reg_write(UC_X86_REG_EBX, MBI)
mu.reg_write(UC_X86_REG_ESP, 0)          # boot.s doit le fixer lui-même
try:
    mu.emu_start(start, 0, timeout=5_000_000, count=50_000_000)
except UcError as e:
    print(f"[emu] exception CPU: {e} à eip=0x{mu.reg_read(UC_X86_REG_EIP):x}")

print("=== SERIE ===")
print(serial_out.decode("latin-1"), end="")
print("=== VGA ===")
vga = mu.mem_read(0xB8000, 4000)
for r in range(25):
    line = "".join(chr(vga[(r * 80 + c) * 2] or 32) for c in range(80)).rstrip()
    if line:
        print(f"{r:2d}| {line}")
pos = crtc["cursor"][0] << 8 | crtc["cursor"][1]
print(f"=== curseur matériel : ligne {pos // 80}, colonne {pos % 80} ; "
      f"isa-debug-exit : {exit_code['v']} ===")
