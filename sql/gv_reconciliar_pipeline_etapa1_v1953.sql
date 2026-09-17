-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- v19.53 (2026-09-17) — EL CRON 68 REESCRIBÍA 16.000 FILAS IDÉNTICAS CADA 10 MINUTOS
--
-- Luis, después del arreglo del cron 34: *"¿qué pasa con los benditos crons?"*.
--
-- Medido con `cron.job_run_details` (últimas 2 h, ya sin el cron 34 encima):
--
-- | cron | schedule | media | máx |
-- |---|---|---|---|
-- | **68 `reconciliar-pipeline-stock`** | `*/10` | **19,5 s** | 21,6 s |
-- | 57 `refresh_stocks_carga_rapida` | `*/5` | 8,1 s | 28,2 s ← incluye esperar el lock del 68 |
-- | 92 `gv-refrescar-articulo-empresa` | `*/15` | 5,2 s | 22,4 s |
-- | 34 `detectar-faltantes-llegaron` | `*/2` | **0,17 s** | 1,1 s ← el de la v19.46 |
--
-- **De los 19,5 s del cron 68, `etapa1` son 14,5 s** (etapa2 = 258 ms).
--
-- LA CAUSA: el bloque *forward-fill* de `etapa1` recalcula TODO el picking desde
-- `Stock_Config.etapa1_pkc_desde` en cada corrida —hoy **5.451 pares (tanda, artículo)**— y lo
-- vuelca con **tres `INSERT … ON CONFLICT … DO UPDATE`**, o sea hasta **16.353 filas tocadas**.
-- Y el `DO UPDATE` no comparaba nada: **reescribía cada fila con el valor que ya tenía**.
--
-- Cada reescritura dispara los **9 triggers** de `Movimientos_Stock`, y el que pesa es
-- `actualizar_saldo_trigger`: por CADA fila hace un agregado del artículo y un `upsert` en
-- `stocks_carga_rapida`. Medido a propósito: un `update … set delta = delta` sobre las 10.305
-- filas de `separar_pedidos` —o sea escribir lo mismo que ya está— tarda **8.856 ms**.
--
-- EL ARREGLO: un `WHERE` en los tres `DO UPDATE` para no escribir lo que no cambió.
-- `IS DISTINCT FROM` (no `<>`) porque `delta` y `legajo` pueden ser NULL.
--
-- **Verificación — el estado final tiene que ser el MISMO, no parecido.** Las dos versiones se
-- corrieron sobre los datos reales en transacciones abortadas, comparando el md5 del conjunto
-- completo de filas de picking (`ref ~ cod_art ~ empresa ~ deposito ~ delta ~ legajo`):
--
-- | | tiempo | filas | md5 del estado final |
-- |---|---|---|---|
-- | vieja | 20.196 ms | 26.740 | `071b9e98dc4354038f9713079460e5a5` |
-- | **nueva** | **2.135 ms** | 26.740 | `071b9e98dc4354038f9713079460e5a5` |
--
-- Idéntico, y **9,5× más rápido**. Las dos devuelven `5451`.
--
-- ⚠ POR QUÉ ESTO IMPORTA MÁS QUE LOS SEGUNDOS: esas 16.000 reescrituras tomaban **row locks**
-- sobre `stocks_carga_rapida` durante 14 s, cada 10 minutos. Cualquier escritura de un
-- supervisor (cancelar, desarmar, mover) que cayera ahí adentro esperaba — y con
-- `statement_timeout = 8 s` no espera: muere. Es la misma familia del problema 382.
--
-- ⚠ Y no toca la lógica: el `WHERE` de un `ON CONFLICT DO UPDATE` que no matchea **no falla**,
-- simplemente deja la fila como está. El tercer upsert (`terminado`) lee las filas de
-- `separar_pedidos` y `excedente` que escriben los dos anteriores; si esos no escriben porque el
-- valor no cambió, lee el mismo valor igual.
--
-- Problema 384. Rollback exacto: `sql/backups/reconciliar_pipeline_etapa1_pre_v1953.sql`.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

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
  DO UPDATE SET delta = excluded.delta, legajo = excluded.legajo
  WHERE "Movimientos_Stock".delta IS DISTINCT FROM excluded.delta
     OR "Movimientos_Stock".legajo IS DISTINCT FROM excluded.legajo;

  INSERT INTO "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, legajo, empresa)
  SELECT art,'excedente', -from_exc,'picking', tanda, coalesce(leg,'pipeline'), coalesce(emp,'Mixto') FROM _fwd_alloc
  ON CONFLICT (upper(trim(ref)), upper(trim(cod_art)), coalesce(empresa,''), deposito, tipo) WHERE tipo IN ('picking','separado','facturado')
  DO UPDATE SET delta = excluded.delta, legajo = excluded.legajo
  WHERE "Movimientos_Stock".delta IS DISTINCT FROM excluded.delta
     OR "Movimientos_Stock".legajo IS DISTINCT FROM excluded.legajo;

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
  legajo = excluded.legajo
  WHERE "Movimientos_Stock".delta IS DISTINCT FROM -(
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
  )
     OR "Movimientos_Stock".legajo IS DISTINCT FROM excluded.legajo;

  SELECT count(*) INTO n1b FROM _fwd_alloc;
  DROP TABLE IF EXISTS _fwd_alloc;

  return n1 + n1b;
end;
$function$;
