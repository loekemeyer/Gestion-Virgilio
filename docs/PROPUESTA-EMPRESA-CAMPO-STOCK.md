# Propuesta — la empresa como CAMPO, no pegada al código (evento de picking)

> **Estado: PROPUESTA. No implementado. Decide el dueño.** (2026-09-08)
> Analiza sacar el sufijo ` LK`/` CH` del código en el pipeline (`437E` → `437E LK`) y
> llevar la empresa como campo aparte, sin romper nada.

---

## 1. El hallazgo que hay que tener claro primero

El `437E LK` **no es una pelotudez para los 4 duales** (437E/438E/439E/809E). En un dual,
`437E` es **dos productos físicos distintos** en **dos góndolas distintas** (el Colador de
Loeke `437E LK` y el de Chef `437E CH`). El operario los pickea de lugares distintos. El
sufijo es la **empresa por línea**, y una tanda **puede mezclar** clientes LK y Chef (hay 6
tandas mixtas reales: C70B, C71A, C82A, D20D, D47B, D53A). Así que la empresa **no** se puede
"adivinar por la tanda" — hay que llevarla.

**Pero** la empresa **ya viene de la NP** y el front **ya la calcula** por línea (para separar
`437E LK` de `437E CH` en el picking). Lo único feo es la **forma**: está *pegada al código*
como sufijo, en vez de viajar en su **propio campo**. Eso es lo que se puede limpiar.

> Además: en el **stock guardado NO hay pelotudez** — `Movimientos_Stock` ya guarda `437E`
> (crudo) + `empresa` en columna aparte (el trigger pela el sufijo al escribir). El sufijo
> vive sólo en el **transporte**: el evento de picking (PKC) y la clave de góndola del front.

---

## 2. Mapa de impacto — TODO lo que toca el sufijo ` LK`/` CH`

### Front (`index.html`)
| dónde | qué hace con el sufijo | ¿lo afecta el cambio? |
|---|---|---|
| `pkCodEmpresa` / `pkResolveArt` / `pkEmpresaArt` / `pkStripL` | **arman** el sufijo (`438E`+`LK`→`438E LK`) usando la góndola | **No** — se quedan igual (el front lo sigue usando internamente) |
| `aggFrom` (líneas 9019/9048) | arma los ítems de picking `it.art = "438E LK"` (separa los 2 duales) | **No** — se queda igual; esa separación es correcta y necesaria |
| Góndola / sector (Planimetría, `GONDOLA["438E LK"]`) | ubica al operario en la góndola correcta del dual | **No** — se queda igual |
| **`pkSendDetail` (emite el PKC)** | escribe `texto = TANDA\|438E LK\|qty\|real` | **SÍ — ÚNICO cambio en el front** |
| `_pvFaltanteFactores` (13809) | lee campo 2 sólo para el m³ (`volOf`), con fallback 1 | No rompe (mejora: `volOf("438E")` matchea mejor que `"438E LK"`); tolera 5 campos |
| historial de picking (9971) | lee campo 2 y aplica `codBase()` (pela el sufijo) | No rompe (con código crudo, `codBase` es no-op) |
| matches por tanda (9625/9648/9956 `ilike t+"\|"`) | filtran por campo **1** (tanda), no por el artículo | No rompe |
| `codBase` (muchos display de stock) | pela el sufijo defensivamente | No rompe (no-op con código crudo) |
| `monitor/`, `recepcion.js` | **no parsean PKC** | No rompe |

### Backend (Supabase)
| objeto | qué hace | ¿lo afecta? |
|---|---|---|
| **`reconciliar_pipeline_stock_etapa1`** | lee el campo 2 del PKC (`438E LK`) → inserta a `Movimientos_Stock` | **SÍ — ÚNICO cambio en backend** |
| `trg_normalizar_empresa_stock` | pela el sufijo + setea `empresa` (BEFORE INSERT) | **No** — se queda igual (sigue siendo el que manda) |
| `reconciliar_..._etapa2` | lee `Movimientos_Stock` (cod_art **ya pelado** + empresa), NO el PKC | **No** |
| `vista_stock_procesada`, `vista_saldos_stock`, `vista_generador_oc`, `vista_faltantes_sin_completar`, `gv_lk_np_feed`, `gv_ppp_web_entregados`, `gv_conciliacion_registrar`, `actualizar_saldo_trigger`, `notificar_conteo_gondola_telegram` | leen `Movimientos_Stock.cod_art` (**ya pelado**) + columna `empresa` | **No** |

