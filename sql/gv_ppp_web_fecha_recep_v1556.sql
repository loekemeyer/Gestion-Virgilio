-- v15.56 — PPP_Web_Programacion.fecha_recep no se llenaba, y sin ella el Resumen de la PPP
-- no puede calcular la Demora (promedio de fecha_entrega − fecha de recepción).
--
-- Causa: las DOS funciones que programan automáticamente escriben la tabla sin esa columna.
--   · ppp_web_armar_tandas        la calcula en su CTE `_sin_tanda` (la usa para ordenar por
--                                 antigüedad) pero NO la incluye en la lista del INSERT.
--   · gv_ppp_web_armar_pendientes (bloque a1) directamente no la menciona.
-- Medido antes del fix: 75 de 84 filas con fecha_recep NULL. Las 9 con dato son las que
-- guardó el front (`pppGuardarWeb`, que sí la manda).
--
-- Por qué un TRIGGER y no parchear las dos funciones: son 24 kB de plpgsql que corren en los
-- crons 71 y 73 (cada 15 min); un `create or replace` de cualquiera de las dos para agregar
-- una columna es mucho más riesgo que un BEFORE de tres líneas, y además el trigger cubre
-- CUALQUIER vía —las dos funciones, el front y lo que venga— en un solo lugar. La tabla es de
-- Gestión (`PPP_Web_*`), no la comparte Producción, y ya lleva dos triggers propios
-- (`trg_ppp_web_prog_touch`, `gv_web_cliente_un_solo_dia`), así que no aplica la prohibición
-- de triggers sobre tablas compartidas.
--
-- De dónde sale el dato: `lk_pedidos_match.fecha_pedido`, que LK empuja por FDW cada 15 min
-- (`sync_pedidos_match_virgilio`). Cubre las 75 de 75 por (empresa, order_id).
--
-- ROLLBACK:
--   drop trigger if exists gv_ppp_web_fecha_recep on public."PPP_Web_Programacion";
--   drop function if exists public.gv_ppp_web_fecha_recep();
--   -- y, si además se quiere deshacer el relleno:
--   update public."PPP_Web_Programacion" set fecha_recep = null
--    where (empresa, order_id, np_idx) in (select empresa, order_id, np_idx
--                                            from public."GV_Backup_FechaRecep_20260911"
--                                           where fecha_recep_old is null);

-- ── 1) Backup de la columna antes de tocarla ────────────────────────────────────────────
create table if not exists public."GV_Backup_FechaRecep_20260911" as
select empresa, order_id, np_idx, np, tanda, fecha_entrega,
       fecha_recep as fecha_recep_old, now() as respaldado_at
  from public."PPP_Web_Programacion";

alter table public."GV_Backup_FechaRecep_20260911" enable row level security;

-- ── 2) El trigger: si la fila entra sin fecha_recep, se resuelve contra lk_pedidos_match ──
create or replace function public.gv_ppp_web_fecha_recep()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  -- Sólo rellena: una fecha ya cargada (la que manda el front, o una corregida a mano) no se pisa.
  if new.fecha_recep is null then
    select m.fecha_pedido into new.fecha_recep
      from public.lk_pedidos_match m
     where m.empresa = new.empresa and m.order_id = new.order_id
     limit 1;   -- (empresa, order_id) es la clave de lk_pedidos_match: una fila por pedido
  end if;
  return new;
end;
$$;

drop trigger if exists gv_ppp_web_fecha_recep on public."PPP_Web_Programacion";
create trigger gv_ppp_web_fecha_recep
  before insert or update on public."PPP_Web_Programacion"
  for each row execute function public.gv_ppp_web_fecha_recep();

-- ── 3) Backfill de lo ya escrito (sólo NULL: no pisa ninguna fecha existente) ────────────
update public."PPP_Web_Programacion" g
   set fecha_recep = m.fecha_pedido
  from public.lk_pedidos_match m
 where g.fecha_recep is null
   and m.empresa = g.empresa and m.order_id = g.order_id
   and m.fecha_pedido is not null;

-- ── 4) Verificación ─────────────────────────────────────────────────────────────────────
-- select count(*) filter (where fecha_recep is null) as sin_recep, count(*) as total
--   from public."PPP_Web_Programacion";        -- esperado: 0 / 84
