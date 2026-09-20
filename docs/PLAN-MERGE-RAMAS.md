# Plan de merge de ramas alternas → `main`

**Escrito el 2026-09-19. NO ejecutado: el árbol de trabajo no fue tocado más que para crear este
archivo.** Lo ejecuta el dueño, paso por paso, en el orden de abajo.

Medición de partida: `origin/main` tiene 88 commits y su historia arranca el 2026-09-18 (fue
reescrita). **Ninguna de las 68 ramas comparte ancestro con `main`**, así que no se mergea nada:
se rescatan archivos con `git show` / `git checkout <rama> -- <archivo>`. Contar commits no sirve.

> ⚠ Todo lo de abajo está medido contra `origin/main` al 2026-09-19 16:15 UTC. Si `main` avanzó,
> volver a correr los chequeos de la sección 6 antes de ejecutar.

---

## 1. Resumen: qué se rescata y qué no

| # | De la rama | Archivo | Estado en la base | Acción |
|---|---|---|---|---|
| 1 | `claude/anclas-definiciones-luis-1keh3k` | `CLAUDE.md` (3 bloques de reglas de Luis, +67 líneas) | — | **rescatar** |
| 2 | `claude/dreamy-bell-29izan` | 4 `sql/gv_ancla_*` + `sql/gv_expresos_puntos_v1945.sql` + bloque de doc | **aplicado y APAGADO** (`ancla_activo = 0`, 10 funciones `gv_ancla_*` vivas) | **rescatar + renumerar doc** |
| 3 | `claude/laughing-darwin-v1n82h` | `sql/gv_todo_automatico_v1974.sql` + bloque de `CLAUDE.md` + bloque de doc | **aplicado** (`zonas_automaticas = '1,2,3,4,5,6,7'`) | **rescatar + renumerar doc** |
| 4 | `claude/charming-curie-ltu3ti` | `sql/gv_ppp_web_base_sin_l_chef.sql` | **aplicado y VIVO** (trigger `trg_gv_ppp_web_base_sin_l_chef` existe) | **rescatar** |
| 5 | `claude/entregas-proveedor-321-u7ay4f` | `sql/gv_oc_recompute_recibido_v1470.sql` | **aplicado** (`gv_oc_recompute_recibido` existe) | **rescatar** |
| 6 | `claude/nifty-babbage-3c80te` | `sql/gv_conciliacion_grants_v1903.sql` | aplicado (revocación de `EXECUTE` a `anon`) | **rescatar** |
| 7 | `claude/kind-shannon-px3zoo` (y 15 gemelas) | `cervantes-admin/gp2/Facturas/index.html` y `.../EntregaProveedoresCervantes.html` | — | **rescatar** |
| 8 | `claude/flujo-pedidos-mapa-j1pbae` | `docs/flujo-ventas.html` | — | **rescatar** |
| 9 | `claude/admiring-darwin-tgboyg` | `docs/SESION-2026-09-15-CUARENTENA-Y-ANULAR.md` | — | **rescatar** (log histórico, opcional) |
| — | `claude/bold-hamilton-g8zkwj` | `sql/gv_cuarentena_repo_chica_v1941.sql` | **revertido en la v19.43** | **descartar** — `main` tiene la v1944 |
| — | `claude/tender-curie-1tr0ml` | `sql/gv_stock_empresa_fantasma_v1886.sql` | superado | **descartar** — `main` tiene v1891 + `gv_centinelas_stock_v1977.sql` |
| — | `claude/gifted-goldberg-zl0cwx`, `claude/modest-curie-iqohkd` | `sql/gv_ppp_np_desarmar_vuelve_v1875_76.sql` | superado | **descartar** — `main` tiene `_v1875_80.sql`, que es el mismo archivo + 40 líneas |

Nada más quedó fuera de `main`: las otras 56 ramas son fotos viejas del mismo repo (versiones
anteriores de `index.html`, `CLAUDE.md`, tests, etc.), sin un solo archivo propio.

---

## 2. Renumeración de las secciones de doc

