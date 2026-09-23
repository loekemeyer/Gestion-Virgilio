-- ============================================================================
-- AGREGAR EXPRESO ISIS — v21.94 (Thomas, 2026-09-23)
-- ============================================================================
-- La cola administrativa de los expresos que el CLIENTE eligio o cambio desde la
-- pagina. Lo empuja LK cada 15 min (sync_expreso_pendiente_virgilio, cron 56 de
-- LK, minuto 1-59/15) por el FDW, con el rol lk_ppp_reader — mismo patron que
-- GV_Cliente_Isis y GV_Clientes_Nuevos.
--
-- ⚠ ESTO NO FRENA NINGUN PEDIDO. Cuando el cliente cambia el expreso, LK escribe
--   la FICHA (customer_delivery_addresses) en el acto, y `v_pedidos_web` la lee
--   EN VIVO: el pedido sale con el expreso nuevo y la PPP, el remito y el camion
--   ya van al galpon correcto. Lo unico que falta es dejarlo igual en ISIS.
--   Si esta pantalla queda sin mirar una semana NO se traba nada — se
--   desincroniza ISIS, que es otra cosa.
--
-- ⚠ La CLAVE es (empresa, id), no id: el id es el de la tabla de LK, y el dia que
--   entre Chef sus ids son de su propio bigserial y chocarian con los de LK.
-- ============================================================================

create table if not exists public."GV_Expreso_Pendiente" (
  id              bigint not null,          -- el id de public.expreso_pendiente de su empresa
  empresa         text not null default 'lk',
  cod_cliente     text,
  razon_social    text,
  sucursal_label  text,
  slot            smallint,
  expreso_anterior    text,
  expreso_nuevo       text,
  direccion_anterior  text,
  direccion_nueva     text,
  localidad_nueva     text,
  provincia_nueva     text,
  del_padron      boolean,
  order_id        bigint,
  estado          text not null default 'pendiente',
  nota_admin      text,
  creado_at       timestamptz,
  resuelto_at     timestamptz,
  resuelto_por    text,
  actualizado_at  timestamptz not null default now(),
  primary key (empresa, id)
);
create index if not exists gv_expreso_pend_estado_idx
  on public."GV_Expreso_Pendiente" (estado, creado_at desc);

alter table public."GV_Expreso_Pendiente" enable row level security;
drop policy if exists "GV_Expreso_Pendiente_lectura" on public."GV_Expreso_Pendiente";
create policy "GV_Expreso_Pendiente_lectura" on public."GV_Expreso_Pendiente"
  for select to anon, authenticated using (true);
drop policy if exists "GV_Expreso_Pendiente_writer" on public."GV_Expreso_Pendiente";
create policy "GV_Expreso_Pendiente_writer" on public."GV_Expreso_Pendiente"
  for all to lk_ppp_reader using (true) with check (true);
grant select on public."GV_Expreso_Pendiente" to anon, authenticated;
grant select, insert, update, delete on public."GV_Expreso_Pendiente" to lk_ppp_reader;
-- ⚠ Los grants por defecto del schema le dan INSERT/UPDATE/DELETE a `anon`
--   igual (medido: venia con los tres). La RLS ya lo frenaba —no hay policy de
--   escritura para anon— pero el grant sobra y queda a una policy de distancia
--   de ser un agujero. Es el mismo criterio que la regla de los backups.
--   Verificado como anon: antes "violates row-level security policy", despues
--   "permission denied". El modulo sigue andando porque escribe por
--   gv_expreso_marcar, que es SECURITY DEFINER.
revoke insert, update, delete, truncate on public."GV_Expreso_Pendiente" from anon, authenticated;

