-- =====================================================================
--  sync_ppp_programacion_diaria() + sync_ppp_base_pedidos()
--  Pull server-side de las hojas PPP desde Google Sheets.
--  Proyecto Supabase: Control Partes Talleristas (hrxfctzncixxqmpfhskv)
--
--  REEMPLAZA el push vía Apps Script (sync-ppp-supabase.gs) para estas dos
--  tablas. El mismo patrón que sync_ppp_entregados_meta() (ya probado):
--  pg_cron + http_get al Sheet público + TRUNCATE+INSERT. Sin credentials
--  externas: la service_role key del Apps Script deja de ser necesaria.
--
--  FUENTE: Google Sheet 1-16YXe0xq6x9i-Yhk5cm5V3VqvQ0PWZtcDbm8OeeKW0
--    gid 1947169223 = PPP Excel Programacion Diaria
--    gid 845301421  = PPP Excel Base Datos Pedidos
--
--  ⚠ PPP_Base_Pedidos usa /export?format=csv (NO gviz). El endpoint gviz
--  infiere tipos de columna y convierte códigos como 035E/943E a número,
--  perdiendo el dato original. /export preserva el texto tal cual. Esto ya
--  lo descubrió el front (GUIA:5897) y usa el mismo endpoint.
--
--  ⚠ PPP_Base_Pedidos tiene columnas `fecha` y `cliente` que NO están en
--  el DDL original (ppp_supabase.sql:73-78) pero SÍ existen en la tabla
--  real (agregadas en v9.02, escritas por el Apps Script desde entonces).
--  Esta función las escribe. Si por algún motivo no existieran, hacer:
--    ALTER TABLE "PPP_Base_Pedidos" ADD COLUMN fecha text;
--    ALTER TABLE "PPP_Base_Pedidos" ADD COLUMN cliente text;
--
--  CRON sugerido: cada 5 minutos (*/5 * * * *). El Apps Script actual es
--  event-driven (se dispara al guardar el Excel), pero la actualización
--  del Sheet ya venía con retraso (GUIA:6376). 5 min es un buen compromiso.
--
--  MIGRACIÓN: después de deployar y verificar estas funciones, desactivar
--  el hook pushPPPToSupabase_ del Apps Script (basta con comentar la línea
--  `try { pushPPPToSupabase_(...) }` en handleCargaPPPSync_). NO borrarlo
--  de una: dejar el código comentado 1 semana como fallback. Después se
--  puede revocar SUPABASE_VIRGILIO_SERVICE_KEY de las Script Properties.
--
--  WATCHDOG: agregar los jobid al VALUES de watchdog_syncs_externos()
--  con umbral de 30 min (~6x el período de 5 min).
-- =====================================================================

