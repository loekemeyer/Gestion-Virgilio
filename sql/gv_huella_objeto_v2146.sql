-- v21.46 · CENTINELA DE HUELLA — `GV_Huella_Objeto` + `gv_huellas_cambiadas`
--
-- Thomas, 2026-09-23, sobre el hueco que dejaba `tests/mon-vs-vista.cjs`: *"si al
-- centinela"*.
--
-- ⚠ EL PROBLEMA QUE TAPA, Y NO ES EL MISMO QUE `gv_reglas_perdidas`:
--
--   | centinela               | qué contesta                          | qué NO ve                      |
--   |-------------------------|---------------------------------------|--------------------------------|
--   | `gv_reglas_perdidas`    | ¿el PATRÓN sigue en el cuerpo?        | que el patrón siga y la CUENTA |
--   |                         |                                       | haya cambiado                  |
--   | `gv_huellas_cambiadas`  | ¿el cuerpo es EXACTAMENTE el mismo?   | nada del cuerpo — pero salta   |
--   |                         |                                       | también por un comentario      |
--
-- Son complementarios: el primero dice QUÉ se perdió, el segundo dice QUE CAMBIÓ.
--
-- ⚠ Existe por una razón concreta: `tests/mon-vs-vista.cjs` compara el monitor grande
-- (JS, que corre de verdad) contra `tests/tools/vista-15.json`, que es una FOTO de
-- `gv_monitor_horas_operario_dia('2026-09-15')`. Las sesiones no pueden pegarle a
-- Supabase, así que esa mitad va congelada. Si alguien le cambia una regla a la
-- función, el JSON no se mueve y **el test queda verde y miente**. Esta vista es la
-- que avisa que hay que volver a congelarlo.
--
-- Al cambiar la función A PROPÓSITO son dos pasos, y el segundo lo dicta la vista:
--   1. volver a congelar `tests/tools/vista-15.json` (cómo, adentro del JSON);
--   2. `update public."GV_Huella_Objeto" set md5_esperado = '<el que imprime la vista>',
--       version = '<vNN.NN>', actualizado_en = now() where objeto = '<el objeto>';`

create table if not exists public."GV_Huella_Objeto" (
  objeto         text not null,
  clase          text not null default 'funcion' check (clase in ('funcion','vista')),
  md5_esperado   text not null,
  por_que        text not null,
  quien_pidio    text,
  version        text,
  activo         boolean not null default true,
  actualizado_en timestamptz not null default now(),
  primary key (objeto, clase)
);

comment on table public."GV_Huella_Objeto" is
  'Objetos cuyo cuerpo está ESPEJADO afuera de la base (un fixture congelado de un test, '
  'una copia en el repo). Guarda el md5 esperado; gv_huellas_cambiadas avisa cuando el '
  'cuerpo vivo dejó de coincidir. Complementa gv_reglas_perdidas, que mira patrones.';

alter table public."GV_Huella_Objeto" enable row level security;
revoke insert, update, delete, truncate on public."GV_Huella_Objeto" from anon, authenticated;

create or replace view public.gv_huellas_cambiadas as
select h.objeto,
       h.clase,
       case when x.cuerpo is null then 'EL OBJETO NO EXISTE'
            else 'EL CUERPO CAMBIO: hay que re-congelar lo que lo espeja y actualizar el md5' end as que_paso,
       h.por_que,
       h.md5_esperado,
       md5(x.cuerpo)   as md5_actual,
       h.version       as version_congelada,
       h.actualizado_en
  from public."GV_Huella_Objeto" h
  left join lateral (
    select case when h.clase = 'vista'
                then (select pg_get_viewdef(c.oid, true) from pg_class c
                        join pg_namespace n on n.oid = c.relnamespace
                       where n.nspname = 'public' and c.relname = h.objeto
                         and c.relkind in ('v','m'))
                else (select p.prosrc from pg_proc p
                        join pg_namespace n on n.oid = p.pronamespace
                       where n.nspname = 'public' and p.proname = h.objeto limit 1)
           end as cuerpo) x on true
 where h.activo
   and (x.cuerpo is null or md5(x.cuerpo) <> h.md5_esperado);

alter view public.gv_huellas_cambiadas set (security_invoker = true);

-- ── La primera fila: la función que `tests/tools/vista-15.json` espeja ────────
insert into public."GV_Huella_Objeto" (objeto, clase, md5_esperado, por_que, quien_pidio, version)
select 'gv_monitor_horas_operario_dia', 'funcion', md5(p.prosrc),
       'tests/tools/vista-15.json es una FOTO de esta funcion. Si el cuerpo cambia y el JSON no, '
       'tests/mon-vs-vista.cjs queda verde y miente: hay que re-congelarlo.',
       'Thomas', 'v21.46'
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'gv_monitor_horas_operario_dia'
on conflict (objeto, clase) do update
   set md5_esperado = excluded.md5_esperado, version = excluded.version, actualizado_en = now();

-- Chequeo: vacía = todo bien.
-- select * from public.gv_huellas_cambiadas;
--
-- Probado rompiéndolo a propósito (transacción abortada): se le metió un comentario al cuerpo de
-- la función y la vista devolvió su fila con `md5_esperado` != `md5_actual`. Al revertir, 0 filas
-- y el cuerpo intacto.
