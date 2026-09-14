-- v17.74 (Luis, 2026-09-14) — BADGE DE HORARIO EN "A PROGRAMAR"
--
-- Pedido: *"para todos esos clientes (excepto Distribuidora GM) + CL 3905 Andser Química,
-- CL 1974 Rayabo S.A, CL 2533 Osa Distribuidora SRL + los clientes que marcan retirar, quiero que
-- cuando aparecen en la pestaña de A Programar tengan un badge con horario. Los pedidos de
-- clientes, actualmente, deberían viajar con día y horario de retiro preferido (por el cliente).
-- La persona que programa debería poder hacer click en ese badge y editar el día y horario
-- manualmente ahí. Y ese dato debería viajar con el pedido a Programación."*
-- Luis, sobre lo viejo: *"forward-facing todo, si se puede hacer un backfill lo vemos después."*
--
-- ── ¿LA PÁGINA MANDA EL HORARIO? SÍ, PERO TODAVÍA NO LLEGA ─────────────────────────────────
-- El checkout de `pagina-LK-copia` ya lo captura: `_esRetira()` → `_retiroSeleccion()` exige día
-- (≥ 3 días hábiles, lun–vie) y franja, y los manda como `retiro_fecha` / `retiro_franja` dentro
-- de `orders.sheets_payload`, además de anteponer `RETIRA dd/mm franja` a las observaciones.
-- ⚠ **Ese front no está deployado**: al 14/09, de **610 pedidos en 90 días, 0** traen la clave
-- `retiro_fecha` (y hubo 65 de retira). Por eso el badge arranca en "----" para todos. Cuando el
-- deploy llegue, empieza a aparecer solo: Gestión ya lo lee.
--
-- ── QUIÉN LLEVA BADGE ──────────────────────────────────────────────────────────────────────
-- Una sola pregunta, `gv_pide_horario(empresa, cod, zona)`:
--   · los súper con `pide_horario` — se agregó esa columna a `GV_Supers` y **Distribuidora GM
--     quedó en false**, que es la excepción que pidió Luis;
--   · los de `GV_Clientes_Horario` — los 3 aparte, **con su espejo de Chef del mismo CUIT**
--     (regla del dueño: *"el cod cliente no significa nada, sólo el CUIT vale"*):
--       Andser Química SRL  → LK 3905 + CH 2188   (CUIT 30681823154)
--       Rayabo S.A          → LK 1974 + CH 1253   (CUIT 30708595418)
--       Osa Distribuidora   → LK 2533 + CH 2340   (CUIT 30715175017)
--   · cualquiera cuya zona diga `retira`.
-- `gv_clientes_horario` es la vista que junta las dos listas y es lo que lee el front.
--
-- ── DÓNDE VIVE EL HORARIO ──────────────────────────────────────────────────────────────────
-- `GV_Pedido_Horario` (empresa, clave, np, fecha, franja, origen). La **clave** es la misma idea
-- que `gv_cuarentena_clave`: el `order_id` si el pedido vino de la página, la NP si es de ISIS —
-- así el dato no se pierde cuando el pedido pasa de A Programar a Programación y recibe su NP.
-- `origen` = `cliente` (lo eligió en el checkout) | `manual` (lo puso el que programa; pisa al otro).
-- Se escribe sólo por `gv_pedido_horario_set` / `gv_pedido_horario_borrar`.
--
-- `gv_ppp_prog_arbol` suma 5 columnas — `clave`, `pide_horario`, `horario_fecha`, `horario_franja`,
-- `horario_origen` — así el horario viaja con el pedido hasta la tabla de Programación.
-- ⚠ Esa función hubo que **dropearla y recrearla** (Postgres no deja cambiar el tipo de retorno
-- con `create or replace`); no le cuelga ninguna vista, sólo la llama el front por RPC.
--
-- ⚠ Virgilio **no tiene FDW contra LK**, así que el merge de las dos fuentes (lo del cliente vive
-- en LK, lo manual en Virgilio) lo hace el front. Lo que se EDITA va siempre a Virgilio, que es lo
-- que lee el árbol. Si algún día se arma el FDW, el merge se puede mudar acá.

-- ── 1) un súper puede no pedir horario ─────────────────────────────────────────────────────
alter table public."GV_Supers" add column if not exists pide_horario boolean not null default true;
update public."GV_Supers" set pide_horario = false where super_key = 'gm';

-- ── 2) los que NO son súper pero coordinan horario igual ────────────────────────────────────
create table if not exists public."GV_Clientes_Horario" (
  empresa        text not null check (empresa in ('lk','chef')),
  cod            text not null,
  cuit           text,
  nombre         text not null,
  activo         boolean not null default true,
  nota           text,
  creado_at      timestamptz not null default now(),
  actualizado_at timestamptz not null default now(),
  actualizado_por text,
  primary key (empresa, cod)
);
alter table public."GV_Clientes_Horario" enable row level security;
drop policy if exists gv_clientes_horario_lectura on public."GV_Clientes_Horario";
create policy gv_clientes_horario_lectura on public."GV_Clientes_Horario" for select to anon, authenticated using (true);
grant select on public."GV_Clientes_Horario" to anon, authenticated;
revoke insert, update, delete, truncate on public."GV_Clientes_Horario" from anon, authenticated;

