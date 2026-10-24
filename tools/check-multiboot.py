#!/usr/bin/env python3
"""check-multiboot.py kernel.elf

Vérifie sans GRUB qu'un noyau ELF contient un en-tête Multiboot 1 valide :
  - magic 0x1BADB002, checksum tel que magic+flags+checksum == 0 (mod 2^32),
  - aligné sur 4 octets,
  - situé dans les 8192 premiers octets du FICHIER (c'est la règle de la spec),
et affiche le point d'entrée et les segments chargés.
"""
import struct, sys

MAGIC = 0x1BADB002

def main(path):
    data = open(path, "rb").read()
    if data[:4] != b"\x7fELF":
        print("pas un fichier ELF"); return 1
    if data[4] != 1:
        print("ELF 64 bits : Multiboot 1 exige un ELF32 (i386)"); return 1
    e_entry, e_phoff = struct.unpack_from("<II", data, 0x18)
    e_phentsize, e_phnum = struct.unpack_from("<HH", data, 0x2A)
    print(f"ELF32, entrée = 0x{e_entry:08x}")
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        p_type, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_flags = \
            struct.unpack_from("<IIIIIII", data, off)
        if p_type == 1:
            fl = ''.join(c if p_flags & b else '-' for c, b in (('r',4),('w',2),('x',1)))
            print(f"  PT_LOAD paddr=0x{p_paddr:08x} filesz=0x{p_filesz:x} memsz=0x{p_memsz:x} {fl}")
    found = None
    for off in range(0, min(len(data), 8192) - 11, 4):
        magic, flags, checksum = struct.unpack_from("<III", data, off)
        if magic == MAGIC:
            found = off
            if (magic + flags + checksum) & 0xFFFFFFFF != 0:
                print(f"en-tête trouvé à l'offset {off} mais CHECKSUM INVALIDE "
                      f"(flags=0x{flags:x}, checksum=0x{checksum:x})"); return 1
            print(f"en-tête Multiboot OK à l'offset {off} (flags=0x{flags:x})")
            break
    if found is None:
        print("AUCUN en-tête Multiboot dans les 8 Ko du fichier : "
              "vérifie que .multiboot est la première section du linker script")
        return 1
    return 0

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__); sys.exit(2)
    sys.exit(main(sys.argv[1]))
