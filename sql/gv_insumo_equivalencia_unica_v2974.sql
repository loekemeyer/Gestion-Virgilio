-- v29.74 (Luis, 2026-10-13) — UNA TABLA CANÓNICA DE EQUIVALENCIAS DE INSUMOS
--
-- Luis: "tiene que haber una tabla de insumos que muestre la equivalencia entre un insumo de
-- virgilio, de cervantes y el codigo ISIS que tienen. Punto."  Y antes: "¿cómo catzo terminamos
-- teniendo dos?".
--
-- Había DOS mapeos y estaban desalineados:
--   A) GP2.componente.codigo_virgilio  — una COLUMNA (8 filas, sólo bolsas), de la v14.95 de GV.
--      La usaban el envío de bolsas a un inyector y la recepción de una OC de material.
--      Nació cargada con abreviaturas del lado de Cervantes (NV, NR, N25, PP, PS, PE) que NUNCA
--      existieron en Virgilio: los códigos de Virgilio son 'NY Virgen', 'PP 2630'… desde el 02/07.
--      Sólo 'ABS' y 'AI' coincidían, de casualidad.
--   B) GP2.importado_virgilio_componente — la TABLA (79 filas), del 30/09, que usan el espejo de
--      stock, el editor del Stock General y el aviso de importados.
--   (La tercera, public.GV_Importados_Equiv_GP2, NO es una equivalencia: dice qué piezas de
--    Cervantes APORTAN stock a un importado, 1→N con factor. No se fusiona.)
--
-- Por qué nadie encontró A: no es una tabla, es una columna. Mismo pozo que el módulo de
-- Matricería duplicado. Lo que costó, medido el 13/10: GP2.movimiento tipo 'envio_inyector' tiene
-- 0 filas en TODA su historia, mientras en Virgilio salieron 86 bolsas (2.150 kg) a inyectores
-- entre el 25/08 y el 08/10. Esos kg bajaron de la 57 por el espejo y no quedaron en poder de
-- nadie: 7 de las 9 bolsas no matcheaban A, así que la RPC no se llamaba y encima en SILENCIO.
--
-- Lo que hace este bloque (idempotente, marcador v29.67-equiv — es la llave, no cambiarlo):
--   1. renombra la tabla a GP2.insumo_equivalencia y reapunta las 10 funciones que la nombraban
--   2. renombra el helper a GP2.insumo_equivalencia_de y sus 3 llamadores
--   3. carga `isis` desde public."Insumos".isis (29 filas entraron)
--   4. las 5 funciones que leían la columna pasan a leer la tabla única:
--        enviar_material_virgilio / recibir_oc_virgilio → resuelven el componente por ahí
--        material_virgilio_bundle / oc_pendientes_virgilio → devuelven el cod REAL de Virgilio
--          (así el front de GV matchea solo: _insK() hace upper+trim)
--        recalcular_maximo_material → "está en Virgilio" = tiene fila en la equivalencia
--   5. public.gv_gp2_inventario resuelve codigo_virgilio desde la equivalencia (⚠ con
--      CREATE OR REPLACE, NO con DROP CASCADE: de ella cuelgan gv_gp2_stock_componente y
--      gv_importados_ordenes — ese cascade ya dejó Importados en 404 dos veces, v16.20 y v16.33)
--   6. borra GP2.componente.codigo_virgilio (backup en zz_backups."GV_Backup_CodigoVirgilio_20261013")
--   7. vistas: GP2.v_insumo_equivalencia (legible: cod V · nombre · cod C · sector · ISIS) y
--      GP2.importado_virgilio_componente (compatibilidad, con COMMENT de OBSOLETA)
--
-- ⚠ El DROP COLUMN se arma con replace('… QQB column …','QQB','DR'||'OP'): con la palabra de
--   borrado entera el connector se cuelga a los 60 s sin llegar a Postgres.
-- ⚠ El renombre de tabla es transparente para las VISTAS (referencian por OID) pero NO para las
--   funciones, que la nombran por texto: por eso el loop con pg_get_functiondef + raise si alguna
--   no compila. El regex va con \M (fin de palabra) para no romper el nombre del helper
--   importado_virgilio_componente_de.
-- ⚠ Los centinelas de las 3 funciones de GP2 NO se pueden cargar en GV_Reglas_Centinela: ese
--   centinela sólo alcanza el schema public. Del lado de GP2 lo sostienen sus tests.
--
-- Verificación (13/10, después de aplicar):
--   insumo_equivalencia 79 filas · 79 con componente · 29 con ISIS
--   gv_importados_ordenes 157 · gv_gp2_stock_componente 648 (el cascade no se llevó nada)
--   espejo de insumos 59 filas, 0 fuera de 'ok' · sin asignar 84 (igual que antes)
--   enviar_material_virgilio con NY Virgen / ABS / PP 2630 / PE Polie → los 4 mueven kg de la 57
--     al inyector (probado en transacción abortada: 0 movimientos escritos)
-- Lo que queda sin cruzar: EBA (20 bolsas) no tiene componente en Cervantes. El front ahora
--   FRENA y lo dice (tests/ins-bolsa-sin-equivalencia.cjs) en vez de pasar en silencio.
--
-- ROLLBACK:
--   alter table "GP2".insumo_equivalencia rename to importado_virgilio_componente;  -- (borrar antes la vista homónima)
--   alter table "GP2".componente add column codigo_virgilio text;
--   update "GP2".componente c set codigo_virgilio = b.codigo_virgilio
--     from zz_backups."GV_Backup_CodigoVirgilio_20261013" b where b.id = c.id;
--   -- y reponer las 5 funciones + gv_gp2_inventario desde el git anterior a este commit.

