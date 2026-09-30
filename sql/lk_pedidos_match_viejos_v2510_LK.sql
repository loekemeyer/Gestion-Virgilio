-- PROYECTO LK (kwkclwhmoygunqmlegrg) · Luis 30/09/2026
-- sync_pedidos_match_virgilio (cron 24, c/5 min) sólo recarga los pedidos de los últimos 14 días.
-- Un pedido más viejo corregido después en la página (LK 1450 · Matiz: cajas de 6/12 -> 1) quedaba con
-- los ítems viejos en Gestión (lk_pedidos_match.items_string, que leen la cuarentena y las alertas).
-- Pasada horaria: corrige SÓLO items_string de pedidos LK de hasta 60 días antes del corte, si difiere.
-- Primera corrida: 2 pedidos (1450 y 1358, que tenía el 246 agregado después). 184 ms el cruce.
-- Chef queda afuera: v_pedidos_match_chef tarda 4 s para una fila (FDW a Chef).
-- Backup de lo que podía tocar (Gestión): zz_backups."GV_Backup_LkPedMatch_items_20260930" (590 filas).
create or replace function public.sync_pedidos_match_virgilio_viejos()
returns integer language plpgsql security definer set search_path to 'public' as $fn$
declare v_corte date; d jsonb; e jsonb; n int := 0;
begin
  select coalesce(max(fecha_pedido), date '2000-01-01') - 14 into v_corte
    from virgilio.lk_pedidos_match where empresa = 'lk';
  with rem as materialized (
    select x.order_id, x.items_string from virgilio.lk_pedidos_match x
     where x.empresa = 'lk' and x.fecha_pedido < v_corte and x.fecha_pedido >= v_corte - 60)
  select coalesce(jsonb_agg(jsonb_build_object('id', v.order_id, 'it', v.items_string)), '[]'::jsonb) into d
    from public.v_pedidos_match v join rem on rem.order_id = v.order_id
   where v.fecha_pedido < v_corte and v.fecha_pedido >= v_corte - 60
     and v.items_string is not null and rem.items_string is distinct from v.items_string;
  for e in select * from jsonb_array_elements(d) loop
    update virgilio.lk_pedidos_match set items_string = e->>'it'
     where empresa = 'lk' and order_id = (e->>'id')::bigint;
    n := n + 1;
  end loop;
  return n;
end $fn$;
revoke all on function public.sync_pedidos_match_virgilio_viejos() from public, anon, authenticated;
select cron.schedule('gv-pedidos-match-viejos', '37 * * * *', 'select public.sync_pedidos_match_virgilio_viejos()');
-- ROLLBACK: select cron.unschedule('gv-pedidos-match-viejos'); drop function public.sync_pedidos_match_virgilio_viejos();
