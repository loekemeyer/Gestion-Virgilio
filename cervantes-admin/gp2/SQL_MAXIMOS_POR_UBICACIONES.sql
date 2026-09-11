-- ============================================================================
-- maximos_sector_por_ubicaciones_ocupadas
--
-- Los maximos de Sector Crudo y Sector Procesado estaban cargados como si el
-- "Max Caj Cerv" / "Max Cajon SP Cerv" de las tablas viejas fuera el total del
-- sector. No lo es: es cuantos cajones entran en UNA ubicacion fisica.
--
-- Convencion de la fabrica: cuando un sector ocupa varias ubicaciones seguidas,
-- solo se nombra la PRIMERA. Por eso hay huecos en la numeracion (no existen J3,
-- J4 ni J6: se los come J2). Las ubicaciones que ocupa un sector se deducen como
-- (numero del proximo codigo de la misma letra) - (numero propio).
--
-- Ej. J2 "Cuerpo Uña": 5 cajones por ubicacion x 3 ubicaciones (J2, J3, J4,
-- porque el siguiente es J5) = 15 cajones = 25.275 unidades. Hoy dice 8.427.
--
-- APLICADA el 30/08/2026 como migracion "maximos_sector_por_ubicaciones_ocupadas".
-- Este archivo queda como referencia de que se corrio. No volver a ejecutarlo:
-- los updates son idempotentes, pero el backup ya existe y no se pisa.
--
-- Resultado real:
--   Sector Crudo:     405 -> 965 cajones   (77 filas, 29 ocupan mas de una ubicacion)
--     maximo en unidades:   879.378 -> 1.855.191
--   Sector Procesado: 540 -> 970 cajones   (83 filas, 28 ocupan mas de una ubicacion)
--     maximo en unidades: 1.006.439 -> 1.851.270
--   Chequeo J2: 5 caj/ubic x 3 ubicaciones = 15 cajones = 25.275 uni (antes 8.427). OK
--
-- Reversible: backup en GP2._bak_inventario_maximo_20260830
-- ============================================================================

begin;

-- 1) Backup de lo que habia, por si hay que volver atras.
create table if not exists "GP2"."_bak_inventario_maximo_20260830" as
select i.id, i.componente_id, i.ubicacion_id, i.cantidad, i.maximo, i.maximo_origen,
       now() as bak_en
from "GP2".inventario i
join "GP2".ubicacion u on u.id = i.ubicacion_id
where u.tipo = 'sector' and u.ref_id in (1, 2);

comment on table "GP2"."_bak_inventario_maximo_20260830" is
  'Backup de GP2.inventario (maximo/cantidad) de Sector Crudo y Procesado, previo a la migracion maximos_sector_por_ubicaciones_ocupadas.';

-- 2) Guardar los dos factores por separado, para no volver a confundirlos.
alter table "GP2".inventario
  add column if not exists cajones_x_ubicacion numeric,
  add column if not exists ubicaciones integer;

comment on column "GP2".inventario.cajones_x_ubicacion is
  'Cajones que entran en UNA ubicacion fisica. Origen: SC Kg."Max Caj Cerv" / SP Kg."Max Cajon SP Cerv".';
comment on column "GP2".inventario.ubicaciones is
  'Ubicaciones fisicas consecutivas que ocupa el sector. Solo se nombra la primera, asi que se deduce como (numero del proximo codigo de la misma letra) - (numero propio). Minimo 1.';
comment on column "GP2".inventario.maximo is
  'Maximo en UNIDADES = cajones_x_ubicacion * ubicaciones * componente.uni_x_cajon.';