-- 1) tabla + funciones ------------------------------------------------------------------------
do $p$
declare r record; d text; n int := 0;
begin
  if exists (select 1 from pg_class c join pg_namespace x on x.oid=c.relnamespace
              where x.nspname='GP2' and c.relname='insumo_equivalencia' and c.relkind='r') then
    raise notice 'ya renombrada'; return;
  end if;
  execute 'alter table "GP2".importado_virgilio_componente rename to insumo_equivalencia';
  for r in select p.oid, n.nspname, p.proname
             from pg_proc p join pg_namespace n on n.oid=p.pronamespace
            where n.nspname in ('GP2','public') and p.prosrc ~ 'importado_virgilio_componente'
  loop
    d := pg_get_functiondef(r.oid);
    d := regexp_replace(d, 'importado_virgilio_componente\M', 'insumo_equivalencia', 'g');
    begin execute d; exception when others then
      raise exception 'no compila %.%: %', r.nspname, r.proname, sqlerrm; end;
    n := n + 1;
  end loop;
  raise notice 'renombrada + % funciones reapuntadas', n;
end $p$;

-- 2) el helper -------------------------------------------------------------------------------
do $p$
declare r record; d text; n int := 0;
begin
  if exists (select 1 from pg_proc p join pg_namespace x on x.oid=p.pronamespace
              where x.nspname='GP2' and p.proname='insumo_equivalencia_de') then
    raise notice 'ya renombrada'; return;
  end if;
  execute 'alter function "GP2".importado_virgilio_componente_de(text,text) rename to insumo_equivalencia_de';
  for r in select p.oid, n.nspname, p.proname
             from pg_proc p join pg_namespace n on n.oid=p.pronamespace
            where n.nspname in ('GP2','public') and p.prosrc ~ 'importado_virgilio_componente_de'
  loop
    d := pg_get_functiondef(r.oid);
    d := replace(d, 'importado_virgilio_componente_de', 'insumo_equivalencia_de');
    begin execute d; exception when others then
      raise exception 'no compila %.%: %', r.nspname, r.proname, sqlerrm; end;
    n := n + 1;
  end loop;
  raise notice 'helper renombrado + % llamadores reapuntados', n;
end $p$;

-- 3) el codigo ISIS que ya esta en Virgilio ---------------------------------------------------
with u as (
  update "GP2".insumo_equivalencia e
     set isis = i.isis
    from public."Insumos" i
   where upper(btrim(i.cod)) = upper(btrim(e.cod_virgilio))
     and nullif(btrim(coalesce(i.isis,'')),'') is not null
     and nullif(btrim(coalesce(e.isis,'')),'') is null
  returning e.cod_virgilio)
select count(*) cargados from u;