-- ── 1) PPP_Programacion_Diaria ─────────────────────────────────────
-- Usa gviz CSV (todos los campos quoted, mismo patrón que entregados_meta).
-- 15 columnas por ordinal del campo entrecomillado:
--   1=Tanda, 2=Tipo, 3=NP, 4=FechaRecep, 5=Cod, 6=RazonSocial, 7=M3,
--   8=V, 9=Direccion, 10=Barrio, 11=Op, 12=FechaEntrega, 13=FechaFc,
--   14=Zona, 15=Observaciones
CREATE OR REPLACE FUNCTION public.sync_ppp_programacion_diaria()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare csv text; n integer;
begin
  select (http_get(
    'https://docs.google.com/spreadsheets/d/1-16YXe0xq6x9i-Yhk5cm5V3VqvQ0PWZtcDbm8OeeKW0/gviz/tq?tqx=out:csv&gid=1947169223'
  )).content into csv;
  if csv is null or length(csv) < 10 then return 0; end if;

  truncate public."PPP_Programacion_Diaria";

  with lines as (
    select row_number() over () rn, l
    from regexp_split_to_table(replace(csv, E'\r', ''), E'\n') l
  ),
  fields as (
    select rn, ord, m[1] val
    from lines, regexp_matches(l, '"([^"]*)"', 'g') with ordinality as t(m, ord)
    where rn > 1
  ),
  wide as (
    select rn,
      max(val) filter (where ord = 1)  c_tanda,
      max(val) filter (where ord = 2)  c_tipo,
      max(val) filter (where ord = 3)  c_np,
      max(val) filter (where ord = 4)  c_fecha_recep,
      max(val) filter (where ord = 5)  c_cod,
      max(val) filter (where ord = 6)  c_razon_social,
      max(val) filter (where ord = 7)  c_m3,
      max(val) filter (where ord = 8)  c_v,
      max(val) filter (where ord = 9)  c_direccion,
      max(val) filter (where ord = 10) c_barrio,
      max(val) filter (where ord = 11) c_op,
      max(val) filter (where ord = 12) c_fecha_entrega,
      max(val) filter (where ord = 13) c_fecha_fc,
      max(val) filter (where ord = 14) c_zona,
      max(val) filter (where ord = 15) c_observaciones
    from fields group by rn
  ),
  clean as (
    select rn,
      trim(c_np) np, trim(c_tanda) tanda, trim(c_tipo) tipo,
      trim(c_fecha_recep) fecha_recep, trim(c_cod) cod,
      trim(c_razon_social) razon_social,
      case when position(',' in coalesce(c_m3, '')) > 0
           then replace(replace(trim(c_m3), '.', ''), ',', '.')
           else trim(coalesce(c_m3, '')) end m3txt,
      trim(c_v) v, trim(c_direccion) direccion,
      trim(c_barrio) barrio, trim(c_op) op,
      trim(c_fecha_entrega) fecha_entrega, trim(c_fecha_fc) fecha_fc,
      trim(c_zona) zona, trim(c_observaciones) observaciones
    from wide
  )
  insert into public."PPP_Programacion_Diaria"
    (np, tanda, tipo, fecha_recep, cod, razon_social, m3, v,
     direccion, barrio, op, fecha_entrega, fecha_fc, zona, observaciones)
  select np, tanda, tipo, fecha_recep, cod, razon_social,
    case when m3txt ~ '^-?[0-9]+(\.[0-9]+)?$' then m3txt::numeric else null end,
    v, direccion, barrio, op, fecha_entrega, fecha_fc, zona, observaciones
  from clean
  where np ~ '\d';

  get diagnostics n = row_count;
  return n;
end $function$;

revoke execute on function public.sync_ppp_programacion_diaria() from public, anon, authenticated;


-- ── 2) PPP_Base_Pedidos ────────────────────────────────────────────
-- Usa /export?format=csv (NO gviz) para preservar artículos como 035E.
-- Layout fijo 6 columnas: Pedido(A), Fecha(B), Articulo(C), ?(D), Cliente(E), Cajas(F).
-- Solo Cliente (col E) puede tener comas (quoted en el CSV).
-- El regex usa greedy match para acomodar comas internas en col E.
CREATE OR REPLACE FUNCTION public.sync_ppp_base_pedidos()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare csv text; n integer;
begin
  select (http_get(
    'https://docs.google.com/spreadsheets/d/1-16YXe0xq6x9i-Yhk5cm5V3VqvQ0PWZtcDbm8OeeKW0/export?format=csv&gid=845301421'
  )).content into csv;
  if csv is null or length(csv) < 10 then return 0; end if;

  -- strip UTF-8 BOM if present
  if left(csv, 1) = E'﻿' then csv := substr(csv, 2); end if;

  truncate public."PPP_Base_Pedidos";

  with lines as (
    select row_number() over () rn, l
    from regexp_split_to_table(replace(csv, E'\r', ''), E'\n') l
    where l <> ''
  ),
  parsed as (
    -- 6 cols fijos: 4 simples a la izq, 1 potencialmente quoted, 1 simple a la der.
    -- ^(f1),(f2),(f3),(f4),(middle),(f6)$   con middle greedy = cliente
    select rn,
      m[1] as pedido_raw,
      m[2] as fecha_raw,
      m[3] as articulo_raw,
      case when m[5] like '"%"'
           then substr(m[5], 2, length(m[5]) - 2)
           else m[5] end as cliente_raw,
      m[6] as cajas_raw
    from lines,
      lateral regexp_matches(l,
        '^([^,]*),([^,]*),([^,]*),([^,]*),(.*),([^,]*)$'
      ) as t(m)
    where rn > 1
  ),
  clean as (
    select
      btrim(pedido_raw) pedido,
      nullif(btrim(fecha_raw), '') fecha,
      btrim(articulo_raw) articulo,
      nullif(btrim(cliente_raw), '') cliente,
      case when position(',' in coalesce(cajas_raw, '')) > 0
           then replace(replace(btrim(cajas_raw), '.', ''), ',', '.')
           else btrim(coalesce(cajas_raw, '')) end cajas_txt
    from parsed
  )
  insert into public."PPP_Base_Pedidos" (pedido, articulo, cajas, fecha, cliente)
  select pedido, articulo,
    case when cajas_txt ~ '^-?[0-9]+(\.[0-9]+)?$' then cajas_txt::numeric else null end,
    fecha, cliente
  from clean
  where pedido ~ '^\d' and articulo <> '';

  get diagnostics n = row_count;
  return n;