-- 3) Cajones por ubicacion, desde las tablas viejas.
update "GP2".inventario i
set cajones_x_ubicacion = v.maxc
from (
  select trim("SC") cod, 1 sid, "Max Caj Cerv"::numeric maxc
    from public."SC Kg" where "Max Caj Cerv" is not null
  union all
  select trim("Sp"), 2, "Max Cajon SP Cerv"::numeric
    from public."SP Kg" where "Max Cajon SP Cerv" is not null
) v,
"GP2".componente c,
"GP2".ubicacion u
where c.codigo = v.cod and c.sector_id = v.sid
  and u.tipo = 'sector' and u.ref_id = v.sid
  and i.componente_id = c.id and i.ubicacion_id = u.id;

-- 4) Ubicaciones ocupadas, por el hueco hasta el proximo codigo de la misma letra.
with base as (
  select c.id comp_id, c.sector_id,
         regexp_replace(c.codigo, '[0-9].*$', '') letra,
         nullif(regexp_replace(c.codigo, '[^0-9]', '', 'g'), '')::int nro,
         regexp_replace(c.codigo, '^[A-Za-z]+[0-9]+', '') sufijo
  from "GP2".componente c
  where c.sector_id in (1, 2) and c.codigo ~ '^[A-Za-z]+[0-9]+[A-Za-z]?$'
), g as (
  select comp_id, sector_id,
         greatest(1, coalesce(lead(nro) over w - nro, 1)) ubic,
         (lead(nro) over w) is null sin_sig
  from base
  window w as (partition by sector_id, letra order by nro, sufijo)
)
update "GP2".inventario i
set ubicaciones = g.ubic,
    maximo_origen = case when g.sin_sig then 'ultimo_de_serie_supuesto_1'
                         else 'hueco_hasta_proximo_codigo' end
from g, "GP2".ubicacion u
where i.componente_id = g.comp_id
  and u.id = i.ubicacion_id and u.tipo = 'sector' and u.ref_id = g.sector_id;

-- Codigos sin numero (ABPM, RULETA): no hay de donde deducir, queda en 1.
update "GP2".inventario i
set ubicaciones = 1, maximo_origen = 'codigo_sin_numero_supuesto_1'
from "GP2".componente c, "GP2".ubicacion u
where c.id = i.componente_id and c.sector_id in (1, 2)
  and u.id = i.ubicacion_id and u.tipo = 'sector' and u.ref_id = c.sector_id
  and i.ubicaciones is null;

-- 5) Recalcular el maximo en unidades.
update "GP2".inventario i
set maximo = round(i.cajones_x_ubicacion * i.ubicaciones * c.uni_x_cajon)
from "GP2".componente c, "GP2".ubicacion u
where c.id = i.componente_id and c.sector_id in (1, 2)
  and u.id = i.ubicacion_id and u.tipo = 'sector' and u.ref_id = c.sector_id
  and i.cajones_x_ubicacion is not null
  and i.ubicaciones is not null
  and c.uni_x_cajon is not null and c.uni_x_cajon > 0;

commit;

-- ---------------------------------------------------------------------------
-- CHEQUEO (correr despues): J2 tiene que dar 5 x 3 = 15 cajones / 25.275 uni
-- ---------------------------------------------------------------------------
-- select c.codigo, i.cajones_x_ubicacion, i.ubicaciones,
--        i.cajones_x_ubicacion * i.ubicaciones caj_total, i.maximo, i.maximo_origen
-- from "GP2".inventario i
-- join "GP2".componente c on c.id = i.componente_id
-- join "GP2".ubicacion u on u.id = i.ubicacion_id
-- where u.nombre = 'Sector Crudo' and c.codigo like 'J%'
-- order by (regexp_replace(c.codigo,'[^0-9]','','g'))::int;

-- ---------------------------------------------------------------------------
-- VOLVER ATRAS
-- ---------------------------------------------------------------------------
-- update "GP2".inventario i set maximo = b.maximo, maximo_origen = b.maximo_origen,
--        cajones_x_ubicacion = null, ubicaciones = null
-- from "GP2"."_bak_inventario_maximo_20260830" b where b.id = i.id;
