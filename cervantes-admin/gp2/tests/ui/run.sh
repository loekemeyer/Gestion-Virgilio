#!/usr/bin/env bash
# Corre toda la suite de tests de UI (Playwright + Chromium, con Supabase STUBEADO:
# no tocan la base real). Uso:  bash tests/ui/run.sh   (desde la raiz del repo o donde sea)
set -u
cd "$(dirname "$0")"

# playwright: local o global (NODE_PATH)
if [ ! -d node_modules/playwright ] && [ -z "${NODE_PATH:-}" ]; then
  export NODE_PATH="$(npm root -g 2>/dev/null)"
fi

pass=0; fail=0; failed=()
for t in test_*.js; do
  echo "== $t"
  if node "$t"; then pass=$((pass+1)); else fail=$((fail+1)); failed+=("$t"); fi
done
echo
echo "RESULTADO: $pass OK, $fail con fallos"
if [ $fail -gt 0 ]; then printf 'FALLARON: %s\n' "${failed[@]}"; exit 1; fi
