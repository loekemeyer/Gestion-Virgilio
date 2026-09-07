-- =============================================================================
-- v14.13 (2026-09-07) — Aviso diario por Telegram de las NP cuya factura de ISIS
-- no coincide con lo que Gestión calculó que había que facturar.
--
-- Cada NP se avisa UNA sola vez: GV_Cruce_Avisadas recuerda cuáles ya salieron.
-- Sin eso el digest repetiría las mismas 85 NP todos los días y en una semana no
-- lo lee nadie.
--
-- Excluye los clientes de súper: tienen lista propia que el cálculo todavía no
-- modela bien, así que su diferencia es esperable y sería ruido puro.
--
-- Cron 77 `gv-alerta-cruce-facturacion`, '30 21 * * 1-5' = 18:30 ART, después de
-- la ventana en que entran los PDF (14–17 h).
--
-- ⚠ La primera corrida arrastra el backlog. Para arrancar limpio:
--   insert into public."GV_Cruce_Avisadas"(np, diff, estado)
--   select np, diff, 'diff' from public.gv_vista_cruce_facturacion
--    where estado='diff' and fecha_salida >= current_date - 45 and not es_super
--   on conflict do nothing;
--
-- Rollback: select cron.unschedule('gv-alerta-cruce-facturacion');
-- =============================================================================

create table if not exists public."GV_Cruce_Avisadas" (
  np          text primary key,
  avisado_at  timestamptz not null default now(),
  diff        numeric,
  estado      text
);

alter table public."GV_Cruce_Avisadas" enable row level security;

create or replace function public.gv_alerta_cruce_facturacion_telegram()
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_hoy    date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
  v_n      integer := 0;
  v_suma   numeric := 0;
  v_lineas text := '';
  r        record;
  v_i      integer := 0;
begin
  if not public.gv_es_dia_habil(v_hoy) then
    return 0;
  end if;

  create temp table if not exists _gv_alerta_nuevas(np text, rs text, diff numeric, pct numeric,
                                                    cajas_ent numeric, cajas_fac numeric, comprobante text);
  delete from _gv_alerta_nuevas where true;

  insert into _gv_alerta_nuevas
  select v.np, v.rs_virgilio, v.diff, v.diff_pct, v.cajas_ent, v.factura_cajas, v.comprobante_id
    from public.gv_vista_cruce_facturacion v
   where v.estado = 'diff'
     and v.fecha_salida >= v_hoy - 45
     and not v.es_super
     and not exists (select 1 from public."GV_Cruce_Avisadas" a where a.np = v.np);

  select count(*), coalesce(sum(diff), 0) into v_n, v_suma from _gv_alerta_nuevas;
  if v_n = 0 then
    return 0;
  end if;

  for r in
    select * from _gv_alerta_nuevas order by abs(diff) desc limit 15
  loop
    v_i := v_i + 1;
    v_lineas := v_lineas || E'\n' ||
      '• NP ' || r.np || ' · ' || coalesce(left(r.rs, 28), '') || E'\n' ||
      '   ' || to_char(r.diff, 'FM999G999G999G990') || ' (' || coalesce(to_char(r.pct, 'FM990D00'), '?') || '%)' ||
      case when r.cajas_ent is not null and r.cajas_fac is not null and r.cajas_ent <> r.cajas_fac
           then ' · cajas ' || round(r.cajas_ent) || '→' || round(r.cajas_fac)
           else '' end ||
      case when r.comprobante is not null then ' · ' || r.comprobante else '' end;
  end loop;

  perform public.tg_enqueue(
    '🧾 CRUCE FACTURACIÓN ↔ ISIS · ' || to_char(v_hoy, 'DD/MM') || E'\n' ||
    v_n || ' NP con diferencia sin revisar · total ' || to_char(v_suma, 'FM999G999G999G990') ||
    E'\n(diferencia = lo que facturó ISIS menos lo que Gestión calculó con las cajas entregadas)' ||
    v_lineas ||
    case when v_n > 15 then E'\n… y ' || (v_n - 15) || ' más' else '' end ||
    E'\n\nDetalle en Facturación → 🔍 Cruce con ISIS. Cada NP se avisa una sola vez.',
    'gv_cruce_diff_' || v_hoy::text);

  insert into public."GV_Cruce_Avisadas"(np, diff, estado)
  select np, diff, 'diff' from _gv_alerta_nuevas
  on conflict (np) do nothing;

  perform public.tg_outbox_flush();
  return v_n;
end
$$;

revoke execute on function public.gv_alerta_cruce_facturacion_telegram() from public;
revoke execute on function public.gv_alerta_cruce_facturacion_telegram() from anon;
revoke execute on function public.gv_alerta_cruce_facturacion_telegram() from authenticated;

-- select cron.schedule('gv-alerta-cruce-facturacion', '30 21 * * 1-5',
--   $c$select public.gv_alerta_cruce_facturacion_telegram()$c$);