**Conclusión del relevamiento:** el sufijo en el EVENTO lo leen sólo **2 lugares** que importan
(`pkSendDetail` lo escribe, `etapa1` lo lee). Todo lo demás lee o el campo 1 (tanda), o el
código ya pelado, o `Movimientos_Stock` (que ya tiene el modelo `(cod, empresa)` limpio).

---

## 3. Diseño propuesto — Nivel 1 (recomendado)

**Evento de picking nuevo:** `TANDA | 438E | qty | real | LK`
(código **crudo** — con la L si es artículo Loeke, ej. `438EL` — y la **empresa en su campo 5**).
Para los no-duales el campo 5 va vacío (hoy tampoco llevan sufijo).

**Dos cambios, quirúrgicos:**

1. **Front — `pkSendDetail`:** en vez de `TANDA|rec|esp|real`, emitir
   `TANDA|codBase(rec)|esp|real|EMP`, donde `EMP` = la empresa que el front **ya tiene**
   (el sufijo actual, extraído: `(rec.match(/\s+(LK|CH)$/i)||[])[1]`), y `codBase(rec)` deja el
   código crudo (conserva la L). **Nada más del front cambia** — góndola, ítems de picking,
   todo sigue usando el sufijo internamente.

2. **Backend — `reconciliar_..._etapa1`:** un adaptador chico
   `gv_pkc_art(texto)` que devuelve el código como lo espera la lógica actual:
   - evento nuevo (`438E` + campo5 `LK`) → `438E LK`
   - evento viejo (`438E LK`, sin campo5) → `438E LK`
   Y en `etapa1` se reemplaza `split_part(texto,'|',2)` por `gv_pkc_art(texto)` (4 usos). **El
   resto de `etapa1`, el trigger y `Movimientos_Stock` quedan intactos**, y el resultado guardado
   es **idéntico** al de hoy.

**Compatibilidad total:** eventos viejos y los que quedaron en la cola offline del celular
siguen andando (el adaptador reensambla las dos formas). Nada que reprocesar, nada que migrar.

**Por qué el front NO va 100% crudo:** la góndola/sector del dual se ubica con la clave
`"438E LK"`; eso tiene que quedar (es cómo el operario encuentra la góndola correcta). Sólo el
**evento** viaja limpio.

---

## 4. Riesgo, rollback y verificación

- **Riesgo:** bajo. 2 puntos de cambio, ambos con compatibilidad hacia atrás; el motor de stock
  (trigger + `Movimientos_Stock` + etapa2) no se toca; resultado guardado idéntico.
- **Backups/rollback:** `pg_get_functiondef` de `etapa1` antes de tocar (a
  `docs/ROLLBACK-PRODUCCION.md`). Rollback = restaurar `etapa1` viejo + revertir el commit del
  front. `gv_pkc_art` se puede dropear.
- **Verificación antes de dar por hecho:**
  1. Correr `etapa1`/`etapa2` en seco y comparar los conteos de `Movimientos_Stock` por
     `(cod_art, empresa)` **antes vs después** con eventos viejos → deben ser idénticos.
  2. Emitir un PKC de prueba en el formato nuevo para un dual (`E.. | 438E | q | r | LK`) y
     confirmar que el stock queda `438E` + `empresa=LK`.
  3. Smoke test del front (`tests/`) + un picking headless.

---

## 5. Nivel 2 — OPCIONAL, NO ahora

Refactor del motor: que `etapa1`/`etapa2`/el trigger keyeen **nativo** por `(cod, empresa)` y se
elimine hasta el reensamble interno del sufijo. **No aporta nada funcional** (el stock guardado
ya es `(cod, empresa)`), suma superficie y riesgo sobre el motor compartido. Se puede dejar para
más adelante si se quiere pureza total; **no se recomienda** junto con el Nivel 1.

---

## 6. Alternativa — no hacer nada

El sufijo **funciona** y el **stock guardado ya está limpio**. El `437E LK` sólo vive en el
transporte y es info real del dual. Si la prolijidad del evento no justifica tocar el motor de
picking/stock, **dejarlo como está** es una opción válida y de riesgo cero.

---

## 7. Recomendación

**Nivel 1.** Es la versión limpia de tu idea (código crudo + empresa en su campo), contenida a
2 puntos, compatible hacia atrás, sin tocar el motor de stock, con el resultado guardado idéntico
y verificable. Nivel 2 y "no hacer nada" quedan como extremos.
