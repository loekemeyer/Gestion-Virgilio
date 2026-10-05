-- v26.69 (Luis, 05/10/2026): «Pedidos Entregados» muestra la FECHA EN QUE LLEGÓ EL PEDIDO
-- DEL CLIENTE (no la de programación). De todo lo que tenga dato, y forward-facing.
--
--   Luis: "en pedidos entregados quiero que figure la fecha de cuando se cargaron los
--   pedidos. de todos los que tengas datos ponele y fowardfacing. sería la fecha de cuando
--   nos llegaron los pedidos de los clientes, no necesariamente de cuando se programaron"
--
-- Fuentes, medidas el 05/10 contra los 1.473 entregados de vista_ppp_pedidos_entregados:
--   · NP web (194): lk_pedidos_match.fecha_pedido + hora_pedido (el momento en que el cliente
--     mandó el pedido por la página), por (empresa, order_id). Fallback
--     PPP_Web_Programacion.fecha_recep (igual a fecha_pedido en 363 de 363 que tienen las dos).
--   · NP de ISIS: GV_PPP_Programacion_Diaria.fecha_recep (la «Fecha Recep» de la PPP) y, si no,
--     GV_PPP_Base_Pedidos.fecha (= fecha_recep en 132 de 133). Cubre las ISIS del 23/06 al 04/09:
--     818 de 1.279. Las anteriores al 23/06 NO tienen dato en ningún lado: quedan sin fecha.
--
-- Por qué una TABLA y no una vista: las dos fuentes de ISIS son espejos que se reescriben y
-- la programación web se poda; lo que se captura acá queda (insert … on conflict do nothing).
-- El cron gv-np-fecha-pedido (59 * * * *, minuto impar libre) captura lo nuevo cada hora.
--
-- Lectura: anon / authenticated SELECT (NP + fecha + hora, nada sensible). Escritura: sólo la
-- función (SECURITY DEFINER).

create table if not exists public."GV_NP_Fecha_Pedido" (
  np            text primary key,           -- la etiqueta que usan los entregados: 'LK 0101', '98615'
  empresa       text,                       -- 'lk' | 'chef'
  fecha_pedido  date not null,              -- cuándo LLEGÓ el pedido del cliente
  hora_pedido   text,                       -- HH:MM:SS (sólo web)
  origen        text not null,              -- 'web' | 'isis_prog' | 'isis_base'
  order_id      bigint,                     -- pedido de la página (web)
  capturado_at  timestamptz not null default now()
);
alter table public."GV_NP_Fecha_Pedido" enable row level security;
revoke insert, update, delete, truncate on public."GV_NP_Fecha_Pedido" from anon, authenticated;
grant select on public."GV_NP_Fecha_Pedido" to anon, authenticated;
drop policy if exists gv_np_fecha_pedido_lectura on public."GV_NP_Fecha_Pedido";
create policy gv_np_fecha_pedido_lectura on public."GV_NP_Fecha_Pedido" for select to anon, authenticated using (true);

create or replace function public.gv_np_fecha_pedido_capturar()
returns integer
language plpgsql
security definer
set search_path = public
as $fn$
declare n int := 0; k int;
begin
  -- (1) NP web: la fecha y la hora en que el cliente mandó el pedido por la página
  with w as (
    select distinct on (lbl) lbl, p.empresa, coalesce(m.fecha_pedido, p.fecha_recep) f, nullif(m.hora_pedido, '') h, p.order_id
      from (select pw.*, public.gv_ppp_web_np_label(pw.empresa, pw.np, pw.np_idx) lbl
              from public."PPP_Web_Programacion" pw where pw.np is not null) p
      left join public.lk_pedidos_match m on m.empresa = p.empresa and m.order_id = p.order_id
     where coalesce(m.fecha_pedido, p.fecha_recep) is not null and lbl is not null
     order by lbl, m.fecha_pedido nulls last
  ), ins as (
    insert into public."GV_NP_Fecha_Pedido" (np, empresa, fecha_pedido, hora_pedido, origen, order_id)
    select lbl, empresa, f, h, 'web', order_id from w
    on conflict (np) do update set hora_pedido = excluded.hora_pedido
     where "GV_NP_Fecha_Pedido".hora_pedido is null and excluded.hora_pedido is not null
    returning 1
  ) select count(*) into k from ins;
  n := n + k;

  -- (2) NP de ISIS: la «Fecha Recep» de la PPP (gana sobre la base: 98704 difiere y la PPP es la explícita)
  with i as (
    select distinct on (np) btrim(np) np, left(fecha_recep, 10)::date f
      from public."GV_PPP_Programacion_Diaria"
     where btrim(coalesce(np, '')) ~ '^[0-9]+$' and fecha_recep ~ '^\d{4}-\d{2}-\d{2}'
     order by np, fecha_recep
  ), ins as (
    insert into public."GV_NP_Fecha_Pedido" (np, empresa, fecha_pedido, origen)
    select np, case when np::bigint > 90000 then 'lk' else 'chef' end, f, 'isis_prog' from i
    on conflict (np) do nothing
    returning 1
  ) select count(*) into k from ins;
  n := n + k;

  -- (3) NP de ISIS que ya no está en la PPP: la fecha de la base de pedidos (espejo del Sheet)
  with b as (
    select btrim(pedido) np, min(left(fecha, 10))::date f
      from public."GV_PPP_Base_Pedidos"
     where btrim(coalesce(pedido, '')) ~ '^[0-9]+$' and fecha ~ '^\d{4}-\d{2}-\d{2}'
     group by btrim(pedido)
  ), ins as (
    insert into public."GV_NP_Fecha_Pedido" (np, empresa, fecha_pedido, origen)
    select np, case when np::bigint > 90000 then 'lk' else 'chef' end, f, 'isis_base' from b
    on conflict (np) do nothing
    returning 1
  ) select count(*) into k from ins;
  n := n + k;

  return n;
end
$fn$;
revoke all on function public.gv_np_fecha_pedido_capturar() from public, anon, authenticated;

-- backfill + cron (idempotentes)
select public.gv_np_fecha_pedido_capturar();
select cron.schedule('gv-np-fecha-pedido', '59 * * * *', 'select public.gv_np_fecha_pedido_capturar()');

-- Chequeo:
--   select origen, count(*), min(fecha_pedido), max(fecha_pedido) from public."GV_NP_Fecha_Pedido" group by 1;
--   cuántos entregados tienen fecha:
--   select count(*), count(f.np) from (select np from public.vista_ppp_pedidos_entregados
--     union select np from public.gv_ppp_entregados) e left join public."GV_NP_Fecha_Pedido" f using (np);
--
-- Rollback:
--   select cron.unschedule('gv-np-fecha-pedido');
--   drop function if exists public.gv_np_fecha_pedido_capturar();
--   drop table if exists public."GV_NP_Fecha_Pedido";
