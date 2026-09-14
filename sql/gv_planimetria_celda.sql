/* gv_planimetria_celda — v17.23 (pedido de Thomas, 2026-09-14: "quiero un módulo
   en la APP que muestre la planimetría … Góndola A / a5 502 Cap / a4 502 Cap …")

   UNA fila por (celda de góndola × código que va ahí). Es lo que dibuja el módulo
   🗺️ Mapa de góndolas: la góndola, la celda, el código y cuántas cajas entran.

   Por qué una vista y no armarlo en el front: la regla de "cuál máximo manda"
   es de negocio, no de pantalla. Hoy el mapa vive en GV_Lugar_Item y la capacidad
   en Capacidad_Sector (la migración quedó a medias: `GV_Lugar_Item.cajas_max` está
   en NULL en las 782 filas — problema 84). La vista resuelve el empate con
   COALESCE(item, capacidad) y DICE de dónde salió en `max_fuente`, así el día que
   se haga el backfill la pantalla no cambia una línea.

   Tres normalizaciones, las mismas que usa el resto del pipeline:
   · sector → letra + número (J9 y J09 son LA MISMA celda; había 9 filas de
     capacidad con la grafía sin cero, todas con el mismo código que su J0x).
   · código → `gv_cod_stock()` para cruzar (066 = 66, 505L = 505, "505 LK" = 505),
     pero se MUESTRA la grafía del mapa, que es la canónica.
   · sólo `tipo='gondola'` y `activo`. Los racks tienen su propia planimetría
     (`Racks_Planimetria`) y no entran acá.

   `estado` es el semáforo de la celda:
     libre           · nadie la reclama
     ok              · mapa y capacidad coinciden
     solo_mapa       · el artículo está mapeado pero no tiene capacidad cargada
     solo_capacidad  · hay capacidad cargada y el mapa no pone el artículo ahí
   Los dos últimos son la mitad abierta del problema 84, a la vista en la pantalla.

   Sólo lectura. No toca ninguna tabla compartida. */
drop view if exists public.gv_planimetria_celda;
create view public.gv_planimetria_celda
with (security_invoker = true) as
with lug as (
  select upper(btrim(l.sector))                                              as sector,
         substring(upper(btrim(l.sector)) from '^[A-ZÑ]+')                   as gondola,
         nullif(regexp_replace(upper(btrim(l.sector)), '^[A-ZÑ]+', ''), '')::int as celda,
         l.empresa, l.orden, l.uso
    from public."GV_Lugar" l
   where l.activo and l.tipo = 'gondola'
), itm as (
  select substring(upper(btrim(sector)) from '^[A-ZÑ]+')                     as g,
         nullif(regexp_replace(upper(btrim(sector)), '^[A-ZÑ]+', ''), '')::int as n,
         gv_cod_stock(cod) as k, min(cod) as cod, min(clase) as clase, max(cajas_max) as cajas_max
    from public."GV_Lugar_Item"
   where activo
   group by 1, 2, 3
), cap as (
  select substring(upper(btrim(sector)) from '^[A-ZÑ]+')                     as g,
         nullif(regexp_replace(upper(btrim(sector)), '^[A-ZÑ]+', ''), '')::int as n,
         gv_cod_stock(cod) as k, min(cod) as cod, max(cajas_max) as cajas_max
    from public."Capacidad_Sector"
   where cod !~* '^\s*libre\s*$'
   group by 1, 2, 3
), par as (
  select g, n, k from itm
  union
  select g, n, k from cap
), nom as (
  select gv_cod_stock(cod) as k, min(descripcion) as descripcion
    from public.vista_nombres_articulos
   where descripcion is not null and btrim(descripcion) <> ''
   group by 1
)
select l.sector,
       l.gondola,
       l.celda,
       l.empresa,
       l.orden,
       l.uso,
       coalesce(i.cod, c.cod)                       as cod,
       p.k                                          as cod_stock,
       n.descripcion,
       coalesce(i.clase, 'articulo')                as clase,
       coalesce(i.cajas_max, c.cajas_max)           as cajas_max,
       case when i.cajas_max is not null then 'item'
            when c.cajas_max is not null then 'capacidad' end as max_fuente,
       case when p.k is null                        then 'libre'
            when i.k is null                        then 'solo_capacidad'
            when c.k is null                        then 'solo_mapa'
            else 'ok' end                           as estado
  from lug l
  left join par p on p.g = l.gondola and p.n = l.celda
  left join itm i on i.g = p.g and i.n = p.n and i.k = p.k
  left join cap c on c.g = p.g and c.n = p.n and c.k = p.k
  left join nom n on n.k = p.k;

comment on view public.gv_planimetria_celda is
  'Planimetría de góndola dibujable: una fila por celda × código, con la capacidad resuelta (item → capacidad) y el estado de la celda. v17.23.';

grant select on public.gv_planimetria_celda to anon, authenticated;
