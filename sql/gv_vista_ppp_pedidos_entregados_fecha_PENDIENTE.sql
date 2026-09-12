-- gv_vista_ppp_pedidos_entregados_fecha_PENDIENTE.sql
-- Arreglo del 500 de `vista_ppp_pedidos_entregados`: `invalid input syntax for type date: ""`.
--
-- ⚠ NO APLICADO. Escrito el 2026-09-12 con el canal SQL del MCP caído.
-- Diagnóstico en docs/HALLAZGOS-LOGS-20260912.md. 39 fallas en 24 h.
--
-- Quién la consulta: `pppRefreshDelivered()` (index.html:30384), o sea el panel
-- **Entregados / En viaje** de la PPP. Falla CALLADO: el front usa `supaFetchAllSafe`, que se
-- traga el error y devuelve [], así que el supervisor ve el panel vacío y cree que no hay
-- entregas — no que la consulta se rompió.
--
-- Hipótesis (a confirmar en el paso 1): las fechas de la PPP son TEXT, no date. Se ve en
-- `gv_ppp_entregados` (sql/gv_ppp_entregados.sql:53), que hace `left(fecha_entrega, 10)` y
-- `fecha_salida::text` justamente para no castear. Si en la versión viva de
-- `vista_ppp_pedidos_entregados` quedó un `::date` pelado sobre una de esas columnas y alguna
-- fila tiene `''` (cadena vacía, que NO es null), la vista entera revienta.
--
-- ⚠ Y ojo: `sql/ppp_vistas_sheet.sql:28` YA NO ES la vista viva — no tiene `fecha_carga` ni
--    `fecha_ppp`, que son dos de las columnas que el front pide. La versión de la base se
--    adelantó al archivo. Parte del trabajo es volver a versionarla.
--
-- ⚠ UNA QUERY POR LLAMADA.

-- ── 1) VER LA VISTA VIVA (esto es lo que falta para saber dónde está el cast) ─────────────
select pg_get_viewdef('public.vista_ppp_pedidos_entregados'::regclass, true);

-- ── 2) REPRODUCIR la falla y encontrar la fila culpable ──────────────────────────────────
-- Confirmar que revienta:
select count(*) from public.vista_ppp_pedidos_entregados;

-- Buscar las cadenas vacías en las columnas de fecha de las tablas madre. `''` no es null:
-- `where fecha is null` NO las encuentra, por eso pasaron desapercibidas.
select 'PPP_Programacion_Diaria' tabla, np, fecha_entrega, fecha_recep, fecha_fc
  from public."PPP_Programacion_Diaria"
 where btrim(coalesce(fecha_entrega,'x')) = '' or btrim(coalesce(fecha_recep,'x')) = ''
    or btrim(coalesce(fecha_fc,'x')) = '';

select 'Facturacion_NP' tabla, np, fecha_salida
  from public."Facturacion_NP" where btrim(coalesce(fecha_salida::text,'x')) = '';

-- Qué tipo tiene cada columna de fecha (para saber cuáles castea la vista y cuáles no):
select table_name, column_name, data_type
  from information_schema.columns
 where table_schema = 'public'
   and table_name in ('PPP_Programacion_Diaria','Facturacion_NP','Facturacion_Cierres',
                      'PPP_Entregados_Meta','Entregas_Virgilio')
   and (column_name ilike 'fecha%' or column_name ilike '%_at')
 order by table_name, column_name;

-- ── 3) BACKUP de la definición viva, antes de tocarla ────────────────────────────────────
create table if not exists zz_backups."GV_Backup_viewdef_ppp_entregados_20260912" as
  select 'vista_ppp_pedidos_entregados' as vista,
         pg_get_viewdef('public.vista_ppp_pedidos_entregados'::regclass, true) as def,
         now() as guardado_en;
alter table zz_backups."GV_Backup_viewdef_ppp_entregados_20260912" enable row level security;
revoke insert, update, delete, truncate on zz_backups."GV_Backup_viewdef_ppp_entregados_20260912"
  from anon, authenticated;

-- ── 4) EL FIX ────────────────────────────────────────────────────────────────────────────
-- El arreglo NO es limpiar los datos: es que la vista no reviente con un dato que la tabla
-- permite guardar. Todo `<x>::date` sobre una columna de texto pasa a
-- `nullif(btrim(<x>), '')::date`, que devuelve NULL en vez de tirar la consulta abajo.
-- El front ya está preparado: `String(r.fecha_carga || "").slice(0,10)` con null da "".
--
-- Se escribe con el patrón que el repo ya usa (leer el viewdef vivo, reemplazar el bloque
-- exacto, volver a crear), y con `raise exception` si el bloque no aparece — así nunca
-- se recrea la vista a medias:
--
--   do $$
--   declare d text; viejo text; nuevo text;
--   begin
--     d := pg_get_viewdef('public.vista_ppp_pedidos_entregados'::regclass, true);
--     viejo := '<el cast exacto que muestre el paso 1>';
--     nuevo := '<el mismo, envuelto en nullif(btrim(...), '''')>';
--     if position(viejo in d) = 0 then raise exception 'no se encontro el cast'; end if;
--     execute 'create or replace view public.vista_ppp_pedidos_entregados '
--          || 'with (security_invoker = true) as ' || replace(d, viejo, nuevo);
--   end $$;
--
-- (El texto exacto sale del paso 1; no lo invento acá.)

-- ── 5) VERIFICAR ─────────────────────────────────────────────────────────────────────────
select count(*) filas from public.vista_ppp_pedidos_entregados;   -- ya no debe reventar

-- El select EXACTO que hace el front (index.html:30384) — es el que fallaba:
select np, tanda, cod_cliente, razon_social, m3, fecha_carga, fecha_ppp, fecha_reparto,
       fecha_salida, facturado_at, cajas_pedidas, cajas_entregadas, cajas_falto
  from public.vista_ppp_pedidos_entregados order by facturado_at desc limit 5;

-- Y a las 24 h: 0 `invalid input syntax for type date` en los logs (hoy 39).

-- ── 6) RE-VERSIONAR ──────────────────────────────────────────────────────────────────────
-- Pisar el bloque de sql/ppp_vistas_sheet.sql:28 con la definición viva ya arreglada, para
-- que el archivo deje de estar atrasado respecto de la base.

-- ── ROLLBACK ─────────────────────────────────────────────────────────────────────────────
--   do $$ begin execute 'create or replace view public.vista_ppp_pedidos_entregados '
--     || 'with (security_invoker = true) as ' || (select def from
--        zz_backups."GV_Backup_viewdef_ppp_entregados_20260912"); end $$;
