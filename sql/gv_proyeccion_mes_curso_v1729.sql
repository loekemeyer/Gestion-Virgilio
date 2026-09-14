-- ============================================================================
-- v17.29 — "Cómo viene el mes": el cierre proyectado del mes en curso
--
-- Proyecto LK (kwkclwhmoygunqmlegrg).
--
-- Thomas (14/09): "calcula proyeccion para compras como lo viene haciendo /
-- fijate si se puede tener el dato (y mostrar en algun lado que tenga sentido)
-- la proyeccion final del mes en curso (considerando los datos del mes que van
-- cayendo en vivo)".
--
-- ⚠ ESTO NO TOCA LA PROYECCION DE COMPRAS. `_fn_proy_window` y
-- `_fn_proy_window_emp` quedan exactamente como estaban (ventana de 6 meses,
-- terminando en el ultimo mes completo). Son dos cosas distintas:
--   * proyeccion de COMPRAS  -> cuanto se vende por mes, para pedir a China
--   * proyeccion DEL MES     -> como va a cerrar septiembre, para mirarlo hoy
--
-- Se puede recien ahora: desde que sales_lines se llena sola desde ISIS
-- (v17.24) el mes corriente esta en vivo. Con el Excel mensual no existia.
--
-- METODO: extrapolar por dias habiles transcurridos. La curva de como se
-- factura dentro del mes resulto casi recta en LK — al 50 % de los dias
-- habiles va el 49,0 % de las cajas, al 75 % el 72,7 %, al 90 % el 90,0 % —
-- asi que no hace falta ninguna curva de forma, alcanza con la regla de tres.
--
-- ERROR MEDIDO (24 meses, LK), contra el cierre real:
--    al 25 % del mes ... 11,8 %
--    al 50 % .......... 12,7 %
--    al 75 % ...........  5,2 %
--    al 90 % ...........  4,8 %
--    adivinar con el promedio de los 3 meses previos, sin dato vivo ... 15,0 %
--
-- ROLLBACK:
--   drop function if exists public.gv_proyeccion_mes();
--   drop view if exists public.gv_proyeccion_mes_curso;
--   (y sacar _gvCargarMes de admin.js)
-- ============================================================================

create or replace view public.gv_proyeccion_mes_curso
with (security_invoker = true) as
with cfg as (select date_trunc('month', current_date)::date mes_ini,
                    (date_trunc('month', current_date) + interval '1 month - 1 day')::date mes_fin),
 habiles as (
  select (select count(*) from generate_series((select mes_ini from cfg), (select mes_fin from cfg), '1 day') g(d)
           where extract(dow from d) between 1 and 5) as dh_mes,
         (select count(*) from generate_series((select mes_ini from cfg), current_date, '1 day') g(d)
           where extract(dow from d) between 1 and 5) as dh_hoy
), v as (
  select empresa, sum(boxes)::numeric cajas, max(invoice_date) ultima
    from public.sales_lines, cfg
   where invoice_date >= to_char(cfg.mes_ini,'YYYY-MM-DD')
     and item_code not in (select item_code from public.sales_excluded_items)
   group by 1
), hist as (
  select empresa, date_trunc('month', invoice_date::date)::date mes, sum(boxes)::numeric total
    from public.sales_lines, cfg
   where invoice_date ~ '^\d{4}-\d{2}-\d{2}'
     and invoice_date::date < cfg.mes_ini
     and item_code not in (select item_code from public.sales_excluded_items)
   group by 1,2
), ref as (
  select empresa,
         max(total) filter (where mes = (select mes_ini from cfg) - interval '1 month') mes_anterior,
         avg(total) filter (where mes >= (select mes_ini from cfg) - interval '3 months') media_3m
    from hist group by 1
)
select v.empresa,
       (select mes_ini from cfg)                                       as mes,
       v.cajas::bigint                                                 as cajas_hasta_hoy,
       v.ultima                                                        as ultima_factura,
       h.dh_hoy                                                        as dias_habiles_transcurridos,
       h.dh_mes                                                        as dias_habiles_del_mes,
       round(100.0 * h.dh_hoy / h.dh_mes)::int                         as pct_mes_transcurrido,
       round(v.cajas * h.dh_mes::numeric / nullif(h.dh_hoy,0))::bigint  as proyeccion_cierre,
       round(ref.mes_anterior)::bigint                                 as mes_anterior,
       round(ref.media_3m)::bigint                                     as media_3_meses,
       round(100.0 * (v.cajas * h.dh_mes::numeric / nullif(h.dh_hoy,0) - ref.media_3m)
             / nullif(ref.media_3m,0))::int                            as vs_media_3m_pct,
       case when h.dh_hoy::numeric / h.dh_mes < 0.3  then '±12 %'
            when h.dh_hoy::numeric / h.dh_mes < 0.6  then '±13 %'
            else '±5 %' end                                            as margen_tipico
  from v cross join habiles h left join ref on ref.empresa = v.empresa;

-- El front no puede leer la vista directo: la RLS de sales_lines solo deja ver
-- las filas propias del cliente logueado. Va por RPC, mismo patron que
-- gv_dashboard (SECURITY DEFINER + guard gv_es_admin()).
create or replace function public.gv_proyeccion_mes()
returns table (
  empresa text, mes date, cajas_hasta_hoy bigint, ultima_factura text,
  dias_habiles_transcurridos int, dias_habiles_del_mes int, pct_mes_transcurrido int,
  proyeccion_cierre bigint, mes_anterior bigint, media_3_meses bigint,
  vs_media_3m_pct int, margen_tipico text)
language plpgsql security definer set search_path = public, pg_temp
as $fn$
begin
  perform gv_es_admin();
  return query
    select p.empresa, p.mes, p.cajas_hasta_hoy, p.ultima_factura,
           p.dias_habiles_transcurridos, p.dias_habiles_del_mes, p.pct_mes_transcurrido,
           p.proyeccion_cierre, p.mes_anterior, p.media_3_meses, p.vs_media_3m_pct, p.margen_tipico
      from public.gv_proyeccion_mes_curso p order by p.empresa;
end $fn$;

revoke execute on function public.gv_proyeccion_mes() from public, anon;
grant  execute on function public.gv_proyeccion_mes() to authenticated;

-- Medido el 14/09 (10 de 22 dias habiles, 45 % del mes):
--   lk    8.127 cj hasta hoy -> cierre proyectado 17.879  (mes ant. 19.076, prom 3m 17.184)
--   chef  2.145 cj           -> cierre proyectado  4.719  (mes ant.  3.463, prom 3m  3.514)
