-- v26.13 — Alerta diaria de la cola de Telegram (cron 12 "outbox-salud", 10:00 ART): contaba TODAS las fallas.
--
-- telegram_outbox tiene 52 mensajes en status 'failed', todos entre el 01/08 y el 08/09 (ninguno después). La alerta
-- los contaba sin ventana de tiempo, así que avisaba todos los días "⚠️ TELEGRAM (outbox) con problemas — 52
-- fallado(s)" por algo que ya no estaba roto. Un aviso que suena siempre deja de mirarse.
--
-- Arreglo: sólo las fallas de las últimas 48 h. 48 y no 24: el cron corre una vez por día y, si una corrida no
-- arranca, la falla igual sale al día siguiente. NO se tocan los 52 mensajes viejos (siguen ahí como historia).
-- Lo de "pendiente hace +30 min" queda igual.
--
-- Medido al aplicarlo (02/10): fallas en 48 h = 0, pendientes viejos = 0 → la corrida de mañana no avisa.

CREATE OR REPLACE FUNCTION public.notificar_outbox_salud()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare nf int; np int; msg text;
begin
  -- v26.13 (Luis, 02/10): sólo las fallas de las últimas 48 h. Contaba las 52 fallas viejas del
  -- 01/08 al 08/09 y avisaba todos los días por algo que ya no estaba roto. 48 h y no 24: corre una
  -- vez por día y, si una corrida no arranca, la falla igual sale al día siguiente.
  select count(*) into nf from public.telegram_outbox
   where status = 'failed' and created_at >= now() - interval '48 hours';
  select count(*) into np from public.telegram_outbox where status = 'pending' and created_at < now() - interval '30 minutes';
  if coalesce(nf,0) = 0 and coalesce(np,0) = 0 then return; end if;
  msg := '⚠️ TELEGRAM (outbox) con problemas — ' ||
         coalesce(nullif(nf,0)::text || ' fallado(s) en las últimas 48 h', '') ||
         case when nf > 0 and np > 0 then ' · ' else '' end ||
         coalesce(nullif(np,0)::text || ' pendiente(s) hace +30 min', '') ||
         E'\nRevisá la conexión a Telegram / el bot. (Los reintentos siguen igual.)';
  perform public.tg_enqueue(msg, 'outbox_salud_' || to_char((now() at time zone 'America/Argentina/Buenos_Aires'),'YYYYMMDDHH24'));
  perform public.tg_outbox_flush();
end $function$;

-- Chequeo: select count(*) from public.telegram_outbox where status = 'failed' and created_at >= now() - interval '48 hours';
--
-- Rollback (la de antes, sin ventana):
--   reemplazar las dos líneas del primer select por
--   select count(*) into nf from public.telegram_outbox where status = 'failed';
--   y el texto ' fallado(s) en las últimas 48 h' por ' fallado(s)'.
