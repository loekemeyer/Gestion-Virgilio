-- =====================================================================
--  reconciliar_pipeline_stock_etapa1() — v17.07 (2026-09-14)
--
--  ⚠ ESTE ARCHIVO REEMPLAZA a sql/reconciliar_pipeline_stock_etapa1.sql, que quedó
--  desactualizado: es anterior al pipeline de la empresa y ni siquiera tiene la
--  columna `emp` en `_fwd_alloc`. Ésta es la definición VIVA, volcada con
--  pg_get_functiondef.
--
--  ── QUÉ SE ARREGLA: la rama forward duplicaba el picking ────────────────
--  Síntoma: la pantalla de Stock mostró 437E, 438E y 809E en rojo (góndola −1, −2 y
--  −43) mientras el histórico de movimientos del mismo artículo daba positivo.
--
--  No era un problema de la vista. El saldo de un depósito es **por empresa**, y el
--  negativo estaba en la partición `Mixto`:
--
--  |          | LK  | CH  | Mixto |
--  |----------|----:|----:|------:|
--  | 437E góndola | 103 |  16 | **−1**  |
--  | 438E góndola |  33 |   — | **−2**  |
--  | 809E góndola |  28 | 120 | **−43** |
--
--  (103 + 16 − 1 = 118, que es justo lo que mostraba el histórico.)
--
--  Causa: a las 09:37 el reconciliador insertó 27 filas de picking **duplicadas**
--  para 8 tandas de agosto (D23A, D32C, D33A, D33B, D33C, D36G, D37A, D38B). Cada
--  una tenía ya su gemela con el mismo delta y empresa `LK`/`CH`.
--
--  El mecanismo, que es lo que hay que entender para no repetirlo:
--   1. `etapa1_pkc_desde` = 13/08, así que esas tandas caen en la rama **forward**,
--      que NO tiene el guard por tanda de la rama vieja y deduplica con
--      `ON CONFLICT (upper(ref), upper(cod_art), coalesce(empresa,''), deposito, tipo)`.
--   2. Son anteriores al corte `pkc_empresa_desde` (11/09 17:55), así que la etapa no
--      puede derivar la empresa del evento → `emp` NULL → inserta `'Mixto'`.
--   3. Pero sus filas existentes ya NO están en `Mixto`: el backfill
--      `gv_empresa_backfill` de ese mismo 11/09 les puso `LK`/`CH`.
--   4. `'Mixto'` ≠ `'CH'` → el ON CONFLICT no matchea → en vez de actualizar, **inserta
--      un duplicado**, y el descuento cae sobre una partición que estaba en 0.
--
--  O sea: **el backfill del 11/09 dejó el desalineo armado**, y se dispara en la
--  primera corrida que reprocese una de esas tandas. Había **64 tandas expuestas**.
--
--  EL FIX (el bloque `UPDATE _fwd_alloc` marcado v17.07): si la empresa no se puede
--  derivar del evento pero la fila ya existe con empresa real, se reusa ESA empresa.
--  Así el ON CONFLICT matchea y hace `DO UPDATE` (idempotente) en vez de insertar.
--
--  Verificado después: `reconciliar_pipeline_stock()` a mano → 0 duplicados por
--  empresa en toda la tabla, 0 filas `Mixto` nuevas, 0 negativos.
--
--  Rollback: zz_backups."GV_Backup_Etapa1_Def_20260914" tiene el CREATE previo.
--  Las 27 filas borradas: zz_backups."GV_Backup_Dup_Mixto_20260914".
-- =====================================================================

