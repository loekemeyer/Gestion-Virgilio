-- v30.44 (Luis, 14/10/2026, D2 corregido): "que sea una excepcion para pedidos que entraron en la
-- cuarentena y clientes nuevos. Los que estan ahora + forward-facing. no arriesgues a traer basura vieja".
-- Reemplaza el criterio de la v30.41 (cualquier aprobado de 31 a 120 días). La excepción a la ventana
-- del armador (ventana_dias = 30) vale SÓLO para los pedidos de esta tabla:
--   · foto del 14/10: los 8 que estaban en cuarentena / clientes nuevos sin aprobar, sin tanda y no
--     anulados (medido contra GV_Cuarentena_Log + gv_pedidos_web_excluidos);
--   · de acá en adelante: todo pedido web al que se le anota 'entro' en GV_Cuarentena_Log (trigger).
-- Lo aprobado ANTES del 14/10 (p. ej. Andser LK 1375, anulado) no entra nunca.
create table if not exists public."GV_Cuarentena_Ventana_Exc" (
  empresa   text   not null,
  order_id  bigint not null,
  origen    text   not null,            -- 'foto_20261014' | 'entro'
  creado_at timestamptz not null default now(),
  primary key (empresa, order_id)
);
alter table public."GV_Cuarentena_Ventana_Exc" enable row level security;
revoke all on table public."GV_Cuarentena_Ventana_Exc" from anon, authenticated;

insert into public."GV_Cuarentena_Ventana_Exc" (empresa, order_id, origen)
values ('lk',1674,'foto_20261014'),('lk',1573,'foto_20261014'),('chef',250,'foto_20261014'),
       ('lk',1604,'foto_20261014'),('lk',1557,'foto_20261014'),('lk',1555,'foto_20261014'),
       ('lk',1559,'foto_20261014'),('lk',1431,'foto_20261014')
on conflict do nothing;

create or replace function public.gv_cuarentena_ventana_exc_trg()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $f$
begin
  -- v30.44-cuar-exc: forward-facing, todo pedido web que entra a cuarentena / cliente nuevo
  if new.evento = 'entro' and coalesce(new.clave, '') ~ '^[0-9]+$' then
    insert into public."GV_Cuarentena_Ventana_Exc" (empresa, order_id, origen)
    values (lower(new.empresa), new.clave::bigint, 'entro')
    on conflict do nothing;
  end if;
  return new;
exception when others then
  return new;   -- la excepción de ventana nunca frena el log de cuarentena
end $f$;

create or replace trigger trg_gv_cuarentena_ventana_exc
  after insert on public."GV_Cuarentena_Log"
  for each row execute function public.gv_cuarentena_ventana_exc_trg();

create or replace function public.gv_cuarentena_liberados_viejos(p_empresa text, p_ventana integer default 30)
returns table(order_id bigint, fecha_pedido date)
language sql stable security definer set search_path to 'public', 'pg_temp'
as $function$
  -- v30.44-cuar-exc: SÓLO los de GV_Cuarentena_Ventana_Exc (foto 14/10 + los que entren desde ahí),
  -- fuera de la ventana y todavía sin tanda. Aprobado o no: el armador los sigue reteniendo si no hay
  -- aprobación (gv_cuarentena_retiene_lote), y así no se caen de la pantalla ni de la tarea de Planify.
  select x.order_id, min(m.fecha_pedido)
    from public."GV_Cuarentena_Ventana_Exc" x
    join public.lk_pedidos_match m on m.empresa = x.empresa and m.order_id = x.order_id
   where x.empresa = lower(p_empresa)
     and m.fecha_pedido < current_date - greatest(coalesce(p_ventana, 30), 1)
     and not exists (select 1 from public."PPP_Web_Programacion" w
                      where w.empresa = x.empresa and w.order_id = x.order_id
                        and coalesce(nullif(btrim(w.tanda), ''), '') <> '')
   group by x.order_id;
$function$;
revoke all on function public.gv_cuarentena_liberados_viejos(text, integer) from public, anon, authenticated;
grant execute on function public.gv_cuarentena_liberados_viejos(text, integer) to service_role;
