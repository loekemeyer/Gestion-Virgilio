-- v13.16 · 2026-09-05 (sábado a la noche) · hallazgo #1 del agente guardian-stock.
-- Aplicado en Virgilio (hrxfctzncixxqmpfhskv) dentro de la migración
-- `gv_gate_supervisor_y_facturado_web_v1316` (parte B). Detalle en docs/SUPABASE-GESTION-VIRGILIO.md §3.ac.
--
-- Problema: la ETAPA 3 del cron de Producción `reconciliar_pipeline_stock()` (jobid 68, cada 10 min)
-- drena `a_facturar` (movimiento `facturado`) sólo para tandas que existan en PPP_Entregados_Meta /
-- PPP_Programacion_Diaria (espejo de ISIS). Una tanda WEB (E01A, F02B…) nunca está ahí → si el
-- navegador del supervisor no llegaba a mandar el movimiento al bajar el Excel ISIS, el stock
-- quedaba "separado" para siempre en `a_facturar`.
--
-- Solución: objeto NUEVO (no se toca la función de Producción). Misma lógica y mismo guard
-- anti-doble; `tandanp` sale de PPP_Web_Programacion + gv_ppp_web_np_label; sólo drena cuando
-- TODAS las NP de la tanda están en Facturacion_NP. El índice mov_stock_pipeline_dedup evita repes.

create or replace function public.gv_reconciliar_facturado_web()
returns text
language plpgsql security definer set search_path = public, pg_temp
as $function$
declare n3 int := 0;
begin
  with src as (
    select case when tipo = 'separado' then upper(trim(ref))
                else upper(trim(split_part(ref, '|', 1))) end as tanda,
           cod_art as art, coalesce(empresa, 'Mixto') as empresa, sum(delta) as net
      from public."Movimientos_Stock"
     where deposito = 'a_facturar' and tipo in ('separado', 'facturado')
     group by 1, 2, 3
  ),
  tandanp as (
    select upper(btrim(w.tanda)) as tanda,
           upper(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx)) as np
      from public."PPP_Web_Programacion" w
     where coalesce(nullif(btrim(w.tanda), ''), '') <> '' and w.np is not null
  )
  insert into public."Movimientos_Stock" (cod_art, deposito, delta, tipo, ref, legajo, empresa)
  select s.art, 'a_facturar', -s.net, 'facturado', s.tanda, 'pipeline', s.empresa
    from src s
   where s.net > 0
     and exists (select 1 from tandanp pp where pp.tanda = s.tanda)
     and not exists (select 1 from public."Movimientos_Stock" m
                      where m.tipo = 'facturado' and m.deposito = 'a_facturar'
                        and (upper(trim(m.ref)) = s.tanda or upper(trim(split_part(m.ref, '|', 1))) = s.tanda))
     and not exists (select 1 from tandanp pp
                      where pp.tanda = s.tanda
                        and not exists (select 1 from public."Facturacion_NP" f where upper(trim(f.np)) = pp.np))
  on conflict do nothing;
  get diagnostics n3 = row_count;
  return format('ok facturado_web=%s', n3);
exception when others then
  return 'error: ' || sqlerrm;
end $function$;
revoke all on function public.gv_reconciliar_facturado_web() from public, anon, authenticated;

-- Cron propio (jobid 74), desfasado 5 min del de Producción (jobid 68 corre en */10).
select cron.schedule('gv-reconciliar-facturado-web', '5-55/10 * * * *', $$select public.gv_reconciliar_facturado_web();$$);

-- Prueba (no escribe si no hay nada que drenar):
--   select public.gv_reconciliar_facturado_web();   -- 'ok facturado_web=0'
-- Rollback:
--   select cron.unschedule('gv-reconciliar-facturado-web');
--   drop function public.gv_reconciliar_facturado_web();
