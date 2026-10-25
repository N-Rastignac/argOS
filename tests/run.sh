#!/usr/bin/env bash
# run.sh <serial.log> <expected.txt>
# Chaque ligne de expected.txt doit apparaître, dans l'ordre, comme PRÉFIXE
# d'une ligne du log série (on ignore ce qui suit, ex: l'adresse Multiboot).
log="$1"; exp="$2"
if [ ! -s "$log" ]; then
  echo "FAIL: $log vide ou absent. Rien n'est sorti sur le port série."
  echo "      → vérifier serial_init / serial_putchar et les accès aux ports (io.h)."
  exit 1
fi
pass=0; fail=0; pos=0
mapfile -t lines < "$log"
while IFS= read -r want; do
  found=0
  for ((i = pos; i < ${#lines[@]}; i++)); do
    line="${lines[$i]%$'\r'}"
    if [[ "$line" == "$want"* ]]; then found=1; pos=$((i + 1)); break; fi
  done
  if [ $found = 1 ]; then echo "  ok    $want"; pass=$((pass+1))
  else echo "  FAIL  $want"; fail=$((fail+1)); fi
done < "$exp"
echo
echo "$pass passed, $fail failed   (complete log : $log)"
[ $fail = 0 ]
