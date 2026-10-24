/* serial.c — UART 16550 sur COM1.
 *
 * Registres (offset depuis 0x3F8) :
 *   +0  DATA   : lecture = octet reçu, écriture = octet à envoyer
 *                (si DLAB=1 : octet bas du diviseur de baud)
 *   +1  IER    : interrupt enable (si DLAB=1 : octet haut du diviseur)
 *   +2  FCR    : FIFO control (écriture) / IIR (lecture)
 *   +3  LCR    : line control : bits de données, parité, stop, DLAB (bit 7)
 *   +4  MCR    : modem control : DTR, RTS, OUT1/OUT2, loopback (bit 4)
 *   +5  LSR    : line status : bit 0 = donnée reçue, bit 5 = émetteur vide
 *
 * Diviseur : bauds = 115200 / diviseur. 3 → 38400.
 */
#include "serial.h"
#include "io.h"
#include <stdint.h>

#define LOOPBACK_TEST_BYTE 0xAE

int serial_init(void)
{
    outb(REG_IER, 0);                     /* interruptions désactivées */
    outb(REG_LCR, LCR_DLAB);              /* DLAB=1 : accès au diviseur */
    outb(REG_DATA, 3);                    /* diviseur, octet bas */
    outb(REG_IER, 0);                     /* diviseur, octet haut */
    outb(REG_LCR, LCR_8N1);               /* 8N1, DLAB=0 */

    outb(REG_FCR, 0xC7);                  /* FIFO activée et vidée, seuil 14 octets */

    /* Test de bouclage : TX relié à RX en interne. */
    outb(REG_MCR, MCR_LOOPBACK | MCR_OUT2 | MCR_OUT1);

    outb(REG_DATA, LOOPBACK_TEST_BYTE);
    uint8_t test_byte = inb(REG_DATA);
    if (test_byte != LOOPBACK_TEST_BYTE) {
        return -1;
    }

    /* Mode normal. */
    outb(REG_MCR, MCR_DTR | MCR_RTS | MCR_OUT1 | MCR_OUT2);

    return 0;
}

static int serial_transmit_empty(void)
{
    uint8_t out = inb(REG_LSR);
    return (out & LSR_TX_EMPTY);
}

void serial_putchar(char c)
{
    while (!serial_transmit_empty());
    outb(REG_DATA, (uint8_t)c);
}

void serial_puts(const char *s)
{
    while (*s)
        serial_putchar(*s++);
}

int serial_received(void)
{
    uint8_t out = inb(REG_LSR);
    return (out & LSR_DATA_READY);
}

char serial_getchar(void)
{
    while (!serial_received());
    return (char)inb(REG_DATA);
}
