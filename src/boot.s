/* boot.s — point d'entrée du noyau (GNU as, syntaxe AT&T).
 *
 * Rôle : fournir l'en-tête Multiboot, mettre en place une pile, puis appeler
 * kernel_main(magic, mbi_addr).
 */

/* --- En-tête Multiboot ------------------------------------------------------
 * Le chargeur (GRUB ou qemu -kernel) cherche ces 3 mots dans les 8 premiers Ko
 * du fichier. magic + flags + checksum doit valoir 0 modulo 2^32.
 * Flags : bit 0 = modules alignés sur 4 Ko, bit 1 = carte mémoire fournie.
 */
.set MB_MAGIC,    0x1BADB002
.set MB_FLAGS,    (1 << 0) | (1 << 1)
.set MB_CHECKSUM, -(MB_MAGIC + MB_FLAGS)

.section .multiboot, "a"      /* "a" = section chargée en mémoire */
.align 4
.long MB_MAGIC
.long MB_FLAGS
.long MB_CHECKSUM

/* --- Pile -------------------------------------------------------------------
 * Multiboot ne garantit pas de pile valide : 16 Ko réservés dans .bss,
 * alignés sur 16 octets (ABI System V). La pile x86 descend.
 */
.section .bss
.align 16
stack_bottom:
.skip 16384
stack_top:

/* --- Point d'entrée ---------------------------------------------------------
 * État garanti par Multiboot : mode protégé 32 bits, interruptions et
 * pagination désactivées, %eax = 0x2BADB002, %ebx = adresse de la structure
 * d'information Multiboot. La GDT et l'IDT sont celles du chargeur.
 */
.section .text
.global _start
.type _start, @function
_start:
    mov $stack_top, %esp

    /* Marqueur de boot "OK" (blanc sur bleu), écrit directement en mémoire
     * VGA avant tout code C ; effacé ensuite par vga_init(). */
    movw $0x1F4F, 0xB8000      /* 'O' */
    movw $0x1F4B, 0xB8002      /* 'K' */

    /* kernel_main(uint32_t magic, uint32_t mbi_addr) : convention cdecl,
     * arguments empilés de droite à gauche. */
    push %ebx
    push %eax
    call kernel_main

    /* kernel_main ne doit pas revenir ; sinon, arrêt définitif. */
    cli
1:  hlt
    jmp 1b

.size _start, . - _start

/* Pile non exécutable (évite un avertissement du linker). */
.section .note.GNU-stack, "", @progbits
