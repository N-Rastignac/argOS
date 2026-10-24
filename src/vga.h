/* vga.h — pilote texte VGA (mode 3, 80x25, mémoire à 0xB8000). */
#ifndef VGA_H
#define VGA_H

#include <stdint.h>
#include <stddef.h>

#define VGA_WIDTH   80
#define VGA_HEIGHT  25
#define VGA_MEMORY  0xB8000

/* Les 16 couleurs standard. Attribut = (fond << 4) | texte. */
enum vga_color {
    VGA_BLACK = 0, VGA_BLUE, VGA_GREEN, VGA_CYAN, VGA_RED, VGA_MAGENTA,
    VGA_BROWN, VGA_LIGHT_GREY, VGA_DARK_GREY, VGA_LIGHT_BLUE, VGA_LIGHT_GREEN,
    VGA_LIGHT_CYAN, VGA_LIGHT_RED, VGA_LIGHT_MAGENTA, VGA_YELLOW, VGA_WHITE,
};

void vga_init(void);                                /* efface, couleur par défaut, curseur en (0,0) */
void vga_clear(void);
void vga_set_color(enum vga_color fg, enum vga_color bg);
void vga_putchar(char c);                           /* gère \n \r \b \t, retour à la ligne et défilement */
void vga_puts(const char *s);
void vga_get_cursor(size_t *row, size_t *col);

#endif
