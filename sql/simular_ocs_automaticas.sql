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
    with norm as (
      select regexp_replace(upper(btrim(m.cod)), '^0+(?=.)', '') as codn,
             btrim(coalesce(m.proveedor, '')) as proveedor,
             coalesce(m.max_cajas, 0)::numeric as max_excel,
             case when coalesce(m.indice, 0) > 0 then m.indice::numeric else 1.5 end as indice
        from public."OC_Maximos" m
       where m.activo and nullif(btrim(m.cod), '') is not null
    ),
    stk as (
      select regexp_replace(upper(btrim(cod_art)), '^0+(?=.)', '') as codn,
             sum(coalesce(terminado, 0) + coalesce(a_guardar, 0) + coalesce(racks, 0) + coalesce(excedente, 0)) as stock
        from public.vista_saldos_stock group by 1
    ),
    pickeadas as (
      select distinct upper(btrim(texto)) as tanda
        from public."Registros_Produccion_Virgilio"
       where opcion = 'TP' and nullif(btrim(coalesce(texto, '')), '') is not null
    ),
    pend_np as (
      select distinct btrim(p.np) as np
        from public."PPP_Programacion_Diaria" p
       where btrim(p.np) not in (select btrim(np) from public."Facturacion_NP")
         and upper(btrim(coalesce(p.tanda, ''))) not in (select tanda from pickeadas)
    ),
    dem as (
      select regexp_replace(upper(btrim(b.articulo)), '^0+(?=.)', '') as codn,
             sum(coalesce(b.cajas, 0)) as pedidos
        from public."PPP_Base_Pedidos" b
        join pend_np n on btrim(b.pedido) = n.np
       where nullif(btrim(b.articulo), '') is not null
       group by 1
    ),
    proy as (
      select regexp_replace(upper(btrim(cod)), '^0+(?=.)', '') as codn,
             max(coalesce(proy_cajas_mes, 0))::numeric as proy
        from public.proyeccion_madre group by 1
    ),
    cap as (
      select regexp_replace(upper(btrim(cod)), '^0+(?=.)', '') as codn,
             sum(coalesce(cajas_max, 0))::numeric as cap
        from public."Capacidad_Sector" group by 1
    ),
    calc as (
      select n.proveedor,
             ceil(least(
               ceil(case when p.proy is not null and p.proy > 0 then p.proy * n.indice else n.max_excel end),
               coalesce(nullif(c.cap, 0), 1e9)
             ) + coalesce(d.pedidos, 0) - coalesce(s.stock, 0)) as a_pedir
        from norm n
        left join stk s on s.codn = n.codn
        left join dem d on d.codn = n.codn
        left join proy p on p.codn = n.codn
        left join cap c on c.codn = n.codn
       where upper(n.proveedor) not in ('RACKS', 'RACK')   -- v7.65: Racks afuera; Log/Fabr SÍ genera
         and nullif(n.proveedor, '') is not null
    ),
    pos as (select proveedor, a_pedir from calc where a_pedir > 0)
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
