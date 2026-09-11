#!/usr/bin/env bash
# Regenera admin/krikos-parsers.js copiando TEXTUALMENTE los parsers de OC de
# supermercado que viven en admin/admin-supercot.js (el panel de LK).
#
# Ese archivo es el que importa la Edge Function `krikos-auto-import` del
# proyecto Supabase de LK — lo lee por HTTPS desde el GitHub Pages de este repo,
# que es el mismo lugar de donde el panel carga admin-supercot.js. Así el
# importador automático y el panel leen el PDF con el MISMO código.
#
# Correr desde la raíz del repo cada vez que se toque un parser, y subir el
# `?v=` de la línea del import en la Edge Function para que Deno no se quede con
# la copia vieja en cache.
set -euo pipefail
SRC="admin/admin-supercot.js"
OUT="admin/krikos-parsers.js"
R1="349,401"     # parseNum y helpers numéricos
R2="444,1660"    # detectSuper, splitLines, findFirstMatch, los 11 parsers, extractPdfTotal, PARSERS
R3="1826,1874"   # codVariants + findInPool (match de código con variantes)
{
  cat scripts/krikos-parsers.head.txt
  sed -n "${R1}p;${R2}p;${R3}p" "$SRC"
  printf '\nexport { parseNum, detectSuper, PARSERS, extractPdfTotal, codVariants, findInPool, splitLines };\n'
} > "$OUT"
node --check "$OUT"
echo "OK: $OUT ($(wc -l < "$OUT") líneas)"
