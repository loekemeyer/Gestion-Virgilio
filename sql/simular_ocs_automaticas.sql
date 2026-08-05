-- =====================================================================
-- simular_ocs_automaticas.sql — SIMULACIÓN (dry-run) del generador de OCs.
--
-- Pedido del usuario: antes de arrancar la generación automática de verdad
-- (prevista para el MIÉRCOLES 12/08, pendiente de confirmación), correr una
-- SIMULACIÓN los miércoles a las 7:00 que haga TODOS los chequeos y la misma
-- cuenta que la real, pero SIN generar nada, y que avise por Telegram el
-- resultado — haya salido bien o mal.
--
-- `simular_ocs_automaticas()` corre la MISMA fórmula que generar_ocs_automaticas()
-- (stock = góndola + a_guardar + racks + excedente; demanda neteada por TP;
--  Máximo = proy × índice topado a capacidad; internos afuera) pero como un
-- SELECT: no inserta en Ordenes_Compra. Siempre manda Telegram:
--   ok   → '🧪 SIMULACIÓN OCs automáticas — Generaría N líneas · P prov · C cajas. Top: …'
--          (+ '⚠ ya hay N OC(s) de hoy → en la real NO se generaría' si aplica)
--   fail → '🧪🚨 SIMULACIÓN OCs — FALLÓ … <error SQL>'
-- dedup 'ocsim_<día>'. Devuelve 'ok_sim:<n>' | 'error: <sqlerrm>'.
--
-- SETEO DE CRONS (estado al 2026-08-04):
--   • ocs-auto-miercoles (generación REAL) → DESACTIVADO (active=false) hasta
--     confirmar el arranque. Si no se desactivaba, generaba de verdad mañana 05/08.
--   • ocs-auto-sim (esta simulación) → ACTIVO, '0 10 * * 3' = miércoles 07:00 AR
--     (10:00 UTC). Arranca mañana 05/08 y corre cada miércoles hasta el go-live.
--
-- 👉 CUANDO SE CONFIRME EL ARRANQUE REAL (miércoles 12/08 u otro):
--   select cron.alter_job((select jobid from cron.job where jobname='ocs-auto-miercoles'), active := true);
--   select cron.alter_job((select jobid from cron.job where jobname='ocs-auto-sim'),      active := false);
--
-- Verificado (transacción + ROLLBACK, sin mandar Telegram): 'ok_sim:111' →
-- "Generaría 111 líneas · 19 proveedores · 9489 cajas. Top: Poly (1930), Oscar
-- (1464), Lucho (996), Pintos (798), Garcia / Lucho (686)".
-- =====================================================================
create or replace function public.simular_ocs_automaticas()
returns text language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_hoy date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
  v_n int; v_cajas numeric; v_prov int; v_top text; v_hay int; v_msg text;
begin
  select count(*) into v_hay from public."Ordenes_Compra" where fecha = v_hoy;

  begin
    with pos as (   -- v7.68: todo el cálculo vive en vista_generador_oc; acá solo se parte por
                    -- proveedor (Prov 1 % pr1 / Prov 2 = resto). Racks afuera; "(sin proveedor)" no cuenta.
      select proveedor, a_pedir from (
        select proveedor, round(total * pr1 / 100.0)::int as a_pedir
          from public.vista_generador_oc where activo and total > 0 and tiene_prov_real
        union all
        select proveedor2, (total - round(total * pr1 / 100.0))::int
          from public.vista_generador_oc where activo and total > 0 and tiene_prov_real and proveedor2 is not null and pr2 > 0
      ) s
      where a_pedir > 0 and nullif(btrim(proveedor), '') is not null and upper(btrim(proveedor)) not in ('RACKS', 'RACK')
    )
    select
      (select count(*) from pos),
      (select coalesce(sum(a_pedir), 0) from pos),
      (select count(distinct proveedor) from pos),
      (select string_agg(prov || ' (' || round(cajas) || ')', ', ' order by cajas desc)
         from (select proveedor prov, sum(a_pedir) cajas from pos group by proveedor order by 2 desc limit 5) t)
    into v_n, v_cajas, v_prov, v_top;
  exception when others then
    v_msg := '🧪🚨 SIMULACIÓN OCs — FALLÓ (' || to_char(v_hoy, 'DD/MM') || ')' || E'\n' ||
             coalesce(sqlerrm, 'error desconocido') || ' (' || coalesce(sqlstate, '?') || ')' || E'\n' ||
             'Es una PRUEBA: no se generó ninguna OC. Si esto pasa el miércoles real, hay que revisar antes.';
    perform public.tg_enqueue(v_msg, 'ocsim_' || to_char(v_hoy, 'YYYYMMDD'));
    perform public.tg_outbox_flush();
    return 'error: ' || coalesce(sqlerrm, '?');
  end;

  v_msg := '🧪 SIMULACIÓN OCs automáticas — ' || to_char(v_hoy, 'DD/MM') || E'\n' ||
           '(PRUEBA — no se generó nada. Arranque real: miércoles 12/08, a confirmar.)' || E'\n\n' ||
           'Generaría: ' || coalesce(v_n, 0) || ' línea(s) · ' || coalesce(v_prov, 0) ||
             ' proveedor(es) · ' || round(coalesce(v_cajas, 0)) || ' cajas.' ||
           case when coalesce(v_n, 0) = 0 then E'\n(No hay nada para pedir: todo en o sobre el máximo.)' else '' end ||
           case when v_top is not null then E'\nTop: ' || v_top else '' end ||
           case when v_hay > 0
                then E'\n\n⚠ OJO: ya hay ' || v_hay || ' OC(s) con fecha de hoy → en la corrida REAL NO se generaría (para no duplicar).'
                else '' end;
  perform public.tg_enqueue(v_msg, 'ocsim_' || to_char(v_hoy, 'YYYYMMDD'));
  perform public.tg_outbox_flush();
  return 'ok_sim:' || coalesce(v_n, 0);
end $fn$;

revoke all on function public.simular_ocs_automaticas() from public;
grant execute on function public.simular_ocs_automaticas() to authenticated;

-- Seteo de crons (ver cabecera para el switch de go-live):
select cron.alter_job((select jobid from cron.job where jobname = 'ocs-auto-miercoles'), active := false);
select cron.unschedule(jobid) from cron.job where jobname = 'ocs-auto-sim';
select cron.schedule('ocs-auto-sim', '0 10 * * 3', $$select public.simular_ocs_automaticas()$$);
