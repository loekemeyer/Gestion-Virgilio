-- v28.56 (Luis, 08/10/2026): ADS Stock — «E.M. plazo Xd».
-- El saldo a H días es: disponible − comprometido H d − E.M. del plazo.
-- E.M. plazo = Est. Madre (cajas/mes) × max(0, H − L) / 30, con L = cuánto tarda un pedido en salir.
-- Los pedidos que entran dentro del plazo salen L días después: sólo los que entran en los primeros
-- H − L días caen dentro del plazo. Lo comprometido ya es lo que entró antes de hoy.
-- L = promedio (entrega − fecha del pedido) de las NP web con entrega en las últimas 2 semanas
-- (gv_ads_lead_auto), salvo que un supervisor fije otro valor desde ADS (Stock_Config.ads_lead_dias).
-- Retira el «disponible − el mayor entre comprometido y E.M.» de la v27.92.
-- REGLA_CONFIRMADA_POR_USUARIO (Luis, 08/10: "que estadistica madre contemple ese dato")

create or replace function public.gv_ads_lead_auto()
 returns numeric language sql stable security definer set search_path to 'public' as $f$
  with h as (select (now() at time zone 'America/Argentina/Buenos_Aires')::date d)
  select round(avg(d), 1) from (
    select distinct on (p.empresa, p.np) (p.fecha_entrega::date - lp.fecha_pedido::date) d
      from "PPP_Web_Programacion" p
      join lk_pedidos_match lp on lp.empresa = p.empresa and lp.order_id::text = p.order_id::text, h
     where p.fecha_entrega between h.d - 14 and h.d and lp.fecha_pedido is not null) z
   where d between 0 and 60;
$f$;

create or replace function public.gv_ads_lead_dias()
 returns numeric language sql stable security definer set search_path to 'public' as $f$
  select coalesce((select nullif(valor, '')::numeric from "Stock_Config" where clave = 'ads_lead_dias'),
                  gv_ads_lead_auto(), 12);
$f$;

create or replace function public.gv_ads_config()
 returns jsonb language sql stable security definer set search_path to 'public' as $f$
  select jsonb_build_object(
    'umbral',  coalesce((select nullif(valor,'')::numeric from "Stock_Config" where clave='ads_umbral'), 0.5),
    'n_ocs',   coalesce((select nullif(valor,'')::int     from "Stock_Config" where clave='ads_n_ocs'), 4),
    'incluir_actual', coalesce((select valor in ('1','true') from "Stock_Config" where clave='ads_incluir_actual'), false),
    'lead_manual', (select nullif(valor,'')::numeric from "Stock_Config" where clave='ads_lead_dias'),
    'lead_auto',   gv_ads_lead_auto(),
    'lead_dias',   gv_ads_lead_dias());
$f$;

-- null = automático (promedio de las últimas 2 semanas)
create or replace function public.gv_ads_lead_guardar(p_dias numeric)
 returns jsonb language plpgsql security definer set search_path to 'public' as $f$
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'SUPERVISOR: sólo un supervisor cambia la config de ADS'; end if;
  if p_dias is not null and (p_dias < 0 or p_dias > 60) then raise exception 'días fuera de rango (0-60)'; end if;
  insert into "Stock_Config"(clave, valor, actualizado) values ('ads_lead_dias', coalesce(p_dias::text, ''), now())
    on conflict (clave) do update set valor = excluded.valor, actualizado = now();
  return gv_ads_config();
end $f$;
grant execute on function public.gv_ads_lead_guardar(numeric) to authenticated;
grant execute on function public.gv_ads_lead_auto(), public.gv_ads_lead_dias() to anon, authenticated;

-- gv_ads_stock2: misma definición viva del 08/10 salvo las tres columnas de saldo.
create or replace function public.gv_ads_stock2()
 returns table(cod text, cod_base text, linea text, descripcion text, terminado numeric, racks numeric, a_guardar numeric, excedente numeric, disponible numeric, proy_mes numeric, comp10 numeric, comp20 numeric, comp30 numeric, saldo10 numeric, saldo20 numeric, saldo30 numeric, dias_cubre numeric, oc_fecha date, oc_prov text, oc_cant integer, oc_rec integer, oc_estado text)
 language sql stable security definer set search_path to 'public'
as $function$
  with hoy as (select (now() at time zone 'America/Argentina/Buenos_Aires')::date d),
  ld as (select gv_ads_lead_dias() l),
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
         round(s.term + s.rk + s.ag + s.ex - coalesce(c.c10,0) - s.proy * greatest(0, 10 - ld.l) / 30.0, 0) /*v28.56-emplazo*/,
         round(s.term + s.rk + s.ag + s.ex - coalesce(c.c20,0) - s.proy * greatest(0, 20 - ld.l) / 30.0, 0),
         round(s.term + s.rk + s.ag + s.ex - coalesce(c.c30,0) - s.proy * greatest(0, 30 - ld.l) / 30.0, 0),
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

update public."GV_Reglas_Centinela"
   set patron = 'greatest\(0, 10 - ld\.l\)',
       regla = 'ADS: saldo = disponible − comprometido − E.M. × max(0, plazo − días que tarda en salir) / 30 (Luis 08/10, v28.56)',
       version = 'v28.56'
 where id = 351;

-- Rollback: sql/gv_ads_saldo_max_v2792.sql (vuelve al «mayor entre comprometido y E.M.»).
