-- ============================================================================
-- v19.05 (2026-09-16, pedido de Luis) — CLIENTES NUEVOS: Speech 1/2, timer, monto con IVA
-- ============================================================================
-- Pedido: en el submódulo "Clientes nuevos" (A Programar):
--   · columna "Tiempo desde primer contacto": arranca a correr cuando se aprieta "Speech 1".
--   · botones "Speech 1" y "Speech 2" que abren WhatsApp Web con el cliente.
--       Speech 1 = pedir 30% adelantado, con el monto CON DESCUENTOS y CON IVA.
--       Speech 2 = preguntar si paga en 24 h; si no, se elimina el pedido.
--   · "Eliminar pedido" (saca de la PPP y guarda registro) → reusa gv_pedido_anular.
--   · "Aprobar pedido" (pasa a Pedidos a programar) → reusa gv_cuarentena_liberar.
--
-- ESTE ARCHIVO agrega SÓLO lo que falta en el backend (aditivo, prefijo gv_/GV_):
--   1) GV_Clientes_Nuevos_Contacto  — cuándo se hizo el PRIMER contacto (el "Speech 1"),
--      persistido para que el timer sobreviva al reload y lo vea cualquier supervisor.
--   2) gv_cliente_nuevo_contacto_marcar(empresa, order_id, por) — sella el primer contacto
--      UNA sola vez (on conflict do nothing) y devuelve el instante que quedó.
--   3) gv_cliente_nuevo_contacto_lote(pedidos) — lee el primer contacto de un lote.
--   4) gv_cliente_nuevo_wpp_lote(pedidos) — teléfono del CLIENTE (whatsapp_clientes) para
--      abrir la conversación. (gv_cuar_contacto_lote prefiere el vendedor; para el Speech
--      queremos hablar con el cliente.) Medido 16/09: 184/367 clientes nuevos tienen tel.
--   5) gv_clientes_nuevos_valor_lote — pasa a devolver TAMBIÉN valor_con_iva.
--
-- ⚠ IVA: precios_venta / precios_venta_chef NO guardan tasa de IVA por artículo (medido 16/09:
--   cols = cod, precio_unit, descripcion, actualizado). El catálogo de Loeke/Chef es rubro
--   bazar/menaje = 21%. Se aplica 21% plano. Si algún día hay artículos a 10,5%, hay que
--   traer la tasa por artículo y cambiar acá. El "con descuentos" ya viene de
--   gv_ppp_web_valor_items (neto con el 2% web condicional).
--
-- ROLLBACK:
--   drop function public.gv_cliente_nuevo_contacto_marcar(text,text,text);
--   drop function public.gv_cliente_nuevo_contacto_lote(jsonb);
--   drop function public.gv_cliente_nuevo_wpp_lote(jsonb);
--   drop table public."GV_Clientes_Nuevos_Contacto";
--   -- y volver gv_clientes_nuevos_valor_lote a la versión de v18.98 (sin valor_con_iva).
-- ============================================================================

-- ── 1) Tabla del primer contacto ────────────────────────────────────────────
create table if not exists public."GV_Clientes_Nuevos_Contacto" (
  empresa           text not null check (empresa in ('lk','chef')),
  order_id          text not null,
  primer_contacto_at timestamptz not null default now(),
  por               text,
  updated_at        timestamptz not null default now(),
  primary key (empresa, order_id)
);
comment on table public."GV_Clientes_Nuevos_Contacto" is
  'v19.05 (Luis): cuándo se hizo el PRIMER contacto (Speech 1) de un pedido de cliente nuevo. '
  'Alimenta el timer "Tiempo desde primer contacto". Una fila por (empresa, order_id).';
alter table public."GV_Clientes_Nuevos_Contacto" enable row level security;
revoke all on table public."GV_Clientes_Nuevos_Contacto" from anon, authenticated, public;
-- Sin policies: sólo las funciones SECURITY DEFINER (owner postgres) la tocan.

-- ── 2) Sellar el primer contacto (idempotente: sólo la primera vez) ──────────
create or replace function public.gv_cliente_nuevo_contacto_marcar(
  p_empresa text, p_order_id text, p_por text default null)
returns timestamptz
language plpgsql security definer set search_path = public as $$
declare v_at timestamptz;
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede marcar el contacto.' using errcode = '42501';
  end if;
  insert into public."GV_Clientes_Nuevos_Contacto" (empresa, order_id, primer_contacto_at, por)
  values (lower(p_empresa), p_order_id, now(), p_por)
  on conflict (empresa, order_id) do nothing;
  select primer_contacto_at into v_at from public."GV_Clientes_Nuevos_Contacto"
   where empresa = lower(p_empresa) and order_id = p_order_id;
  return v_at;
