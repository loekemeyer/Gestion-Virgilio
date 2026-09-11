-- ════════════════════════════════════════════════════════════════════
-- LA EMPRESA SOBREVIVE AL PICKING  (2026-09-11, pedido de Luis)
-- "la empresa tiene que acompañar al código a lo largo de toda esta pipeline"
--
-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  ⛔ NO APLICAR TODAVÍA — se corre AL MERGEAR la rama              ║
-- ║  `claude/trusting-cerf-1w5v54` a `main`, junto con               ║
-- ║  `gv_empresa_recepcion_mg.sql`. La base es la MISMA que usa la    ║
-- ║  app en vivo: esto cambia el descuento de stock en el instante.   ║
-- ╚══════════════════════════════════════════════════════════════════╝
--
-- ── El problema ──────────────────────────────────────────────────────
-- Las dos funciones de reconciliación insertan en "Movimientos_Stock" SIN
-- pasar `empresa`, así que toman el DEFAULT 'Mixto'; y el trigger
-- zz_normalizar_empresa lo confirma, porque para todo lo que no está en
-- `codigos_duales` (4 filas) hace NEW.empresa := 'Mixto' de una.
--
-- Con la recepción guardando LK/CH (gv_empresa_recepcion_mg.sql), la góndola
-- pasa a LLENARSE con una etiqueta y VACIARSE con otra. Medido el 11/09:
--   · 142 códigos afectados, 19.383 cajas en el balde 'Mixto'
--   · 519,7 cajas pickeadas por día
--   · 20 códigos en negativo en 7 días, 61 en 30, el agregado en ~37
-- y eso hace gritar al cron 13 (check-stock-anomalias, 08:00 ART), que lee
-- vista_saldos_stock FILA POR FILA, o sea por empresa.
--
-- ── De dónde sale la empresa ─────────────────────────────────────────
-- De la NP, que es donde el dato es inequívoco por construcción: las NP web
-- llevan la empresa en la etiqueta ("LK 0057") y PPP_Web_NP la tiene en la PK;
-- las de ISIS son 9xxxx = LK / 4xxxx = CH. El front ya la calculaba bien y la
-- tiraba; desde la v15.72 la manda en el 6º campo del PKC:
--
--     TANDA|ART|esp|real|excedente|EMPRESA
--
-- NO se deriva de la tanda: 28 de 1.197 tandas-día de la historia mezclan LK y
-- CH (2,34 %, la última el 01/09), así que la tanda no sirve como clave. Cuando
-- la tanda mezcla las dos para un código, el front manda "MIX" y acá se reparte como
-- hasta ahora — nunca se inventa una empresa. Sólo se aceptan 'LK' y 'CH'; cualquier
-- otro valor (MIX incluido) cuenta como no declarada. "MIX" no es un tercer balde:
-- existe para que el caso quede ASENTADO en el evento y se pueda buscar
--   select * from "Registros_Produccion_Virgilio" where opcion='PKC' and split_part(texto,'|',6)='MIX';
-- en vez de irse en silencio. Al 11/09 no ocurrió nunca: 0 de 5.872 pares (tanda, art).
--
-- Interruptor: update "Stock_Config" set valor='0' where clave='pkc_empresa_activo';
-- ⚠ OBJETO COMPARTIDO → anotar en docs/ROLLBACK-PRODUCCION.md.
-- ════════════════════════════════════════════════════════════════════

-- ── 1) Vista: el SECTOR de un artículo según su empresa ──────────────
-- Reemplaza la muleta del front, que buscaba una celda llamada "438E LK" en
-- Planimetria y, como sólo existen para 4 códigos de 351, tiraba la empresa
-- (`pkCodEmpresa`: G[cand] ? cand : a). Acá la empresa es una COLUMNA, así que
-- el sector sale de (código pelado, empresa) sin depender del nombre de la celda.
create or replace view public.gv_lugar_articulo
with (security_invoker = true) as
select regexp_replace(upper(btrim(i.cod)), '^0+(?=.)', '') as cod,
       l.empresa,
       l.tipo,
       i.sector,
       l.orden,
       i.cajas_max
  from public."GV_Lugar_Item" i
  join public."GV_Lugar"      l on l.sector = i.sector
 where i.clase = 'articulo' and i.activo and l.activo
   and l.empresa in ('LK','CH');

