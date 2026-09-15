-- v18.65 (2026-09-15) — GV_Tandas_Lock: una tanda tomada no se vuelve a tomar hasta que se
-- ANULE o PASE a la etapa siguiente. Pedido de Luis.
--
-- ============================================================================================
-- Qué estaba mal
-- ============================================================================================
-- El lock existía (`Tandas_Lock` + `tanda_reservar`, atómico con ON CONFLICT DO NOTHING) pero
-- se soltaba solo por dos vías, y las dos dejan la puerta abierta:
--
--   1) **Vencía a las 10 horas.** `tanda_reservar` arranca con
--         DELETE FROM "Tandas_Lock" WHERE tanda=t AND fase=f AND ts < now() - interval '10 hours'
--      así que un picking abierto de ayer queda libre hoy aunque nadie lo haya cerrado.
--   2) **El TP lo soltaba.** Al terminar el picking se llamaba `tanda_liberar`, o sea que una
--      tanda YA PICKEADA quedaba libre y cualquiera podía volver a abrirle el picking.
--
-- De (2) salen los «EP fantasma»: alguien reabre una tanda ya terminada, casi siempre sin
-- querer. Medidos: **6 en 120 días**, 5 de ellos con el lock ya vencido y 1 apenas 0,8 h
-- después del TP (ése entró justamente porque el TP libera). Dos siguen abiertos desde julio
-- y agosto — C69C (legajo 104, reabierta 7 días después de que otro la cerrara) y D30A.
--
-- Y son peligrosos: `anular_picking_virgilio` pone en cero TODO el picking de la tanda
-- (`update Movimientos_Stock set delta = 0 where tipo='picking' and ref = tanda`), sin filtrar
-- por legajo ni por fecha. Anular un EP fantasma de D30A borraría los 36 movimientos del
-- picking bueno, que además ya está armado.
--
-- ============================================================================================
-- El modelo nuevo: la fase tiene ESTADO, no presencia
-- ============================================================================================
--   (tanda, fase) →  libre  →  'tomada'  →  'completada'
--                      ↑___________|______________|
--                         sólo por anulación explícita
--
--   · 'tomada'      la agarró alguien y está trabajando. Nadie más entra. NO vence por tiempo.
--   · 'completada'  la fase terminó (TP para picking, TAP para armado). Nadie la reabre.
--   · libre         nunca se tomó, o se anuló a propósito.
--
-- Con esto, el picking de una tanda terminada deja de ser reabrible (mata los EP fantasma) y
-- un picking abierto no se suelta solo (que era lo que permitía que otro la agarrara).
-- «Pasar a la etapa siguiente» es exactamente esto: al TP la fase *picking* queda completada y
-- la fase *armado* nace libre, lista para que alguien la tome.
--
-- ⚠ La salida de un lock trabado es la ANULACIÓN, que ya existe en la app: «Anular picking» y
-- «No la armo yo» (v18.50). Sin TTL, ésa es la única puerta — a propósito.
--
-- ============================================================================================
-- Por qué tabla NUEVA y no tocar `Tandas_Lock`
-- ============================================================================================
-- `Tandas_Lock` la comparte **Producción Virgilio**, que sigue viva (`index.html:6861` de ese
-- repo llama a `tanda_reservar`). Si Gestión escribiera en la misma tabla, la función VIEJA de
-- Producción seguiría aplicando su `DELETE ... < now() - 10 hours` y rompería el invariante
-- nuevo sin que nadie se entere.
-- Medido antes de decidir: Producción ya NO pickea — su último EP y su último AP son del
-- 09/09; lo que sigue mandando es recepción (RT, LT, ROC, PC, RSP). Así que separar las dos
-- tablas no le saca nada a nadie, y es reversible sin tocar Producción.

create table if not exists public."GV_Tandas_Lock" (
  tanda     text not null,
  fase      text not null,
  legajo    text,
  nombre    text,
  estado    text not null default 'tomada',
  ts        timestamptz not null default now(),   -- cuándo se tomó
  ts_estado timestamptz not null default now(),   -- último cambio de estado
  constraint gv_tandas_lock_pk primary key (tanda, fase),
  constraint gv_tandas_lock_fase   check (fase in ('picking','armado')),
  constraint gv_tandas_lock_estado check (estado in ('tomada','completada'))
);
alter table public."GV_Tandas_Lock" enable row level security;
-- El front no la lee directo (todo pasa por las RPC de abajo, que son SECURITY DEFINER),
-- pero el monitor sí necesita poder mirar quién tiene qué.
drop policy if exists gv_tandas_lock_read on public."GV_Tandas_Lock";
create policy gv_tandas_lock_read on public."GV_Tandas_Lock"
  for select to anon, authenticated using (true);

