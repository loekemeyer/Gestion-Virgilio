-- v29.62 (13/10/2026, pedido de Giuliana, problema 766): el EXCEDENTE que una tanda puede
-- tomar es el que EXISTIA cuando se pickeo (movimientos con ts <= su ultimo PKC), no el de hoy.
--
-- Antes, el pase forward (tandas con PKC desde etapa1_pkc_desde) recalculaba from_exc de TODAS
-- las tandas contra el saldo de excedente de HOY: una tanda sin dato de deposito en el PKC
-- (want_exc = picked) se llevaba el excedente que aparecio DESPUES de su picking. El 13/10 el
-- conteo de la estanteria P cargo excedente en 26 codigos y la corrida 15:11 del cron 68 le
-- devolvio a gondola el de 14 (501, 315, 222, 220, 862, 221, 355, 207, 560, 654, 234, 026, 902,
-- 570). Los totales por codigo quedaban bien; el reparto gondola/excedente no, cada 10 min.
--
-- Cambio: CTE ya_exc (lo que cada tanda ya tiene tomado del excedente); en alloc, una tanda con fila
-- de excedente conserva su reparto TAL CUAL (tambien si el PKC trae la pila: ese dato ya se aplico
-- la primera vez, topado al excedente que habia; E12F/512 y F21C/440E decian 1 de excedente con
-- excedente 0 y recalcularlas dejaba -1) y solo una tanda NUEVA toma del excedente libre de hoy.
-- Probado en transaccion abortada: 0 saldos cambian sobre el estado actual (idempotente), y con los
-- 14 ajustes del conteo cargados en el medio cambian exactamente esos 14. Se descarto el 'excedente al momento del PKC' (as-of):
-- re-repartia 106 saldos de 50 codigos y dejaba 4 gondolas en negativo.
-- Marcador: v29.62-exc-fijo.
--
-- Rollback: sql/reconciliar_pipeline_stock_etapa1_v1953.sql + sql/reconciliar_pipeline_stock_etapa1_v1707.sql
-- (la definicion viva anterior esta en zz_backups."GV_Backup_Etapa1_def_20261013", md5 7d6a3bb2c56bf77feebe4cd78db17188).

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
  fwd AS (select p.tanda, p.art, p.picked, p.picked_exc, p.tiene_dep, p.emp, p.leg, l.last_pk
          from picks p join lastpk l on l.tanda=p.tanda
          where p.picked>=0 and l.last_pk >= v_desde),
  fwd_t AS (select distinct tanda from fwd),
  -- v29.62-exc-fijo: lo que una tanda YA tomo del excedente no se recalcula contra el excedente
  -- de hoy (un conteo cargado despues no se reparte hacia atras). Solo una tanda NUEVA, sin fila
  -- de excedente, toma del excedente libre de hoy (si el PKC dice de que pila salio, manda el PKC
  -- en esa primera vez; despues la fila queda).
  -- Los cruces van por el codigo SIN ceros a la izquierda: el PKC puede decir '66' y la fila de
  -- stock '066' (D72C, 09/09): con el cruce crudo la tanda parecia nueva, no encontraba excedente
  -- y cada corrida le devolvia 28 cajas a gondola que el trigger en vivo volvia a sacar del excedente.
  ya_exc AS (
    select upper(trim(m.ref)) tanda, regexp_replace(upper(trim(m.cod_art)),'^0+(?=.)','') artn, -sum(m.delta) tomado
    from "Movimientos_Stock" m
    where m.deposito='excedente' and m.tipo='picking' and upper(trim(m.ref)) in (select tanda from fwd_t)
    group by 1,2
  ),
  exc_avail AS (
    select regexp_replace(upper(trim(cod_art)),'^0+(?=.)','') artn, greatest(0, sum(delta))::numeric exc   -- excedente LIBRE hoy
    from "Movimientos_Stock" where deposito='excedente' group by 1
  ),
  fwd2 AS (
    select f.*, regexp_replace(f.art,'^0+(?=.)','') artn, y.tomado,
           case when (f.tiene_dep and v_dep_on) then least(f.picked, greatest(f.picked_exc, 0))
                else f.picked end as want_exc
    from fwd f left join ya_exc y on y.tanda=f.tanda and y.artn=regexp_replace(f.art,'^0+(?=.)','')
  ),
  alloc AS (
    select f.tanda, f.art, f.picked, f.leg, f.emp,
           case
             when f.tomado is not null then least(f.picked, greatest(f.tomado, 0))   -- ya repartida: queda
             else least(f.want_exc, greatest(0, coalesce(x.exc,0)
                    - coalesce(sum(f.want_exc) filter (where f.tomado is null) over (partition by f.artn order by f.tanda
                               rows between unbounded preceding and 1 preceding),0)))
           end as from_exc
    from fwd2 f left join exc_avail x on x.artn=f.artn
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

-- Centinela (la regla no se puede perder):
-- insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
-- values ('reconciliar_pipeline_stock_etapa1','funcion','least\\(f\\.picked, greatest\\(f\\.tomado, 0\\)\\)',
--         'una tanda que ya tiene fila de excedente conserva su reparto: el excedente de hoy no se reparte hacia atras (conteo 13/10)',
--         'Giuliana De La Vega','v29.62');
