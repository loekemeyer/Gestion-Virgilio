-- v26.13 — Reportes de gerencia (Luis, 02/10/2026): "se sigue mandando a las 8 con lo que haya y se avisa de lo
-- cobrado el último plazo completo".
--
-- El reporte de LK necesita saber CUÁNDO se subió cada cuenta de la conciliación: un día está completo cuando las
-- cuatro cuentas tienen una carga posterior a ese día (el extracto de ayer se sube hoy a la mañana). Lo dice
-- "GV_Conc_Cargas" (una fila por subida de la macro), que lk_ppp_reader no puede leer. Mismo patrón que la v26.11:
-- función SECURITY DEFINER con lo justo (banco, empresa, cuándo) + vista security_invoker, sólo para lk_ppp_reader.
--
-- Medido el 02/10: las subidas caen entre las 06:52 y las 09:49. El 02/10 las cuatro cuentas subieron después de las
-- 08:00, así que el diario de ese día no tenía ningún día nuevo completo (el 01/10 va en el del 03/10).

-- 1) las subidas (120 días alcanzan: el reporte mira la última antes del envío y la del reporte anterior)
create or replace function public.gv_rep_gerencia_conc_cargas_fn()
returns table(banco text, empresa text, cargado_en timestamptz)
language sql stable security definer set search_path = public, pg_temp as $$
  select split_part(k.banco, '_', 1),
         case split_part(k.banco, '_', 2) when 'ch' then 'chef' else split_part(k.banco, '_', 2) end,
         k.cargado_en
    from public."GV_Conc_Cargas" k where k.cargado_en >= now() - interval '120 days'
$$;
revoke execute on function public.gv_rep_gerencia_conc_cargas_fn() from public, anon, authenticated;
grant execute on function public.gv_rep_gerencia_conc_cargas_fn() to lk_ppp_reader;
create or replace view public.gv_rep_gerencia_conc_cargas with (security_invoker = true) as
  select * from public.gv_rep_gerencia_conc_cargas_fn();
revoke all on public.gv_rep_gerencia_conc_cargas from anon, authenticated;
grant select on public.gv_rep_gerencia_conc_cargas to lk_ppp_reader;

-- 2) la vista de la v26.11 suma "ultima_carga" al final. Función nueva (cambia el tipo de retorno: un DROP de la
--    vieja no entra por el MCP). gv_rep_gerencia_conc_al_fn() queda sin uso, de rollback.
create or replace function public.gv_rep_gerencia_conc_estado_fn()
returns table(banco text, empresa text, conciliado_al date, ultima_carga timestamptz)
language sql stable security definer set search_path = public, pg_temp as $$
  with c as (
    select split_part(k.banco, '_', 1) banco,
           case split_part(k.banco, '_', 2) when 'ch' then 'chef' else split_part(k.banco, '_', 2) end empresa,
           max(k.cargado_en) ultima_carga
      from public."GV_Conc_Cargas" k group by 1, 2)
  select coalesce(l.banco, c.banco), coalesce(l.empresa, c.empresa), l.conciliado_al, c.ultima_carga
    from public.gv_conc_linea l full join c on c.banco = l.banco and c.empresa = l.empresa
$$;
revoke execute on function public.gv_rep_gerencia_conc_estado_fn() from public, anon, authenticated;
grant execute on function public.gv_rep_gerencia_conc_estado_fn() to lk_ppp_reader;
create or replace view public.gv_rep_gerencia_conc_al with (security_invoker = true) as
  select banco, empresa, conciliado_al, ultima_carga from public.gv_rep_gerencia_conc_estado_fn();
revoke all on public.gv_rep_gerencia_conc_al from anon, authenticated;
grant select on public.gv_rep_gerencia_conc_al to lk_ppp_reader;

-- En LK (FDW): alter foreign table virgilio.gv_rep_gerencia_conc_al add column if not exists ultima_carga timestamptz;
--              import foreign schema public limit to (gv_rep_gerencia_conc_cargas) from server virgilio_db into virgilio;
--
-- Chequeo:
--   select * from public.gv_rep_gerencia_conc_al;                      -- 4 cuentas, con conciliado_al y ultima_carga
--   select banco, empresa, max(cargado_en) from public.gv_rep_gerencia_conc_cargas group by 1, 2;
--
-- Rollback:
--   create or replace view public.gv_rep_gerencia_conc_al with (security_invoker = true) as
--     select * from public.gv_rep_gerencia_conc_al_fn();   -- ojo: no se puede sacar una columna con create or replace
--   drop view if exists public.gv_rep_gerencia_conc_cargas;
--   drop function if exists public.gv_rep_gerencia_conc_cargas_fn(), public.gv_rep_gerencia_conc_estado_fn();
