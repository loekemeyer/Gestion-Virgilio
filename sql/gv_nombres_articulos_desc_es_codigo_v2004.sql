-- v20.04 (2026-09-18) — La descripción del 043 era "043"
--
-- Thomas, 18/09: "la descripción del 043 y esos otros códigos no debería ser 043, algo se rompió ahí".
--
-- `vista_nombres_articulos` YA tenía el guard "la descripción no puede ser el propio código", en
-- las tres fuentes que arma por CTE. El guard comparaba así:
--
--     upper(btrim(descripcion)) <> upper(regexp_replace(cod, '^0+(.)', '\1'))
--                ^ cruda                              ^ normalizada, SIN el cero adelante
--
-- o sea: la descripción cruda contra el código SIN ceros. Cuando la basura viene escrita CON el
-- cero —"043" en el código 043— las dos puntas no coinciden ("043" <> "43"), el guard la deja
-- pasar y el código termina siendo su propio nombre. El guard existía y no servía justo para el
-- caso que más aparece.
--
-- Medido el 18/09: 18 de las 616 filas de la vista. Las 18 salen de `proyeccion_madre.gv_descripcion`,
-- que es la fuente de MÁS prioridad, así que tapaba nombres buenos que ya estaban en las otras dos:
--
--   cod | lo que mostraba | lo que hay en Articulos Virgilio X Tallerista / OC_Maximos
--   ----+-----------------+----------------------------------------------------------
--   043 | 043             | Abrelatas Uña 3 En 1
--   052 | 052             | Cepillo Lavavajilla
--   053 | 053             | Pinza De Fiambre Inox Cachas Plásticas 23cm
--   054 | 054             | Pinza De Ensalada Inox Cachas Plásticas 23cm
--   055 | 055             | Pinza De Fideos Inox Cachas Plásticas 25cm
--   097 | 097             | Afila Cuchillos Base Blanca/Verde
--   099 | 099             | Pelapapas Mgo Plástico Ergonómico
--
-- Los otros 11 son los códigos con L (026L, 027L, 031L, 035EL, 058L…) y un "000E": ésos no tienen
-- nombre en NINGUNA fuente. Por eso el segundo cambio, abajo.
--
-- ⚠ No se toca el dato de `proyeccion_madre`: el guard de la vista existe exactamente para ignorar
-- una descripción basura, y arreglar 18 filas a mano no evita la número 19.
--
-- CAMBIO 1 — el guard compara las dos puntas NORMALIZADAS (sin el cero adelante), en las 4 CTE.
-- CAMBIO 2 — fallback `base_L`: un código que termina en L es el mismo artículo de Loekemeyer
--   vendido por Chef (regla del dueño v13.71: 505 → 505L), así que si no tiene nombre propio hereda
--   el del código base. 10 de los 11 códigos L quedan con nombre; el "000E" queda sin descripción,
--   que es lo correcto — antes decía "000E" y parecía un nombre.
--
-- Rollback: volver a aplicar la definición anterior (git show HEAD~1 de este archivo no existe: la
-- versión previa quedó sólo en la base, guardada acá abajo como comentario en el commit v20.04).

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
         nullif(btrim(a."Desc"), '') as d
    from public."Articulos Virgilio X Tallerista" a
   where nullif(btrim(coalesce(a."Desc", '')), '') is not null
     and regexp_replace(upper(btrim(coalesce(a."Desc", ''))), '^0+(.)', '\1')
         <> upper(regexp_replace(coalesce(btrim(a."Cod_Art"::text), ''), '^0+(.)', '\1'))
   order by 1, 2
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