`docs/SUPABASE-GESTION-VIRGILIO.md` de `main` tiene 25.593 líneas y su última sección es
**§3.kn**. Las letras **§3.ko, §3.kp, §3.kq, §3.kr, §3.ks están libres** (verificado: no aparecen
ni como título ni como referencia). Las secciones que traen las ramas chocan con letras que `main`
ya usa para otra cosa, así que se renumeran:

| Rama | Letra en la rama | Qué es | Letra que ya usa `main` para otra cosa | **Nueva letra** |
|---|---|---|---|---|
| `dreamy-bell` | §3.ja | v19.40 armado por anclas geográficas | §3.ja = v19.52 RETIRA con día elegido | **§3.ko** |
| `dreamy-bell` | §3.jb | v19.41 agosto confirma el modelo | §3.jb = v19.53 los otros dos crons (y v19.54) | **§3.kp** |
| `dreamy-bell` | §3.jc | v19.45 puntos de expreso | (libre en `main`, pero se mueve igual para que las 4 queden juntas) | **§3.kq** |
| `dreamy-bell` | §3.jd | v19.46 el ancla del expreso | §3.jd = v19.55 el techo del armador | **§3.kr** |
| `laughing-darwin` | §3.ji | v19.74 todo se programa solo | §3.ji = Cencosud D72B/D72C | **§3.ks** |

**Referencias cruzadas que hay que reescribir junto con los títulos:**

- Dentro del bloque de anclas: `§3.ja` ×1 (además del título), `§3.jb` ×1, `§3.jc` ×2.
- Dentro de `sql/gv_ancla_expreso_v1946.sql`: `§3.jc` ×2.
- Dentro del bloque de v19.74: `§3.ji` ×1 (además del título).
- **No tocar** `§3.ic` (bloque de anclas) ni `§3.ib` (bloque v19.74): las dos apuntan a secciones
  de `main` que existen y son el tema correcto (súper mezclado y tanda por camión).

---

## 3. Ejecución, paso por paso

Todo se hace desde `main` al día:

```bash
cd /home/user/Gestion-Virgilio
git fetch origin
git checkout main && git pull origin main
```

### Paso 1 — Las reglas de Luis en `CLAUDE.md`

La rama `anclas-definiciones-luis-1keh3k` es `main` **+ 1 commit** que sólo toca `CLAUDE.md`
(+67 líneas: "REGLA de TONO", "ROL: analista logístico" y "LA LÓGICA DE PROGRAMACIÓN"). Entra
limpio, sin conflicto:

```bash
git checkout origin/claude/anclas-definiciones-luis-1keh3k -- CLAUDE.md
git diff --stat            # tiene que decir: CLAUDE.md | 67 +++++
```

### Paso 2 — Los 5 archivos SQL sueltos (entran limpios: ninguno existe en `main`)

```bash
git checkout origin/claude/dreamy-bell-29izan            -- sql/gv_ancla_v1940.sql \
                                                            sql/gv_ancla_localidad_faltante_v1941.sql \
                                                            sql/gv_expresos_puntos_v1945.sql \
                                                            sql/gv_ancla_expreso_v1946.sql
git checkout origin/claude/laughing-darwin-v1n82h        -- sql/gv_todo_automatico_v1974.sql
git checkout origin/claude/charming-curie-ltu3ti         -- sql/gv_ppp_web_base_sin_l_chef.sql
git checkout origin/claude/entregas-proveedor-321-u7ay4f -- sql/gv_oc_recompute_recibido_v1470.sql
git checkout origin/claude/nifty-babbage-3c80te          -- sql/gv_conciliacion_grants_v1903.sql
```

Y la renumeración dentro del SQL de anclas:

```bash
sed -i 's/§3\.jc/§3.kq/g' sql/gv_ancla_expreso_v1946.sql
grep -n '§3\.' sql/gv_ancla_*.sql     # sólo tiene que quedar §3.kq
```

### Paso 3 — Las dos pantallas de GP2 (entran limpias)

