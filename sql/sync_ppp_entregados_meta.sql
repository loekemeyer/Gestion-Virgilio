-- =====================================================================
--  sync_ppp_entregados_meta()  —  espeja el Sheet "PPP Pedidos Entregados
--  2026" (gid 2146771217) a la tabla public."PPP_Entregados_Meta".
--
--  Está DEPLOYADO en Supabase (proyecto Virgilio hrxfctzncixxqmpfhskv) y corre
--  por cron pg_cron "sync-ppp-entregados-meta" cada :07 y :37 (7,37 * * * *).
--  Este archivo es la copia versionada para el repo (la fuente de verdad es la DB).
--
--  v6.99 (2026-08-03): además de np/cod/rs ahora captura TANDA (col A / ord 1),
--  Mt3 = m³ (col G / ord 7 — NO "Mt3 FC" que es col H / ord 8) y FECHA DE ENTREGA
--  (col M / ord 13). Así "Pedidos Entregados" en la app muestra TODO el histórico
--  con fecha y m³, no solo NP+cliente. Modelo: truncate + insert (igual que antes).
--
--  Layout del Sheet (por campo entrecomillado, ordinal):
--    1 Tanda · 3 NP · 5 Cod Cliente · 6 Razon Social · 7 Mt3 · 8 Mt3 FC ·
--    13 Fecha de Entrega · 14 Fecha de Fc
-- =====================================================================
CREATE OR REPLACE FUNCTION public.sync_ppp_entregados_meta()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare csv text; n integer;
begin
  select (http_get('https://docs.google.com/spreadsheets/d/1-16YXe0xq6x9i-Yhk5cm5V3VqvQ0PWZtcDbm8OeeKW0/gviz/tq?tqx=out:csv&gid=2146771217')).content into csv;
  if csv is null or length(csv) < 10 then return 0; end if;

  truncate public."PPP_Entregados_Meta";

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
      max(val) filter (where ord=1)  c_tanda,
      max(val) filter (where ord=2)  c1,
      max(val) filter (where ord=3)  c2,
      max(val) filter (where ord=5)  c_cod,
      max(val) filter (where ord=6)  c_rs,
      max(val) filter (where ord=7)  c_m3,
      max(val) filter (where ord=13) c_fent
    from fields group by rn
  ),
  clean as (
    select rn, trim(c_cod) cod, trim(c_rs) rs, trim(c_tanda) tanda,
      case when trim(c_fent) ~ '^\d{4}-\d{2}-\d{2}' then substr(trim(c_fent),1,10) else '' end fecha_entrega,
      case when position(',' in coalesce(c_m3,'')) > 0
           then replace(replace(trim(c_m3), '.', ''), ',', '.')
           else trim(coalesce(c_m3,'')) end m3txt,
      coalesce(c1,'') c1, coalesce(c2,'') c2
    from wide
  ),
  np_rows as (
    select rn, cod, rs, tanda, fecha_entrega,
      case when m3txt ~ '^-?[0-9]+(\.[0-9]+)?$' then m3txt::numeric else null end m3,
      trim(np) np
    from (
      select rn, cod, rs, tanda, fecha_entrega, m3txt,
        regexp_split_to_table(c1 || '/' || c2, '[,/]') np
      from clean
    ) x
    where trim(np) ~ '^[0-9]{2,7}$'
  ),
  pick as (
    select distinct on (np) np, cod, rs, tanda, m3, fecha_entrega
    from np_rows
    order by np, (nullif(rs,'') is not null) desc, rn desc
  )
  insert into public."PPP_Entregados_Meta"(np, cod, rs, tanda, m3, fecha_entrega)
  select np, cod, rs, tanda, m3, fecha_entrega from pick;

  get diagnostics n = row_count;
  return n;
end $function$;
