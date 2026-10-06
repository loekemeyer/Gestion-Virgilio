-- v27.20 (Luis, 06/10/2026): ADS · ALERTAS DAMIÁN STOCK
-- Dos lecturas + config + badge. Sólo lectura sobre Ordenes_Compra, stocks_carga_rapida y
-- gv_demanda_programada_pendiente. Escribe sólo 3 claves de Stock_Config (ads_*), con guard de supervisor.
--
-- 1) gv_ads_talleristas(p_n, p_incluir_actual): por (proveedor de la OC, código) en las ÚLTIMAS N OC
--    (fechas de generación, rubro 'Art Term'). La OC de cada semana REEMPLAZA a la anterior (lleva lo
--    que faltaba entregar + lo nuevo), así que lo PEDIDO no es la suma de las OC:
--      pedido = 1.ª OC del rango + Σ max(0, OC_k − (OC_{k−1} − recibido_{k−1}))
--      entregado = Σ recibido de cada OC (cantidad_recibida, ya imputada por gv_oc_recompute_recibido)
--    Ejemplo de Luis: OC1 300 (entregó 150), OC2 200 (entregó 100) → pedido 300 + (200−150) = 350,
--    entregado 250, 71 %.
--    p_incluir_actual = false (default) deja afuera la OC más nueva: su semana todavía corre.
-- 2) gv_ads_stock(): disponible (góndola + racks + racks CH + a guardar) − comprometido (NP programadas
--    sin pickear con entrega hasta hoy+N, vencidas incluidas) − Est. Madre × N/30, a 10/20/30 días,
--    con la última OC vigente del código.
-- 3) gv_ads_badge(): talleristas con % entregado < umbral en el rango configurado.
-- Rollback: drop function public.gv_ads_talleristas(int,boolean), public.gv_ads_stock(),
--   public.gv_ads_badge(), public.gv_ads_config(), public.gv_ads_config_guardar(numeric,int,boolean);
--   delete from public."Stock_Config" where clave like 'ads\_%';

create or replace function public.gv_ads_config()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'umbral',  coalesce((select nullif(valor,'')::numeric from "Stock_Config" where clave='ads_umbral'), 0.5),
    'n_ocs',   coalesce((select nullif(valor,'')::int     from "Stock_Config" where clave='ads_n_ocs'), 4),
    'incluir_actual', coalesce((select valor in ('1','true') from "Stock_Config" where clave='ads_incluir_actual'), false));
$$;

