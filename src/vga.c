/* vga.c — pilote texte VGA.
 *
 * L'écran texte est un tableau de 80x25 cellules de 16 bits à 0xB8000 :
 *
 *      bit :  15 14 13 12 | 11 10  9  8 |  7 ... 0
 *             ----fond----   ---texte---   caractère (CP437)
 *
 * La cellule (row, col) est à l'index row*80 + col. La carte relit cette
 * mémoire en continu : écrire une cellule suffit à l'afficher.
 */
#include "vga.h"
#include "io.h"
#include "string.h"
#include <stdint.h>

/* Registres CRTC du contrôleur VGA (schéma index/donnée). */
#define CRTC_INDEX       0x3D4
#define CRTC_DATA        0x3D5
#define CRTC_CURSOR_HIGH 0x0E
#define CRTC_CURSOR_LOW  0x0F

static volatile uint16_t *const vga = (volatile uint16_t *)VGA_MEMORY;
static size_t  cur_row;
static size_t  cur_col;
static uint8_t cur_attr;

/* Construit une cellule : attribut dans l'octet haut, caractère dans l'octet bas. */
static inline uint16_t vga_entry(char c, uint8_t attr)
{
    uint16_t haut = attr << 8;
    uint16_t cell = haut + (uint8_t)c;
    return cell;
}

/* Positionne le curseur matériel sur (cur_row, cur_col). */
static void vga_update_cursor(void)
{
    outb(CRTC_INDEX, CRTC_CURSOR_LOW);
    outb(CRTC_DATA, ((uint8_t)((uint16_t)(cur_row * VGA_WIDTH + cur_col) & 0x0FF)));
    outb(CRTC_INDEX, CRTC_CURSOR_HIGH);
    outb(CRTC_DATA, ((uint8_t)((uint16_t)(cur_row * VGA_WIDTH + cur_col) >> 8)));
}

/* Décale l'écran d'une ligne vers le haut et vide la dernière ligne. */
static void vga_scroll(void)
{
    int temp_col = 0;
    int temp_row = 0;
    for (int i = 0; i < VGA_HEIGHT * VGA_WIDTH - VGA_WIDTH; ++i){
        vga[VGA_WIDTH * temp_row + temp_col] = vga[(temp_row + 1) * VGA_WIDTH + (temp_col)];
        ++temp_col;
        if (temp_col == VGA_WIDTH){
            temp_col = 0;
            ++temp_row;
        }
    }

    temp_col = 0;

    for (int i = 0; i < VGA_WIDTH; ++i){
        vga[VGA_WIDTH * temp_row + temp_col] = vga_entry(' ', cur_attr);
        ++temp_col;
    }
}

void vga_set_color(enum vga_color fg, enum vga_color bg)
{
    cur_attr = (uint8_t)((bg << 4) | (fg & 0x0F));
}

/* Remplit l'écran d'espaces avec la couleur courante, curseur en (0,0). */
void vga_clear(void)
{
    for (int i = 0; i < VGA_HEIGHT * VGA_WIDTH; ++i){
        vga[i] = vga_entry(' ', cur_attr);
    }

    cur_col = 0;
    cur_row = 0;
}

void vga_init(void)
{
    vga_set_color(VGA_LIGHT_GREY, VGA_BLACK);
    cur_row = 0;
    cur_col = 0;
    vga_clear();
    vga_update_cursor();
}

/* Passe à la ligne suivante ; défile si l'on dépasse la dernière ligne. */
static void vga_newline(void){
    cur_col = 0;
    ++cur_row;
    if (cur_row == VGA_HEIGHT) {
        vga_scroll();
        cur_row = VGA_HEIGHT - 1;
    }
}

void vga_putchar(char c)
{
    switch (c) {
        case '\n':
            vga_newline();
            break;
        case '\r':
            cur_col = 0;
            break;
        case '\b':
            if (cur_col > 0){
                cur_col--;
            }
            break;
        case '\t':
            cur_col = (cur_col - cur_col % 8) + 8;
            break;
        default:
            if(cur_col == VGA_WIDTH){
                vga_newline();
            }
            vga[cur_row * VGA_WIDTH + cur_col] = vga_entry(c, cur_attr);
            ++cur_col;
            break;
    }

    vga_update_cursor();
}

void vga_puts(const char *s)
{
    while (*s)
        vga_putchar(*s++);
}

void vga_get_cursor(size_t *row, size_t *col)
{
    if (row) *row = cur_row;
    if (col) *col = cur_col;
}
