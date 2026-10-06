-- v27.28 (Luis, 06/10, D6): ADS «Entregado» = lo que RECIBIÓ VIRGILIO de ese proveedor y código
-- en el período de las OC evaluadas (Entregas Tallerista Virgilio + Entregas Prov AT), no lo
-- imputado a cada OC. Topado en lo pedido por artículo: el exceso de un código no compensa a otro.
-- Período = desde la 1.ª OC del ARTÍCULO en el rango (v27.31; antes la del rango) hasta la OC siguiente a la última (o hoy).
-- Proveedor: gv_prov_match + GV_OC_Fabrica_Para (Pedernera / Blistpack / Oscar → OC a Log/ Fabr).
-- Misma firma que la v27.20 (sin DROP). Rollback: la definición anterior está en
-- sql/gv_ads_alertas_damian_v2720.sql.
CREATE OR REPLACE FUNCTION public.gv_ads_talleristas(p_n integer DEFAULT NULL::integer, p_incluir_actual boolean DEFAULT NULL::boolean)
 RETURNS TABLE(proveedor text, pkey text, codigo text, descripcion text, ocs integer, pedido numeric, entregado numeric, pct numeric, desde date, hasta date, ult_fecha date, ult_cant integer, ult_rec integer, ult_estado text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with cfg as (select coalesce(p_n, (gv_ads_config()->>'n_ocs')::int) n,
                      coalesce(p_incluir_actual, (gv_ads_config()->>'incluir_actual')::boolean) inc),
  f_all as (select distinct o.fecha from "Ordenes_Compra" o where o.rubro = 'Art Term' and o.fecha is not null),
  f_ok as (select f.fecha from f_all f, cfg
            where cfg.inc or f.fecha < (select max(fecha) from f_all)
            order by f.fecha desc limit (select n from cfg)),
  -- v27.28-recibido: ventana de recepción del rango
  vent as (select min(fecha) d0,
                  coalesce((select min(a.fecha) from f_all a where a.fecha > (select max(fecha) from f_ok)),
                           current_date + 1) d1
             from f_ok),
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
          from w),
  art as (select max(x.proveedor) filter (where x.rn_desc = 1) proveedor, x.pk, x.cod,
                 max(x.descripcion) filter (where x.rn_desc = 1) descripcion,
                 count(*)::int ocs, sum(x.ped) ped,
                 min(x.fecha) desde, max(x.fecha) hasta,
                 max(x.fecha) filter (where x.rn_desc = 1) ult_fecha, max(x.cant) filter (where x.rn_desc = 1)::int ult_cant,
                 max(x.rec) filter (where x.rn_desc = 1)::int ult_rec, max(x.estado) filter (where x.rn_desc = 1) ult_estado,
                 regexp_replace(x.cod, '\s+(LK|CH)$', '') cod_b,
                 substring(x.cod from '\s(LK|CH)$') emp_oc,
                 gv_norm_prov_keys(max(x.proveedor))
                   || coalesce((select array_agg(gv_norm_prov_key(f.fabricante)) from "GV_OC_Fabrica_Para" f
                                 where gv_norm_prov_key(f.recibe_la_oc) = x.pk), '{}'::text[]) pkeys
            from x group by x.pk, x.cod),
  ent as (
    select regexp_replace(norm_cod("Cod"), '\s+(LK|CH)$', '') cod,
           nullif(upper(btrim(coalesce(gv_empresa, ''))), '') emp,
           gv_norm_prov_keys("Nombre_Tall") pk,
           coalesce("Fecha_RTO", case when "Fecha" ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then "Fecha"::date end) f,
           coalesce("Cajas",0)::numeric caj
      from "Entregas Tallerista Virgilio"
    union all
    select regexp_replace(norm_cod("Cod_Art"), '\s+(LK|CH)$', ''), null::text, gv_norm_prov_keys("Proveedor"),
           coalesce("Fecha_RTO", case
             when "Dia_mes" ~ '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{2}$' then to_date("Dia_mes",'DD/MM/YY')
             when "Dia_mes" ~ '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$' then to_date("Dia_mes",'DD/MM/YYYY')
             when "Dia_mes" ~ '^[0-9]{1,2}-[0-9]{1,2}$' then to_date("Dia_mes"||'-'||extract(year from current_date)::text,'DD-MM-YYYY')
           end),
           coalesce("Cantidad",0)::numeric
      from "Entregas Prov AT"),
  ent_v as (select e.* from ent e, vent v where e.f >= v.d0 and e.f < v.d1 and e.caj > 0),
  rec as (select a.pk, a.cod, coalesce(sum(e.caj),0) recibido
            from art a
            left join ent_v e on e.cod = a.cod_b and (a.emp_oc is null or e.emp is null or e.emp = a.emp_oc)
                             and e.f >= a.desde   -- v27.31: desde la 1.ª OC de ESE artículo, no del rango
                             and gv_prov_match(a.pkeys, e.pk)
           group by a.pk, a.cod)
  select a.proveedor, a.pk, a.cod, a.descripcion, a.ocs, a.ped,
         least(r.recibido, a.ped),
         case when a.ped > 0 then round(least(r.recibido, a.ped) / a.ped, 4) end,
         a.desde, a.hasta, a.ult_fecha, a.ult_cant, a.ult_rec, a.ult_estado
    from art a join rec r on r.pk = a.pk and r.cod = a.cod;
$function$;
