-- gv_tanda_empresa_guard — una tanda NO mezcla empresas LK/CH
-- Luis, 2026-10-01 (problema 664, caso F21C). Shipped con app v25.81.
--
-- POR QUÉ: F21C quedó con 8 NPs de LK + 2 de Chef (todas Zona 1 - CABA Sur, 05/10).
-- El armador nunca mezcla empresas (corre por empresa) y la fusión automática filtra por
-- empresa, así que la mezcla la armó una persona desde el panel (tanda renombrada; fusión
-- manual de una tanda de Chef dentro de la de LK). No saltó ninguna alarma porque los 4
-- centinelas de tanda cortan por CAMIÓN, no por empresa: como ambas empresas son Zona 1 =
-- camión Capital Sur, la mezcla de empresas pasaba invisible. No existía guard ni centinela
-- de "tanda mezcla LK/CH".
--
-- QUÉ HACE: un guard reusable (gv_ppp_tanda_empresa_guard) que frena cualquier asignación
-- manual que dejaría una tanda con las dos empresas, llamado desde los 4 RPC que asignan
-- NP -> tanda a mano, + un centinela (gv_ppp_tanda_empresa_mezclada) que lista las tandas
-- ya mezcladas. El armador NO se toca (nunca produce la mezcla, así que el guard nunca le
-- salta). F21C queda como está (Luis: "dejala, no la toques") y el centinela la muestra.
--
-- ROLLBACK:
--   drop view if exists public.gv_ppp_tanda_empresa_mezclada;
--   -- y sacar la llamada 'gv_ppp_tanda_empresa_guard' de los 4 RPC (pg_get_functiondef + quitar la línea),
--   -- y borrar sus 4 filas de GV_Reglas_Centinela.
--   drop function if exists public.gv_ppp_tanda_empresa_guard(text, text[]);

-- 1) El guard
create or replace function public.gv_ppp_tanda_empresa_guard(p_tanda text, p_emps_nuevas text[])
returns void language plpgsql security definer set search_path to 'public','pg_temp' as $fn$
declare v_t text := upper(btrim(coalesce(p_tanda,''))); v_n int; v_lista text;
begin
  -- v25.74 (Luis, 01/10, problema 664): una tanda no lleva LK y CH juntas.
  if v_t = '' then return; end if;
  with dst as (
    select distinct lower(btrim(w.empresa)) emp from public."PPP_Web_Programacion" w
     where upper(btrim(w.tanda)) = v_t and coalesce(btrim(w.empresa),'') <> ''
  ),
  inc as (
    select distinct lower(btrim(e)) emp from unnest(coalesce(p_emps_nuevas,'{}'::text[])) e
     where coalesce(btrim(e),'') <> ''
  ),
  u as (select emp from dst union select emp from inc)
  select count(*), string_agg(emp,'+' order by emp) into v_n, v_lista from u;
  if coalesce(v_n,0) > 1 then
    raise exception 'EMPRESA_MEZCLA: la tanda % mezclaria empresas (%). Una tanda no puede llevar LK y CH juntas.', v_t, v_lista
      using errcode = 'P0001';
  end if;
end $fn$;

-- 2) El centinela
create or replace view public.gv_ppp_tanda_empresa_mezclada as
select upper(btrim(w.tanda)) tanda,
       string_agg(distinct lower(btrim(w.empresa)), '+' order by lower(btrim(w.empresa))) empresas,
       count(distinct lower(btrim(w.empresa))) n_empresas,
       count(*) nps,
       min(w.fecha_entrega) fecha,
       string_agg(distinct w.zona, ' | ' order by w.zona) zonas
from public."PPP_Web_Programacion" w
where coalesce(btrim(w.tanda),'') <> '' and coalesce(btrim(w.empresa),'') <> ''
group by upper(btrim(w.tanda))
having count(distinct lower(btrim(w.empresa))) > 1;

alter view public.gv_ppp_tanda_empresa_mezclada set (security_invoker = true);

-- 3) Las 4 llamadas al guard (aplicadas por pg_get_functiondef + replace, idempotentes):
--    gv_ppp_nps_mover_a        -> perform ...guard(v_t, empresas de las NP que se mueven)   [fusión / cambiar de día]
--    gv_ppp_web_tanda_programar-> perform ...guard(p_codigo, array[p_empresa])              [programar a mano]
--    gv_ppp_web_tanda_reusar   -> perform ...guard(r.tanda, array[v_emp]) por tanda previa  [reusar código]
--    gv_ppp_tanda_renombrar    -> perform ...guard(v_b, empresas de la tanda vieja)         [renombre / fusión de bajo nivel]
--    Cada uno con su fila en GV_Reglas_Centinela (patrón 'gv_ppp_tanda_empresa_guard').

-- CHEQUEO:
--   select * from public.gv_ppp_tanda_empresa_mezclada;   -- al 01/10: sólo F21C (chef+lk), que se deja a propósito
--   select * from public.gv_reglas_perdidas;              -- vacía = los 4 guards siguen puestos
