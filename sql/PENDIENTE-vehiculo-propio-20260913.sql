-- ============================================================================
-- PENDIENTE DE EJECUTAR — espera el "dale" de Thomas. NADA de esto se corrió.
-- v16.72 · 2026-09-13 · GV_Vehiculo_Propio: tandas que salen en vehículo PROPIO (la kangoo) y por eso
-- no ocupan camión de fletero en el cálculo de jornada (`_pppComputeErrors().jornadaDia`).
--
-- Caso real: E11A (Extralimp S.A., Luján, NP 98651, 0,745 m³, mié 16/09) salió en kangoo aparte
-- (Thomas, 11/09). Con esa tanda contada como camión, el 16/09 daba 17,0 h de camión / 8,5 h por
-- fletero (aviso "Día que no entra en la jornada"); sin ella, 11,3 h / 5,6 h — entra.
--
-- POR QUÉ UNA TABLA Y NO UNA COLUMNA `gv_vehiculo` EN PPP_Web_Programacion:
--   1. E11A es una tanda de ISIS: vive en GV_PPP_Programacion_Diaria (espejo, "se agrega, no se
--      modifica"), NO en PPP_Web_Programacion. Una columna en la tabla web ni siquiera la alcanzaría.
--   2. La marca es por TANDA (un vehículo lleva la tanda entera), no por pedido: 1 fila por tanda,
--      sin repetir el dato en cada NP y sin tocar ninguna tabla compartida.
--   3. Sirve para tandas de ISIS y web por igual, y el front la lee con un solo select.
--
-- QUÉ LA LEE: sólo el front (v16.72: `pppRefreshVehPropio` → `_pppVehPropio` → `_pppCamEsVehPropio`
--   en `_pppComputeErrors`). Si la tabla no existe (404) o el select falla/viene vacío, el front sigue
--   igual que hoy — por eso este archivo puede esperar sin que nada se rompa. Ninguna vista ni función
--   la usa todavía. Sin UI para marcar: se carga por SQL (la UI viene después).
--
-- RLS y grants: copiados de GV_Dias_No_Habiles (sql/gv_dias_no_habiles.sql): leen todos; escriben
--   supervisores (gv_es_supervisor_o_servicio(), existe) y service_role.
-- ============================================================================

create table if not exists public."GV_Vehiculo_Propio" (
  tanda      text primary key,                       -- código de tanda completo, mayúsculas: 'E11A'
  vehiculo   text not null default 'kangoo',         -- 'kangoo' | lo que sea (sólo se muestra)
  fecha      date,                                   -- día de entrega, informativo (la tanda ya tiene fecha)
  activo     boolean not null default true,          -- false = la marca no cuenta (sin borrar la historia)
  nota       text,
  creado_por text,
  creado_en  timestamptz not null default now()
);
comment on table public."GV_Vehiculo_Propio" is
  'v16.72: tandas que salen en vehículo propio (kangoo) y no ocupan camión de fletero en el cálculo de jornada de la PPP. La lee el front (pppRefreshVehPropio).';

alter table public."GV_Vehiculo_Propio" enable row level security;
drop policy if exists gv_vehiculo_propio_sel on public."GV_Vehiculo_Propio";
create policy gv_vehiculo_propio_sel on public."GV_Vehiculo_Propio" for select to anon, authenticated using (true);
drop policy if exists gv_vehiculo_propio_sup on public."GV_Vehiculo_Propio";
create policy gv_vehiculo_propio_sup on public."GV_Vehiculo_Propio" for all to authenticated
  using (public.gv_es_supervisor_o_servicio()) with check (public.gv_es_supervisor_o_servicio());
grant select on public."GV_Vehiculo_Propio" to anon, authenticated, service_role;
grant insert, update, delete on public."GV_Vehiculo_Propio" to authenticated, service_role;

-- la marca de la tanda E11 (Luján)
insert into public."GV_Vehiculo_Propio" (tanda, vehiculo, fecha, activo, nota, creado_por)
values ('E11A', 'kangoo', '2026-09-16', true,
        'Extralimp S.A. (Luján, NP 98651, 0,745 m3): salió en kangoo aparte, no en el camión Norte — Thomas 11/09',
        'claude v16.72')
on conflict (tanda) do update set vehiculo = excluded.vehiculo, fecha = excluded.fecha, activo = true, nota = excluded.nota;

-- verificación
select * from public."GV_Vehiculo_Propio";                                   -- 1 fila, E11A
-- (como lo pide el front — tiene que devolver la fila con la anon key)
--   GET /rest/v1/GV_Vehiculo_Propio?select=tanda,vehiculo&activo=eq.true
select tanda, vehiculo from public."GV_Vehiculo_Propio" where activo;
-- chequeo de CLAUDE.md: ninguna tabla de public sin RLS y escribible por anon
select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity
   and (has_table_privilege('anon', c.oid, 'INSERT') or has_table_privilege('anon', c.oid, 'UPDATE') or has_table_privilege('anon', c.oid, 'DELETE'));   -- vacío

-- Para marcar otra tanda:  insert into public."GV_Vehiculo_Propio" (tanda, vehiculo, fecha, nota, creado_por) values ('E23A', 'kangoo', '2026-09-18', 'motivo', 'quién');
-- Para desmarcar:          update public."GV_Vehiculo_Propio" set activo = false where tanda = 'E23A';

-- ROLLBACK:  drop table public."GV_Vehiculo_Propio";   (el front tolera que no exista)
