/* kernel.c — point d'entrée C.
 *
 * kernel_main est appelée par boot.s avec :
 *   magic    = 0x2BADB002 si le noyau a été chargé par un chargeur Multiboot
 *   mbi_addr = adresse physique de la structure d'information Multiboot
 */
#include <stdint.h>
#include "vga.h"
#include "serial.h"
#include "kprintf.h"
#include "io.h"

#define MULTIBOOT_BOOTLOADER_MAGIC 0x2BADB002

#define QEMU_EXIT_PORT  0xF4
#define QEMU_EXIT_OK    0x10        /* QEMU sort avec (0x10 << 1) | 1 = 33 */

#define KEY_QUIT        0x04        /* Ctrl-D */
#define KEY_DEL         0x7F        /* code envoyé par la touche retour arrière */

/* Durée d'attente d'une touche avant de continuer, en appels à io_wait().
 * Approximative : sans timer (PIT), la durée réelle dépend de la machine hôte.
 * Doit rester bien en dessous du timeout de `make test` (8 s). */
#define ECHO_WAIT_LOOPS 40000000

/* Attend une touche sur le port série. Retourne 1 si une touche est arrivée. */
static int wait_for_key(uint32_t loops)
{
    for (uint32_t i = 0; i < loops; i++) {
        if (serial_received())
            return 1;
        io_wait();
    }
    return 0;
}

/* Réaffiche chaque caractère reçu sur le port série, jusqu'à Ctrl-D. */
static void echo_loop(void)
{
    kprintf("echo : write text, Ctrl-D to exit\n");
    for (;;) {
        char c = serial_getchar();
        if (c == KEY_QUIT) {
            kputchar('\n');
            break;
        }
        if (c == '\r')              /* un terminal en mode brut envoie \r pour Entrée */
            c = '\n';
        if (c == KEY_DEL) {         /* reculer, effacer, reculer */
            kputs("\b \b");
            continue;
        }
        kputchar(c);
    }
}

/* Demande à QEMU de se terminer avec le code (val << 1) | 1.
 * Nécessite -device isa-debug-exit,iobase=0xf4,iosize=0x04 ;
 * sans effet sur du vrai matériel. */
static void qemu_exit(uint8_t val)
{
    outw(QEMU_EXIT_PORT, val);
}

/* Auto-test : la sortie série est comparée à tests/expected.txt par `make test`.
 * Les chaînes sont recherchées telles quelles ; ne pas les modifier sans mettre
 * le fichier attendu à jour. */
static void selftest(void)
{
    kprintf("[selftest] begin\n");
    kprintf("[selftest] char=%c str=%s pct=%%\n", 'Z', "ok");
    kprintf("[selftest] dec=%d neg=%d zero=%d\n", 42, -42, 0);
    kprintf("[selftest] u=%u max=%u\n", 7u, 4294967295u);
    kprintf("[selftest] hex=%x HEX=%X ptr=%p\n", 0xdeadbeef, 0xCAFE, (void *)0x1000);
    kprintf("[selftest] min=%d\n", -2147483647 - 1);
    kprintf("[selftest] seq=%u%d i=%i null=%s\n", 1, 2, -3, (const char *)0);
    kprintf("[selftest] end\n");
}

void kernel_main(uint32_t magic, uint32_t mbi_addr)
{
    vga_init();
    int serial_ok = serial_init();

    vga_set_color(VGA_WHITE, VGA_BLUE);
    kprintf("argOS\n");
    vga_set_color(VGA_LIGHT_GREY, VGA_BLACK);

    kprintf("serial: %s\n", serial_ok == 0 ? "ok" : "loopback FAILED");

    if (magic != MULTIBOOT_BOOTLOADER_MAGIC)
        kprintf("warning: bad multiboot magic %x (expected %x)\n",
                magic, MULTIBOOT_BOOTLOADER_MAGIC);
    else
        kprintf("multiboot magic ok, info struct at %x\n", mbi_addr);

    selftest();

    /* Mode écho optionnel : sans touche (cas de `make test`), on continue. */
    kprintf("press any key to enter echo mode...\n");
    if (wait_for_key(ECHO_WAIT_LOOPS))
        echo_loop();

    kprintf("halting.\n");
    qemu_exit(QEMU_EXIT_OK);

    for (;;)
        __asm__ volatile ("hlt");
}