end $function$;

revoke execute on function public.sync_ppp_base_pedidos() from public, anon, authenticated;


-- =====================================================================
--  CRON JOBS
-- =====================================================================
-- select cron.schedule(
--   'sync-ppp-programacion-diaria',
--   '*/5 * * * *',
--   'select public.sync_ppp_programacion_diaria();'
-- );
-- select cron.schedule(
--   'sync-ppp-base-pedidos',
--   '*/5 * * * *',
--   'select public.sync_ppp_base_pedidos();'
-- );
--
-- Para ver los jobid asignados:
--   select jobid, jobname from cron.job
--    where jobname in ('sync-ppp-programacion-diaria', 'sync-ppp-base-pedidos');
--
-- Agregar al watchdog (reemplazar NN/MM por los jobid reales):
--   Sumar (NN, 30), (MM, 30) al VALUES de watchdog_syncs_externos().
--
-- Rollback:
--   select cron.unschedule('sync-ppp-programacion-diaria');
--   select cron.unschedule('sync-ppp-base-pedidos');
--   drop function if exists public.sync_ppp_programacion_diaria();
--   drop function if exists public.sync_ppp_base_pedidos();
--   -- y descomentar pushPPPToSupabase_ en el Apps Script

-- =====================================================================
--  VERIFICACIÓN post-deploy
-- =====================================================================
-- 1. Correr a mano:
--      select public.sync_ppp_programacion_diaria();
--      select public.sync_ppp_base_pedidos();
--    Deben devolver el conteo de filas (ej: ~148 y ~11954).
--
-- 2. Comparar contra lo que tiene hoy (ANTES de desactivar el Apps Script):
--      select count(*) from "PPP_Programacion_Diaria";  -- ~148
--      select count(*) from "PPP_Base_Pedidos";          -- ~11954
--    Los conteos deben ser iguales o muy cercanos.
--
-- 3. Verificar que los artículos texto se preservan:
--      select distinct articulo from "PPP_Base_Pedidos"
--       where articulo ~ '[A-Za-z]' order by 1;
--    Debe incluir 035E, 580E, 943E, etc. Si alguno aparece como número
--    o vacío, el gviz está interfiriendo → confirmar que se usa /export.
--
-- 4. Verificar m³ de Programacion:
--      select count(*), round(sum(m3)::numeric, 1) from "PPP_Programacion_Diaria"
--       where m3 is not null;
--    Comparar con el Sheet.
--
-- 5. Dejar corriendo 24 h con el Apps Script todavía activo (ambos escriben;
--    como ambos hacen TRUNCATE+INSERT, el último en correr gana y no hay
--    conflicto). Verificar que los conteos se mantienen estables.
--
-- 6. Desactivar el Apps Script: comentar la línea
--      try { pushPPPToSupabase_(data.sheetName, data.values); }
--    en handleCargaPPPSync_ de "Carga PPP.gs".
--
-- 7. Después de 1 semana sin problemas: revocar SUPABASE_VIRGILIO_SERVICE_KEY
--    de las Script Properties del Apps Script.
