-- v31.44 (Luis, 16/10/2026): "Quiero que quede un registro referenciable. una tabla o algo".
--
--   select * from public."GV_NP_Remito_Estado" order by actualizado_at desc;
--
-- UNA fila por NP con el estado de su remito. No hay una tabla madre de NP que cubra ISIS + web
-- (PPP_Programacion_Diaria es por día, PPP_Web_Programacion sólo web, GV_NP_Remito sólo las ISIS
-- con remito resuelto), así que el estado va en una tabla propia, con la NP como clave.
--
-- La FUENTE sigue siendo el log Registros_Produccion_Virgilio; esta tabla es DERIVADA y se recalcula
-- sola por trigger en cada CCN / CRN / FSS (alta, cambio o baja). gv_np_remito_estado_recalc(np)
-- recalcula una NP desde cero (idempotente), así que nunca acumula error.
--
--   estado            'en_camion'  = último evento es la carga al camión (CCN), falta el control
--                     'controlado' = último evento es Recepción Remitos → «Terminé» (CRN) = ENTREGADO
--                     'volvio'     = último evento es «↩ s/salida» (FSS) = volvió al depósito
--   cargado_at / fletero / vuelta   del ÚLTIMO CCN
--   controlado_at / controlado_legajo  del PRIMER CRN (cuándo se entregó, mismo criterio que
--                     gv_remitos_controlados y el bot de WhatsApp)
--   volvio_at / volvio_legajo       del ÚLTIMO FSS
--   tanda             la del último evento que la trae
--   veces_cargado / veces_controlado / veces_volvio   cantidad de eventos de cada tipo

create table if not exists public."GV_NP_Remito_Estado" (
  np                 text primary key,
  estado             text not null check (estado in ('en_camion', 'controlado', 'volvio')),
  tanda              text,
  cargado_at         timestamptz,
  fletero            text,
  vuelta             text,
  controlado_at      timestamptz,
  controlado_legajo  text,
  volvio_at          timestamptz,
  volvio_legajo      text,
  veces_cargado      integer not null default 0,
  veces_controlado   integer not null default 0,
  veces_volvio       integer not null default 0,
  actualizado_at     timestamptz not null default now()
);
comment on table public."GV_NP_Remito_Estado" is
  'Estado del remito por NP (en_camion / controlado / volvio). DERIVADA de Registros_Produccion_Virgilio (CCN, CRN, FSS) por trigger; recalcular una NP con gv_np_remito_estado_recalc(np). v31 (Luis, 16/10/2026).';
alter table public."GV_NP_Remito_Estado" enable row level security;
revoke all on public."GV_NP_Remito_Estado" from anon;
grant select on public."GV_NP_Remito_Estado" to authenticated;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'GV_NP_Remito_Estado'
                 and policyname = 'lectura_authenticated') then
    create policy lectura_authenticated on public."GV_NP_Remito_Estado" for select to authenticated using (true);
  end if;
end $$;
create index if not exists gv_np_remito_estado_estado_idx on public."GV_NP_Remito_Estado" (estado, actualizado_at desc);

-- búsqueda por NP normalizada en el log (para que el recálculo por NP no recorra todos los eventos)
create index if not exists idx_rpv_remito_np on public."Registros_Produccion_Virgilio"
  (regexp_replace(upper(btrim(split_part(texto, '|', 1))), '\.0+$', ''))
  where opcion in ('CCN', 'CRN', 'FSS');

