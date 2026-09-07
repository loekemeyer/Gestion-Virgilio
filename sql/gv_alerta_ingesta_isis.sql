-- =============================================================================
-- v14.15 (2026-09-07) — Watchdog de la ingesta de PDF de ISIS.
--
-- POR QUÉ EXISTE: los PDF de factura que emite ISIS los levanta un agente Python
-- que corre en una PC de la oficina y los sube a los buckets isis-lk / isis-ch.
-- Si esa PC se apaga o la tarea programada no arranca, NO entra ninguna factura y
-- hoy no se entera nadie: el trigger que dispara el aviso de WhatsApp nunca corre,
-- el cruce contra Facturación se queda sin comprobantes, y todo falla en silencio.
-- Al 07/09 la ingesta llevaba 52,6 h parada (último PDF: Loeke 05/09 08:31,
-- Chef 04/09 16:08) sin que ninguna señal lo dijera.
--
-- QUÉ HACE: cada media hora, en día hábil y en horario de oficina, mira cuándo fue
-- el último PDF procesado (las dos empresas). Si pasaron más de 2 horas, avisa por
-- Telegram. Un aviso por día como máximo: mientras siga caída no repite.
--
-- Cron 78 `gv-alerta-ingesta-isis`, '*/30 13-22 * * 1-5' = 10:00–19:00 ART.
-- Rollback: select cron.unschedule('gv-alerta-ingesta-isis');
--
-- ⚠ PENDIENTE ASOCIADO: el script del agente NO está versionado en ningún repo,
-- sólo existe en esa PC. Su hermano de las NC sí está: agente-local/nc_ingest.py.
-- =============================================================================

create or replace function public.gv_alerta_ingesta_isis_telegram(p_horas integer default 2)
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_ahora   timestamptz := now();
  v_hoy     date := (v_ahora at time zone 'America/Argentina/Buenos_Aires')::date;
  v_ult_lk  timestamptz;
  v_ult_ch  timestamptz;
  v_ult     timestamptz;
  v_horas   numeric;
begin
  if not public.gv_es_dia_habil(v_hoy) then
    return 0;
  end if;

  select max(procesado_at) into v_ult_lk from isis_lk.ingesta_log;
  select max(procesado_at) into v_ult_ch from isis_ch.ingesta_log;
  v_ult := greatest(coalesce(v_ult_lk, 'epoch'::timestamptz), coalesce(v_ult_ch, 'epoch'::timestamptz));

  v_horas := round(extract(epoch from (v_ahora - v_ult)) / 3600.0, 1);
  if v_horas < p_horas then
    return 0;
  end if;

  perform public.tg_enqueue(
    '🛑 ISIS — NO ENTRAN FACTURAS · ' ||
      to_char(v_ahora at time zone 'America/Argentina/Buenos_Aires', 'DD/MM HH24:MI') || E'\n' ||
    'Hace ' || v_horas || ' h que no se sube ningún PDF (umbral: ' || p_horas || ' h).' || E'\n' ||
    'Último: Loeke ' ||
      coalesce(to_char(v_ult_lk at time zone 'America/Argentina/Buenos_Aires', 'DD/MM HH24:MI'), 'nunca') ||
      ' · Chef ' ||
      coalesce(to_char(v_ult_ch at time zone 'America/Argentina/Buenos_Aires', 'DD/MM HH24:MI'), 'nunca') || E'\n\n' ||
    'Los PDF los levanta el agente que corre en la PC de la oficina. Chequear que esa ' ||
    'máquina esté prendida y que la tarea programada esté corriendo.' || E'\n' ||
    'Mientras esté caído: no se manda ningún aviso de factura por WhatsApp y el cruce ' ||
    'de Facturación se queda sin comprobantes.',
    'gv_ingesta_parada_' || v_hoy::text);

  perform public.tg_outbox_flush();
  return 1;
end
$$;

revoke execute on function public.gv_alerta_ingesta_isis_telegram(integer) from public;
revoke execute on function public.gv_alerta_ingesta_isis_telegram(integer) from anon;
revoke execute on function public.gv_alerta_ingesta_isis_telegram(integer) from authenticated;

-- select cron.schedule('gv-alerta-ingesta-isis', '*/30 13-22 * * 1-5',
--   $c$select public.gv_alerta_ingesta_isis_telegram(2)$c$);