-- --------------------------------------------------------------------------------------------
-- RESERVAR — atómica. Devuelve jsonb: {ok, motivo, legajo, nombre, estado, desde}
--   ok=true   → la tanda es tuya (recién tomada, o ya la tenías y estás reanudando)
--   ok=false  → motivo 'tomada' (la tiene otro) o 'ya_completada' (la fase ya terminó)
-- --------------------------------------------------------------------------------------------
create or replace function public.gv_tanda_reservar(
  p_tanda text, p_fase text, p_legajo text, p_nombre text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  t text := upper(btrim(coalesce(p_tanda,'')));
  f text := lower(btrim(coalesce(p_fase,'')));
  l text := btrim(coalesce(p_legajo,''));
  r public."GV_Tandas_Lock";
begin
  if t = '' or f not in ('picking','armado') then
    return jsonb_build_object('ok', false, 'motivo', 'datos_invalidos');
  end if;
  -- El legajo de PRUEBA no reserva ni es bloqueado (mismo criterio que el resto de la app).
  if public.es_legajo_test(l) then
    return jsonb_build_object('ok', true, 'motivo', 'prueba');
  end if;

  -- Atómico: gana el primero. Si ya hay fila, no la pisa.
  insert into public."GV_Tandas_Lock" (tanda, fase, legajo, nombre, estado)
  values (t, f, nullif(l,''), nullif(btrim(coalesce(p_nombre,'')),''), 'tomada')
  on conflict (tanda, fase) do nothing;

  select * into r from public."GV_Tandas_Lock" where tanda = t and fase = f;

  if r.estado = 'completada' then
    -- La fase ya terminó. No se reabre sola: hay que anularla a propósito.
    return jsonb_build_object('ok', false, 'motivo', 'ya_completada',
      'legajo', r.legajo, 'nombre', r.nombre, 'estado', r.estado, 'desde', r.ts_estado);
  end if;

  if coalesce(r.legajo,'') = l or public.es_legajo_test(coalesce(r.legajo,'')) then
    -- es mía (o quedó un lock de prueba viejo): sigo trabajando
    return jsonb_build_object('ok', true, 'motivo', 'propia',
      'legajo', r.legajo, 'nombre', r.nombre, 'estado', r.estado, 'desde', r.ts);
  end if;

  return jsonb_build_object('ok', false, 'motivo', 'tomada',
    'legajo', r.legajo, 'nombre', r.nombre, 'estado', r.estado, 'desde', r.ts);
end $$;

-- --------------------------------------------------------------------------------------------
-- COMPLETAR — la fase terminó (TP / TAP). NO borra: deja 'completada' para que no se reabra.
-- --------------------------------------------------------------------------------------------
create or replace function public.gv_tanda_completar(p_tanda text, p_fase text, p_legajo text default null)
returns text language plpgsql security definer set search_path = public as $$
declare
  t text := upper(btrim(coalesce(p_tanda,'')));
  f text := lower(btrim(coalesce(p_fase,'')));
begin
  if t = '' or f not in ('picking','armado') then return 'datos_invalidos'; end if;
  insert into public."GV_Tandas_Lock" (tanda, fase, legajo, nombre, estado, ts_estado)
  values (t, f, nullif(btrim(coalesce(p_legajo,'')),''), null, 'completada', now())
  on conflict (tanda, fase) do update
     set estado = 'completada', ts_estado = now(),
         legajo = coalesce(public."GV_Tandas_Lock".legajo, excluded.legajo);
  return 'ok';
end $$;

-- --------------------------------------------------------------------------------------------
-- ANULAR EL LOCK — la tanda vuelve a estar LIBRE. La llaman anular_picking_virgilio y
-- anular_armado_virgilio. Es la única salida de 'completada', y es a propósito.
-- --------------------------------------------------------------------------------------------
create or replace function public.gv_tanda_lock_anular(p_tanda text, p_fase text, p_legajo text default null)
returns text language plpgsql security definer set search_path = public as $$
declare
  t text := upper(btrim(coalesce(p_tanda,'')));
  f text := lower(btrim(coalesce(p_fase,'')));
begin
  if t = '' or f not in ('picking','armado') then return 'datos_invalidos'; end if;
  delete from public."GV_Tandas_Lock" where tanda = t and fase = f;
  return 'ok';
end $$;

revoke execute on function public.gv_tanda_reservar(text,text,text,text) from public;
revoke execute on function public.gv_tanda_completar(text,text,text) from public;
revoke execute on function public.gv_tanda_lock_anular(text,text,text) from public;
grant execute on function public.gv_tanda_reservar(text,text,text,text) to anon, authenticated;
grant execute on function public.gv_tanda_completar(text,text,text)     to anon, authenticated;
grant execute on function public.gv_tanda_lock_anular(text,text,text)   to anon, authenticated;

-- ============================================================================================
-- BACKFILL — sin esto el invariante nace vacío y todas las tandas viejas quedan reabribles.
-- Se marca 'completada' cada fase que YA terminó (TP → picking, TAP → armado) en los últimos
-- 45 días, que es lo operable. Lo anterior no lo va a tocar nadie.
-- Las que quedaron TOMADAS y sin cerrar NO se backfillean a propósito: son las abandonadas de
-- hoy, y tienen que quedar libres para que mañana alguien las pueda agarrar.
-- ============================================================================================
insert into public."GV_Tandas_Lock" (tanda, fase, legajo, estado, ts, ts_estado)
select upper(btrim(split_part(r.texto,'|',1))),
       case when r.opcion = 'TP' then 'picking' else 'armado' end,
       (array_agg(r.legajo order by r.ts_cliente desc))[1],
       'completada', min(r.ts_cliente), max(r.ts_cliente)
  from public."Registros_Produccion_Virgilio" r
 where r.opcion in ('TP','TAP')
   and coalesce(btrim(r.texto),'') <> ''
   and not public.es_legajo_test(r.legajo)
   and r.ts_cliente >= now() - interval '45 days'
 group by 1, 2
on conflict (tanda, fase) do nothing;

-- Chequeo: cuántas fases quedaron marcadas y cuántas tandas siguen tomadas
--   select estado, fase, count(*) from public."GV_Tandas_Lock" group by 1,2 order by 1,2;
--
-- Rollback completo (no toca nada de Producción):
--   drop function public.gv_tanda_reservar(text,text,text,text);
--   drop function public.gv_tanda_completar(text,text,text);
--   drop function public.gv_tanda_lock_anular(text,text,text);
--   drop table public."GV_Tandas_Lock";
--   ... y en index.html volver `tandaReservar`/`tandaLiberar` a las RPC viejas.
