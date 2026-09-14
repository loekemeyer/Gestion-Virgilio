-- =====================================================================
--  Canonización: candado en GV_Lugar_Item + etapa 3 recortada — v17.51 (2026-09-14)
--  Plan: docs/PLAN-CANONIZACION-UNICA.md · Etapas 0 y 1: sql/gv_canon_centinelas_v1746.sql
--
--  Dos cosas chicas y medidas, y una que se DESCARTA con el número delante.
--
-- ─────────────────────────────────────────────────────────────────────
--  (1) CANDADO DE CANONIZACIÓN EN `GV_Lugar_Item`
-- ─────────────────────────────────────────────────────────────────────
--  Cierra el hueco que encontraron los dos handoffs de planimetría del 14/09:
--  `Capacidad_Sector` (el ESPEJO) tenía trigger de canonización y `GV_Lugar_Item` —la tabla
--  MADRE del mapa, la que lee el picking vía `gv_lugar_articulo`— **no tenía ninguno**.
--  Dependía 100 % de que todo el mundo entrara por la RPC, y el handoff documenta que se
--  escribió a mano por SQL.
--
--  ⚠ Se eligió `fn_canon_col_cod` —el MISMO trigger que ya tiene `Capacidad_Sector`— y no
--  una función nueva que mire `clase`, a propósito: **no se inventa una regla**. La RPC
--  `gv_lugar_item_guardar` YA canoniza con `canon_cod_art_val` sin mirar la clase, y
--  `fn_canon_col_cod` es exactamente ese camino. Así las dos tablas hermanas canonizan
--  idéntico y el trigger sólo garantiza, para quien no pase por la RPC, lo que la RPC ya hace.
--
--  Medido antes: 790 filas, **cambian 0**; 0 filas con `clase = 'insumo'`.
--  Verificado después, en una transacción con ROLLBACK: un `INSERT` a mano con el código
--  escrito sucio (`'  66 '`) quedó guardado como **`066`**.
--  Backup: `zz_backups."GV_Backup_Lugar_Item_pre_canon_20260914"` (790 filas).
--
-- ─────────────────────────────────────────────────────────────────────
--  (2) ETAPA 3 RECORTADA: `canon_cod` pasa a ser envoltorio de `norm_cod`
-- ─────────────────────────────────────────────────────────────────────
--  En la v17.46 se dejó sin fusionar porque vive dentro del índice único
--  `gv_precios_cliente_canon_uk ON "GV_Precios_Cliente" (empresa, cod_cliente, canon_cod(cod))`.
--  Ahora sí, porque el riesgo está acotado y medido:
--    • idéntica a `norm_cod` sobre las 523 entradas del dominio real, bordes incluidos;
--    • la tabla tiene **4 filas** y **0 claves cambian**;
--    • sigue `IMMUTABLE` (obligatorio: vive en un índice) porque `norm_cod` lo es.
--  Se hizo `reindex index public.gv_precios_cliente_canon_uk` igual, por higiene.
--  Verificado después: índice `indisvalid = true`, 4 filas, `Z. ALARMA` en 0.
--  Backup: `zz_backups."GV_Backup_Precios_Cliente_pre_canon_20260914"` (4 filas).
--
--  Con esto la regla de "pelar ceros a la izquierda" tiene **UNA sola implementación**
--  (`norm_cod`); `canon_cod` y `cob_norm_cod` son envoltorios.
--
--  ⚠ Se llamó de verdad a las 5 funciones que usan `canon_cod`, porque Postgres no revalida
--  el cuerpo hasta la primera llamada (lección del `DROP COLUMN` de la v16.39):
--  `isis_pedido_json`, `gv_isis_pedido_json`, `gv_conciliacion_comparar`,
--  `gv_ppp_web_valor_items` (camino de precio) y `gv_cruce_fc_asignacion`. Las 5 sin error.
--
-- ─────────────────────────────────────────────────────────────────────
--  (3) ETAPA 2b — **NO SE HACE**, y acá está el número que lo decide
-- ─────────────────────────────────────────────────────────────────────
--  Era: que `gv_cod_stock` resuelva contra `OC_Maximos` en vez de pelar ceros a ciegas.
--  El riesgo que la justificaba era "alguien compara `gv_cod_stock(a)` contra un `b` crudo".
--  **Se midió y no existe: las 8 comparaciones que involucran `gv_cod_stock` son SIMÉTRICAS**
--  (`gv_cod_stock(x) = gv_cod_stock(y)`), incluido el `v_codstock` de `gv_importados_resync`,
--  que se asigna con `select gv_cod_stock(cod_art) into v_codstock`.
--
--  Lo que sí existe es otra cosa, y más chica: **3 vistas la usan como VALOR, no como clave**,
--  así que muestran el código con los ceros pelados —
--    `gv_venta_mensual_cliente` 574 filas de 8.892 · `vista_venta_mensual` 60 de 845 ·
--    `vista_stock_vs_pedidos` 19 de 301 — todas del tipo `31`→`031`, `26`→`026`, `35E`→`035E`.
--
--  Es **cosmético**: no corrompe datos ni duplica nada (los joins son simétricos). Y los dos
--  arreglos posibles son desproporcionados con el depósito operando:
--    (a) tocar `gv_cod_stock` la vuelve **STABLE** (leería una tabla), y la usan 8 funciones
--        + 14 vistas, entre ellas la matview `vista_stock_procesada`;
--    (b) reescribir las 3 vistas: `vista_stock_vs_pedidos` tiene **12 dependientes directos**
--        y las tres tienen `GROUP BY`, así que cambiar la expresión de `cod` cambia el
--        agrupamiento.
--  Queda medido para una ventana. `gv_cod_stock` no está en ningún índice (se verificó), así
--  que la opción (a) sigue siendo técnicamente posible el día que se quiera.
--
-- ─────────────────────────────────────────────────────────────────────
--  ⚠ LECCIÓN MEDIDA: el hash de una vista contra una foto vieja NO aísla nada
-- ─────────────────────────────────────────────────────────────────────
--  Al comparar contra la foto de la v17.46, `vista_facturable_anticipado` dio **hash distinto**
--  con las mismas 582 filas. Parecía que el cambio de `canon_cod` la había movido.
--  No era eso. La prueba que lo separó, y que es la que hay que usar:
--
--    begin;
--      create or replace function public.canon_cod(x text) ... -- el cuerpo VIEJO
--      select md5(...) from public.vista_facturable_anticipado;
--    rollback;
--
--  Con el cuerpo viejo, **sobre los datos de ahora**, dio el MISMO hash que con el nuevo. O sea
--  que lo que cambió fueron **los datos** (es facturación anticipada, se mueve sola), no la
--  función. Una foto de hace una hora contra una base que opera no prueba nada: la comparación
--  válida es **las dos versiones de la función sobre los mismos datos, dentro de una
--  transacción**.
--
--  Rollback:
--    drop trigger if exists trg_canon_gv_lugar_item_cod on public."GV_Lugar_Item";
--    create or replace function public.canon_cod(x text) returns text language sql immutable
--    as $$ SELECT CASE WHEN coalesce(trim(x),'') = '' THEN ''
--                      WHEN trim(x) ~ '^0+$' THEN '0'
--                      ELSE ltrim(upper(trim(x)), '0') END $$;
--    reindex index public.gv_precios_cliente_canon_uk;
-- =====================================================================


-- (1) candado en la tabla madre del mapa de góndolas
create trigger trg_canon_gv_lugar_item_cod
  before insert or update of cod on public."GV_Lugar_Item"
  for each row execute function public.fn_canon_col_cod();


-- (2) una sola implementación de "pelar ceros": norm_cod
CREATE OR REPLACE FUNCTION public.canon_cod(x text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select public.norm_cod(x)
$function$;

reindex index public.gv_precios_cliente_canon_uk;


-- ── CHEQUEO DE SALUD AL CERRAR (todo verificado el 14/09) ────────────
-- select (select count(*) from public.gv_canon_divergencias where motivo like 'Z.%') alarma,        -- 0
--        (select count(*) from public.gv_endpoints_rotos)                            endpoints,     -- 0
--        (select count(*) from public."GV_Lugar_Item")                               lugar_item,    -- 790
--        (select indisvalid from pg_index
--          where indexrelid='public.gv_precios_cliente_canon_uk'::regclass)          idx_ok,        -- true
--        (select count(*) from public.gv_stock_particion_sospechosa)                 particion;     -- 0
