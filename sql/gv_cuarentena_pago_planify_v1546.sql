-- v15.46 (2026-09-11) — Cuarentena: botón "Ya pagó" + tarea en el Planify de Viviana Gauna.
-- Pedidos de Thomas: "si hay uno en cuarentena, que le aparezca a Viviana Gauna en Planify" y
-- "agregame un botón en cada box que diga Ya pagó, para que Viviana los pueda habilitar".
-- Rollback al final del archivo.

-- ── 1. "Ya pagó" ──────────────────────────────────────────────────────────
create table if not exists public."GV_Cuarentena_Pagados" (
  empresa        text        not null,
  cod            text        not null,
  pagado_at      timestamptz not null default now(),
  pagado_por     text,
  fuente_at      timestamptz,   -- cargado_at del reporte de deuda vigente al momento del pago
  deuda_al_pagar numeric,
  primary key (empresa, cod)
);
alter table public."GV_Cuarentena_Pagados" enable row level security;   -- sin policies: sólo por RPC

create or replace function public.gv_cuarentena_pago(p_empresa text, p_cod text)
returns table(cod text, empresa text, deuda_al_pagar numeric, pedidos_liberados int)
language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_emp text := lower(nullif(btrim(p_empresa), ''));
  v_cod text := nullif(btrim(p_cod), '');
  v_at timestamptz; v_deuda numeric; v_n int := 0;
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Solo un supervisor puede marcar un cliente como pagado.' using errcode='42501';
  end if;
  if v_emp is null or v_cod is null then
    raise exception 'Falta empresa o codigo de cliente.' using errcode='22023';
  end if;
  select max(f.cargado_at) into v_at from public."GV_Cuarentena_Fuente" f
   where f.empresa = v_emp and f.tipo = 'deuda';
  select round(f.deuda, 2) into v_deuda from public."GV_Cuarentena_Fuente" f
   where f.empresa = v_emp and f.tipo = 'deuda' and f.cod = v_cod limit 1;
  insert into public."GV_Cuarentena_Pagados" (empresa, cod, pagado_at, pagado_por, fuente_at, deuda_al_pagar)
  values (v_emp, v_cod, now(), lower(coalesce(auth.jwt()->>'email','')), v_at, v_deuda)
  on conflict (empresa, cod) do update
    set pagado_at = now(), pagado_por = excluded.pagado_por,
        fuente_at = excluded.fuente_at, deuda_al_pagar = excluded.deuda_al_pagar;
  select count(*) into v_n from public."PPP_Web_Programacion" pw
   where pw.empresa = v_emp and pw.cod_cliente = v_cod and pw.tanda is null;
  return query select v_cod, v_emp, v_deuda, v_n;
end;
$function$;
revoke all on function public.gv_cuarentena_pago(text,text) from public, anon;
grant execute on function public.gv_cuarentena_pago(text,text) to authenticated, service_role;

-- En gv_cuarentena_marcar, el motivo 'deuda' (y su monto) llevan además:
--   and not exists (select 1 from public."GV_Cuarentena_Pagados" pg
--                    where pg.empresa = p.empresa and pg.cod = p.cod
--                      and pg.pagado_at >= coalesce(f.cargado_at, '-infinity'::timestamptz))
-- Definición completa en la base; la vieja (v15.04) es la misma sin ese bloque.

-- ── 2. la tarea de Viviana ────────────────────────────────────────────────
create table if not exists public."GV_Cuarentena_Planify" (
  empresa    text        not null,
  order_id   text        not null,
  task_id    bigint      not null,
  creada_at  timestamptz not null default now(),
  cerrada_at timestamptz,
  primary key (empresa, order_id)
);
alter table public."GV_Cuarentena_Planify" enable row level security;

-- gv_cuarentena_planify_sync(p_empresa, p_pedidos): alta de una tarea por pedido retenido en el
-- Planify de Viviana Gauna (employee_id 4) y cierre de las que ya no están en cuarentena.
-- Sólo service_role: la llama la Edge Function gv-ppp-web-tandas-diarias (crons 71 y 73).
-- Definición completa en la base.

-- ── rollback ──────────────────────────────────────────────────────────────
-- drop function public.gv_cuarentena_pago(text,text);
-- drop function public.gv_cuarentena_planify_sync(text,jsonb);
-- drop table public."GV_Cuarentena_Pagados", public."GV_Cuarentena_Planify";
-- volver gv_cuarentena_marcar a la v15.04 y sacar cuarYaPago del front.