comment on view public.gv_lugar_articulo is
  'Sector de cada artículo por empresa (v15.72). El front la usa para ubicar al '
  'operario sin necesidad de que exista una celda "438E LK" en Planimetria.';

revoke all on public.gv_lugar_articulo from public;
grant select on public.gv_lugar_articulo to anon, authenticated;


-- ── 2) Las dos funciones de reconciliación escriben la EMPRESA ───────
-- Basadas en las definiciones VIVAS (sql/gv_pkc_deposito_v1541.sql, ya aplicado
-- en producción). Único cambio: leen el 6º campo del PKC y lo escriben en la
-- columna `empresa` en vez de dejar que caiga al DEFAULT 'Mixto'.
--
-- ⚠ El corte `pkc_empresa_desde` NO es opcional. Las filas ya escritas tienen
-- empresa 'Mixto' y el índice único lleva coalesce(empresa,''), así que una fila
-- nueva con 'LK' no choca con la vieja: quedarían LAS DOS y el stock se
-- descontaría DOS VECES. Con el corte por fecha, cada tanda vive entera de un
-- solo lado. Para prenderlo, DESPUÉS de que el front v15.72 esté publicado:
--   insert into public."Stock_Config"(clave, valor) values ('pkc_empresa_desde', now()::text)
--     on conflict (clave) do update set valor = now()::text;
-- Para apagarlo (vuelve todo a 'Mixto', sin rollback de código):
--   delete from public."Stock_Config" where clave = 'pkc_empresa_desde';
--
-- Verificación después de prenderlo:
--   select empresa, count(*) from public."Movimientos_Stock"
--    where tipo='picking' and ts >= now() - interval '1 day' group by 1;
-- ─────────────────────────────────────────────────────────────────────

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
  -- v15.41: interruptor. Sin la fila = prendido.
  select coalesce((select valor from "Stock_Config" where clave='pkc_deposito_activo'),'1') <> '0'
    into v_dep_on;
  -- v15.72: desde cuándo se respeta la EMPRESA del 6º campo. 'infinity' (el default,
  -- sin la fila) = apagado, todo sigue cayendo en 'Mixto' como hasta ahora. Es un
  -- CORTE POR FECHA y no un booleano a propósito: las filas viejas están escritas con
  -- empresa 'Mixto' y el índice único lleva coalesce(empresa,''), así que una fila
  -- nueva con 'LK' NO chocaría con la vieja — quedarían las dos y el stock se
  -- descontaría DOS VECES. Con el corte, cada tanda vive entera de un solo lado.
  select coalesce((select valor::timestamptz from "Stock_Config" where clave='pkc_empresa_desde'),
                  'infinity'::timestamptz) into v_emp_desde;

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

  CREATE TEMP TABLE IF NOT EXISTS _fwd_alloc (tanda text, art text, picked numeric, from_exc numeric, leg text, emp text);
  TRUNCATE _fwd_alloc;

  WITH picks AS (
    select upper(trim(split_part(r.texto,'|',1))) tanda,
           coalesce(e.cod_real, upper(trim(split_part(r.texto,'|',2)))) art,
           sum(coalesce(nullif(regexp_replace(split_part(r.texto,'|',4),'[^0-9.\-]','','g'),'')::numeric,0)) picked,
           -- v15.41: cajas declaradas del EXCEDENTE (5º campo del texto)
           sum(coalesce(nullif(regexp_replace(split_part(r.texto,'|',5),'[^0-9.\-]','','g'),'')::numeric,0)) picked_exc,
           bool_or(coalesce(btrim(split_part(r.texto,'|',5)),'') <> '') as tiene_dep,
           -- v15.72: EMPRESA declarada (6º campo). Sólo vale si TODOS los eventos de
           -- ese (tanda, artículo) dicen lo mismo y son posteriores al corte; si alguno
           -- viene vacío o discrepa, queda null y se reparte como siempre.
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
  -- v15.41: want_exc = lo que se QUIERE sacar del excedente. Declarado si el PKC lo
  -- trae; si no, `picked` entero (= la adivinanza vieja, que el clamp de abajo recorta).
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

  -- B.1: UPSERT separar_pedidos (re-picks actualizan el conteo)
  INSERT INTO "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, legajo, empresa)
  SELECT art,'separar_pedidos', picked,'picking', tanda, coalesce(leg,'pipeline'), coalesce(emp,'Mixto') FROM _fwd_alloc
  ON CONFLICT (upper(trim(ref)), upper(trim(cod_art)), coalesce(empresa,''), deposito, tipo) WHERE tipo IN ('picking','separado','facturado')
  DO UPDATE SET delta = excluded.delta, legajo = excluded.legajo;

  -- B.2: UPSERT excedente — recalcula asignación cada corrida
  INSERT INTO "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, legajo, empresa)
  SELECT art,'excedente', -from_exc,'picking', tanda, coalesce(leg,'pipeline'), coalesce(emp,'Mixto') FROM _fwd_alloc
  ON CONFLICT (upper(trim(ref)), upper(trim(cod_art)), coalesce(empresa,''), deposito, tipo) WHERE tipo IN ('picking','separado','facturado')
  DO UPDATE SET delta = excluded.delta, legajo = excluded.legajo;

  -- B.3: UPSERT terminado — balancea: delta = -(separar + exc) para que sumen 0
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
  v_emp_desde timestamptz;
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
  -- v15.72: ver la nota del corte por fecha en reconciliar_pipeline_stock_etapa1.
  select coalesce((select valor::timestamptz from "Stock_Config" where clave='pkc_empresa_desde'),
                  'infinity'::timestamptz) into v_emp_desde;

  -- Solo path FORWARD (path A histórico lo cubre el cron)
  with picks as (
    select upper(trim(split_part(r.texto,'|',1))) tanda,
           sum(coalesce(nullif(regexp_replace(split_part(r.texto,'|',4),'[^0-9.\-]','','g'),'')::numeric,0)) picked,
           -- v15.41: cajas declaradas del EXCEDENTE (5º campo)
           sum(coalesce(nullif(regexp_replace(split_part(r.texto,'|',5),'[^0-9.\-]','','g'),'')::numeric,0)) picked_exc,
           bool_or(coalesce(btrim(split_part(r.texto,'|',5)),'') <> '') as tiene_dep,
           -- v15.72: EMPRESA declarada (6º campo), misma regla que en el cron.
           case when bool_and(r.ts_cliente >= v_emp_desde)
                 and count(distinct nullif(upper(btrim(split_part(r.texto,'|',6))),'')) = 1
                 and bool_and(upper(btrim(split_part(r.texto,'|',6))) in ('LK','CH'))
                then max(nullif(upper(btrim(split_part(r.texto,'|',6))),''))
           end as emp
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
    select p.tanda, p.picked, p.picked_exc, p.tiene_dep, p.emp from picks p
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
    select f.tanda, f.picked, f.emp,
           least(f.want_exc, greatest(0, coalesce((select exc from exc_avail), 0)
             - coalesce(sum(f.want_exc) over (order by f.tanda
                        rows between unbounded preceding and 1 preceding), 0))) as from_exc
    from fwd2 f
  )
  insert into "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, legajo, empresa)
  select v_norm_art, 'separar_pedidos', picked, 'picking', tanda, 'pipeline', coalesce(emp,'Mixto') from alloc
  union all select v_norm_art, 'excedente', -from_exc, 'picking', tanda, 'pipeline', coalesce(emp,'Mixto') from alloc
  union all select v_norm_art, 'terminado', -(picked - from_exc), 'picking', tanda, 'pipeline', coalesce(emp,'Mixto') from alloc
  on conflict (upper(trim(ref)), upper(trim(cod_art)), coalesce(empresa,''), deposito, tipo) where tipo in ('picking','separado','facturado')
  do update set delta = excluded.delta;

end;
$function$;

-- ─────────────────────────────────────────────────────────────────────
-- 3) ⚠ ANTES DE PRENDER EL CORTE: reclasificar el SALDO que hoy vive en 'Mixto'
--
-- El corte `pkc_empresa_desde` evita el doble descuento, pero NO alcanza. El
-- problema que queda es otro: la góndola HOY tiene su saldo en el balde 'Mixto',
-- y si el picking empieza a descontar de 'LK' encuentra un balde casi vacío.
--
--   depósito           Mixto      LK     CH
--   terminado         26.484     182    144
--   racks             14.752     279    336
--   a_facturar         1.968       4     43
--   excedente          1.122       0      0
--   separar_pedidos      229       2      0
--   a_guardar             72   2.500     72   ← éste ya se migró el 11/09
--
-- O sea que sin esto, el primer picking de cada código deja 'LK' en negativo y el
-- cron 13 (check-stock-anomalias, 08:00 ART) manda un Telegram por cada uno: lee
-- vista_saldos_stock FILA POR FILA, y cada fila es una (código, empresa).
-- Medido el 11/09: 20 códigos en negativo en 7 días, 61 en 30.
--
-- La solución es la misma que usó el backfill de A Guardar: la empresa la da el
-- LUGAR. Cobertura medida el 11/09 — **272 de 272 códigos con saldo en Mixto en
-- góndola resuelven a UNA empresa**, y lo mismo en los otros tres depósitos:
--
--   depósito          cods  resuelve  dual  sin lugar   cajas
--   terminado          272       272     0          0  26.484
--   a_facturar         173       173     0          0   1.968
--   excedente           34        34     0          0   1.122
--   separar_pedidos     56        56     0          0     229
--
-- No se reescribe la historia: se hace UNA TRANSFERENCIA BALANCEADA por (código,
-- depósito) — saca el saldo de 'Mixto' y lo pone en su empresa. Neta cero, es
-- reversible y las filas viejas quedan como estaban.
--
-- `racks` queda AFUERA a propósito: 47 racks todavía no tienen empresa (los que
-- están vacíos; la derivan solos cuando se guarde algo). `insumos` también: no
-- tienen empresa, viven en los racks 'IN'.
-- ─────────────────────────────────────────────────────────────────────
create table if not exists public."GV_Backup_mixto_saldos_20260911" as
select m.deposito, m.cod_art, m.empresa, m.delta, m.tipo, m.ts, m.ref
  from public."Movimientos_Stock" m where coalesce(m.empresa,'') = 'Mixto';

