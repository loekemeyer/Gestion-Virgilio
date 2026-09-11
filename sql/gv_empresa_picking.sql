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
