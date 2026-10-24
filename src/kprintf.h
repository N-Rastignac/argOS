/* kprintf.h — printf du noyau : écrit sur l'écran VGA et sur le port série.
 *
 * Formats supportés : %c %s %d %i %u %x %X %p %%
 * (entiers 32 bits, sans largeur ni précision). */
#ifndef KPRINTF_H
#define KPRINTF_H

#include <stdarg.h>

void kputchar(char c);
void kputs(const char *s);
int  kprintf(const char *fmt, ...);
int  kvprintf(const char *fmt, va_list ap);

#endif