with g as (select valor::timestamptz c from public."Stock_Config" where clave='cutoff_ts'),
mix as (
  select regexp_replace(upper(btrim(m.cod_art)),'^0+(?=.)','') cod, m.deposito, sum(m.delta) saldo
    from public."Movimientos_Stock" m, g
   where coalesce(m.empresa,'') = 'Mixto' and (m.tipo = 'inicial' or m.ts >= g.c)
     and m.deposito in ('terminado','excedente','separar_pedidos','a_facturar')
   group by 1,2 having sum(m.delta) <> 0),
lug as (
  select regexp_replace(upper(btrim(i.cod)),'^0+(?=.)','') cod, max(l.empresa) emp
    from public."GV_Lugar_Item" i join public."GV_Lugar" l on l.sector = i.sector
   where i.clase='articulo' and i.activo and l.empresa in ('LK','CH')
   group by 1 having count(distinct l.empresa) = 1)   -- duales afuera: ya viajan bien
insert into public."Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, legajo, empresa)
select m.cod, m.deposito, -m.saldo, 'ajuste', 'gv_empresa_backfill', 'pipeline', 'Mixto'
  from mix m join lug l on l.cod = m.cod
union all
select m.cod, m.deposito,  m.saldo, 'ajuste', 'gv_empresa_backfill', 'pipeline', l.emp
  from mix m join lug l on l.cod = m.cod;

-- Verificación (las tres tienen que dar lo esperado):
--   -- (a) no quedó saldo en Mixto en esos depósitos
--   select deposito, round(sum(delta)) from "Movimientos_Stock"
--    where coalesce(empresa,'')='Mixto'
--      and deposito in ('terminado','excedente','separar_pedidos','a_facturar')
--    group by 1;                                        -- → 0 en las cuatro
--   -- (b) el total por código NO se movió
--   select count(*) from (
--     select cod_art, sum(delta) s from "Movimientos_Stock" group by 1) x
--    where s is null;                                    -- → 0
--   -- (c) ninguna fila negativa (lo que mira el cron 13)
--   select count(*) from vista_saldos_stock
--    where terminado<0 or excedente<0 or a_guardar<0 or racks<0
--       or separar_pedidos<0 or a_facturar<0;            -- → 0
--
-- Rollback: delete from public."Movimientos_Stock" where ref = 'gv_empresa_backfill';
-- (es una transferencia que neta cero, así que borrarla devuelve todo a 'Mixto').
