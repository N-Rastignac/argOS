/* linker.ld — disposition du noyau en mémoire.
 *
 *   - le noyau est chargé à 1 Mo (0x100000), au-dessus des zones BIOS/VGA ;
 *   - .multiboot doit se trouver dans les 8 premiers Ko du fichier : elle est
 *     placée en premier, et KEEP empêche l'éditeur de liens de l'éliminer ;
 *   - _start (boot.s) est le point d'entrée.
 */
ENTRY(_start)

SECTIONS
{
    . = 1M;

    .multiboot ALIGN(4) :
    {
        KEEP(*(.multiboot))
    }

    .text ALIGN(4K) :
    {
        *(.text .text.*)
    }

    .rodata ALIGN(4K) :
    {
        *(.rodata .rodata.*)
    }

    .data ALIGN(4K) :
    {
        *(.data .data.*)
    }

    .bss ALIGN(4K) :
    {
        *(COMMON)
        *(.bss .bss.*)
    }

    /* Fin du noyau en mémoire, accessible depuis le C : extern char kernel_end[]; */
    kernel_end = .;

    /DISCARD/ : { *(.note.gnu.property) *(.comment) *(.eh_frame) }
}
