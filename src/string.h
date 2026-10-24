/* string.h — fonctions mémoire/chaînes minimales.
 * Sans libc en freestanding, elles doivent être fournies : GCC peut émettre
 * de lui-même des appels à memset/memcpy (initialisation de structures),
 * d'où ces signatures standard. */
#ifndef STRING_H
#define STRING_H

#include <stddef.h>
#include <stdint.h>

size_t strlen(const char *s);
void  *memset(void *dst, int c, size_t n);
void  *memcpy(void *dst, const void *src, size_t n);
int    memcmp(const void *a, const void *b, size_t n);
int    strcmp(const char *a, const char *b);

#endif