create or replace function public.gv_ads_config_guardar(p_umbral numeric, p_n int, p_incluir boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then raise exception 'SUPERVISOR: sólo un supervisor cambia la config de ADS'; end if;
  if p_umbral is not null and (p_umbral <= 0 or p_umbral > 1) then raise exception 'umbral fuera de rango (0-1]'; end if;
  if p_n is not null and (p_n < 1 or p_n > 52) then raise exception 'cantidad de OC fuera de rango (1-52)'; end if;
  if p_umbral is not null then insert into "Stock_Config"(clave,valor,actualizado) values('ads_umbral',p_umbral::text,now())
     on conflict (clave) do update set valor=excluded.valor, actualizado=now(); end if;
  if p_n is not null then insert into "Stock_Config"(clave,valor,actualizado) values('ads_n_ocs',p_n::text,now())
     on conflict (clave) do update set valor=excluded.valor, actualizado=now(); end if;
  if p_incluir is not null then insert into "Stock_Config"(clave,valor,actualizado) values('ads_incluir_actual',case when p_incluir then '1' else '0' end,now())
     on conflict (clave) do update set valor=excluded.valor, actualizado=now(); end if;
  return gv_ads_config();
end $$;

create or replace function public.gv_ads_talleristas(p_n int default null, p_incluir_actual boolean default null)
returns table(proveedor text, pkey text, codigo text, descripcion text, ocs int, pedido numeric,
              entregado numeric, pct numeric, desde date, hasta date,
              ult_fecha date, ult_cant int, ult_rec int, ult_estado text)
language sql stable security definer set search_path = public as $$
  with cfg as (select coalesce(p_n, (gv_ads_config()->>'n_ocs')::int) n,
                      coalesce(p_incluir_actual, (gv_ads_config()->>'incluir_actual')::boolean) inc),
  f_all as (select distinct o.fecha from "Ordenes_Compra" o where o.rubro = 'Art Term' and o.fecha is not null),
  f_ok as (select f.fecha from f_all f, cfg
            where cfg.inc or f.fecha < (select max(fecha) from f_all)
            order by f.fecha desc limit (select n from cfg)),
  oc as (select gv_norm_prov_key(o.proveedor) pk, o.proveedor, norm_cod(o.codigo) cod, o.descripcion,
                o.fecha, o.id, coalesce(o.cantidad,0)::numeric cant, coalesce(o.cantidad_recibida,0)::numeric rec, o.estado
           from "Ordenes_Compra" o
          where o.rubro = 'Art Term' and o.fecha in (select fecha from f_ok)
            and nullif(btrim(o.codigo),'') is not null and lower(coalesce(o.estado,'')) <> 'cerrada'),
  w as (select oc.*, lag(oc.cant) over p prev_cant, lag(oc.rec) over p prev_rec,
               row_number() over (partition by pk, cod order by fecha desc, id desc) rn_desc
          from oc window p as (partition by pk, cod order by fecha, id)),
  x as (select w.*, case when prev_cant is null then cant
                         else greatest(0, cant - greatest(0, prev_cant - prev_rec)) end ped
          from w)
  select max(x.proveedor) filter (where x.rn_desc = 1), x.pk, x.cod,
         max(x.descripcion) filter (where x.rn_desc = 1),
         count(*)::int, sum(x.ped), sum(x.rec),
         case when sum(x.ped) > 0 then round(least(sum(x.rec) / sum(x.ped), 9.99), 4) end,
         min(x.fecha), max(x.fecha),
         max(x.fecha) filter (where x.rn_desc = 1), max(x.cant) filter (where x.rn_desc = 1)::int,
         max(x.rec) filter (where x.rn_desc = 1)::int, max(x.estado) filter (where x.rn_desc = 1)
    from x group by x.pk, x.cod;
$$;

create or replace function public.gv_ads_badge()
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from (
    select t.pkey from gv_ads_talleristas() t group by t.pkey
    having sum(t.pedido) > 0 and sum(t.entregado) / sum(t.pedido) < (gv_ads_config()->>'umbral')::numeric) z;
$$;

create or replace function public.gv_ads_stock()
returns table(cod text, cod_base text, linea text, descripcion text, terminado numeric, racks numeric,
              a_guardar numeric, disponible numeric, proy_mes numeric,
              comp10 numeric, comp20 numeric, comp30 numeric,
              saldo10 numeric, saldo20 numeric, saldo30 numeric, dias_cubre numeric,
              oc_fecha date, oc_prov text, oc_cant int, oc_rec int, oc_estado text)
language sql stable security definer set search_path = public as $$
  with hoy as (select (now() at time zone 'America/Argentina/Buenos_Aires')::date d),
  s as (select s.cod, s.cod_base, s.linea, s.descripcion,
               coalesce(s.terminado,0) term, coalesce(s.racks,0) + coalesce(s.racks_ch,0) rk,
               coalesce(s.a_guardar,0) ag, coalesce(s.proy_cajas_mes,0) proy
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
  select s.cod, s.cod_base, s.linea, s.descripcion, s.term, s.rk, s.ag, s.term + s.rk + s.ag, s.proy,
         coalesce(c.c10,0), coalesce(c.c20,0), coalesce(c.c30,0),
         round(s.term + s.rk + s.ag - coalesce(c.c10,0) - s.proy * 10 / 30.0, 1),
         round(s.term + s.rk + s.ag - coalesce(c.c20,0) - s.proy * 20 / 30.0, 1),
         round(s.term + s.rk + s.ag - coalesce(c.c30,0) - s.proy * 30 / 30.0, 1),
         case when s.proy > 0 then round(greatest(s.term + s.rk + s.ag - coalesce(c.c30,0), 0) / (s.proy / 30.0), 0) end,
         oc.fecha, oc.prov, oc.cant, oc.rec, oc.est
    from s left join c on c.cod = s.cod left join oc on oc.cod = s.cod
   where s.proy > 0 or coalesce(c.c30,0) > 0;
$$;

revoke all on function public.gv_ads_config_guardar(numeric,int,boolean) from public, anon;
grant execute on function public.gv_ads_config_guardar(numeric,int,boolean) to authenticated;
grant execute on function public.gv_ads_config(), public.gv_ads_talleristas(int,boolean),
  public.gv_ads_badge(), public.gv_ads_stock() to anon, authenticated;