`main` tiene esas dos páginas bajo `cervantes-admin/entero/Facturas/`, pero **no** bajo `gp2/`.
Las de `gp2/` son distintas (traen el piso de letra de 44 px / 19 px de la idea 7214 y el
`?v=20260904t` del `auth-guard`), así que hay que copiarlas, no linkear a las de `entero`.
El blob es idéntico en las 16 ramas que las tienen; se usa cualquiera.

```bash
git checkout origin/claude/kind-shannon-px3zoo -- \
  "cervantes-admin/gp2/Facturas/index.html" \
  "cervantes-admin/gp2/Facturas/EntregaProveedoresCervantes.html"
```

### Paso 4 — Los dos documentos sueltos

```bash
git checkout origin/claude/flujo-pedidos-mapa-j1pbae -- docs/flujo-ventas.html
git checkout origin/claude/admiring-darwin-tgboyg    -- docs/SESION-2026-09-15-CUARENTENA-Y-ANULAR.md
```

### Paso 5 — El bloque de anclas en `docs/SUPABASE-GESTION-VIRGILIO.md` (§3.ko … §3.kr)

⚠ **No se copia el archivo entero de la rama**: el de `dreamy-bell` es una foto del 17/09 y le
faltan ~2.800 líneas que `main` ya tiene. Se extrae sólo el bloque y se APPENDEA al final.

```bash
git show origin/claude/dreamy-bell-29izan:docs/SUPABASE-GESTION-VIRGILIO.md \
  | sed -n '22404,22764p' > /tmp/ancla_block.md      # 361 líneas, empieza con "---"

sed -i -e 's/§3\.ja/§3.ko/g' -e 's/§3\.jb/§3.kp/g' \
       -e 's/§3\.jc/§3.kq/g' -e 's/§3\.jd/§3.kr/g' /tmp/ancla_block.md

printf '\n' >> docs/SUPABASE-GESTION-VIRGILIO.md
cat /tmp/ancla_block.md >> docs/SUPABASE-GESTION-VIRGILIO.md
```

### Paso 6 — El bloque de v19.74 (§3.ks) y la corrección de `zonas_automaticas`

```bash
git show origin/claude/laughing-darwin-v1n82h:docs/SUPABASE-GESTION-VIRGILIO.md \
  | sed -n '23460,23589p' > /tmp/v1974_block.md      # 130 líneas, empieza con el título §3.ji

sed -i 's/§3\.ji/§3.ks/g' /tmp/v1974_block.md

printf '\n---\n\n' >> docs/SUPABASE-GESTION-VIRGILIO.md
cat /tmp/v1974_block.md >> docs/SUPABASE-GESTION-VIRGILIO.md
```

Y el bloque de regla en `CLAUDE.md` (líneas 809-839 del `CLAUDE.md` de esa rama), que va
**inmediatamente antes** de la sección "⚠ QUIÉN ORGANIZA LA PROGRAMACIÓN":

```bash
git show origin/claude/laughing-darwin-v1n82h:CLAUDE.md | sed -n '809,839p' > /tmp/v1974_regla.md
sed -i 's/§3\.ji/§3.ks/' /tmp/v1974_regla.md
# insertarlo a mano antes de la línea "## ⚠ QUIÉN ORGANIZA LA PROGRAMACIÓN" de CLAUDE.md
```

⚠ **Y en el mismo paso, corregir el dato viejo de `CLAUDE.md`**: hoy dice
`zonas_automaticas = '1,2,3' desde v13.07` (alrededor de la línea 1300 de `main`) y la base dice
**`1,2,3,4,5,6,7`** desde la v19.74. Medido el 2026-09-19.

### Paso 7 — Bump de versión y commit

```bash
node scripts/bump-version.cjs --patch
node tests/run.sh          # o los dos tests de versión que corre el script de bump
git add -A && git commit && git push origin main
```

⚠ El árbol de trabajo tiene una modificación previa sin commitear en `docs/IDEAS-USUARIO.md`
(+10 líneas). Decidir si entra en este commit o va aparte **antes** del `git add -A`.

---

## 4. Conflictos: ninguno bloqueante

