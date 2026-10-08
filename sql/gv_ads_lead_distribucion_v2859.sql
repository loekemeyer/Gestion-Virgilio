-- v28.59 (Luis, 08/10/2026, D4 sí): ADS «E.M. plazo Xd» con la DISTRIBUCIÓN real de lo que tarda un pedido en salir.
-- Cron diario (04:19 ART) guarda la foto de las últimas 2 semanas en GV_ADS_Lead: promedio y la curva
-- F(d) = parte de las NP web entregadas que salió en d días corridos o menos (d = 0..60).
-- E.M. plazo H = Est. Madre/30 × Σ_{t=0}^{H-1} F(H − t)  (pedidos que entran el día t y salen antes del día H).
-- Si un supervisor fija los días a mano (Stock_Config.ads_lead_dias), queda el escalón: Est. Madre × max(0, H − L)/30.
-- El botón «%» de ADS vuelve al automático. Reemplaza la cuenta de la v28.57 (promedio fijo).
-- REGLA_CONFIRMADA_POR_USUARIO (Luis, 08/10: "D4 sí")

create table if not exists public."GV_ADS_Lead" (
  fecha date primary key,
  prom numeric, n int, cdf jsonb, calculado_en timestamptz default now());
alter table public."GV_ADS_Lead" enable row level security;
revoke insert, update, truncate on public."GV_ADS_Lead" from anon, authenticated;

create or replace function public.gv_ads_lead_calcular()
 returns jsonb language sql security definer set search_path to 'public' as $f$
  with h as (select (now() at time zone 'America/Argentina/Buenos_Aires')::date d),
  l as (select (p.fecha_entrega::date - lp.fecha_pedido::date) d
          from (select distinct on (p.empresa, p.np) p.* from "PPP_Web_Programacion" p, h
                 where p.fecha_entrega between h.d - 14 and h.d) p
          join lk_pedidos_match lp on lp.empresa = p.empresa and lp.order_id::text = p.order_id::text
         where lp.fecha_pedido is not null),
  ok as (select d from l where d between 0 and 60),
  c as (select g.d, (select count(*) from ok where ok.d <= g.d)::numeric / nullif((select count(*) from ok), 0) f
          from generate_series(0, 60) g(d)),
  fila as (select (select d from h) fecha, (select round(avg(d), 1) from ok) prom, (select count(*) from ok)::int n,
                  (select jsonb_agg(round(coalesce(f, 0), 4) order by d) from c) cdf),
  w as (insert into "GV_ADS_Lead"(fecha, prom, n, cdf, calculado_en)
        select fecha, prom, n, cdf, now() from fila where n > 0
        on conflict (fecha) do update set prom = excluded.prom, n = excluded.n, cdf = excluded.cdf, calculado_en = now()
        returning fecha, prom, n)
  select coalesce((select to_jsonb(w) from w), jsonb_build_object('n', 0));
$f$;

-- promedio automático = la última foto guardada (si no hay, se calcula al vuelo)
create or replace function public.gv_ads_lead_auto()
 returns numeric language sql stable security definer set search_path to 'public' as $f$
  select coalesce((select prom from "GV_ADS_Lead" order by fecha desc limit 1),
    (with h as (select (now() at time zone 'America/Argentina/Buenos_Aires')::date d)
     select round(avg(d), 1) from (
       select distinct on (p.empresa, p.np) (p.fecha_entrega::date - lp.fecha_pedido::date) d
         from "PPP_Web_Programacion" p
         join lk_pedidos_match lp on lp.empresa = p.empresa and lp.order_id::text = p.order_id::text, h
        where p.fecha_entrega between h.d - 14 and h.d and lp.fecha_pedido is not null) z
      where d between 0 and 60));
$f$;

-- días equivalentes de Est. Madre que caen en un plazo de H días (E.M. plazo = Est. Madre × esto / 30)
create or replace function public.gv_ads_em_dias(p_h int)
 returns numeric language sql stable security definer set search_path to 'public' as $f$
  with m as (select nullif(valor, '')::numeric l from "Stock_Config" where clave = 'ads_lead_dias'),
       c as (select cdf from "GV_ADS_Lead" order by fecha desc limit 1)
  select case
    when (select l from m) is not null then greatest(0, p_h - (select l from m))   /*v28.59-manual*/
    when (select cdf from c) is not null then
      (select coalesce(sum(((select cdf from c) ->> least(p_h - t, 60))::numeric), 0)
         from generate_series(0, p_h - 1) t)                                        /*v28.59-cdf*/
    else greatest(0, p_h - 12) end;
$f$;

create or replace function public.gv_ads_config()
 returns jsonb language sql stable security definer set search_path to 'public' as $f$
  select jsonb_build_object(
    'umbral',  coalesce((select nullif(valor,'')::numeric from "Stock_Config" where clave='ads_umbral'), 0.5),
    'n_ocs',   coalesce((select nullif(valor,'')::int     from "Stock_Config" where clave='ads_n_ocs'), 4),
    'incluir_actual', coalesce((select valor in ('1','true') from "Stock_Config" where clave='ads_incluir_actual'), false),
    'lead_manual', (select nullif(valor,'')::numeric from "Stock_Config" where clave='ads_lead_dias'),
    'lead_auto',   gv_ads_lead_auto(),
    'lead_dias',   gv_ads_lead_dias(),
    'lead_fecha',  (select fecha from "GV_ADS_Lead" order by fecha desc limit 1),
    'em_dias', jsonb_build_object('10', gv_ads_em_dias(10), '20', gv_ads_em_dias(20), '30', gv_ads_em_dias(30)));
