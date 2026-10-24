/* serial.h — port série COM1 (UART 16550), sortie de debug vers QEMU. */
#ifndef SERIAL_H
#define SERIAL_H

#include <stdint.h>

/* Registres (COM1 + offset). */
#define COM1        0x3F8
#define REG_DATA    (COM1 + 0)   /* DLAB=1 : diviseur, octet bas  */
#define REG_IER     (COM1 + 1)   /* DLAB=1 : diviseur, octet haut */
#define REG_FCR     (COM1 + 2)
#define REG_LCR     (COM1 + 3)
#define REG_MCR     (COM1 + 4)
#define REG_LSR     (COM1 + 5)

/* LCR : format de trame. */
#define LCR_8N1     0x03         /* 8 bits de données, pas de parité, 1 stop */
#define LCR_DLAB    (1 << 7)

/* MCR : lignes de contrôle modem. */
#define MCR_DTR      (1 << 0)
#define MCR_RTS      (1 << 1)
#define MCR_OUT1     (1 << 2)
#define MCR_OUT2     (1 << 3)
#define MCR_LOOPBACK (1 << 4)

/* LSR : état de la ligne. */
#define LSR_DATA_READY (1 << 0)
#define LSR_TX_EMPTY   (1 << 5)

/* Initialise COM1 en 38400 bauds, 8N1, FIFO activée.
 * Retourne 0 si OK, -1 si le test de bouclage (loopback) échoue. */
int  serial_init(void);
void serial_putchar(char c);
void serial_puts(const char *s);

/* Réception : serial_received() indique si un octet est disponible,
 * serial_getchar() l'attend (lecture bloquante). */
int  serial_received(void);
char serial_getchar(void);

#endif
