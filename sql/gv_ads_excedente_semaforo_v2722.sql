-- v27.22 (Luis, 06/10/2026, D2 «sí cuenta»): el EXCEDENTE entra en el disponible de ADS.
-- v27.23 (Luis, 06/10): sólo artículos con tallerista (filtro al final de gv_ads_stock2).
-- D3: badge del botón = violeta a la izquierda (talleristas, gv_ads_badge) + semáforo a la derecha
--     (gv_ads_badge_stock: quiebres a 10 rojo · 20 naranja · 30 amarillo).
-- Cambiar el tipo de retorno exige DROP, y el DROP se cuelga en el MCP: va como función NUEVA
-- gv_ads_stock2 (con excedente). gv_ads_stock (v27.21) queda sin llamador, de rollback.
-- Rollback: volver a correr el bloque gv_ads_stock de sql/gv_ads_alertas_damian_v2720.sql y
--   el front vuelve a gv_ads_stock.
create or replace function public.gv_ads_stock2()
returns table(cod text, cod_base text, linea text, descripcion text, terminado numeric, racks numeric,
              a_guardar numeric, excedente numeric, disponible numeric, proy_mes numeric,
              comp10 numeric, comp20 numeric, comp30 numeric,
              saldo10 numeric, saldo20 numeric, saldo30 numeric, dias_cubre numeric,
              oc_fecha date, oc_prov text, oc_cant int, oc_rec int, oc_estado text)
language sql stable security definer set search_path = public as $$
  with hoy as (select (now() at time zone 'America/Argentina/Buenos_Aires')::date d),
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
         round(s.term + s.rk + s.ag + s.ex - coalesce(c.c10,0) - s.proy * 10 / 30.0, 1),
         round(s.term + s.rk + s.ag + s.ex - coalesce(c.c20,0) - s.proy * 20 / 30.0, 1),
         round(s.term + s.rk + s.ag + s.ex - coalesce(c.c30,0) - s.proy * 30 / 30.0, 1),
         case when s.proy > 0 then round(greatest(s.term + s.rk + s.ag + s.ex - coalesce(c.c30,0), 0) / (s.proy / 30.0), 0) end,
         oc.fecha, oc.prov, oc.cant, oc.rec, oc.est
    from s left join c on c.cod = s.cod left join oc on oc.cod = s.cod
   where (s.proy > 0 or coalesce(c.c30,0) > 0)
     -- v27.23 (Luis, 06/10): sólo artículos con TALLERISTA (los importados que no tienen tallerista no van).
     -- Tallerista = proveedor activo en OC_Maximos (el que el generador le emite la OC). Un importado que
     -- igual se compra a un tallerista local (437E, 590E, 26…) SÍ entra: tiene OC.
     and exists (select 1 from "OC_Maximos" m
                  where coalesce(m.activo, true) and nullif(btrim(m.proveedor), '') is not null
                    and regexp_replace(norm_cod(m.cod), '\s+(LK|CH)$', '') = s.cod_base);
$$;


create or replace function public.gv_ads_badge_stock()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('q10', count(*) filter (where saldo10 < 0),
                            'q20', count(*) filter (where saldo20 < 0),
                            'q30', count(*) filter (where saldo30 < 0)) from gv_ads_stock2();
$$;
grant execute on function public.gv_ads_stock2(), public.gv_ads_badge_stock() to anon, authenticated;
