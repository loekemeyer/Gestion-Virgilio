-- =====================================================================
--  Candados de código: precios_super_lk y Ordenes_Compra (v17.08, 2026-09-14)
--
--  ── LO QUE CAMBIÓ LA EVALUACIÓN ────────────────────────────────────────
--  El plan era "canonizar las 9 tablas con grafías dobles" (problema 134). Al leer
--  cómo busca cada lector, el diagnóstico se dio vuelta:
--
--  **Todos los lectores ya normalizan.** Por eso ninguna de las 30 grafías dobles
--  causó un problema real:
--   • `precios_super_lk` → la vista `cobranzas_precios_super` hace
--     `cob_norm_cod(cod) AS nc` y `gv_ppp_web_valor_items` compara `ps.nc = cob_norm_cod(...)`.
--   • `Ordenes_Compra` → `gv_oc_recompute_recibido` y `oc_vigentes_por_proveedor` usan
--     `norm_cod(o.codigo)`, `oc_backfill_valores` canoniza, y el front usa `_ocgNorm`
--     **145 veces**.
--
--  **El daño real no vino nunca de un lector: vino de una CLAVE DE DEDUPE.** Las dos
--  roturas del día fueron en `Movimientos_Stock`, donde el índice compara texto crudo:
--  el problema 130 (cambió el `cod_art` → el cron duplicó el picking) y el 136 (el
--  backfill cambió la `empresa` → el cron duplicó otra vez).
--
--  Conclusión: **el riesgo no es "el código está escrito distinto", es "la columna
--  entra en una clave de dedupe o de unicidad"**. Eso reordenó qué vale la pena hacer.
--
--  ── (1) precios_super_lk: el candado que SÍ tiene consecuencia medible ──
--  La PK es `(super_key, cod)` CRUDO, así que nada impedía cargar `26` y `026` para el
--  mismo súper. Si eso pasara, el join de `cobranzas_precios_super` devolvería DOS filas
--  para el mismo artículo y **el precio se contaría dos veces**. Hoy no pasa (0 casos,
--  medido), y este índice lo hace imposible.
--
--  ⚠ La expresión va INLINE, no `canon_cod_art_val(cod)`: esa función es **STABLE**
--  (lee `OC_Maximos`) y Postgres no la acepta en un índice. `cob_norm_cod` sí es
--  IMMUTABLE, pero se prefiere la expresión literal para no atar el índice a una función
--  que alguien pueda redefinir.
--
--  Probado: `insert ... ('abastecedor','026',999)` →
--  `duplicate key value violates unique constraint` con
--  `Key (super_key, regexp_replace(...))=(abastecedor, 26) already exists`.
--
--  ── (2) Ordenes_Compra: el trigger, que es barato ──────────────────────
--  Beneficio menor (los lectores ya normalizan) pero riesgo nulo: la PK es `id`, no hay
--  unique por `codigo`, y sólo afecta escrituras futuras. Probado con ROLLBACK: un
--  insert con `'0515'` queda guardado como `'515'`.
--
--  ── LO QUE NO SE TOCÓ, Y POR QUÉ ───────────────────────────────────────
--  `Ubicaciones_Articulos` (65 filas cambiarían), `Stock_Ubicaciones` (30) y
--  `Stock_Inicial_Cartones` (17): **no las lee NADIE** — 0 funciones, 0 vistas, 0 front.
--  Canonizarlas es mover datos históricos sin ningún consumidor que se beneficie.
--  Además `Stock_Inicial_Cartones` tiene **PK sobre `cod`** y una colisión (`52`/`052`),
--  así que ni siquiera se podría normalizar sin decidir a mano qué fila gana.
--  `Planimetria` (16) queda fuera: tiene 3 consumidores vivos y está para retirar.
--  Las tres de INSUMOS tampoco: `fn_canon_col_cod` resuelve contra `OC_Maximos`, que es
--  el maestro de artículos y no lleva insumos.
--
--  Rollback:
--    drop index public.precios_super_lk_super_cod_norm_uidx;
--    drop trigger trg_canon_ordenes_compra_cod on public."Ordenes_Compra";
-- =====================================================================

-- (1) impide dos grafías del mismo código para el mismo súper (duplicaría el precio)
create unique index if not exists precios_super_lk_super_cod_norm_uidx
  on public.precios_super_lk (super_key, (regexp_replace(upper(btrim(cod)),'^0+(?=.)','')));

-- (2) canoniza el código de artículo al escribir una OC
create trigger trg_canon_ordenes_compra_cod
  before insert or update of codigo on public."Ordenes_Compra"
  for each row execute function fn_canon_col_codigo();