end;
$$;
revoke all on function public.gv_cliente_nuevo_contacto_marcar(text,text,text) from public, anon;
grant execute on function public.gv_cliente_nuevo_contacto_marcar(text,text,text) to authenticated, service_role;

-- ── 3) Lote del primer contacto ──────────────────────────────────────────────
create or replace function public.gv_cliente_nuevo_contacto_lote(p_pedidos jsonb)
returns table(empresa text, order_id text, primer_contacto_at timestamptz)
language sql stable security definer set search_path = public as $$
  select c.empresa, c.order_id, c.primer_contacto_at
  from public."GV_Clientes_Nuevos_Contacto" c
  join (select distinct lower(coalesce(e->>'empresa','lk')) empresa, nullif(trim(e->>'order_id'),'') order_id
          from jsonb_array_elements(coalesce(p_pedidos,'[]'::jsonb)) e) i
    on i.empresa = c.empresa and i.order_id = c.order_id
  where es_supervisor_virgilio() or gv_es_supervisor_o_servicio();
$$;
revoke all on function public.gv_cliente_nuevo_contacto_lote(jsonb) from public, anon;
grant execute on function public.gv_cliente_nuevo_contacto_lote(jsonb) to authenticated, service_role;

-- ── 4) Teléfono del CLIENTE (para abrir la conversación del Speech) ──────────
create or replace function public.gv_cliente_nuevo_wpp_lote(p_pedidos jsonb)
returns table(empresa text, cod text, telefono text)
language sql stable security definer set search_path = public as $$
  select i.empresa, i.cod, nullif(trim(wc.telefono),'') as telefono
  from (select distinct lower(coalesce(e->>'empresa','lk')) empresa, nullif(trim(e->>'cod'),'') cod
          from jsonb_array_elements(coalesce(p_pedidos,'[]'::jsonb)) e
         where nullif(trim(e->>'cod'),'') is not null) i
  join public.whatsapp_clientes wc on wc.cod_cliente = i.cod
  where (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
    and nullif(trim(wc.telefono),'') is not null;
$$;
revoke all on function public.gv_cliente_nuevo_wpp_lote(jsonb) from public, anon;
grant execute on function public.gv_cliente_nuevo_wpp_lote(jsonb) to authenticated, service_role;

-- ── 5) Monto: agregar valor_con_iva (21% plano — ver nota arriba) ────────────
-- Cambia el tipo de retorno → DROP + CREATE (create or replace no puede). Se revoca anon.
drop function if exists public.gv_clientes_nuevos_valor_lote(jsonb);
create function public.gv_clientes_nuevos_valor_lote(p_pedidos jsonb)
 returns table(order_id text, empresa text, valor numeric, valor_con_iva numeric)
 language sql security definer set search_path to 'public'
as $function$
  select nullif(trim(e->>'order_id'), '')          as order_id,
         lower(coalesce(e->>'empresa','lk'))        as empresa,
         round(public.gv_ppp_web_valor_items(
                 lower(coalesce(e->>'empresa','lk')),
                 nullif(trim(e->>'cod'), ''),
                 e->'items',
                 nullif(e->>'cond','')), 2)          as valor,
         round(public.gv_ppp_web_valor_items(
                 lower(coalesce(e->>'empresa','lk')),
                 nullif(trim(e->>'cod'), ''),
                 e->'items',
                 nullif(e->>'cond','')) * 1.21, 2)   as valor_con_iva
  from jsonb_array_elements(coalesce(p_pedidos, '[]'::jsonb)) e
  where (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
    and nullif(trim(e->>'order_id'), '') is not null;
$function$;
revoke all on function public.gv_clientes_nuevos_valor_lote(jsonb) from public, anon;
grant execute on function public.gv_clientes_nuevos_valor_lote(jsonb) to authenticated, service_role;
comment on function public.gv_clientes_nuevos_valor_lote(jsonb) is
  'v19.05 (Luis): monto por lista de cada pedido de Clientes nuevos. valor = neto con descuentos '
  '(gv_ppp_web_valor_items); valor_con_iva = valor * 1.21 (21% plano; precios_venta no guarda IVA '
  'por artículo). Gate supervisor; sin gate 0 filas.';

-- Chequeos:
--   select has_function_privilege('anon','public.gv_clientes_nuevos_valor_lote(jsonb)','EXECUTE');  -- false
--   select has_table_privilege('anon','public."GV_Clientes_Nuevos_Contacto"','SELECT');            -- false