CREATE OR REPLACE FUNCTION public.reconciliar_pipeline_stock_etapa1()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
declare v_cutoff timestamptz; v_desde timestamptz; v_dep_on boolean; v_emp_desde timestamptz; n1 int := 0; n1b int := 0;
begin
  select coalesce((select valor::timestamptz from "Stock_Config" where clave='cutoff_ts'),
                  '2026-06-26 00:01:00-03'::timestamptz) into v_cutoff;
  select coalesce((select valor::timestamptz from "Stock_Config" where clave='etapa1_pkc_desde'),
                  'infinity'::timestamptz) into v_desde;
  select coalesce((select valor from "Stock_Config" where clave='pkc_deposito_activo'),'1') <> '0'
    into v_dep_on;
  select coalesce((select valor::timestamptz from "Stock_Config" where clave='pkc_empresa_desde'),
                  'infinity'::timestamptz) into v_emp_desde;

  with picks as (
    select upper(trim(split_part(r.texto,'|',1))) tanda,
           coalesce(e.cod_real, upper(trim(split_part(r.texto,'|',2)))) art,
           sum(coalesce(nullif(regexp_replace(split_part(r.texto,'|',4),'[^0-9.\-]','','g'),'')::numeric,0)) picked,
           (array_agg(r.legajo::text ORDER BY r.ts_cliente DESC NULLS LAST))[1] AS leg
    from "Registros_Produccion_Virgilio" r
    left join "Equivalencias_Codigos" e
      on regexp_replace(upper(btrim(e.cod_pedido)),'^0+(?=.)','')
       = regexp_replace(upper(btrim(split_part(r.texto,'|',2))),'^0+(?=.)','')
    where r.opcion='PKC' and coalesce(split_part(r.texto,'|',2),'')<>''
      and r.ts_cliente >= v_cutoff
    group by 1,2
  ),
  lastpk as (select upper(trim(split_part(texto,'|',1))) tanda, max(ts_cliente) last_pk
             from "Registros_Produccion_Virgilio" where opcion='PKC'
               and ts_cliente >= v_cutoff
             group by 1),
  elig as (
    select p.tanda, p.art, p.picked, p.leg from picks p join lastpk l on l.tanda=p.tanda
    where p.picked>0 and l.last_pk >= v_cutoff and l.last_pk < v_desde
      and exists (select 1 from "Registros_Produccion_Virgilio" r
                  where r.opcion='TP' and upper(trim(split_part(r.texto,'|',1)))=p.tanda)
      and not exists (select 1 from "Movimientos_Stock" m
                      where m.deposito='separar_pedidos' and upper(trim(m.ref))=p.tanda)
  ),
  exc_avail as (select upper(trim(cod_art)) art, greatest(0, sum(delta))::numeric exc
                from "Movimientos_Stock" where deposito='excedente' group by upper(trim(cod_art))),
  alloc as (
    select e.tanda, e.art, e.picked, e.leg,
           least(e.picked, greatest(0, coalesce(x.exc,0)
             - coalesce(sum(e.picked) over (partition by e.art order by e.tanda
                        rows between unbounded preceding and 1 preceding),0))) as from_exc
    from elig e left join exc_avail x on x.art=e.art
  )
  insert into "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, legajo)
  select art,'separar_pedidos', picked,'picking', tanda, coalesce(leg,'pipeline') from alloc
  union all select art,'excedente', -from_exc,'picking', tanda, coalesce(leg,'pipeline') from alloc where from_exc>0
  union all select art,'terminado', -(picked-from_exc),'picking', tanda, coalesce(leg,'pipeline') from alloc where (picked-from_exc)>0
  on conflict do nothing;
  get diagnostics n1 = row_count;

  CREATE TEMP TABLE IF NOT EXISTS _fwd_alloc (tanda text, art text, picked numeric, from_exc numeric, leg text, emp text);
  TRUNCATE _fwd_alloc;

  WITH picks AS (
    select upper(trim(split_part(r.texto,'|',1))) tanda,
           coalesce(e.cod_real, upper(trim(split_part(r.texto,'|',2)))) art,
           sum(coalesce(nullif(regexp_replace(split_part(r.texto,'|',4),'[^0-9.\-]','','g'),'')::numeric,0)) picked,
           sum(coalesce(nullif(regexp_replace(split_part(r.texto,'|',5),'[^0-9.\-]','','g'),'')::numeric,0)) picked_exc,
           bool_or(coalesce(btrim(split_part(r.texto,'|',5)),'') <> '') as tiene_dep,
           case when bool_and(r.ts_cliente >= v_emp_desde)
                 and count(distinct nullif(upper(btrim(split_part(r.texto,'|',6))),'')) = 1
                 and bool_and(upper(btrim(split_part(r.texto,'|',6))) in ('LK','CH'))
                then max(nullif(upper(btrim(split_part(r.texto,'|',6))),''))
           end as emp,
           (array_agg(r.legajo::text ORDER BY r.ts_cliente DESC NULLS LAST))[1] AS leg
    from "Registros_Produccion_Virgilio" r
    left join "Equivalencias_Codigos" e
      on regexp_replace(upper(btrim(e.cod_pedido)),'^0+(?=.)','')
       = regexp_replace(upper(btrim(split_part(r.texto,'|',2))),'^0+(?=.)','')
    where r.opcion='PKC' and coalesce(split_part(r.texto,'|',2),'')<>''
      and r.ts_cliente >= v_desde
    group by 1,2
  ),
  lastpk AS (select upper(trim(split_part(texto,'|',1))) tanda, max(ts_cliente) last_pk
             from "Registros_Produccion_Virgilio" where opcion='PKC'
               and ts_cliente >= v_desde
             group by 1),
  fwd AS (select p.tanda, p.art, p.picked, p.picked_exc, p.tiene_dep, p.emp, p.leg
          from picks p join lastpk l on l.tanda=p.tanda
          where p.picked>=0 and l.last_pk >= v_desde),
  fwd_t AS (select distinct tanda from fwd),
  exc_avail AS (
    select upper(trim(cod_art)) art, greatest(0, sum(delta))::numeric exc
    from "Movimientos_Stock"
    where deposito='excedente' and not (tipo='picking' and upper(trim(ref)) in (select tanda from fwd_t))
    group by upper(trim(cod_art))
  ),
  fwd2 AS (
    select f.*,
           case when (f.tiene_dep and v_dep_on) then least(f.picked, greatest(f.picked_exc, 0))
                else f.picked end as want_exc
    from fwd f
  ),
  alloc AS (
    select f.tanda, f.art, f.picked, f.leg, f.emp,
           least(f.want_exc, greatest(0, coalesce(x.exc,0)
             - coalesce(sum(f.want_exc) over (partition by f.art order by f.tanda
                        rows between unbounded preceding and 1 preceding),0))) as from_exc
    from fwd2 f left join exc_avail x on x.art=f.art
  )
  INSERT INTO _fwd_alloc SELECT tanda, art, picked, from_exc, leg, emp FROM alloc;

  -- v17.07 — SIN ESTO SE DUPLICA EL PICKING. Si la empresa no se puede derivar del
  -- evento (tanda anterior al corte pkc_empresa_desde del 11/09) pero la fila YA existe
  -- con empresa real -se la puso el backfill gv_empresa_backfill de ese dia-, hay que
  -- reusar ESA empresa. Si no, abajo se inserta con coalesce(emp,'Mixto') y el
  -- ON CONFLICT -que incluye coalesce(empresa,'')- no matchea contra la fila 'CH'/'LK'
  -- existente, asi que en vez de actualizar INSERTA UN DUPLICADO. Paso el 14/09: 27 filas
  -- duplicadas en 8 tandas de agosto (D23A, D33B, D38B...), que dejaron la particion
  -- 'Mixto' de 437E/438E/809E en negativo (-1, -2, -43) mientras LK y CH estaban bien.
  -- Habia 64 tandas expuestas al mismo caso.
  UPDATE _fwd_alloc f SET emp = m.empresa
    FROM "Movimientos_Stock" m
   WHERE f.emp IS NULL
     AND upper(trim(m.ref)) = f.tanda
     AND upper(trim(m.cod_art)) = upper(trim(f.art))
     AND m.tipo = 'picking' AND m.deposito = 'separar_pedidos'
     AND coalesce(m.empresa, 'Mixto') <> 'Mixto';

  INSERT INTO "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, legajo, empresa)
  SELECT art,'separar_pedidos', picked,'picking', tanda, coalesce(leg,'pipeline'), coalesce(emp,'Mixto') FROM _fwd_alloc
  ON CONFLICT (upper(trim(ref)), upper(trim(cod_art)), coalesce(empresa,''), deposito, tipo) WHERE tipo IN ('picking','separado','facturado')
  DO UPDATE SET delta = excluded.delta, legajo = excluded.legajo;

  INSERT INTO "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, legajo, empresa)
  SELECT art,'excedente', -from_exc,'picking', tanda, coalesce(leg,'pipeline'), coalesce(emp,'Mixto') FROM _fwd_alloc
  ON CONFLICT (upper(trim(ref)), upper(trim(cod_art)), coalesce(empresa,''), deposito, tipo) WHERE tipo IN ('picking','separado','facturado')
  DO UPDATE SET delta = excluded.delta, legajo = excluded.legajo;

  INSERT INTO "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, legajo, empresa)
  SELECT art,'terminado', -(picked-from_exc),'picking', tanda, coalesce(leg,'pipeline'), coalesce(emp,'Mixto') FROM _fwd_alloc
  ON CONFLICT (upper(trim(ref)), upper(trim(cod_art)), coalesce(empresa,''), deposito, tipo) WHERE tipo IN ('picking','separado','facturado')
  DO UPDATE SET delta = -(
    COALESCE((SELECT m.delta FROM "Movimientos_Stock" m
      WHERE m.deposito='separar_pedidos' AND m.tipo='picking'
        AND upper(trim(m.ref)) = upper(trim("Movimientos_Stock".ref))
        AND upper(trim(m.cod_art)) = upper(trim("Movimientos_Stock".cod_art)) AND coalesce(m.empresa,'') = coalesce("Movimientos_Stock".empresa,'')
      LIMIT 1), 0)
    + COALESCE((SELECT m.delta FROM "Movimientos_Stock" m
      WHERE m.deposito='excedente' AND m.tipo='picking'
        AND upper(trim(m.ref)) = upper(trim("Movimientos_Stock".ref))
        AND upper(trim(m.cod_art)) = upper(trim("Movimientos_Stock".cod_art)) AND coalesce(m.empresa,'') = coalesce("Movimientos_Stock".empresa,'')
      LIMIT 1), 0)
  ),
  legajo = excluded.legajo;

  SELECT count(*) INTO n1b FROM _fwd_alloc;
  DROP TABLE IF EXISTS _fwd_alloc;

  return n1 + n1b;
end;
$function$;
