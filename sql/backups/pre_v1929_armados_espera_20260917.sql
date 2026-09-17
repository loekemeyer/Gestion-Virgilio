-- BACKUP previo a la v19.29 («Armados en espera») — 2026-09-17.
-- Ejecutar ESTE archivo entero deja los tres objetos como estaban antes del cambio.
-- Después de restaurar, borrar la marca si quedó alguna:
--   delete from public."GV_PPP_Armados_Espera" where true;   -- las NP vuelven a su fecha:
--   ⚠ OJO: una tanda que se dejó en espera tiene la fecha en NULL (web). Restaurar estos objetos
--   NO le devuelve la fecha: hay que reprogramarla con gv_ppp_tanda_mover (o desde la app).
--   Qué estaba parado: select * from public."GV_PPP_Armados_Espera";

-- ── 1) el espejo de ISIS, sin la rama de espera ────────────────────────────────────────────
create or replace view public.gv_ppp_programacion_diaria as
 with multi as (
         select regexp_replace(btrim(g.cod), '\.0+$'::text, ''::text) as cod
           from public."GV_PPP_Programacion_Diaria" g
          where coalesce(btrim(g.razon_social), ''::text) <> ''::text
          group by (regexp_replace(btrim(g.cod), '\.0+$'::text, ''::text))
         having count(distinct lower(btrim(g.razon_social))) > 1
        )
 select p.id,
    p.np,
        case
            when coalesce(o.desprogramada, false) then ''::text
            else coalesce(nullif(btrim(o.tanda), ''::text), p.tanda)
        end as tanda,
    p.tipo,
    p.fecha_recep,
    coalesce(nullif(btrim(o.cod), ''::text), p.cod) as cod,
    coalesce(nullif(btrim(o.razon_social), ''::text),
        case
            when m.cod is not null then nullif(btrim(p.razon_social), ''::text)
            else null::text
        end, rs.razon_social, p.razon_social) as razon_social,
    coalesce(o.m3, p.m3) as m3,
    p.v,
    coalesce(nullif(btrim(o.direccion), ''::text), p.direccion) as direccion,
    coalesce(nullif(btrim(o.barrio), ''::text), p.barrio) as barrio,
    p.op,
        case
            when coalesce(o.desprogramada, false) then ''::text
            else coalesce(o.fecha_entrega::text || ' 00:00:00'::text, p.fecha_entrega)
        end as fecha_entrega,
    p.fecha_fc,
    coalesce(nullif(btrim(o.zona), ''::text), p.zona) as zona,
    p.observaciones
   from public."GV_PPP_Programacion_Diaria" p
     cross join public.gv_espejo_corte() c(lk, chef)
     left join public."GV_PPP_Prog_Override" o on o.np = regexp_replace(p.np, '\.0+$'::text, ''::text)
     left join public."GV_Cliente_Razon_Social" rs on rs.cod = regexp_replace(btrim(coalesce(nullif(btrim(o.cod), ''::text), p.cod)), '\.0+$'::text, ''::text) and rs.empresa = public.gv_empresa_de_np_texto(p.np)
     left join multi m on m.cod = regexp_replace(btrim(coalesce(nullif(btrim(o.cod), ''::text), p.cod)), '\.0+$'::text, ''::text)
  where public.gv_espejo_np_pasa(p.np, c.lk, c.chef) and not coalesce(o.oculto, false);

alter view public.gv_ppp_programacion_diaria set (security_invoker = true);

-- ── 2) y 3) el árbol y el mover, versión v19.11 ────────────────────────────────────────────
-- Están en git: `git show 6447dfd:sql/` no los tiene sueltos, así que la fuente es la base.
-- Para recuperarlos tal cual estaban:
--   select pg_get_functiondef('public.gv_ppp_prog_arbol(date,date)'::regprocedure);
--   select pg_get_functiondef('public.gv_ppp_tanda_mover(text,date,text,boolean)'::regprocedure);
-- Las diferencias que introdujo la v19.29, y que hay que deshacer a mano si se vuelve atrás:
--   · gv_ppp_prog_arbol: CTE `esp`, el `or exists(...)` de la rama ISIS, `en_espera` en `uni`,
--     y el CTE `dia` con `fe_dia`. Sacando esas cuatro cosas queda la v19.11.
--   · gv_ppp_tanda_mover: el guard de `p_fecha = gv_ppp_espera_fecha()` y el `delete from
--     "GV_PPP_Armados_Espera"`. Sacando esas dos queda la v19.11.
--   · gv_ppp_tanda_espera y GV_PPP_Armados_Espera son NUEVOS: se pueden dropear enteros.
--     drop function if exists public.gv_ppp_tanda_espera(text, text, text);
--     drop table if exists public."GV_PPP_Armados_Espera";
--     drop function if exists public.gv_ppp_espera_fecha();
