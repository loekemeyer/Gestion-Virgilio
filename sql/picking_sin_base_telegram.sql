-- =====================================================================
-- picking_sin_base_telegram.sql — NPs que están en Programación Diaria
-- pero NO tienen artículos cargados en PPP_Base_Pedidos (no se puede
-- armar el picking).
--
-- ✅ APLICADO 2026-08-28 (migraciones notificar_picking_sin_base_cron,
--    vista_np_prog_sin_base, notificar_picking_sin_base_usa_vista).
-- Cron: cada 30 minutos (*/30 * * * *), jobname picking-sin-base-check.
-- Dedup por tanda+día → una alerta por tanda por día.
-- Usa tg_enqueue → telegram_outbox → grupo Faltantes (-1004379879565).
--
-- v12.05 — La vista `vista_np_prog_sin_base` pasa a ser la ÚNICA fuente de
-- verdad: la lee el cron Y la sección nueva del módulo "Pedidos sin cargar
-- en PPP" del panel supervisor (stkOpenNpFaltan). Antes esto vivía solo en
-- Telegram: el módulo del panel NO podía verlo porque sus dos vistas miran
-- el problema al revés —
--   · vista_np_sin_programar     = está en la BASE y no en programación,
--   · vista_np_faltantes_secuencia = números que no existen en NINGUNA fuente
--     (y estas NP sí existen, justamente en Programación Diaria).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Vista: NP programada sin artículos en la base.
-- Normaliza el ".0" final (PPP_Base_Pedidos guardó "98574.0" en su momento)
-- igual que las otras dos vistas del módulo, y descarta lo ya facturado /
-- entregado / cancelado: si el pedido ya salió, no hay picking que armar.
-- ---------------------------------------------------------------------
create or replace view public.vista_np_prog_sin_base as
with prog as (
  select regexp_replace(btrim(np), '\.0+$', '')      as np,
         nullif(btrim(coalesce(tanda, '')), '')      as tanda,
         nullif(btrim(coalesce(razon_social, '')), '') as cliente,
         nullif(left(btrim(coalesce(fecha_entrega, '')), 10), '') as fecha_entrega,
         coalesce(m3, 0)                             as m3
  from "PPP_Programacion_Diaria"
  where np is not null and btrim(np) <> ''
),
base as (
  select distinct regexp_replace(btrim(pedido), '\.0+$', '') as np
  from "PPP_Base_Pedidos"
  where pedido is not null
),
salidas as (
  select regexp_replace(btrim(np), '\.0+$', '') as np from "Facturacion_NP"     where np is not null
  union
  select regexp_replace(btrim(np), '\.0+$', '')        from "PPP_Entregados_Meta" where np is not null
  union
  select regexp_replace(btrim(np), '\.0+$', '')        from "NP_Canceladas"       where np is not null
)
select p.np,
       max(p.tanda)                        as tanda,
       max(p.cliente)                      as cliente,
       max(p.fecha_entrega)                as fecha_entrega,
       round(sum(p.m3)::numeric, 2)        as m3
from prog p
where not exists (select 1 from base    b where b.np = p.np)
  and not exists (select 1 from salidas s where s.np = p.np)
group by p.np;

alter view public.vista_np_prog_sin_base set (security_invoker = on);
grant select on public.vista_np_prog_sin_base to anon, authenticated;

-- ---------------------------------------------------------------------
-- Alerta Telegram (cron). Lee la vista, así el aviso y el panel no pueden
-- discrepar. La ventana sigue siendo los próximos 7 días.
-- Antes cruzaba `bp.pedido = pd.np` a secas: un "98574.0" en la base se leía
-- como NP sin artículos → alerta en falso. Y `tanda` o `fecha_entrega` vacías
-- dejaban el mensaje entero en NULL (concatenar con NULL da NULL).
-- ---------------------------------------------------------------------
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
  for r in
    select coalesce(v.tanda, '(sin tanda)')          as tanda,
           string_agg(v.np, ', ' order by v.np)      as nps,
           count(*)::int                             as cant,
           min(v.fecha_entrega)                      as entrega
    from public.vista_np_prog_sin_base v
    where v.fecha_entrega between hoy::text and (hoy + 7)::text
    group by coalesce(v.tanda, '(sin tanda)')
  loop
    dedup := 'picking_sin_base_' || r.tanda || '_' || hoy::text;
    msg   := '⚠️ BASE DE PICKING INCOMPLETA'
          || E'\n\nTanda: '  || r.tanda
          || E'\nEntrega: '  || coalesce(to_char(r.entrega::date, 'DD/MM/YYYY'), 's/fecha')
          || E'\nPedidos sin artículos: ' || r.cant || ' (' || r.nps || ')'
          || E'\n\nCargá los artículos en la base de pedidos antes de que arranquen el picking.';
    perform tg_enqueue(msg, dedup);
  end loop;
end $fn$;

-- Registrar el cron (idempotente):
-- select cron.unschedule('picking-sin-base-check') where exists (select 1 from cron.job where jobname = 'picking-sin-base-check');
-- select cron.schedule('picking-sin-base-check', '*/30 * * * *', $$select public.notificar_picking_sin_base();$$);
