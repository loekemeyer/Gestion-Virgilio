-- =====================================================================
-- gv_pkc_deposito_v1541.sql — 2026-09-11 (pedido de Luis)
--
-- QUÉ ARREGLA
-- El picking le dice al operario DE DÓNDE levantar cada caja (paso de góndola
-- con su sector, paso de excedente con su ubicación) y después tiraba ese dato:
-- el evento PKC era `TANDA|ART|esp|real`, sin depósito. El backend RE-DERIVABA
-- el reparto al reconciliar, con los saldos VIVOS de ese momento:
--     from_exc = least(picked, excedente_disponible - lo_ya_tomado_por_otras_tandas)
-- O sea, adivinaba a las 09:17 algo que el operario tenía en la mano a las 09:15.
--
-- Encima los dos pasos del mismo artículo compartían client_id
-- (pkc_<legajo>_<tanda>_<ART>_<día>) y el POST va con merge-duplicates, así que
-- el PKC del excedente PISABA al de góndola y las cajas de góndola se perdían
-- del registro. Huella: 802 de 815 pickings con excedente (60 días) figuraban
-- como 100 % excedente y 0 de góndola.
--
-- CÓMO QUEDA
-- El front (v15.41) manda UN SOLO evento por (tanda, artículo) con los TOTALES
-- de los dos pasos y un 5º campo:
--     TANDA|ART|esp|real|excedente      ← "de las `real`, tantas salieron del excedente"
-- Un solo evento a propósito: hay 12 objetos en la base que leen PKC asumiendo
-- una fila por (tanda, artículo); partirlo en dos los rompía a todos.
--
-- Estas dos funciones pasan a USAR ese campo en vez de adivinar:
--   · reconciliar_pipeline_stock_etapa1()  — el cron (jobid 68, cada 10 min)
--   · reconciliar_stock_articulo_rt()      — el trigger en tiempo real (trg_pkc_reconciliar_rt)
-- Las DOS, si no: el trigger escribiría la adivinanza en cada PKC y el cron la
-- corregiría 10 minutos después — flip-flop.
--
-- COMPATIBILIDAD
--   · PKC viejo (4 campos) → `tiene_dep` = false → reparto por saldos, IGUAL que hoy.
--   · Rama A (histórico, gated por Stock_Config.etapa1_pkc_desde) NO se toca:
--     esos eventos son todos viejos.
--   · Si al front le falla la consulta de excedente, NO manda el 5º campo
--     (_pk.excOk = false) → el backend vuelve a adivinar. Un fetch caído no se
--     confunde con "no hay excedente".
--   · Se mantiene el clamp contra el excedente disponible y la ventana por tanda,
--     así que el excedente NUNCA queda negativo (fix v11.73 intacto).
--
-- INTERRUPTOR
--   update "Stock_Config" set valor='0' where clave='pkc_deposito_activo';
--   → vuelve a adivinar sin tocar código. Default (sin la fila) = prendido.
--
-- ⚠ OBJETO COMPARTIDO con Producción Virgilio → anotado en docs/ROLLBACK-PRODUCCION.md.
-- BACKUP de las definiciones previas: sql/backups/reconciliar_pkc_pre_v1541_20260911.sql
-- =====================================================================

