# osdev-sandbox — Module 01 : environnement

Noyau x86 32 bits minimal, démarré via Multiboot, qui sert de socle au reste du projet :
chaîne de compilation croisée, pilotes de sortie texte (VGA et port série), `kprintf`
maison, tests automatisés et débogage sous QEMU + GDB.

Ce module fait partie d'**osdev-sandbox**, un projet d'apprentissage du développement de
systèmes d'exploitation où chaque brique (GDT, interruptions, mémoire, multitâche…) est
implémentée à la main, module par module.

```
osdev-sandbox :: module 01 :: environnement
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
appuie sur une touche pour le mode echo...
halting.
```

## Fonctionnalités

- **Démarrage Multiboot** : en-tête, pile de 16 Ko et appel de `kernel_main` en assembleur (`boot.s`) ; noyau chargé à 1 Mo.
- **Accès aux ports d'E/S** : `inb` / `outb` / `inw` / `outw` en assembleur inline GCC.
- **Pilote VGA texte** (80×25, mémoire à `0xB8000`) : couleurs, `\n` `\r` `\t` `\b`, retour à la ligne automatique, défilement, curseur matériel via les registres CRTC.
- **Pilote série UART 16550** (COM1) : 38400 bauds en 8N1, FIFO, test de bouclage à l'initialisation, émission et réception par scrutation (*polling*).
- **`kprintf`** : `%c %s %d %i %u %x %X %p %%` sur les deux sorties à la fois. Gère `0`, `INT32_MIN`, `%s` avec `NULL` et les spécificateurs collés.
- **Mode écho** : si une touche est pressée au démarrage, le noyau réaffiche les caractères reçus sur le port série, jusqu'à Ctrl-D.
- **Arrêt de QEMU** depuis le noyau via le périphérique `isa-debug-exit` (code de sortie 33).

## Arborescence

```
01-environnement/
├── Makefile
├── linker.ld          disposition mémoire (chargement à 1 Mo, .multiboot en tête)
├── src/
│   ├── boot.s         en-tête Multiboot, pile, point d'entrée _start
│   ├── kernel.c       kernel_main, auto-test, mode écho, sortie de QEMU
│   ├── io.h           instructions in/out (asm inline)
│   ├── vga.c/h        pilote texte VGA
│   ├── serial.c/h     pilote UART 16550
│   ├── kprintf.c/h    formatage et sortie
│   └── string.c/h     strlen, memset, memcpy, memcmp, strcmp
└── tests/
    ├── expected.txt   lignes attendues sur le port série
    └── run.sh         comparaison du log série avec expected.txt
```

## Prérequis

| Outil | Rôle |
|---|---|
| `i686-elf-gcc`, `i686-elf-binutils` | cross-compilation (à défaut, repli automatique sur `gcc -m32`) |
| `qemu-system-i386` | exécution et tests |
| `gdb` | débogage (`make debug`) |
| `grub-mkrescue`, `xorriso`, `mtools` | optionnel : image ISO bootable |

Les cibles `debug`, `check` et `smoke` utilisent les scripts du dossier `tools/` à la racine d'osdev-sandbox.

## Compilation et exécution


```bash
# Télécharge d'abord les deux archives et pose-les dans ~/opt/cross-src/ :
#   https://ftp.gnu.org/gnu/binutils/         binutils-X.YY.tar.xz
#   https://ftp.gnu.org/gnu/gcc/gcc-X.Y.Z/    gcc-X.Y.Z.tar.xz
./tools/install-toolchain.sh --check   # confirme que les archives sont trouvées
./tools/install-toolchain.sh            
./tools/check-env.sh

```sh
make            # build/kernel.elf
make run        # QEMU avec fenêtre VGA ; port série sur le terminal
make run-nox    # sans fenêtre, port série uniquement
make test       # démarrage headless et vérification de la sortie série
make debug      # QEMU gelé (-s -S) et GDB attaché, arrêt sur kernel_main
make iso        # image ISO GRUB (build/os.iso), puis make run-iso
make clean
```

Variables utiles : `OPT=-O2` (défaut `-O0` pour le débogage), `QEMUFLAGS="-d int"`, `EXTRA_CFLAGS=...`.

**Mode écho** : avec `make run-nox`, appuyer sur une touche pendant l'invite du démarrage, taper du texte, puis Ctrl-D. QEMU se termine avec le code 33 (`echo $?`).

## Tests

`make test` démarre le noyau sans affichage, capture le port série dans `build/serial.log`,
puis vérifie que chaque ligne de `tests/expected.txt` y apparaît, dans l'ordre, comme préfixe.
Le noyau termine lui-même QEMU par `isa-debug-exit` ; `make` signale ce code 33, qui est ignoré.

```
12 réussi(s), 0 échec(s)   (log complet : build/serial.log)
```

## Notes techniques

**Démarrage.** Le chargeur Multiboot laisse le CPU en mode protégé 32 bits, sans pagination ni
interruptions, avec `eax = 0x2BADB002` et `ebx` pointant sur la structure d'information.
`_start` installe la pile, écrit un marqueur « OK » directement en mémoire VGA, puis appelle
`kernel_main(magic, mbi_addr)` selon la convention cdecl.

**Sortie de QEMU.** `-device isa-debug-exit,iobase=0xf4,iosize=0x04` ajoute un périphérique
virtuel sur le port `0xF4`. Une écriture de `val` termine QEMU avec le code `(val << 1) | 1`,
toujours impair, ce qui le distingue d'une sortie normale. Sur du vrai matériel, cette
écriture n'a aucun effet.

**Négation de `INT32_MIN`.** `-2147483648` n'a pas d'opposé représentable en `int32_t`.
`kprintf` calcule donc la valeur absolue en non signé (`-(uint32_t)n`), où le résultat est défini.

**Limites connues.**
- Pas de largeur ni de précision dans `kprintf` (`%08x`, `%5d`).
- Entiers 32 bits uniquement (la division 64 bits demande libgcc).
- La durée d'attente du mode écho est calibrée en boucles d'`io_wait`, sans horloge : elle dépend de la machine hôte. Un vrai timer arrive avec le PIT (module 04).

## Suite du projet

| Module | Sujet |
|---|---|
| 02 | Démarrage : structure Multiboot, carte mémoire, symboles du linker |
| 03 | GDT |
| 04 | Interruptions : IDT, PIC, PIT, clavier |
| 05 – 07 | Mémoire physique, pagination, heap noyau |
| 08 – 10 | Multitâche, mode utilisateur et appels système, chargement ELF |
| 11 – 14 | Synchronisation, système de fichiers, pilotes, bonus |

## Références

- [OSDev Wiki](https://wiki.osdev.org) : *Bare Bones*, *Printing To Screen*, *Text Mode Cursor*, *Serial Ports*, *Inline Assembly*
- Intel® 64 and IA-32 Architectures Software Developer's Manual, vol. 2 (instructions `IN`, `OUT`, `HLT`)
- Spécification Multiboot 0.6.96
- Texas Instruments, *PC16550D UART* (fiche technique)
- GCC, *Extended Asm* et *Machine Constraints*
