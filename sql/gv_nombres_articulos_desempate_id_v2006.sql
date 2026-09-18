-- v20.06 (2026-09-18) — El 055 se llamaba "Pinza De Ensalada", igual que el 054
--
-- Cola de la v20.05: con el guard arreglado, el 055 pasó a mostrar "Pinza De Ensalada Mgo Pla X 12"
-- — el nombre del 054. `Articulos Virgilio X Tallerista` tiene DOS filas por código (una por
-- tallerista) y las de Rafael están cruzadas:
--
--   cod | Log/ Fabr (id viejo)                        | Rafael (id nuevo)              | OC_Maximos
--   ----+---------------------------------------------+--------------------------------+---------------------
--   053 | Pinza De Fiambre Inox Cachas Plásticas 23cm | Pinza De Fiambre Mgo Plast X12 | Pinza De Fiambre X 12
--   054 | Pinza De Ensalada Inox Cachas Plásticas 23cm| Pinza De FIDEOS Mgo Plast X 12 | Pinza De Ensaladas X 12
--   055 | Pinza De Fideos Inox Cachas Plásticas 25cm  | Pinza De ENSALADA Mgo Pla X 12 | Pinza De Fideos X 12
--
-- La CTE desempataba con `order by k, descripcion` — o sea **alfabético**, que no significa nada —
-- y para el 055 eso elegía justo la fila cruzada. Ahora desempata por **`id`**: la fila más vieja,
-- que es la que coincide con OC_Maximos.
--
-- Medido: 20 códigos tienen más de una descripción en esa tabla y **8 cambian de nombre**. Cuatro
-- mejoran claro (055 Fideos, 564 "C Pizza 8 LK" → "Corta Pizza Gastronomico", 609 "Pisa Papa" →
-- "Pisa Papas Acero Inox", 558 sin el "(GRJ5)" pegado), tres son la misma palabra con otra
-- capitalización y uno (GRJ10 arandela/resorte) es indistinto.
--
-- ⚠ Las otras dos fuentes (`proyeccion_madre`, `OC_Maximos`) tienen **0** códigos con más de una
-- descripción, así que su `order by` no desempata nada y se dejan como están.
--
-- ⚠ NO se toca el dato: las filas cruzadas de Rafael siguen en `Articulos Virgilio X Tallerista`.
-- Corregirlas es decisión del dueño (y son datos de otra pantalla).
--
-- Incluye todo lo de la v20.05 (guard normalizado en las 4 CTE + fallback base_L).
-- Rollback: `order by 1, 2` en norm_vxt.

create or replace view public.vista_nombres_articulos as
with norm_pm as (
  select distinct on (upper(regexp_replace(coalesce(btrim(p.cod), ''), '^0+(.)', '\1')))
         upper(regexp_replace(coalesce(btrim(p.cod), ''), '^0+(.)', '\1')) as k,
         nullif(btrim(p.gv_descripcion), '') as d
    from public.proyeccion_madre p
   where nullif(btrim(coalesce(p.gv_descripcion, '')), '') is not null
     and regexp_replace(upper(btrim(coalesce(p.gv_descripcion, ''))), '^0+(.)', '\1')
         <> upper(regexp_replace(coalesce(btrim(p.cod), ''), '^0+(.)', '\1'))
   order by 1, 2
), norm_vxt as (
  select distinct on (upper(regexp_replace(coalesce(btrim(a."Cod_Art"::text), ''), '^0+(.)', '\1')))
         upper(regexp_replace(coalesce(btrim(a."Cod_Art"::text), ''), '^0+(.)', '\1')) as k,
         nullif(btrim(a."Desc"), '') as d, a.id
    from public."Articulos Virgilio X Tallerista" a
   where nullif(btrim(coalesce(a."Desc", '')), '') is not null
     and regexp_replace(upper(btrim(coalesce(a."Desc", ''))), '^0+(.)', '\1')
         <> upper(regexp_replace(coalesce(btrim(a."Cod_Art"::text), ''), '^0+(.)', '\1'))
   order by 1, a.id
), norm_oc as (
  select distinct on (upper(regexp_replace(coalesce(btrim(o.cod), ''), '^0+(.)', '\1')))
         upper(regexp_replace(coalesce(btrim(o.cod), ''), '^0+(.)', '\1')) as k,
         nullif(btrim(o.descripcion), '') as d
    from public."OC_Maximos" o
   where o.activo = true
     and nullif(btrim(coalesce(o.descripcion, '')), '') is not null
     and regexp_replace(upper(btrim(coalesce(o.descripcion, ''))), '^0+(.)', '\1')
         <> upper(regexp_replace(coalesce(btrim(o.cod), ''), '^0+(.)', '\1'))
   order by 1, 2
), norm_hist as (
  select h.cod as k, h.descripcion as d
    from public."GV_Articulo_Nombre_Historico" h
   where regexp_replace(upper(btrim(coalesce(h.descripcion, ''))), '^0+(.)', '\1')
         <> upper(regexp_replace(btrim(coalesce(h.cod, '')), '^0+(.)', '\1'))
), keys_l as (
  -- las claves que terminan en L entran SIEMPRE, aunque su descripción sea basura y las CTE de
  -- arriba las hayan filtrado: si no, no llegan al fallback `base_L` de abajo y quedan sin nombre.
  select upper(regexp_replace(coalesce(btrim(p.cod), ''), '^0+(.)', '\1')) as k
    from public.proyeccion_madre p
   where upper(btrim(coalesce(p.cod, ''))) like '%L'
), keys as (
  select k from norm_pm union select k from norm_vxt union select k from norm_oc
  union select k from norm_hist union select k from keys_l
), resuelto as (
  select kk.k,
         coalesce(pm.d, v.d, o.d, h.d) as d,
         case when pm.d is not null then 'proyeccion_madre'
              when v.d  is not null then 'virgilio_x_tall'
              when o.d  is not null then 'excel'
              else 'historico' end as fuente
    from keys kk
    left join norm_pm   pm on pm.k = kk.k
    left join norm_vxt  v  on v.k  = kk.k
    left join norm_oc   o  on o.k  = kk.k
    left join norm_hist h  on h.k  = kk.k
   where kk.k <> ''
)
select r.k as cod, r.d as descripcion, r.fuente
  from resuelto r
 where r.d is not null
union all
-- un código terminado en L es el artículo de Loekemeyer vendido por Chef (regla v13.71): si no
-- tiene nombre propio, hereda el del base. Nunca pisa un nombre propio (sólo entra con r.d null).
select r.k, b.d, 'base_L'
  from resuelto r
  join resuelto b on b.k = left(r.k, length(r.k) - 1) and b.d is not null
 where r.d is null and r.k like '%L' and length(r.k) > 1;

alter view public.vista_nombres_articulos set (security_invoker = true);