insert into public."GV_Clientes_Horario" (empresa, cod, cuit, nombre, nota, actualizado_por) values
 ('lk'  ,'3905','30681823154','Andser Quimica SRL'    ,'pedido de Luis'             ,'claude v17.74'),
 ('chef','2188','30681823154','Andser Quimica SRL'    ,'espejo Chef del mismo CUIT' ,'claude v17.74'),
 ('lk'  ,'1974','30708595418','Rayabo S.A'            ,'pedido de Luis'             ,'claude v17.74'),
 ('chef','1253','30708595418','Rayabo S.A'            ,'espejo Chef del mismo CUIT' ,'claude v17.74'),
 ('lk'  ,'2533','30715175017','Osa Distribuidora SRL' ,'pedido de Luis'             ,'claude v17.74'),
 ('chef','2340','30715175017','Osa Distribuidora SRL' ,'espejo Chef del mismo CUIT' ,'claude v17.74')
on conflict (empresa, cod) do nothing;

-- ── 3) LA pregunta ─────────────────────────────────────────────────────────────────────────
create or replace function public.gv_pide_horario(p_empresa text, p_cod text, p_zona text default null)
returns boolean language sql stable parallel safe
set search_path to 'public','pg_temp' as $$
  select coalesce(btrim(coalesce(p_zona,'')) ~* 'retira', false)
      or exists (select 1 from public."GV_Supers" s
                  where s.activo and s.pide_horario
                    and s.empresa = public.gv_emp_norm(p_empresa)
                    and s.cod = regexp_replace(btrim(coalesce(p_cod,'')), '\.0+$', ''))
      or exists (select 1 from public."GV_Clientes_Horario" h
                  where h.activo
                    and h.empresa = public.gv_emp_norm(p_empresa)
                    and h.cod = regexp_replace(btrim(coalesce(p_cod,'')), '\.0+$', ''));
$$;
create or replace function public.gv_pide_horario_np(p_np text, p_cod text, p_zona text default null)
returns boolean language sql stable parallel safe
set search_path to 'public','pg_temp' as $$
  select public.gv_pide_horario(public.gv_emp_de_np(p_np), p_cod, p_zona);
$$;
grant execute on function public.gv_pide_horario(text,text,text), public.gv_pide_horario_np(text,text,text)
  to anon, authenticated;

create or replace view public.gv_clientes_horario
with (security_invoker = true) as
select empresa, cod, cuit, nombre, 'super'::text as origen, nota, activo
  from public."GV_Supers" where activo and pide_horario
union all
select empresa, cod, cuit, nombre, 'cliente', nota, activo
  from public."GV_Clientes_Horario" where activo;
grant select on public.gv_clientes_horario to anon, authenticated;

-- ── 4) el horario de cada pedido ───────────────────────────────────────────────────────────
create table if not exists public."GV_Pedido_Horario" (
  empresa        text not null check (empresa in ('lk','chef')),
  clave          text not null,   -- order_id si vino de la página, NP si es de ISIS
  np             text,
  fecha          date,
  franja         text,
  origen         text not null default 'manual' check (origen in ('cliente','manual')),
  creado_at      timestamptz not null default now(),
  actualizado_at timestamptz not null default now(),
  actualizado_por text,
  primary key (empresa, clave)
);
alter table public."GV_Pedido_Horario" enable row level security;
drop policy if exists gv_pedido_horario_lectura on public."GV_Pedido_Horario";
create policy gv_pedido_horario_lectura on public."GV_Pedido_Horario" for select to anon, authenticated using (true);
grant select on public."GV_Pedido_Horario" to anon, authenticated;
revoke insert, update, delete, truncate on public."GV_Pedido_Horario" from anon, authenticated;

create or replace function public.gv_pedido_horario_set(
  p_empresa text, p_clave text, p_fecha date, p_franja text,
  p_np text default null, p_origen text default 'manual', p_por text default null)
