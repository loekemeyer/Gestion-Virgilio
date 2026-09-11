-- v15.85 — las OC de supermercados de Krikos se ven en "A Programar".
--
-- Pedido del dueño (2026-09-11): "yo quiero que se vea acá" (la pantalla A Programar de
-- Gestión), no sólo en la Bandeja del panel de LK.
--
-- ⚠ ESTO ES EL AVISO, NO LA CARGA. Una OC de Krikos NO es un pedido: no tiene NP, ni
-- artículos cargados en Gestión, ni m³, así que no se puede tildar ni meter en una tanda.
-- El dueño después pidió que además vayan "directo a PPP" — eso es otra cosa y NO está
-- hecho (ver el informe en el chat: el parser de PDF por cadena vive en admin-supercot.js).
--
-- POR QUÉ ESTE CAMINO: las OC viven en el proyecto Supabase de LK (krikos_oc_inbox) y
-- Virgilio NO tiene FDW contra LK — el FDW va al revés: LK lee y escribe en Virgilio
-- (schema virgilio.*, rol lk_ppp_reader). Así que se usa el MISMO patrón que
-- lk_pedidos_match: LK empuja acá. No se abre ninguna credencial ni FDW nuevo.

------------------------------------------------------------------------------
-- EN VIRGILIO (hrxfctzncixxqmpfhskv)
------------------------------------------------------------------------------
create table if not exists public."GV_Krikos_OC" (
  inbox_id      bigint primary key,             -- krikos_oc_inbox.id, del proyecto LK
  doc_id        text,
  nro_documento text,
  cadena        text,
  sucursal      text,
  direccion     text,
  fecha_entrega text,                           -- crudo dd/mm/yyyy [hh:mm], como lo manda el súper
  fecha_entrega_d date,                         -- parseada, para ordenar y marcar atrasadas
  link          text,
  tiene_pdf     boolean default false,
  estado        text,
  mail_fecha    timestamptz,
  actualizado_at timestamptz default now()
);

create index if not exists gv_krikos_oc_fecha_idx on public."GV_Krikos_OC" (fecha_entrega_d);

alter table public."GV_Krikos_OC" enable row level security;

-- el front la lee con la anon key (sólo lectura)
drop policy if exists gv_krikos_oc_lectura on public."GV_Krikos_OC";
create policy gv_krikos_oc_lectura on public."GV_Krikos_OC"
  for select to anon, authenticated using (true);

-- ⚠ RLS está prendida y lk_ppp_reader NO tiene BYPASSRLS: sin esta policy el sync de LK
-- insertaría 0 filas SIN DAR ERROR. Mismo par que lk_pedidos_match.
drop policy if exists gv_krikos_oc_writer on public."GV_Krikos_OC";
create policy gv_krikos_oc_writer on public."GV_Krikos_OC"
  for all to lk_ppp_reader using (true) with check (true);

grant select on public."GV_Krikos_OC" to anon, authenticated;
grant select, insert, update, delete on public."GV_Krikos_OC" to lk_ppp_reader;

------------------------------------------------------------------------------
-- EN LK (kwkclwhmoygunqmlegrg)
------------------------------------------------------------------------------
-- import foreign schema public limit to ("GV_Krikos_OC")
--   from server virgilio_db into virgilio;
--
-- create or replace function public.sync_krikos_oc_virgilio()
-- returns integer language plpgsql security definer set search_path to 'public' as $$
-- declare v_n integer;
-- begin
--   -- Espejo COMPLETO de lo pendiente: se vacía y se reescribe. Es chico (decenas de
--   -- filas) y así una OC que se carga o se descarta DESAPARECE sola del aviso.
--   delete from virgilio."GV_Krikos_OC";
--   insert into virgilio."GV_Krikos_OC"
--     (inbox_id, doc_id, nro_documento, cadena, sucursal, direccion,
--      fecha_entrega, fecha_entrega_d, link, tiene_pdf, estado, mail_fecha, actualizado_at)
--   select k.id, k.doc_id, k.nro_documento, k.cadena, k.sucursal, k.direccion,
--          k.fecha_entrega,
--          case when k.fecha_entrega ~ '^\d{2}/\d{2}/\d{4}'
--               then to_date(left(k.fecha_entrega, 10), 'DD/MM/YYYY') else null end,
--          k.link, k.storage_path is not null, k.estado, k.mail_fecha, now()
--     from public.krikos_oc_inbox k
--    where k.estado = 'pendiente' and k.order_id is null;
--   get diagnostics v_n = row_count;
--   return v_n;
-- end; $$;
--
-- select cron.schedule('krikos-oc-a-virgilio-10min', '5-59/10 * * * *',
--   $c$select public.sync_krikos_oc_virgilio();$c$);     -- jobid 42
--
-- (Aplicado como migración en LK: sync_krikos_oc_virgilio_v1583. Queda acá para que el
--  repo de Gestión tenga el cuadro completo: la mitad del puente vive en el otro proyecto.)

------------------------------------------------------------------------------
-- MEDICIÓN (la consulta que lo prueba, no "no debería afectar")
------------------------------------------------------------------------------
-- En LK:       select public.sync_krikos_oc_virgilio();   → 6
-- En Virgilio: select count(*) from public."GV_Krikos_OC"; → 6
--   (5 OC nuevas que aparecieron al ampliar la ventana del ingest de 30 a 90 días,
--    + la COTO 21881017093 reabierta a mano para la prueba del dueño.)
--   Las 6 en estado 'error' quedan AFUERA a propósito: sin PDF no se pueden cargar.

------------------------------------------------------------------------------
-- ROLLBACK
------------------------------------------------------------------------------
-- En LK:       select cron.unschedule('krikos-oc-a-virgilio-10min');
--              drop function if exists public.sync_krikos_oc_virgilio();
--              drop foreign table if exists virgilio."GV_Krikos_OC";
-- En Virgilio: drop table if exists public."GV_Krikos_OC";
-- Nada más lo lee: el bloque de A Programar simplemente deja de dibujarse.