-- Lo que ve el modulo. security_invoker = true (regla del repo: sin eso corre
-- como postgres y saltea la RLS).
create or replace view public.gv_expreso_pendiente as
select
  e.id, e.empresa, e.cod_cliente, e.razon_social, e.sucursal_label, e.slot,
  e.expreso_anterior, e.expreso_nuevo, e.direccion_anterior, e.direccion_nueva,
  e.localidad_nueva, e.provincia_nueva, e.del_padron, e.order_id,
  e.estado, e.nota_admin, e.creado_at, e.resuelto_at, e.resuelto_por,
  (now()::date - e.creado_at::date) as dias,
  case
    when e.del_padron then 'cambiar el expreso del cliente en ISIS'
    when coalesce(btrim(e.direccion_nueva),'') = ''
      then 'ALTA de expreso nuevo en ISIS — FALTA la direccion, hay que preguntarsela al cliente'
    else 'ALTA de expreso nuevo en ISIS'
  end as que_hacer,
  -- El unico caso que necesita llamar al cliente: expreso que no esta en el
  -- padron Y sin direccion. La direccion es OPCIONAL a proposito.
  (not coalesce(e.del_padron,false) and coalesce(btrim(e.direccion_nueva),'') = '') as falta_direccion
from public."GV_Expreso_Pendiente" e
where e.estado = 'pendiente';
alter view public.gv_expreso_pendiente set (security_invoker = true);
grant select on public.gv_expreso_pendiente to anon, authenticated;

-- Marcar cargado / descartado. El front entra por aca (la tabla no tiene UPDATE
-- para anon), y el guard de supervisor vive ADENTRO.
create or replace function public.gv_expreso_marcar(
  p_id bigint, p_estado text default 'cargado_isis',
  p_nota text default null, p_por text default null
) returns jsonb
language plpgsql security definer set search_path = public as $fn$
declare v_n int;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Solo un supervisor puede marcar un expreso como cargado en ISIS.';
  end if;
  if p_estado not in ('cargado_isis','descartado','pendiente') then
    raise exception 'Estado invalido: %', p_estado;
  end if;
  update public."GV_Expreso_Pendiente"
     set estado = p_estado,
         nota_admin = coalesce(nullif(btrim(coalesce(p_nota,'')),''), nota_admin),
         resuelto_at = case when p_estado='pendiente' then null else now() end,
         resuelto_por = case when p_estado='pendiente' then null
                             else coalesce(nullif(btrim(coalesce(p_por,'')),''),'supervisor') end,
         actualizado_at = now()
   where id = p_id;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'No existe el pendiente %', p_id; end if;
  return jsonb_build_object('ok', true, 'id', p_id, 'estado', p_estado);
end $fn$;
revoke execute on function public.gv_expreso_marcar(bigint,text,text,text) from public;
grant execute on function public.gv_expreso_marcar(bigint,text,text,text) to anon, authenticated;

-- ============================================================================
-- ⚠ PENDIENTE DEL "SI" DEL DUENO — los dos centinelas
-- ============================================================================
-- Medido el 23/09: los dos patrones aparecen UNA sola vez en el cuerpo de su
-- objeto, o sea que SON la regla y no el vecindario (regla v21.84). Borrar la
-- regla borra la palabra, que es la prueba que pide el repo.
--
--   insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
--   values
--     ('gv_expreso_marcar','funcion','es_supervisor_virgilio',
--      'Marcar un expreso como cargado en ISIS es de SUPERVISOR. El front entra por esta RPC porque la tabla no tiene UPDATE para anon: sin el guard, cualquiera con la clave publica vacia la cola.',
--      'Thomas','v21.94'),
--     ('gv_expreso_pendiente','vista','falta_direccion',
--      'La cola distingue el expreso que se puede dar de alta solo del que necesita llamar al cliente (no esta en el padron Y vino sin direccion). Sin esa columna los dos casos se ven iguales y el que falta dato se carga mal en ISIS.',
--      'Thomas','v21.94');
--
-- Chequeo despues de cargarlos:  select * from public.gv_reglas_perdidas;   -- vacia = todo bien
