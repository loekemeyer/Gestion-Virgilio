-- =====================================================================
-- picking_sin_base_telegram.sql — Alerta cuando hay NPs en programación
-- sin artículos en PPP_Base_Pedidos.
--
-- ✅ APLICADO 2026-08-28 (migración notificar_picking_sin_base_cron).
-- Cron: cada 30 minutos (*/30 * * * *), jobname picking-sin-base-check.
-- Dedup por tanda+día → una alerta por tanda por día.
-- Usa tg_enqueue → telegram_outbox → grupo Faltantes (-1004379879565).
-- =====================================================================

create or replace function public.notificar_picking_sin_base()
returns void language plpgsql security definer
set search_path = public, pg_temp
as $fn$
declare
  hoy   date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
  r     record;
  msg   text;
  dedup text;
begin
  -- NPs en programación (próximos 7 días) sin filas en la base de pedidos.
  for r in
    select
      pd.tanda,
      string_agg(pd.np, ', ' order by pd.np) as nps,
      count(*)::int                           as cant,
      left(min(pd.fecha_entrega::text), 10)   as entrega
    from "PPP_Programacion_Diaria" pd
    where left(pd.fecha_entrega::text, 10) between hoy::text and (hoy + 7)::text
      and not exists (
        select 1 from "PPP_Base_Pedidos" bp
        where bp.pedido = pd.np
      )
    group by pd.tanda
  loop
    dedup := 'picking_sin_base_' || r.tanda || '_' || hoy::text;
    msg   := '⚠️ BASE DE PICKING INCOMPLETA'
          || E'\n\nTanda: '    || r.tanda
          || E'\nEntrega: '    || to_char(r.entrega::date, 'DD/MM/YYYY')
          || E'\nPedidos sin artículos: ' || r.cant || ' (' || r.nps || ')'
          || E'\n\nCargá los artículos en la base de pedidos antes de que arranquen el picking.';
    perform tg_enqueue(msg, dedup);
  end loop;
end $fn$;

-- Registrar el cron (idempotente):
-- select cron.unschedule('picking-sin-base-check') where exists (select 1 from cron.job where jobname = 'picking-sin-base-check');
-- select cron.schedule('picking-sin-base-check', '*/30 * * * *', $$select public.notificar_picking_sin_base();$$);
