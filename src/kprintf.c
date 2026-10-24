/* kprintf.c — formatage minimal.
 *
 * Conversion des entiers en 32 bits uniquement : un CPU 32 bits ne sait pas
 * diviser un uint64_t sans l'aide de libgcc.
 */
#include "kprintf.h"
#include "vga.h"
#include "serial.h"
#include "string.h"
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

void kputchar(char c)
{
    vga_putchar(c);
    serial_putchar(c);
}

void kputs(const char *s)
{
    while (*s)
        kputchar(*s++);
}

/* Affiche p dans la base donnée (10 ou 16). Les chiffres sont extraits du
 * poids faible vers le poids fort, puis émis dans l'ordre inverse.
 * Retourne le nombre de caractères écrits. */
static uint32_t print_unsigned_int(uint32_t p, uint32_t base, bool upper){
    int8_t buffer[12];
    int j = 0;
    uint32_t written = 0;

    do {
        buffer[j++] = p % base;
        p/= base;
    } while(p != 0);

    const char *digits = upper ? "0123456789ABCDEF" : "0123456789abcdef";

    for(; j > 0;){
        kputchar(digits[buffer[j - 1]]);
        ++written;
        --j;
    }

    return written;
}

/* Affiche p en décimal signé. La négation est faite en non signé :
 * -INT32_MIN ne tient pas dans un int32_t, mais tient dans un uint32_t. */
static uint32_t print_signed_int(int32_t p){
    uint32_t u;
    uint32_t written = 0;

    if (p < 0){
        u = -(uint32_t) p;
        kputchar('-');
        ++written;
    } else if (p >= 0) {
        u = (uint32_t) p;
    }

    written += print_unsigned_int(u, 10, false);

    return written;
}

int kvprintf(const char *fmt, va_list ap)
{
    uint32_t count = 0;

    for (int i = 0; fmt[i] != '\0'; ++i) {

        /* Caractère ordinaire. */
        if (fmt[i] != '%') {
            kputchar(fmt[i]);
            ++count;
            continue;
        }

        ++i;
        if (fmt[i] == '\0') {          /* '%' isolé en fin de chaîne */
            kputchar('%');
            ++count;
            break;
        }

        switch (fmt[i]) {
        case 'd':
        case 'i':
            count += print_signed_int(va_arg(ap, int32_t));
            break;

        case 'c':
            kputchar((char)va_arg(ap, int));        /* char promu en int */
            ++count;
            break;

        case 's': {
            const char *s = va_arg(ap, const char *);
            if (s == NULL)
                s = "(null)";
            kputs(s);
            count += (int)strlen(s);
            break;
        }

        case 'u':
            count += print_unsigned_int(va_arg(ap, uint32_t), 10, false);
            break;

        case 'x':
            count += print_unsigned_int(va_arg(ap, uint32_t), 16, false);
            break;

        case 'X':
            count += print_unsigned_int(va_arg(ap, uint32_t), 16, true);
            break;

        case 'p':
            kputs("0x");
            count += 2 + print_unsigned_int((uint32_t)(uintptr_t)va_arg(ap, void *), 16, false);
            break;

        case '%':
            kputchar('%');
            ++count;
            break;

        default:                        /* spécificateur inconnu : affiché tel quel */
            kputchar('%');
            kputchar(fmt[i]);
            count += 2;
            break;
        }
    }

    return count;
}

int kprintf(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int n = kvprintf(fmt, ap);
    va_end(ap);
    return n;
}
