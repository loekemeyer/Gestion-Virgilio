-- PROYECTO LK (kwkclwhmoygunqmlegrg) · Luis 30/09/2026 · v25.11 (reemplaza la v25.10)
-- sync_pedidos_match_virgilio (cron 24) sólo recarga los últimos 14 días. Un pedido más viejo
-- corregido después en la página quedaba con los ítems viejos en Gestión (lk_pedidos_match).
-- Ahora, para LK y Chef, corrige items_string y match_string de lo anterior a esos 14 días:
--   · cada hora (:37)             ventana 60 días · Chef desde chef_orders_cache (sin FDW)
--   · domingos 04:23 ART (07:23Z) TODO el historial · Chef por FDW (chef_orders), ~3,5 s
-- Trae la copia remota de una sola vez (jsonb) y actualiza de a una fila: un UPDATE por FDW con un
-- cursor remoto abierto se cuelga (pasó en la v25.10).
-- Medido 30/09: con todo el historial, ítems desfasados 0 en LK y 0 en Chef; match_string viejo en 4 de LK.
-- Primera corrida (todo el historial): LK 4 match_string, Chef 0. Segunda: 0 y 0.
-- Backup (Gestión): zz_backups."GV_Backup_LkPedMatch_items_match_20260930b" (1.293 filas).
drop function if exists public.sync_pedidos_match_virgilio_viejos();
create or replace function public.sync_pedidos_match_virgilio_viejos(p_dias int default 60, p_chef_remoto boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare v_cl date; v_cc date; r jsonb; d jsonb; e jsonb; nl int := 0; nc int := 0; v_err text;
begin
  select coalesce(max(fecha_pedido) filter (where empresa='lk'),   date '2000-01-01') - 14,
         coalesce(max(fecha_pedido) filter (where empresa='chef'), date '2000-01-01') - 14
    into v_cl, v_cc from virgilio.lk_pedidos_match;
  select coalesce(jsonb_object_agg(empresa||':'||order_id, jsonb_build_array(items_string, match_string)), '{}'::jsonb)
    into r from virgilio.lk_pedidos_match
   where (empresa='lk' and fecha_pedido < v_cl and fecha_pedido >= v_cl - p_dias)
      or (empresa='chef' and fecha_pedido < v_cc and fecha_pedido >= v_cc - p_dias);

  -- LK
  select coalesce(jsonb_agg(jsonb_build_object('id', v.order_id, 'it', v.items_string, 'ms', v.match_string)), '[]'::jsonb) into d
    from public.v_pedidos_match v
   where v.fecha_pedido < v_cl and v.fecha_pedido >= v_cl - p_dias and v.items_string is not null
     and r ? ('lk:'||v.order_id)
     and (r->('lk:'||v.order_id)->>0 is distinct from v.items_string
       or r->('lk:'||v.order_id)->>1 is distinct from v.match_string);
  for e in select * from jsonb_array_elements(d) loop
    update virgilio.lk_pedidos_match set items_string = e->>'it', match_string = e->>'ms'
     where empresa = 'lk' and order_id = (e->>'id')::bigint;
    nl := nl + 1;
  end loop;

  -- CHEF (mismo cálculo que v_pedidos_match_chef)
  begin
    drop table if exists _vch;
    create temp table _vch on commit drop as
      select o.id, o.created_at, o.customer_id, o.sheets_payload from public.chef_orders_cache o where false;
    if p_chef_remoto then
      insert into _vch select o.id, o.created_at, o.customer_id, o.sheets_payload from public.chef_orders o
       where o.created_at >= ((v_cc - p_dias)::timestamp at time zone 'America/Argentina/Buenos_Aires');
    else
      insert into _vch select o.id, o.created_at, o.customer_id, o.sheets_payload from public.chef_orders_cache o
       where o.created_at >= ((v_cc - p_dias)::timestamp at time zone 'America/Argentina/Buenos_Aires');
    end if;
    select coalesce(jsonb_agg(jsonb_build_object('id', z.id, 'it', z.it,
             'ms', z.cod || '|' || to_char(z.fecha, 'YYYY-MM-DD') || '|' || z.it)), '[]'::jsonb) into d
      from (select o.id, (o.created_at at time zone 'America/Argentina/Buenos_Aires')::date fecha,
                   coalesce(nullif(o.sheets_payload->>'cod_cliente',''), c.cod_cliente::text) cod,
                   (select string_agg((t.cod||'x')||case when t.suma = trunc(t.suma) then trunc(t.suma)::bigint::text else t.suma::text end, ',' order by t.cod)
                      from (select i->>'cod_art' cod, sum((i->>'cajas')::numeric) suma
                              from jsonb_array_elements(o.sheets_payload->'items') i group by 1) t) it
              from _vch o left join public.chef_customers_cache c on c.id = o.customer_id
             where jsonb_typeof(o.sheets_payload->'items') = 'array') z
     where z.fecha < v_cc and z.it is not null and z.cod is not null and r ? ('chef:'||z.id)
       and (r->('chef:'||z.id)->>0 is distinct from z.it
         or r->('chef:'||z.id)->>1 is distinct from z.cod || '|' || to_char(z.fecha, 'YYYY-MM-DD') || '|' || z.it);
    for e in select * from jsonb_array_elements(d) loop
      update virgilio.lk_pedidos_match set items_string = e->>'it', match_string = e->>'ms'
       where empresa = 'chef' and order_id = (e->>'id')::bigint;
      nc := nc + 1;
    end loop;
  exception when others then v_err := sqlerrm;
  end;
  return jsonb_build_object('lk', nl, 'chef', nc, 'dias', p_dias, 'chef_remoto', p_chef_remoto, 'error_chef', v_err);
end $fn$;
revoke all on function public.sync_pedidos_match_virgilio_viejos(int, boolean) from public, anon, authenticated;
select cron.alter_job((select jobid from cron.job where jobname='gv-pedidos-match-viejos'),
       command := 'select public.sync_pedidos_match_virgilio_viejos(60, false)');
select cron.schedule('gv-pedidos-match-viejos-todo', '23 7 * * 0', 'select public.sync_pedidos_match_virgilio_viejos(10000, true)');
-- ROLLBACK: select cron.unschedule('gv-pedidos-match-viejos-todo'); select cron.unschedule('gv-pedidos-match-viejos');
--           drop function public.sync_pedidos_match_virgilio_viejos(int, boolean);
