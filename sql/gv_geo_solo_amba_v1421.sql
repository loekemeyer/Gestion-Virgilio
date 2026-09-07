-- gv_geo_solo_amba — v14.21 (2026-09-07) · Virgilio (hrxfctzncixxqmpfhskv)
--
-- EL DUEÑO, DOS VECES
-- ===================
--     "no entrego en ninguno del interior"
--     "donde yo no entrego, no interesa que lo ubiques. Solamente me interesa que ubiques a
--      los de Capital Federal, o AMBA"
--
-- Se geocodifica **sólo al cliente de CABA / Buenos Aires**. El interior sale de la cola: no se
-- le gasta ni una llamada más a Nominatim.
--
-- Las filas del interior NO se borran de `GV_Clientes_Direcciones`: el dato no molesta, y si
-- alguna vez hiciera falta el punto del expreso, ya está el `barrio_entrega` de la v14.20 y basta
-- con sacar el filtro de acá.
--
-- EFECTO MEDIDO
--   cola:       1.055  →  562
--   cobertura de lo que importa (clientes AMBA, contando GV_Geo_Cliente + PPP_Geo):
--     Chef  337 direcciones · 303 ubicadas (89,9 %) · 17 Retira · 17 faltan
--     LK    917 direcciones · 240 ubicadas (26,2 %) · 130 Retira · 547 faltan
--
-- ROLLBACK: sacar el `where coalesce(d.provincia,'') in ('CABA','Buenos Aires')` de las dos
-- vistas (queda como estaba en `sql/gv_geo_barrio_entrega_v1420.sql`).

create or replace view public.gv_geo_faltantes_padron
with (security_invoker = true) as
  select 'PADRON'::text as fuente, d.cod, d.razon_social, d.direccion,
         d.barrio_entrega as barrio, d.zona_expreso as zona, d.dir_key,
         coalesce(x.direccion_ok, gv_dir_geo_query(d.direccion)) as dir_query,
         coalesce(x.barrio_ok, d.barrio_entrega) as barrio_geo,
         (x.dir_key is not null) as corregida, null::date as fecha_entrega,
         d.empresa, null::text as provincia, true as amba
    from public."GV_Clientes_Direcciones" d
    left join public."GV_Geo_Correccion" x on x.dir_key = d.dir_key
    left join public."GV_Geo_Cliente"    c on c.cod = d.cod and c.dir_key = d.dir_key
    left join public."PPP_Geo"           g on g.dir_key = d.dir_key and g.lat is not null
    left join public."GV_Geo_Fallidas"   f on f.cod = d.cod and f.dir_key = d.dir_key
   where coalesce(d.provincia,'') in ('CABA','Buenos Aires')   -- <- sólo AMBA
     and gv_dir_geo_query(d.direccion) is not null
     and coalesce(btrim(d.barrio_entrega),'') <> ''
     and c.cod is null and g.dir_key is null
     and coalesce(f.intentos,0) < 3
     and lower(coalesce(d.zona_expreso,'')) not like '%retira%'
   order by d.empresa, d.cod;

drop view if exists public.gv_geo_cobertura;
create view public.gv_geo_cobertura
with (security_invoker = true) as
  select d.empresa,
         count(*) as direcciones,
         count(*) filter (where u.ubicada)                     as ubicadas,
         count(*) filter (where not u.ubicada and u.retira)     as retira,
         count(*) filter (where not u.ubicada and not u.retira) as faltan,
         round(100.0 * count(*) filter (where u.ubicada) / nullif(count(*), 0), 1) as pct
    from public."GV_Clientes_Direcciones" d
    cross join lateral (
      select (exists (select 1 from public."GV_Geo_Cliente" g
                       where g.cod = d.cod and g.dir_key = d.dir_key and g.lat is not null)
           or exists (select 1 from public."PPP_Geo" p
                       where p.dir_key = d.dir_key and p.lat is not null)) as ubicada,
             (lower(coalesce(d.zona_expreso,'')) like '%retira%')          as retira
    ) u
   where coalesce(d.provincia,'') in ('CABA','Buenos Aires')
   group by 1 order by 1;