returns public."GV_Pedido_Horario" language plpgsql security definer
set search_path to 'public','pg_temp' as $$
declare v_emp text; v_cl text; out public."GV_Pedido_Horario";
begin
  v_emp := public.gv_emp_norm(p_empresa);
  v_cl  := regexp_replace(btrim(coalesce(p_clave,'')), '\.0+$', '');
  if v_cl = '' then raise exception 'Falta la clave del pedido'; end if;
  if p_fecha is null and nullif(btrim(coalesce(p_franja,'')),'') is null then
    delete from public."GV_Pedido_Horario" where empresa = v_emp and clave = v_cl;
    return null;   -- vaciar los dos campos = sacar el horario
  end if;
  insert into public."GV_Pedido_Horario" (empresa, clave, np, fecha, franja, origen, actualizado_por)
  values (v_emp, v_cl, nullif(btrim(coalesce(p_np,'')),''), p_fecha,
          nullif(btrim(coalesce(p_franja,'')),''),
          case when p_origen = 'cliente' then 'cliente' else 'manual' end, p_por)
  on conflict (empresa, clave) do update
     set fecha = excluded.fecha, franja = excluded.franja, origen = excluded.origen,
         np = coalesce(excluded.np, public."GV_Pedido_Horario".np),
         actualizado_at = now(), actualizado_por = excluded.actualizado_por
  returning * into out;
  return out;
end $$;

create or replace function public.gv_pedido_horario_borrar(p_empresa text, p_clave text, p_por text default null)
returns void language sql security definer
set search_path to 'public','pg_temp' as $$
  delete from public."GV_Pedido_Horario"
   where empresa = public.gv_emp_norm(p_empresa)
     and clave = regexp_replace(btrim(coalesce(p_clave,'')), '\.0+$', '');
$$;
revoke all on function public.gv_pedido_horario_set(text,text,date,text,text,text,text) from public;
revoke all on function public.gv_pedido_horario_borrar(text,text,text) from public;
grant execute on function public.gv_pedido_horario_set(text,text,date,text,text,text,text) to anon, authenticated;
grant execute on function public.gv_pedido_horario_borrar(text,text,text) to anon, authenticated;

-- ── 5) EN EL PROYECTO DE LK (kwkclwhmoygunqmlegrg) ─────────────────────────────────────────
-- Vista NUEVA, no toca ninguna existente. Hoy devuelve 0 filas; cuando el front de la página esté
-- deployado empieza a traer el día y la franja que eligió el cliente.
--
--   create or replace view public.gv_pedidos_web_retiro
--   with (security_invoker = true) as
--   select o.id as order_id, 'lk'::text as empresa,
--          nullif(btrim(o.sheets_payload->>'retiro_fecha'), '')::date  as retiro_fecha,
--          nullif(btrim(o.sheets_payload->>'retiro_franja'), '')       as retiro_franja,
--          o.created_at
--     from public.orders o
--    where o.sheets_payload ? 'retiro_fecha'
--      and nullif(btrim(coalesce(o.sheets_payload->>'retiro_fecha','')), '') is not null;
--   grant select on public.gv_pedidos_web_retiro to anon, authenticated;

-- ── 6) gv_ppp_prog_arbol: 5 columnas nuevas ────────────────────────────────────────────────
-- El CREATE completo está en `sql/gv_ppp_prog_arbol_v1766.sql` (se actualizó ahí).

-- ── MEDICIÓN (14/09) ───────────────────────────────────────────────────────────────────────
-- · `gv_clientes_horario` = 24 filas (18 súper con horario + 6 de la lista aparte).
-- · `gv_pide_horario`: Coto → true · Distribuidora GM (LK 4080) → **false** · Andser (LK 3905) →
--   true · Osa (LK 2533) → true · zona "Retira en depósito" → true · un cliente común → false.
-- · En el árbol (hoy −180 / +120 días): **186 NP con badge** = 160 súper + 2 retira + 24 de los 3.
--   Los totales del árbol NO cambiaron: 2.237 NP y 762,13 m³, iguales a `gv_ppp_avance_dias`.
-- · Circuito probado de punta a punta: `gv_pedido_horario_set` sobre una NP de ISIS (98426) y sobre
--   un pedido web (order_id 1388) → los dos salen por `gv_ppp_prog_arbol` con su fecha, franja y
--   origen. Las filas de prueba se borraron (`GV_Pedido_Horario` quedó en 0).
-- · En LK: `gv_pedidos_web_retiro` = 0 filas (el front que las graba no está deployado).

-- ── ROLLBACK ───────────────────────────────────────────────────────────────────────────────
-- 1) En el front, sacar `aprHorBadge(p)` de las dos fichas y el bloque del badge.
-- 2) Recrear `gv_ppp_prog_arbol` sin las 5 columnas (versión del commit v17.72).
-- 3) drop function if exists public.gv_pedido_horario_set(text,text,date,text,text,text,text),
--      public.gv_pedido_horario_borrar(text,text,text),
--      public.gv_pide_horario_np(text,text,text), public.gv_pide_horario(text,text,text);
--    drop view if exists public.gv_clientes_horario;
--    drop table if exists public."GV_Pedido_Horario", public."GV_Clientes_Horario";
--    alter table public."GV_Supers" drop column if exists pide_horario;
-- 4) En LK: drop view if exists public.gv_pedidos_web_retiro;
