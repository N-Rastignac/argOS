/* io.h — accès aux ports d'entrée/sortie x86 (instructions in/out).
 *
 * Contraintes d'asm inline utilisées :
 *   "a"(x)   x est placé dans %al / %ax / %eax (taille déduite du type)
 *   "Nd"(p)  p est un immédiat 8 bits (N) ou est placé dans %dx (d)
 *   "=a"(r)  r reçoit %al / %ax / %eax après l'instruction
 * Ce sont les seules formes que l'ISA accepte pour IN et OUT.
 */
#ifndef IO_H
#define IO_H

#include <stdint.h>

/* Écrit un octet sur un port. */
static inline void outb(uint16_t port, uint8_t val)
{
    __asm__ volatile ("outb %0, %1" : : "a"(val), "Nd"(port));
}

/* Lit un octet depuis un port. */
static inline uint8_t inb(uint16_t port)
{
    uint8_t ret;
    __asm__ volatile ("inb %1, %0" : "=a"(ret) : "Nd"(port));
    return ret;
}

/* Écrit un mot (16 bits) sur un port. */
static inline void outw(uint16_t port, uint16_t val)
{
    __asm__ volatile ("outw %0, %1" : : "a"(val), "Nd"(port));
}

/* Lit un mot (16 bits) depuis un port. */
static inline uint16_t inw(uint16_t port)
{
    uint16_t ret;
    __asm__ volatile ("inw %1, %0" : "=a"(ret) : "Nd"(port));
    return ret;
}

/* Courte pause (~1 µs sur du vrai matériel) : écriture sur le port 0x80,
 * port de diagnostic POST inutilisé. Utile après certaines commandes PIC/PIT. */
static inline void io_wait(void)
{
    outb(0x80, 0);
}

#endif