create or replace function public.gv_np_remito_estado_recalc(p_np text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_np text := regexp_replace(upper(btrim(coalesce(p_np, ''))), '\.0+$', '');
  x record;
begin
  if v_np = '' then return; end if;
  with ev as (
    select r.opcion, btrim(r.legajo) as legajo, r.ts_cliente,
           nullif(btrim(split_part(r.texto, '|', 2)), '') as tanda,
           nullif(btrim(split_part(r.texto, '|', 3)), '') as fletero,
           nullif(btrim(split_part(r.texto, '|', 4)), '') as vuelta
      from public."Registros_Produccion_Virgilio" r
     where r.opcion in ('CCN', 'CRN', 'FSS')
       and regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', '') = v_np
       and not public.es_legajo_test(r.legajo)
  )
  select
    (select e.opcion from ev e order by e.ts_cliente desc limit 1)                        as ult_op,
    (select e.tanda from ev e where e.tanda is not null order by e.ts_cliente desc limit 1) as tanda,
    (select max(e.ts_cliente) from ev e where e.opcion = 'CCN')                             as cargado_at,
    (select e.fletero from ev e where e.opcion = 'CCN' order by e.ts_cliente desc limit 1)  as fletero,
    (select e.vuelta  from ev e where e.opcion = 'CCN' order by e.ts_cliente desc limit 1)  as vuelta,
    (select min(e.ts_cliente) from ev e where e.opcion = 'CRN')                             as controlado_at,
    (select e.legajo from ev e where e.opcion = 'CRN' order by e.ts_cliente limit 1)        as controlado_legajo,
    (select max(e.ts_cliente) from ev e where e.opcion = 'FSS')                             as volvio_at,
    (select e.legajo from ev e where e.opcion = 'FSS' order by e.ts_cliente desc limit 1)   as volvio_legajo,
    (select count(*) from ev e where e.opcion = 'CCN')::int                                 as n_ccn,
    (select count(*) from ev e where e.opcion = 'CRN')::int                                 as n_crn,
    (select count(*) from ev e where e.opcion = 'FSS')::int                                 as n_fss
  into x;

  if x.ult_op is null then
    -- sin eventos (se borraron todos): la NP sale de la tabla
    delete from public."GV_NP_Remito_Estado" where np = v_np;
    return;
  end if;

  insert into public."GV_NP_Remito_Estado" as t
    (np, estado, tanda, cargado_at, fletero, vuelta, controlado_at, controlado_legajo,
     volvio_at, volvio_legajo, veces_cargado, veces_controlado, veces_volvio, actualizado_at)
  values (v_np,
          case x.ult_op when 'CRN' then 'controlado' when 'FSS' then 'volvio' else 'en_camion' end,
          x.tanda, x.cargado_at, x.fletero, x.vuelta, x.controlado_at, x.controlado_legajo,
          x.volvio_at, x.volvio_legajo, x.n_ccn, x.n_crn, x.n_fss, now())
  on conflict (np) do update set
    estado = excluded.estado, tanda = excluded.tanda, cargado_at = excluded.cargado_at,
    fletero = excluded.fletero, vuelta = excluded.vuelta, controlado_at = excluded.controlado_at,
    controlado_legajo = excluded.controlado_legajo, volvio_at = excluded.volvio_at,
    volvio_legajo = excluded.volvio_legajo, veces_cargado = excluded.veces_cargado,
    veces_controlado = excluded.veces_controlado, veces_volvio = excluded.veces_volvio,
    actualizado_at = now();
end $$;
comment on function public.gv_np_remito_estado_recalc(text) is
  'Recalcula desde cero la fila de GV_NP_Remito_Estado de una NP a partir de los eventos CCN/CRN/FSS. Idempotente. v31.';
revoke all on function public.gv_np_remito_estado_recalc(text) from public, anon, authenticated;

create or replace function public.trg_gv_np_remito_estado()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if tg_op in ('UPDATE', 'DELETE') and old.opcion in ('CCN', 'CRN', 'FSS') then
    perform public.gv_np_remito_estado_recalc(split_part(old.texto, '|', 1));
  end if;
  if tg_op in ('INSERT', 'UPDATE') and new.opcion in ('CCN', 'CRN', 'FSS') then
    perform public.gv_np_remito_estado_recalc(split_part(new.texto, '|', 1));
  end if;
  return null;
exception when others then
  -- nunca frenar el registro del operario por esta tabla derivada
  raise warning 'trg_gv_np_remito_estado: %', sqlerrm;
  return null;
end $$;

-- alta y cambio (la app hace upsert de CRN/CCN por id)
create or replace trigger trg_gv_np_remito_estado
  after insert or update of opcion, texto, ts_cliente, legajo on public."Registros_Produccion_Virgilio"
  for each row execute function public.trg_gv_np_remito_estado();
-- baja de un evento
create or replace trigger trg_gv_np_remito_estado_baja
  after delete on public."Registros_Produccion_Virgilio"
  for each row when (old.opcion in ('CCN', 'CRN', 'FSS'))
  execute function public.trg_gv_np_remito_estado();

-- carga inicial: todas las NP con algún CCN / CRN / FSS
do $$
declare v text;
begin
  for v in select distinct regexp_replace(upper(btrim(split_part(texto, '|', 1))), '\.0+$', '')
             from public."Registros_Produccion_Virgilio"
            where opcion in ('CCN', 'CRN', 'FSS') and btrim(split_part(texto, '|', 1)) <> ''
  loop
    perform public.gv_np_remito_estado_recalc(v);
  end loop;
end $$;
