-- gv_geo_habituales — v14.22 (2026-09-07) · Virgilio (hrxfctzncixxqmpfhskv)
--
-- EL DUEÑO
-- ========
--     "Revisá solamente los que están en pedidos entregados, espero que tenés datos desde el
--      primero de enero de dos mil veintiséis en adelante. Cuáles te faltan: con eso son mis
--      clientes habituales. Puede pasar que entre un cliente nuevo o que alguien que no me haya
--      comprado me compre, pero la mayoría los vas a tener cubiertos dentro de ese rango."
--
-- Tenía el dato justo: `gv_ppp_entregados_meta` arranca el **2026-01-02** y llega al 02/09.
-- 2.719 entregas desde el 1º de enero, de **615 clientes** (527 de LK + 88 de Chef).
--
-- QUÉ CAMBIA
-- ==========
-- La cola del padrón se limita a esos clientes. Antes eran las 2.307 direcciones del padrón
-- entero, muchas de gente que no compra hace años.
--
--   cola:  1.055 (v14.20)  →  562 (v14.21, sólo AMBA)  →  **227** (acá)
--
-- **El cliente nuevo NO queda descubierto**, que es lo que el dueño preveía: el geocodificador
-- mira PRIMERO `gv_geo_faltantes`, que sale de la programación. Al que le entra un pedido se le
-- ubica la dirección esa misma corrida, sea habitual o no. Esta lista es sólo para adelantarse
-- a los que ya sabemos que van a comprar.
--
-- La empresa se deriva de la NP (`^9` = LK, resto Chef), el mismo criterio que usa Facturación:
-- los códigos de cliente de LK y Chef son independientes y el mismo número es otro cliente en
-- cada empresa.
--
-- COBERTURA MEDIDA de lo que de verdad importa (habituales + AMBA):
--   Chef   43 direcciones ·  36 ubicadas (83,7 %) ·  5 Retira ·   2 faltan
--   LK    446 direcciones · 161 ubicadas (36,1 %) · 59 Retira · 226 faltan
--
-- ROLLBACK: sacar el `join public.gv_clientes_habituales` de las dos vistas (quedan como en
-- `sql/gv_geo_solo_amba_v1421.sql`).

create or replace view public.gv_clientes_habituales
with (security_invoker = true) as
  select distinct btrim(e.cod) as cod,
         case when btrim(e.np) ~ '^9' then 'lk' else 'chef' end as empresa
    from public.gv_ppp_entregados_meta e
   where e.fecha_entrega >= '2026-01-01'
     and btrim(coalesce(e.cod,'')) <> '';

comment on view public.gv_clientes_habituales is
  'v14.22 — clientes con al menos una entrega desde el 01/01/2026. Es el universo que importa '
  'para geocodificar; al cliente nuevo lo cubre gv_geo_faltantes cuando se le programa el pedido.';

create or replace view public.gv_geo_faltantes_padron
with (security_invoker = true) as
  select 'PADRON'::text as fuente, d.cod, d.razon_social, d.direccion,
         d.barrio_entrega as barrio, d.zona_expreso as zona, d.dir_key,
         coalesce(x.direccion_ok, gv_dir_geo_query(d.direccion)) as dir_query,
         coalesce(x.barrio_ok, d.barrio_entrega) as barrio_geo,
         (x.dir_key is not null) as corregida, null::date as fecha_entrega,
         d.empresa, null::text as provincia, true as amba
    from public."GV_Clientes_Direcciones" d
    join public.gv_clientes_habituales h on h.cod = d.cod and h.empresa = d.empresa
    left join public."GV_Geo_Correccion" x on x.dir_key = d.dir_key
    left join public."GV_Geo_Cliente"    c on c.cod = d.cod and c.dir_key = d.dir_key
    left join public."PPP_Geo"           g on g.dir_key = d.dir_key and g.lat is not null
    left join public."GV_Geo_Fallidas"   f on f.cod = d.cod and f.dir_key = d.dir_key
   where coalesce(d.provincia,'') in ('CABA','Buenos Aires')
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
    join public.gv_clientes_habituales h on h.cod = d.cod and h.empresa = d.empresa
    cross join lateral (
      select (exists (select 1 from public."GV_Geo_Cliente" g
                       where g.cod = d.cod and g.dir_key = d.dir_key and g.lat is not null)
           or exists (select 1 from public."PPP_Geo" p
                       where p.dir_key = d.dir_key and p.lat is not null)) as ubicada,
             (lower(coalesce(d.zona_expreso,'')) like '%retira%')          as retira
    ) u
   where coalesce(d.provincia,'') in ('CABA','Buenos Aires')
   group by 1 order by 1;
