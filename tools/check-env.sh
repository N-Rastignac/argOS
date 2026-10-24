#!/usr/bin/env bash
# check-env.sh — vérifie la présence des outils. Sortie 0 si l'essentiel est là.
ok=0; miss=0
check() { # $1 = commande, $2 = requis(1)/optionnel(0), $3 = conseil
  if command -v "$1" >/dev/null 2>&1; then
    printf '  [ok]   %-20s %s\n' "$1" "$(command -v "$1")"; ok=$((ok+1))
  else
    if [ "$2" = 1 ]; then printf '  [MANQUE] %-18s %s\n' "$1" "$3"; miss=$((miss+1))
    else printf '  [opt]  %-20s %s\n' "$1" "$3"; fi
  fi
}
echo "Outils :"
check i686-elf-gcc      1 "→ ./tools/install-toolchain.sh (ou export PATH=\$HOME/opt/cross/bin:\$PATH)"
check i686-elf-ld       1 "→ idem"
check qemu-system-i386  1 "→ sudo apt install qemu-system-x86"
check gdb               1 "→ sudo apt install gdb"
check make              1 "→ sudo apt install build-essential"
check python3           1 "→ sudo apt install python3"
check grub-mkrescue     0 "(pour make iso) → sudo apt install grub-pc-bin xorriso mtools"
check xorriso           0 "(pour make iso)"
check gcc               0 "(fallback -m32 si pas de cross-compilateur)"
echo
if [ "$miss" = 0 ]; then echo "Environnement complet."; else echo "$miss outil(s) requis manquant(s)."; exit 1; fi