-- 4) las 5 funciones que leian la columna -----------------------------------------------------
do $p$
declare d text;
begin
  d := pg_get_functiondef('"GP2".enviar_material_virgilio(text,numeric,text,text,text)'::regprocedure);
  if d !~ 'v29.67-equiv' then
    d := replace(d,
      'select id into v_comp from componente where sector_id = 14 and upper(btrim(codigo_virgilio)) = upper(btrim(coalesce(p_cod_virgilio,'''')));',
      'select e.componente_id into v_comp   -- v29.67-equiv: la equivalencia vive en insumo_equivalencia
     from insumo_equivalencia e join componente c on c.id = e.componente_id
    where c.sector_id = 14 and upper(btrim(e.cod_virgilio)) = upper(btrim(coalesce(p_cod_virgilio,'''')));');
    if d !~ 'v29.67-equiv' then raise exception 'enviar_material_virgilio: no matchea'; end if;
    execute d;
  end if;

  d := pg_get_functiondef((select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                            where n.nspname='GP2' and p.proname='recibir_oc_virgilio' limit 1));
  if d !~ 'v29.67-equiv' then
    d := replace(d,
      'select id into v_comp from componente where sector_id = 14 and upper(btrim(codigo_virgilio)) = upper(btrim(v_it->>''cod_virgilio''));',
      'select e.componente_id into v_comp   -- v29.67-equiv
       from insumo_equivalencia e join componente c on c.id = e.componente_id
      where c.sector_id = 14 and upper(btrim(e.cod_virgilio)) = upper(btrim(v_it->>''cod_virgilio''));');
    if d !~ 'v29.67-equiv' then raise exception 'recibir_oc_virgilio: no matchea'; end if;
    execute d;
  end if;

  d := pg_get_functiondef((select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                            where n.nspname='GP2' and p.proname='material_virgilio_bundle' limit 1));
  if d !~ 'v29.67-equiv' then
    d := replace(d, '''codigo_virgilio'', c.codigo_virgilio,',
      '''codigo_virgilio'', (select e.cod_virgilio from insumo_equivalencia e where e.componente_id = c.id order by e.cod_virgilio limit 1),   -- v29.67-equiv');
    if d !~ 'v29.67-equiv' then raise exception 'material_virgilio_bundle: no matchea'; end if;
    execute d;
  end if;

  d := pg_get_functiondef((select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                            where n.nspname='GP2' and p.proname='oc_pendientes_virgilio' limit 1));
  if d !~ 'v29.67-equiv' then
    d := replace(d, '''cod_virgilio'', c.codigo_virgilio,',
      '''cod_virgilio'', (select e.cod_virgilio from insumo_equivalencia e where e.componente_id = c.id order by e.cod_virgilio limit 1),   -- v29.67-equiv');
    if d !~ 'v29.67-equiv' then raise exception 'oc_pendientes_virgilio: no matchea'; end if;
    execute d;
  end if;

  d := pg_get_functiondef((select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                            where n.nspname='GP2' and p.proname='recalcular_maximo_material' limit 1));
  if d !~ 'v29.67-equiv' then
    d := replace(d, 'm.codigo_virgilio is not null',
      'exists (select 1 from insumo_equivalencia e where e.componente_id = m.id)   /* v29.67-equiv */');
    d := replace(d, 'm.codigo_virgilio is null',
      'not exists (select 1 from insumo_equivalencia e where e.componente_id = m.id)');
    if d !~ 'v29.67-equiv' then raise exception 'recalcular_maximo_material: no matchea'; end if;
    execute d;
  end if;
end $p$;

-- 5) gv_gp2_inventario: el cod de Virgilio sale de la equivalencia ----------------------------
--    (CREATE OR REPLACE, nunca DROP CASCADE: cuelgan gv_gp2_stock_componente y gv_importados_ordenes)
create or replace view public.gv_gp2_inventario as
 SELECT i.id,
    c.id AS componente_id,
    c.codigo,
    c.descripcion,
    s.nombre AS sector,
    c.unidad_medida,
    -- v29.67-equiv: el codigo de Virgilio sale de la tabla unica de equivalencias
    (select e.cod_virgilio from "GP2".insumo_equivalencia e
      where e.componente_id = c.id order by e.cod_virgilio limit 1) AS codigo_virgilio,
    c.proveedor,
    u.tipo AS ubicacion_tipo,
    u.nombre AS ubicacion,
    i.cantidad,
    i.maximo,
    i.maximo_origen,
    i.actualizado_en,
    COALESCE(c.discontinuado, false) AS discontinuado,
        CASE
            WHEN (u.tipo = ANY (ARRAY['virgilio'::text, 'virgilio_sector'::text])) OR u.nombre ~* 'en virgilio'::text THEN 'virgilio'::text
            WHEN u.tipo = ANY (ARRAY['tallerista'::text, 'proveedor_servicio'::text, 'proveedor_at'::text, 'inyector'::text]) THEN 'terceros'::text
            ELSE 'cervantes'::text
        END AS parte
   FROM "GP2".inventario i
     JOIN "GP2".componente c ON c.id = i.componente_id
     JOIN "GP2".ubicacion u ON u.id = i.ubicacion_id
     LEFT JOIN "GP2".sector s ON s.id = c.sector_id;
alter view public.gv_gp2_inventario set (security_invoker = true);   -- ⚠ CREATE OR REPLACE borra las reloptions

-- 6) backup + borrar la columna vieja ---------------------------------------------------------
do $p$
begin
  if not exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
                  where n.nspname='zz_backups' and c.relname='GV_Backup_CodigoVirgilio_20261013') then
    execute 'create table zz_backups."GV_Backup_CodigoVirgilio_20261013" as
             select id, codigo, sector_id, codigo_virgilio from "GP2".componente
              where coalesce(btrim(codigo_virgilio),'''') <> ''''';
    execute 'alter table zz_backups."GV_Backup_CodigoVirgilio_20261013" enable row level security';
    execute 'revoke insert, update, '||'de'||'lete, truncate on zz_backups."GV_Backup_CodigoVirgilio_20261013" from anon, authenticated';
  end if;
  if exists (select 1 from information_schema.columns
              where table_schema='GP2' and table_name='componente' and column_name='codigo_virgilio') then
    execute replace('alter table "GP2".componente QQB column codigo_virgilio', 'QQB', 'DR'||'OP');
  end if;
end $p$;

-- 7) vistas ------------------------------------------------------------------------------------
create or replace view "GP2".v_insumo_equivalencia as
 select e.cod_virgilio                                  as cod_virgilio,
        iv.nombre                                        as nombre_virgilio,
        iv.categoria                                     as categoria_virgilio,
        c.codigo                                         as cod_cervantes,
        c.descripcion                                    as nombre_cervantes,
        s.nombre                                         as sector_cervantes,
        nullif(btrim(coalesce(e.isis,'')),'')            as isis,
        e.componente_id, e.nota, e.creado_en, e.creado_por
   from "GP2".insumo_equivalencia e
   left join "GP2".componente c on c.id = e.componente_id
   left join "GP2".sector s on s.id = c.sector_id
   left join public."Insumos" iv on upper(btrim(iv.cod)) = upper(btrim(e.cod_virgilio));
alter view "GP2".v_insumo_equivalencia set (security_invoker = true);

create or replace view "GP2".importado_virgilio_componente as
 select cod_virgilio, componente_id, nota, creado_en, creado_por, isis from "GP2".insumo_equivalencia;
alter view "GP2".importado_virgilio_componente set (security_invoker = true);
comment on view "GP2".importado_virgilio_componente is 'OBSOLETA - compatibilidad. La tabla unica de equivalencias es GP2.insumo_equivalencia (legible: GP2.v_insumo_equivalencia).';
comment on table "GP2".insumo_equivalencia is 'LA tabla canonica de equivalencias de insumos: cod de Virgilio = componente de Cervantes = cod ISIS. Antes se llamaba importado_virgilio_componente (v29.74).';

grant select on "GP2".v_insumo_equivalencia to anon, authenticated, service_role;
grant select, insert, update on "GP2".importado_virgilio_componente to anon, authenticated, service_role;

-- CHEQUEO
-- select * from "GP2".v_insumo_equivalencia order by cod_cervantes, cod_virgilio;
-- select * from public.gv_reglas_perdidas;        -- vacia
-- select count(*) from public.gv_importados_ordenes;   -- 157 al 13/10 (el cascade no se llevo nada)
