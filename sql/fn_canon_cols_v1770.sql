-- =====================================================================
--  fn_canon_cols() — UNA canonizadora de columna para todas las tablas — v17.70 (2026-09-14)
--
--  Reemplaza a las CINCO funciones que eran la misma escrita con distinto nombre de columna:
--    fn_canon_col_cod · fn_canon_col_cod_art · fn_canon_col_codigo ·
--    fn_canon_col_cod_art_quoted · fn_canon_col_articulo   (las 5 DROPEADAS)
--  Las cinco tenían exactamente el mismo cuerpo:
--    `NEW.<col> := public.canon_cod_art_val(NEW.<col>); return NEW;`
--
--  Y agrega el candado que faltaba en `Correcciones_Pedido`, que tiene DOS columnas de código
--  (`cod_principal`, `cod_secundario`) — justo el caso que no se podía cubrir sin fabricar
--  otra función más.
--
--  Resultado: **13 triggers, 1 función.** Antes: 12 triggers, 4 funciones + 1 huérfana.
--
-- ─────────────────────────────────────────────────────────────────────
--  LO QUE SE MIDIÓ ANTES (el riesgo NO era cero, y no era el que parecía)
-- ─────────────────────────────────────────────────────────────────────
--  1. **`jsonb_populate_record` reconstruye el record ENTERO**, no sólo la columna tocada. Las
--     12 tablas tienen **26 columnas `numeric` y 16 `timestamptz`** — si alguna no
--     round-tripeara limpio, el trigger la cambiaría sin que nadie lo pida.
--     **Medido y descartado**: `numeric` con ceros finales (`10.500`), `numeric(12,4)`,
--     `timestamptz` con microsegundos, `bigint` por encima de 2^53 (`9007199254740993`), `date`
--     y `boolean` vuelven **idénticos**, y el record completo compara igual.
--  2. **El riesgo real era la falla SILENCIOSA**: un dedazo en el nombre de columna del
--     `TG_ARGV` haría que `v_rec ->> 'mal'` diera NULL y el trigger **dejara de canonizar sin
--     avisar**. Por eso la función **explota** si la columna no existe en el record. Ése es el
--     guard que convierte el error mudo en error ruidoso.
--  3. **Un borde donde la primera versión difería de las viejas**: `canon_cod_art_val('   ')`
--     devuelve `''`, así que las viejas normalizan un valor de sólo espacios. El guard original
--     (`btrim(v_val) <> ''`) lo dejaba pasar. **Se sacó**: ahora sólo se saltea el NULL, igual
--     que las viejas (`canon_cod_art_val(null)` es NULL en las dos).
--  4. **Costo**: 20.000 inserts con la vieja 401 ms, con la genérica 698 ms → **1,74×**, pero en
--     absoluto **0,035 ms por fila**. Para `Entregas_Virgilio` (la más caliente, 10.439 filas)
--     es irrelevante: 100 filas = 3,5 ms.
--  5. El mapeo tabla→columna **no se tipeó a mano**: se deriva del nombre de la función vieja
--     de cada trigger y se validó contra `information_schema` — las 12 columnas existen y son
--     `text`.
--
-- ─────────────────────────────────────────────────────────────────────
--  VERIFICACIÓN DESPUÉS, sobre las 13 TABLAS REALES (transacción con ROLLBACK)
-- ─────────────────────────────────────────────────────────────────────
--  Un `UPDATE` con el código sucio `'  66 '` en una fila de cada tabla (el `UPDATE` dispara el
--  mismo trigger y esquiva los `NOT NULL` y las FK que frenaban al `INSERT`):
--    **12 dieron `066`** · `Volumen_Articulos` dio *duplicate key* — que **es el trigger
--    funcionando**: canonizó a `066` y chocó contra una fila que ya lo tenía.
--  → **13 de 13.**
--
--  ⚠ Y el propio guard de verificación frenó un error mío: el primer intento contaba las viejas
--  con `proname like 'fn_canon_col_%'`, y en `LIKE` el `_` es **comodín**, así que matcheaba
--  también `fn_canon_cols` y daba "quedaron 13 triggers con las viejas". El `DO` abortó y no
--  quedó nada a medias. Se pasó a lista explícita.
--
--  Las 5 viejas se dropearon **después** de verificar: 0 triggers usándolas y 0 funciones o
--  vistas nombrándolas.
--
--  Rollback: recrear las 5 (cuerpo de una línea cada una, arriba) y volver cada trigger a la
--  suya. El mapeo tabla→columna→trigger está en el bloque de abajo.
-- =====================================================================

create or replace function public.fn_canon_cols()
 returns trigger language plpgsql as $body$
declare v_col text; v_rec jsonb := to_jsonb(NEW);
begin
  -- Canoniza con canon_cod_art_val las columnas nombradas en TG_ARGV.
  -- El guard de columna inexistente es lo que evita la falla SILENCIOSA: sin él, un dedazo
  -- en el nombre haría que el trigger dejara de canonizar sin que nadie se entere.
  foreach v_col in array TG_ARGV loop
    if not (v_rec ? v_col) then
      raise exception 'fn_canon_cols: la tabla "%" no tiene la columna "%"', TG_TABLE_NAME, v_col;
    end if;
    if v_rec ->> v_col is not null then
      v_rec := jsonb_set(v_rec, array[v_col], to_jsonb(public.canon_cod_art_val(v_rec ->> v_col)));
    end if;
  end loop;
  NEW := jsonb_populate_record(NEW, v_rec);
  return NEW;
end $body$;

-- Los 13 triggers (tabla · columna · nombre):
--   Articulos_Cajas ............ "Cod_Art"  trg_canon_articulos_cajas_cod
--   Articulos_Discontinuados ... cod        trg_canon_articulos_disc_cod
--   Capacidad_Sector ........... cod        trg_canon_capacidad_sector_cod
--   Entregas_Virgilio .......... cod_art    trg_canon_entregas_cod_art
--   Envasar_Ubicaciones ........ cod_art    trg_canon_envasar_ubicaciones_cod
--   Faltantes_Notas ............ cod        trg_canon_faltantes_notas_cod
--   GV_Lugar_Item .............. cod        trg_canon_gv_lugar_item_cod
--   Importados ................. cod_art    trg_canon_importados_cod
--   Importados_Volumen ......... cod        trg_canon_importados_vol_cod
--   Ordenes_Compra ............. codigo     trg_canon_ordenes_compra_cod
--   Volumen_Articulos .......... codigo     trg_canon_volumen_articulos_cod
--   codigos_duales ............. cod        trg_canon_codigos_duales_cod
--   Correcciones_Pedido ........ cod_principal + cod_secundario   trg_canon_correcciones_pedido  ← NUEVO
--
-- create trigger <tg> before insert or update of <col> on public."<tabla>"
--   for each row execute function public.fn_canon_cols('<col>'[, '<col2>']);
--
-- Chequeo:
--   select count(*) from pg_trigger t join pg_proc p on p.oid=t.tgfoid
--    where not t.tgisinternal and p.proname='fn_canon_cols';   -- 13