CREATE OR REPLACE FUNCTION public.reconciliar_pipeline_stock_etapa1()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
declare v_cutoff timestamptz; v_desde timestamptz; v_dep_on boolean; n1 int := 0; n1b int := 0;
begin
  select coalesce((select valor::timestamptz from "Stock_Config" where clave='cutoff_ts'),
                  '2026-06-26 00:01:00-03'::timestamptz) into v_cutoff;
  select coalesce((select valor::timestamptz from "Stock_Config" where clave='etapa1_pkc_desde'),
                  'infinity'::timestamptz) into v_desde;
  -- v15.41: interruptor. Sin la fila = prendido.
  select coalesce((select valor from "Stock_Config" where clave='pkc_deposito_activo'),'1') <> '0'
    into v_dep_on;

  -- ===== A) HISTÓRICO (last_pk < v_desde): lógica ORIGINAL, por tanda, gated en TP, DO NOTHING =====
  -- v11.72: legajo real del PKC en vez de 'pipeline'
  -- v11.78: fix decimales — regex permite '.' y cast a numeric en vez de int
  -- v15.41: NO se toca — son todos eventos viejos, sin el campo de depósito.
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

  -- ===== B) FORWARD (last_pk >= v_desde): por ARTÍCULO, sin gate de TP =====
  -- FIX 2026-08-24: split INSERT para NO reasignar excedente de tandas existentes.
  -- v11.72: legajo real del PKC en vez de 'pipeline'
  -- v11.73: B.2 cambia DO NOTHING → DO UPDATE para recalcular excedente cada corrida
  --         (fix drift acumulativo que causaba excedente negativo, ej. art 546 → -2).
  -- v11.78: fix decimales — regex permite '.' y cast a numeric en vez de int
  -- v15.41: si el PKC trae el 5º campo (cajas del EXCEDENTE), se USA ese número en
  --         vez de repartir por saldos. El clamp y la ventana por tanda siguen.

  CREATE TEMP TABLE IF NOT EXISTS _fwd_alloc (tanda text, art text, picked numeric, from_exc numeric, leg text);
  TRUNCATE _fwd_alloc;

  WITH picks AS (
    select upper(trim(split_part(r.texto,'|',1))) tanda,
           coalesce(e.cod_real, upper(trim(split_part(r.texto,'|',2)))) art,
           sum(coalesce(nullif(regexp_replace(split_part(r.texto,'|',4),'[^0-9.\-]','','g'),'')::numeric,0)) picked,
           -- v15.41: cajas declaradas del EXCEDENTE (5º campo del texto)
           sum(coalesce(nullif(regexp_replace(split_part(r.texto,'|',5),'[^0-9.\-]','','g'),'')::numeric,0)) picked_exc,
           bool_or(coalesce(btrim(split_part(r.texto,'|',5)),'') <> '') as tiene_dep,
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
  fwd AS (select p.tanda, p.art, p.picked, p.picked_exc, p.tiene_dep, p.leg
          from picks p join lastpk l on l.tanda=p.tanda
          where p.picked>=0 and l.last_pk >= v_desde),
  fwd_t AS (select distinct tanda from fwd),
  exc_avail AS (
    select upper(trim(cod_art)) art, greatest(0, sum(delta))::numeric exc
    from "Movimientos_Stock"
    where deposito='excedente' and not (tipo='picking' and upper(trim(ref)) in (select tanda from fwd_t))
    group by upper(trim(cod_art))
  ),
  -- v15.41: want_exc = lo que se QUIERE sacar del excedente. Declarado si el PKC lo
  -- trae; si no, `picked` entero (= la adivinanza vieja, que el clamp de abajo recorta).
  fwd2 AS (
    select f.*,
           case when (f.tiene_dep and v_dep_on) then least(f.picked, greatest(f.picked_exc, 0))
                else f.picked end as want_exc
    from fwd f
  ),
  alloc AS (
    select f.tanda, f.art, f.picked, f.leg,
           least(f.want_exc, greatest(0, coalesce(x.exc,0)
             - coalesce(sum(f.want_exc) over (partition by f.art order by f.tanda
                        rows between unbounded preceding and 1 preceding),0))) as from_exc
    from fwd2 f left join exc_avail x on x.art=f.art
  )
  INSERT INTO _fwd_alloc SELECT tanda, art, picked, from_exc, leg FROM alloc;

  -- B.1: UPSERT separar_pedidos (re-picks actualizan el conteo)
  INSERT INTO "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, legajo)
  SELECT art,'separar_pedidos', picked,'picking', tanda, coalesce(leg,'pipeline') FROM _fwd_alloc
  ON CONFLICT (upper(trim(ref)), upper(trim(cod_art)), coalesce(empresa,''), deposito, tipo) WHERE tipo IN ('picking','separado','facturado')
  DO UPDATE SET delta = excluded.delta, legajo = excluded.legajo;

  -- B.2: UPSERT excedente — recalcula asignación cada corrida
  INSERT INTO "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, legajo)
  SELECT art,'excedente', -from_exc,'picking', tanda, coalesce(leg,'pipeline') FROM _fwd_alloc
  ON CONFLICT (upper(trim(ref)), upper(trim(cod_art)), coalesce(empresa,''), deposito, tipo) WHERE tipo IN ('picking','separado','facturado')
  DO UPDATE SET delta = excluded.delta, legajo = excluded.legajo;

  -- B.3: UPSERT terminado — balancea: delta = -(separar + exc) para que sumen 0
  INSERT INTO "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, legajo)
  SELECT art,'terminado', -(picked-from_exc),'picking', tanda, coalesce(leg,'pipeline') FROM _fwd_alloc
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

-- =====================================================================
-- 2) El MISMO criterio en el reconciliador de TIEMPO REAL (lo dispara el trigger
--    trg_pkc_reconciliar_rt en cada INSERT de PKC). Sin esto, el trigger escribiría
--    la adivinanza en cada evento y el cron la corregiría 10 min después: flip-flop.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.reconciliar_stock_articulo_rt(p_tanda text, p_cod_raw text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
declare
  v_desde timestamptz;
  v_norm_art text;
  v_dep_on boolean;
begin
  -- Normalizar código
  v_norm_art := regexp_replace(upper(btrim(
    coalesce(
      (select cod_real from "Equivalencias_Codigos"
       where regexp_replace(upper(btrim(cod_pedido)),'^0+(?=.)','')
           = regexp_replace(upper(btrim(p_cod_raw)),'^0+(?=.)','')
       limit 1),
      p_cod_raw
    )
  )), '^0+(?=.)', '');

  if v_norm_art = '' or v_norm_art is null then return; end if;

  select coalesce((select valor::timestamptz from "Stock_Config" where clave='etapa1_pkc_desde'),
                  'infinity'::timestamptz) into v_desde;
  select coalesce((select valor from "Stock_Config" where clave='pkc_deposito_activo'),'1') <> '0'
    into v_dep_on;

  -- Solo path FORWARD (path A histórico lo cubre el cron)
  with picks as (
    select upper(trim(split_part(r.texto,'|',1))) tanda,
           sum(coalesce(nullif(regexp_replace(split_part(r.texto,'|',4),'[^0-9.\-]','','g'),'')::numeric,0)) picked,
           -- v15.41: cajas declaradas del EXCEDENTE (5º campo)
           sum(coalesce(nullif(regexp_replace(split_part(r.texto,'|',5),'[^0-9.\-]','','g'),'')::numeric,0)) picked_exc,
           bool_or(coalesce(btrim(split_part(r.texto,'|',5)),'') <> '') as tiene_dep
    from "Registros_Produccion_Virgilio" r
    where r.opcion = 'PKC'
      and r.ts_cliente >= v_desde
      and coalesce(
            (select cod_real from "Equivalencias_Codigos"
             where regexp_replace(upper(btrim(cod_pedido)),'^0+(?=.)','')
                 = regexp_replace(upper(btrim(split_part(r.texto,'|',2))),'^0+(?=.)','')
             limit 1),
            regexp_replace(upper(btrim(split_part(r.texto,'|',2))),'^0+(?=.)','')
          ) = v_norm_art
    group by 1
  ),
  fwd as (
    select p.tanda, p.picked, p.picked_exc, p.tiene_dep from picks p
    where p.picked >= 0
  ),
  fwd_t as (select distinct tanda from fwd),
  exc_avail as (
    select greatest(0, sum(delta))::numeric exc
    from "Movimientos_Stock"
    where regexp_replace(upper(btrim(cod_art)),'^0+(?=.)','') = v_norm_art
      and deposito = 'excedente'
      and not (tipo = 'picking' and upper(trim(ref)) in (select tanda from fwd_t))
  ),
  fwd2 as (
    select f.*,
           case when (f.tiene_dep and v_dep_on) then least(f.picked, greatest(f.picked_exc, 0))
                else f.picked end as want_exc
    from fwd f
  ),
  alloc as (
    select f.tanda, f.picked,
           least(f.want_exc, greatest(0, coalesce((select exc from exc_avail), 0)
             - coalesce(sum(f.want_exc) over (order by f.tanda
                        rows between unbounded preceding and 1 preceding), 0))) as from_exc
    from fwd2 f
  )
  insert into "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, legajo)
  select v_norm_art, 'separar_pedidos', picked, 'picking', tanda, 'pipeline' from alloc
  union all select v_norm_art, 'excedente', -from_exc, 'picking', tanda, 'pipeline' from alloc
  union all select v_norm_art, 'terminado', -(picked - from_exc), 'picking', tanda, 'pipeline' from alloc
  on conflict (upper(trim(ref)), upper(trim(cod_art)), coalesce(empresa,''), deposito, tipo) where tipo in ('picking','separado','facturado')
  do update set delta = excluded.delta;

end;
$function$;