| Archivo | ¿Cambió en `main`? | Conflicto |
|---|---|---|
| Los 8 archivos SQL / HTML / doc nuevos | no existen en `main` | **ninguno** |
| `CLAUDE.md` (paso 1) | la rama es `main` + 1 commit | **ninguno** |
| `CLAUDE.md` (paso 6) | la rama es una foto vieja | **sí, si se copia el archivo** → se copia sólo el bloque, a mano |
| `docs/SUPABASE-GESTION-VIRGILIO.md` | `main` tiene ~2.800 líneas más | **sí, si se copia el archivo** → se appendean sólo los bloques |
| Letras §3.ja/jb/jd/ji | ocupadas en `main` por otra cosa | resuelto por la renumeración de la sección 2 |

---

## 5. Ramas

### 5.1 Conservar hasta ejecutar el plan (9)

```
claude/anclas-definiciones-luis-1keh3k     CLAUDE.md, 3 reglas de Luis
claude/dreamy-bell-29izan                  4 SQL de anclas + doc §3.ko-kr
claude/laughing-darwin-v1n82h              gv_todo_automatico_v1974 + regla + doc §3.ks
claude/charming-curie-ltu3ti               gv_ppp_web_base_sin_l_chef (trigger VIVO)
claude/entregas-proveedor-321-u7ay4f       gv_oc_recompute_recibido_v1470
claude/nifty-babbage-3c80te                gv_conciliacion_grants_v1903
claude/flujo-pedidos-mapa-j1pbae           docs/flujo-ventas.html
claude/admiring-darwin-tgboyg              docs/SESION-2026-09-15-CUARENTENA-Y-ANULAR.md
claude/kind-shannon-px3zoo                 las 2 pantallas de cervantes-admin/gp2/Facturas
```

Una vez ejecutados los pasos 1-7 y pusheado `main`, estas 9 también se borran.

### 5.2 Borrables ya (59)

Ninguna tiene un archivo que `main` no tenga, o lo que tiene está superado.

```
claude/809e-stock-compras-ch-duplicate-yxk4v8   claude/agentes-facturas-pdf-isis-i9e9dy
claude/agents-general-review-b10rq4             claude/articulos-sin-lugar-planimetria-i091kr
claude/automatizar-ventas-supa-vb4mzz           claude/blissful-cerf-lld7fw
claude/bold-hamilton-g8zkwj                     claude/brave-fermat-jvghb5
claude/busy-feynman-suyd1u                      claude/cencosud-pedido-entregado-ej9o84
claude/charming-wozniak-dm0xsi                  claude/clientes-sin-telefono-whatsapp-ffviaq
claude/confident-turing-htmdnc                  claude/ecstatic-archimedes-x0wwpy
claude/ecstatic-planck-x6a8ox                   claude/focused-clarke-edd9iz
claude/foto-visible-after-load-6cogho           claude/friendly-edison-i7c0m8
claude/gallant-rubin-2y1ieh                     claude/gestion-virgilio-pantallas-bgr3s9
claude/gifted-goldberg-zl0cwx                   claude/great-clarke-1zjjvp
claude/happy-feynman-by8dma                     claude/hopeful-babbage-uszov2
claude/import-orders-shipment-dates-r4iu4y      claude/importados-lk-clarity-yzp5k9
claude/inspiring-brahmagupta-tdj1lm             claude/inspiring-ramanujan-7y9a74
claude/intelligent-feynman-u8ukqz               claude/jolly-curie-3pm3h9
claude/keen-galileo-yb906o                      claude/krikos-tema-anterior-v0l88o
claude/laughing-albattani-1fvi5c                claude/lucid-bohr-14chwn
claude/magical-archimedes-dpweyv                claude/modest-curie-iqohkd
claude/new-session-nqgfq3                       claude/pipeline-estructura-supabase-1haka4
claude/pipeline-status-update-ww2e4d            claude/ppp-delivery-locality-merge-569qk5
claude/relaxed-ramanujan-vjhd2d                 claude/reporte-gestion-virgilio-8oww1h
claude/serene-meitner-yuxhmk                    claude/sharp-pasteur-tn6yx6
claude/stoic-einstein-ayqfpv                    claude/tender-curie-1tr0ml
claude/tender-maxwell-rjlj0t                    claude/thomas-13-9-cfossv
claude/trusting-cerf-1w5v54                     claude/trusting-feynman-dziik6
claude/virgilio-isis-api-integration-ax1d9t     claude/wonderful-pascal-8hmbpm
claude/zealous-galileo-8qe74a                   idea/2048
idea/2510                                       idea/4528
idea/5162                                       idea/7828
idea/7999
```