$f$;
grant execute on function public.gv_ads_em_dias(int) to anon, authenticated;

-- gv_ads_stock2: definición viva del 08/10 (v28.57) cambiando sólo cómo entra la E.M. del plazo
create or replace function public.gv_ads_stock2()
 returns table(cod text, cod_base text, linea text, descripcion text, terminado numeric, racks numeric, a_guardar numeric, excedente numeric, disponible numeric, proy_mes numeric, comp10 numeric, comp20 numeric, comp30 numeric, saldo10 numeric, saldo20 numeric, saldo30 numeric, dias_cubre numeric, oc_fecha date, oc_prov text, oc_cant integer, oc_rec integer, oc_estado text)
 language sql stable security definer set search_path to 'public'
as $function$
  with hoy as (select (now() at time zone 'America/Argentina/Buenos_Aires')::date d),
  ld as (select gv_ads_em_dias(10) e10, gv_ads_em_dias(20) e20, gv_ads_em_dias(30) e30),
  s as (select s.cod, s.cod_base, s.linea, s.descripcion,
               coalesce(s.terminado,0) term, coalesce(s.racks,0) + coalesce(s.racks_ch,0) rk,
               coalesce(s.a_guardar,0) ag, coalesce(s.excedente,0) ex, coalesce(s.proy_cajas_mes,0) proy
          from stocks_carga_rapida s
         where not coalesce(s.es_insumo,false) and coalesce(s.visible_en_stock,true)),
  dem as (select d.codn, d.emp, d.fecha_entrega, d.cajas from gv_demanda_programada_pendiente d
           where d.fecha_entrega is not null and d.fecha_entrega <= (select d from hoy) + 30),
  c as (select s.cod,
               coalesce(sum(dem.cajas) filter (where dem.fecha_entrega <= (select d from hoy) + 10),0) c10,
               coalesce(sum(dem.cajas) filter (where dem.fecha_entrega <= (select d from hoy) + 20),0) c20,
               coalesce(sum(dem.cajas),0) c30
          from s join dem on dem.codn = s.cod_base and (s.cod = s.cod_base or s.linea = dem.emp)
         group by s.cod),
  ocv as (select norm_cod(o.codigo) cod, max(o.fecha) fecha from "Ordenes_Compra" o
           where o.rubro = 'Art Term' and lower(coalesce(o.estado,'')) in ('pendiente','recibida')
           group by 1),
  oc as (select v.cod, v.fecha, string_agg(distinct o.proveedor, ' + ') prov,
                sum(o.cantidad)::int cant, sum(o.cantidad_recibida)::int rec,
                case when bool_and(lower(o.estado) = 'recibida') then 'recibida' else 'pendiente' end est
           from ocv v join "Ordenes_Compra" o on norm_cod(o.codigo) = v.cod and o.fecha = v.fecha
            and o.rubro = 'Art Term' and lower(coalesce(o.estado,'')) in ('pendiente','recibida')
          group by v.cod, v.fecha)
  select s.cod, s.cod_base, s.linea, s.descripcion, s.term, s.rk, s.ag, s.ex, s.term + s.rk + s.ag + s.ex, s.proy,
         coalesce(c.c10,0), coalesce(c.c20,0), coalesce(c.c30,0),
         round(s.term + s.rk + s.ag + s.ex - coalesce(c.c10,0) - s.proy * ld.e10 / 30.0, 0) /*v28.59-emplazo*/,
         round(s.term + s.rk + s.ag + s.ex - coalesce(c.c20,0) - s.proy * ld.e20 / 30.0, 0),
         round(s.term + s.rk + s.ag + s.ex - coalesce(c.c30,0) - s.proy * ld.e30 / 30.0, 0),
         case when s.proy > 0 then round(greatest(s.term + s.rk + s.ag + s.ex - coalesce(c.c30,0), 0) / (s.proy / 30.0), 0) end,
         oc.fecha, oc.prov, oc.cant, oc.rec, oc.est
    from s cross join ld left join c on c.cod = s.cod left join oc on oc.cod = s.cod
   where (s.proy > 0 or coalesce(c.c30,0) > 0)
     -- v27.32 (Luis D11): saldos en cajas ENTERAS: quiebre sólo si falta media caja o más
     -- v27.23 (Luis, 06/10): sólo artículos con TALLERISTA (proveedor activo en OC_Maximos)
     and exists (select 1 from "OC_Maximos" m
                  where coalesce(m.activo, true) and nullif(btrim(m.proveedor), '') is not null
                    and regexp_replace(norm_cod(m.cod), '\s+(LK|CH)$', '') = s.cod_base);
$function$;

-- cron diario 04:19 ART (07:19 UTC; minuto 19 sin pesados en gv_cron_colisiones), con anti-solape
-- select cron.schedule('gv-ads-lead-diario', '19 7 * * *',
--   $cron$do $c$ begin if pg_try_advisory_xact_lock(hashtext('cron:gv_ads_lead_calcular')::bigint) then perform public.gv_ads_lead_calcular(); end if; end $c$$cron$);
-- centinela 351 → patrón 'ld\.e10' · rollback: sql/gv_ads_em_plazo_v2857.sql
