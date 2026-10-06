-- v27.30 (Luis, 06/10, D10): pestaña Stock de ADS — la última OC lleva además lo RECIBIDO POR VIRGILIO
-- desde la fecha de esa OC (talleristas + prov AT, del proveedor de la OC o su fabricante de
-- GV_OC_Fabrica_Para), no sólo lo imputado. gv_ads_stock3 = gv_ads_stock2 + oc_rec_v (columna nueva
-- al final; sin DROP de la 2, que queda de rollback).
CREATE OR REPLACE FUNCTION public.gv_ads_stock3()
 RETURNS TABLE(cod text, cod_base text, linea text, descripcion text, terminado numeric, racks numeric, a_guardar numeric, excedente numeric, disponible numeric, proy_mes numeric, comp10 numeric, comp20 numeric, comp30 numeric, saldo10 numeric, saldo20 numeric, saldo30 numeric, dias_cubre numeric, oc_fecha date, oc_prov text, oc_cant integer, oc_rec integer, oc_estado text, oc_rec_v integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with st as (select * from public.gv_ads_stock2()),
  ocp as (select st.cod, st.oc_fecha,
                 regexp_replace(st.cod, '\s+(LK|CH)$', '') cod_b, substring(st.cod from '\s(LK|CH)$') emp,
                 (select array_agg(distinct k) from (
                    select unnest(gv_norm_prov_keys(o.proveedor)) k
                      from "Ordenes_Compra" o
                     where norm_cod(o.codigo) = st.cod and o.fecha = st.oc_fecha and o.rubro = 'Art Term'
                    union
                    select gv_norm_prov_key(f.fabricante)
                      from "Ordenes_Compra" o join "GV_OC_Fabrica_Para" f on gv_norm_prov_key(f.recibe_la_oc) = gv_norm_prov_key(o.proveedor)
                     where norm_cod(o.codigo) = st.cod and o.fecha = st.oc_fecha and o.rubro = 'Art Term') z) pkeys
            from st where st.oc_fecha is not null),
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
  rv as (select p.cod, coalesce(sum(e.caj),0)::int rec_v
           from ocp p left join ent e on e.cod = p.cod_b and (p.emp is null or e.emp is null or e.emp = p.emp)
                                     and e.f >= p.oc_fecha and e.caj > 0 and gv_prov_match(p.pkeys, e.pk)
          group by p.cod)
  select st.*, rv.rec_v from st left join rv on rv.cod = st.cod;
$function$;
grant execute on function public.gv_ads_stock3() to anon, authenticated;