Borrado (el dueño; NO lo hace Claude):

```bash
# revisar la lista, después:
while read b; do git push origin --delete "$b"; done < lista-de-borrar.txt
```

---

## 6. Chequeos antes y después

**Antes** (que la foto siga siendo la de este plan):

```bash
# 1) la última sección de main sigue siendo §3.kn y ko..ks siguen libres
git show origin/main:docs/SUPABASE-GESTION-VIRGILIO.md | grep -cE '§3\.k[o-s]'      # 0
# 2) los 8 archivos siguen sin estar en main
for f in sql/gv_ancla_v1940.sql sql/gv_ancla_localidad_faltante_v1941.sql \
         sql/gv_expresos_puntos_v1945.sql sql/gv_ancla_expreso_v1946.sql \
         sql/gv_todo_automatico_v1974.sql sql/gv_ppp_web_base_sin_l_chef.sql \
         sql/gv_oc_recompute_recibido_v1470.sql sql/gv_conciliacion_grants_v1903.sql; do
  git cat-file -e "origin/main:$f" 2>/dev/null && echo "YA ESTA: $f"; done
# 3) la rama de anclas sigue siendo main + 1 commit de CLAUDE.md
git diff --stat origin/main origin/claude/anclas-definiciones-luis-1keh3k
```

**Después:**

```bash
# ninguna letra §3 repetida entre las nuevas
grep -oE '^#{2,4} *§3\.k[o-s]' docs/SUPABASE-GESTION-VIRGILIO.md | sort | uniq -c   # 5 líneas, cada una en 1
# no quedó ninguna referencia a las letras viejas dentro de lo rescatado
grep -n '§3\.j[abcdi]' sql/gv_ancla_*.sql                                            # vacío
node scripts/bump-version.cjs --patch && bash tests/run.sh
```

Y, en la base, que lo rescatado siga siendo lo que corre:

```sql
select (select count(*) from pg_trigger where tgname='trg_gv_ppp_web_base_sin_l_chef') trigger_l,
       (select valor_texto from public."PPP_Web_Config" where clave='zonas_automaticas')  zonas,
       (select valor       from public."PPP_Web_Config" where clave='ancla_activo')       ancla;
-- al 2026-09-19: 1 · '1,2,3,4,5,6,7' · 0
```

---

## 7. Nota sobre el trigger de la "L" (`gv_ppp_web_base_sin_l_chef`)

Se rescata. **No se descartó a propósito: está vivo en la base y su fuente nunca llegó al repo.**
Medido el 2026-09-19: `trg_gv_ppp_web_base_sin_l_chef` existe, y hoy hay **0 pedidos de Chef con
un código exclusivo de Chef terminado en L** (de 96 filas de Chef con L, todas son TdF o duales).

No choca con la regla "LA L NO ES UN CÓDIGO — ES UNA DENOTACIÓN" del `CLAUDE.md`. Esa regla dice
que no hay que limpiar la L de `PPP_Web_Base` **cuando el artículo es de Loekemeyer** — sacársela
manda al operario a la góndola de Chef. El trigger hace lo contrario: sólo pela la L cuando el
código base **existe en `precios_venta_chef` y NO existe en `precios_venta`**, o sea cuando el
artículo es exclusivo de Chef y la L nunca debió estar (la ponía la página de Chef por tener a
Dorinka / Chango Más en el grupo de "supers con sufijo L"). Los 4 duales y los artículos de Loeke
de Tierra del Fuego quedan intactos por construcción.

⚠ Queda pendiente, y no es parte de este plan: el arreglo de raíz está en la página
(`paginach`, `admin-supercot.js`, `addLSuffix`), no en Gestión. El trigger es la red.
