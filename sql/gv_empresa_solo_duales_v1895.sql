-- v18.95 — LA EMPRESA EN EL STOCK SÓLO TIENE SENTIDO EN LOS CÓDIGOS DUALES
--
-- ⚠⚠ ESTE ARCHIVO **NO ESTÁ APLICADO**. Se corre a la hora de cierre del depósito.
-- Tarea de Planify 3527 · problema 337 (y de paso destapó el 340).
--
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 1. QUÉ ARREGLA
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Un código **NO DUAL tiene UNA SOLA PILA FÍSICA**: una góndola, un rack. Marcarle `empresa`
-- al movimiento no describe nada. Pero se marca, y **de forma asimétrica**: las SALIDAS
-- llevan LK/CH y las ENTRADAS históricas están en 'Mixto', así que el − no cancela al +.
-- Al 16/09: **62 códigos / 1.709 cajas** partidas (racks 1.105 · góndola 368 · excedente
-- 236), y creciendo todos los días.
--
-- | | empezó a marcar LK/CH | lo que entró |
-- |---|---|---|
-- | `picking` | 11/09 (2.222 filas viejas 'Mixto' contra 204 nuevas) | recepción vieja: 'Mixto' |
-- | `baja_racks` | 14/09 (empresa del sector, `Racks_Planimetria`) | ingreso/inicial/traslado: 100 % 'Mixto' |
--
-- **Los duales son SÓLO 4** — 437E, 438E, 439E y 809E — y son artículos **distintos** que
-- comparten número (809E: CH = Corta Queso, LK = Corta Pizza). Ésos conservan su LK/CH.
--
-- ⚠ Se verificó que la lista de 4 está COMPLETA: se buscaron códigos con celda de góndola en
-- las dos empresas y sólo aparecieron dos candidatos, **702E y 725E**, que NO son duales —
-- tienen una sola góndola (CH: M09/M10 y L40/L45) y el "LK" les viene del RACK (X1, X26).
--
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 2. LO QUE **NO** SE ROMPE (verificado uno por uno, no supuesto)
-- ═══════════════════════════════════════════════════════════════════════════════════════
--  1. **El saldo por código NO cambia.** Sólo cambia una etiqueta; ningún `delta`, ningún
--     depósito, ninguna fecha.
--  2. **`vista_saldos_stock`** agrupa por `outkey`, y `outkey` lleva la empresa **sólo si el
--     código es dual**. Para el resto el agrupamiento es idéntico; lo único que cambia es el
--     valor de la columna `empresa` de esa fila.
--  3. **`stocks_carga_rapida`** (la llena `actualizar_saldo_trigger`): su clave `norm_cod`
--     también lleva la empresa sólo si es dual. Sin cambio.
--  4. **`gv_stock_negativos`** suma todas las empresas antes de decidir → el `saldo` no se
--     mueve; sólo cambia el texto de `detalle_empresas`.
--  5. **`gv_stock_particion_sospechosa`** (centinela que ya existía para esto) **se vacía**
--     para los no duales. Mejora.
--  6. **Front, `_stkMovMatch`**: el filtro por empresa se aplica sólo si el código trae
--     sufijo (`"438E LK"`), o sea sólo para duales. Para el resto `emp = ""` y no filtra.
--  7. **`recepcion.js`** decide si un código es dual con `clave !== cod_art`, **no** con la
--     empresa; para un no dual suma todas las filas. `gondAcumPorCod` / `gondCapPorCod`
--     quedan igual.
--  8. **Producción Virgilio** escribe `empresa` pero **no la lee nunca**: 0 filtros
--     `empresa=eq.` y 0 `select` de esa columna sobre `Movimientos_Stock` en todo el repo.
--  9. **Los 4 duales no se tocan.**
--
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 3. ⚠⚠ EL TRIGGER Y EL BACKFILL VAN JUNTOS — MEDIDO, NO INFERIDO
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- `empresa` entra en dos índices ÚNICOS de deduplicación y los reconciliadores los usan como
-- `ON CONFLICT`:
--
--   mov_stock_pipeline_dedup  UNIQUE (upper(trim(ref)), upper(trim(cod_art)),
--                                     COALESCE(empresa,''), deposito, tipo)
--                             WHERE tipo IN ('picking','separado','facturado')
--   mov_stock_aguardar_dedup  UNIQUE (…, COALESCE(empresa,''), deposito) WHERE tipo='aguardar'
--
-- El propio código lo avisa, en `reconciliar_pipeline_stock_etapa1` (v17.07): *"SIN ESTO SE
-- DUPLICA EL PICKING … el ON CONFLICT —que incluye `coalesce(empresa,'')`— no matchea contra
-- la fila 'CH'/'LK'"*.
--
-- **Probado con las dos mitades, en transacciones revertidas, sobre `601E / E12E`:**
--
--   trigger nuevo + fila backfilleada a 'Mixto' → reinsert con 'LK' → **0 filas**  ✔ no duplica
--   trigger nuevo y la fila vieja en 'LK'       → reinsert con 'LK' → **1 fila**   ✘ DUPLICA
--
-- Lo que hace que funcione: en Postgres el **BEFORE INSERT corre ANTES de la comprobación de
-- unicidad**, así que el reconciliador manda `LK`, el trigger lo pisa a `Mixto`, y choca
-- contra la fila ya backfilleada. Si el backfill no se hizo, no choca y entra de nuevo.
--
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 4. LO QUE SÍ HAY QUE ARREGLAR EN EL MISMO PASO: `gv_ocupacion_lugar` (problema 340)
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Cruza el saldo contra el lugar con `AND s.empresa = l.empresa`, o sea exige que la empresa
-- del MOVIMIENTO sea la del LUGAR. Con todo en 'Mixto' no matchearía nunca.
--
-- ⚠ **Pero ya está mal HOY**, y por lo mismo: agarra sólo la porción etiquetada del saldo.
-- Medido: de 790 filas, **458 difieren del saldo real** y 55 dan NULL teniendo saldo —
-- **57.181 cajas de diferencia**. No la lee nadie (0 en el front de Gestión, 0 en el de
-- Producción, 0 vistas, 0 funciones, 0 crons; sólo está expuesta a `anon`), así que hoy no
-- hace daño, pero se arregla acá porque es el mismo principio: filtrar por empresa **sólo si
-- el código es dual**.
--
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 5. MEDIDO ANTES DE APLICAR
-- ═══════════════════════════════════════════════════════════════════════════════════════
--   · filas de códigos NO duales con empresa LK/CH ....................... 5.794
--   · colisiones contra mov_stock_pipeline_dedup ......................... 3  (benignas)
--   · colisiones contra mov_stock_aguardar_dedup ......................... 0  (0 filas afectadas)
--   · costo del UPDATE: 200 filas en 231 ms → ~6,7 s las 5.794
--     ⚠ el `statement_timeout` ronda los 8 s → **por lotes de 1.000**. El costo lo pone
--     `actualizar_saldo_trigger`, que recalcula el saldo completo del artículo una vez por fila.
--
-- Las 3 colisiones son el mismo caso y **no cambian ningún saldo**: tanda D72A, artículo 520,
-- donde convive una fila 'Mixto' con **delta 0** y la fila CH con el delta real
-- (55638992/63471807 excedente · 55634924/63467166 separar_pedidos · 55643060/63476448
-- terminado). El paso 4 las excluye.
--
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 6. CUÁNDO — depósito cerrado, y con los crons de escritura APAGADOS
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Cinco crons escriben en `Movimientos_Stock`. Los jobs **57 y 68 ya se serializan** con el
-- advisory lock **5768** (por eso el paso 2 lo toma también), pero **74 y 81 NO lo toman** y
-- corren cada 10 y cada 2 minutos: si uno inserta durante la migración, esa fila queda con
-- LK/CH sin backfillear y el reconciliador siguiente la puede duplicar. Por eso se apagan.
--
--   34 detectar-faltantes-llegaron      */2
--   57 refresh_stocks_carga_rapida      */5   (toma el lock 5768)
--   68 reconciliar-pipeline-stock       */10  (toma el lock 5768)
--   74 gv-reconciliar-facturado-web     5-55/10
--   81 gv-reconciliar-aguardar          */2
--
-- Chequeo de que el depósito está quieto (tiene que dar 0 filas):
--
--   select legajo, upper(btrim(split_part(texto,'|',1))) tanda,
--          round(extract(epoch from (now() - max(ts_cliente)))/60) hace_min
--     from public."Registros_Produccion_Virgilio"
--    where ts_cliente >= now() - interval '3 hours' and not public.es_legajo_test(legajo)
--    group by 1,2 having max(ts_cliente) > now() - interval '30 minutes';
--
-- y que no quede picking ni armado abierto (EP sin TP, AP sin TAP).
--
-- ═══════════════════════════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────────────────────────
-- PASO 0 — APAGAR LOS CRONS QUE ESCRIBEN
-- ───────────────────────────────────────────────────────────────────────────────────────
select cron.alter_job(34, active := false);
select cron.alter_job(57, active := false);
select cron.alter_job(68, active := false);
select cron.alter_job(74, active := false);
select cron.alter_job(81, active := false);

-- ───────────────────────────────────────────────────────────────────────────────────────
-- PASO 1 — BACKUP (el paso 4 pisa datos reales)
-- ───────────────────────────────────────────────────────────────────────────────────────
create table zz_backups."GV_Backup_MovStock_empresa_nodual_20260916" as
with du as (select distinct regexp_replace(upper(btrim(cod)),'^0+(?=.)','') cod from public.codigos_duales)
select m.id, m.empresa
  from public."Movimientos_Stock" m
  left join du on du.cod = regexp_replace(upper(btrim(m.cod_art)),'^0+(?=.)','')
 where du.cod is null and m.empresa in ('LK','CH');

alter table zz_backups."GV_Backup_MovStock_empresa_nodual_20260916" enable row level security;
revoke insert, update, delete, truncate on zz_backups."GV_Backup_MovStock_empresa_nodual_20260916"
  from anon, authenticated;

-- ~5.794. Si da muy distinto, PARAR y volver a medir.
select count(*) from zz_backups."GV_Backup_MovStock_empresa_nodual_20260916";

-- Y la foto del saldo ANTES, para comparar al final (paso 6c):
select md5(string_agg(cod_art || '|' || deposito || '|' || s, ',' order by cod_art, deposito)) as md5_antes
  from (select cod_art, deposito, sum(delta) s from public."Movimientos_Stock" group by 1,2) z;

-- ───────────────────────────────────────────────────────────────────────────────────────
-- PASO 2 — EL TRIGGER: un código NO dual se escribe SIEMPRE 'Mixto'
-- ───────────────────────────────────────────────────────────────────────────────────────
-- El bloque va ANTES de los de la v18.24 y la v18.86: esos dos eligen entre las DOS góndolas
-- de un dual, y en un código de una sola pila no hay nada que elegir.
do $mig$
declare d text; d0 text;
begin
  perform pg_advisory_xact_lock(5768);   -- el mismo que usan los jobs 57 y 68
  select pg_get_functiondef('public.trg_normalizar_empresa_stock()'::regprocedure) into d;
  d0 := d;
  d := replace(d,
    '  -- v18.24: una fila SIN empresa cuyo ref es una tanda ya pickeada hereda la empresa',
    '  -- v18.95: un codigo NO DUAL tiene UNA SOLA PILA FISICA (una gondola, un rack), asi que'  || chr(10) ||
    '  -- la empresa del movimiento no describe nada. Marcarla igual partia el saldo, porque se' || chr(10) ||
    '  -- marcaba ASIMETRICO: las salidas con LK/CH y las entradas historicas en Mixto, asi que' || chr(10) ||
    '  -- el - no cancelaba al +. Al 16/09 eran 62 codigos / 1.709 cajas y crecia todos los dias.'|| chr(10) ||
    '  -- Va ANTES de los bloques v18.24 y v18.86: esos dos eligen entre las DOS gondolas de un' || chr(10) ||
    '  -- dual, y aca no hay dos. Los duales son solo 4: 437E, 438E, 439E, 809E. Problema 337.'   || chr(10) ||
    '  IF NOT COALESCE(v_dual,false) THEN'                                                        || chr(10) ||
    '    NEW.empresa := ''Mixto'';'                                                               || chr(10) ||
    '    RETURN NEW;'                                                                             || chr(10) ||
    '  END IF;'                                                                                   || chr(10) ||
    '  -- v18.24: una fila SIN empresa cuyo ref es una tanda ya pickeada hereda la empresa');
  if d = d0 then raise exception 'el ancla del bloque v18.24 no matcheo: la funcion cambio, revisar'; end if;
  execute d;
end $mig$;

-- ───────────────────────────────────────────────────────────────────────────────────────
-- PASO 3 — `gv_ocupacion_lugar`: filtrar por empresa SÓLO si el código es dual (problema 340)
-- ───────────────────────────────────────────────────────────────────────────────────────
-- ⚠ NO usar `LEFT JOIN LATERAL` acá: la subconsulta se evalúa una vez por fila (790) contra
-- `saldo`, que es un seq scan de 62.495 movimientos → ~49 M de filas y la consulta SE CUELGA
-- (probado: timeout). Con dos joins planos son **858 ms**.
--
-- Verificado contra el saldo real: la vista nueva da **0 filas que difieran, 0 NULL teniendo
-- saldo y 0 cajas de diferencia** para los no duales, contra 458 / 55 / 57.181 de la actual.
drop view if exists public.gv_ocupacion_lugar;
create view public.gv_ocupacion_lugar
with (security_invoker = true) as
with du as (
  select distinct regexp_replace(upper(btrim(cod)),'^0+(?=.)','') cod from public.codigos_duales
), saldo as (
  select upper(btrim(m.cod_art)) as cod,
         upper(btrim(coalesce(m.empresa,''))) as empresa,
         case when m.deposito in ('racks','racks_ch') then 'rack'
              when m.deposito = 'insumos' then 'insumo' else 'gondola' end as destino,
         sum(m.delta) as saldo
    from public."Movimientos_Stock" m
   group by 1,2,3
), saldo_tot as (
  -- un codigo NO DUAL tiene UNA sola pila: todas las empresas juntas
  select cod, destino, sum(saldo) saldo from saldo group by 1,2
)
select l.sector, l.tipo, l.empresa, l.orden, li.cod, li.clase, li.cajas_max,
       sum(li.cajas_max) over (partition by li.cod, l.empresa) as cajas_max_total_cod,
       coalesce(sd.saldo, st.saldo) as saldo_cod,
       case when sum(li.cajas_max) over (partition by li.cod, l.empresa) > 0
            then round(100 * coalesce(sd.saldo, st.saldo)
                       / sum(li.cajas_max) over (partition by li.cod, l.empresa), 1)
       end as pct_ocupado_cod
  from public."GV_Lugar" l
  join public."GV_Lugar_Item" li on li.sector = l.sector and li.activo
  left join du dd on dd.cod = regexp_replace(upper(btrim(li.cod)),'^0+(?=.)','')
  -- DUAL: el saldo de SU gondola (el 809E de Loeke es un Corta Pizza y el de Chef un Corta Queso)
  left join saldo sd on dd.cod is not null
       and sd.cod = upper(btrim(li.cod)) and sd.empresa = l.empresa
       and sd.destino = case when li.clase = 'insumo' then 'insumo' else l.tipo end
  -- NO DUAL: el saldo entero, sin mirar la etiqueta de empresa
  left join saldo_tot st on dd.cod is null
       and st.cod = upper(btrim(li.cod))
       and st.destino = case when li.clase = 'insumo' then 'insumo' else l.tipo end
 where l.activo;

alter view public.gv_ocupacion_lugar set (security_invoker = true);

-- ───────────────────────────────────────────────────────────────────────────────────────
-- PASO 4 — BACKFILL, POR LOTES DE 1.000 (repetir hasta que devuelva 0 filas)
-- ───────────────────────────────────────────────────────────────────────────────────────
-- Excluye las 3 filas de D72A/520 que chocarían con mov_stock_pipeline_dedup.
with du as (select distinct regexp_replace(upper(btrim(cod)),'^0+(?=.)','') cod from public.codigos_duales),
objetivo as (
  select m.id from public."Movimientos_Stock" m
    left join du on du.cod = regexp_replace(upper(btrim(m.cod_art)),'^0+(?=.)','')
   where du.cod is null and m.empresa in ('LK','CH')
     and m.id not in (63471807, 63467166, 63476448)   -- D72A / 520, chocarían con el índice
   order by m.id limit 1000
)
update public."Movimientos_Stock" x set empresa = 'Mixto'
  from objetivo o where x.id = o.id;

-- ───────────────────────────────────────────────────────────────────────────────────────
-- PASO 5 — PRENDER LOS CRONS DE VUELTA
-- ───────────────────────────────────────────────────────────────────────────────────────
select cron.alter_job(34, active := true);
select cron.alter_job(57, active := true);
select cron.alter_job(68, active := true);
select cron.alter_job(74, active := true);
select cron.alter_job(81, active := true);

-- ───────────────────────────────────────────────────────────────────────────────────────
-- PASO 6 — VERIFICAR
-- ───────────────────────────────────────────────────────────────────────────────────────
-- (a) el centinela: vacío, o a lo sumo con es_dual = true
select es_dual, deposito, count(*) codigos, sum(fantasma) cajas
  from public.gv_stock_empresa_fantasma group by 1,2 order by 1 desc, 4 desc;

-- (b) no quedan no duales con LK/CH salvo las 3 de D72A/520  → esperado: 3
with du as (select distinct regexp_replace(upper(btrim(cod)),'^0+(?=.)','') cod from public.codigos_duales)
select count(*) from public."Movimientos_Stock" m
  left join du on du.cod = regexp_replace(upper(btrim(m.cod_art)),'^0+(?=.)','')
 where du.cod is null and m.empresa in ('LK','CH');

-- (c) el saldo por código NO se movió: mismo md5 que el del paso 1
select md5(string_agg(cod_art || '|' || deposito || '|' || s, ',' order by cod_art, deposito)) as md5_despues
  from (select cod_art, deposito, sum(delta) s from public."Movimientos_Stock" group by 1,2) z;

-- (d) ⚠ EL QUE IMPORTA: correr el reconciliador y ver que NO inserte nada nuevo.
--     Es la prueba de que el ON CONFLICT sigue matcheando y el picking no se duplica.
select public.reconciliar_pipeline_stock_etapa1();   -- esperado: 0
select public.gv_reconciliar_aguardar();             -- esperado: 0
-- Y que el centinela viejo tampoco se despierte:
select count(*) from public.gv_stock_particion_sospechosa;

-- ───────────────────────────────────────────────────────────────────────────────────────
-- ROLLBACK
-- ───────────────────────────────────────────────────────────────────────────────────────
-- (1) datos:
--   update public."Movimientos_Stock" m set empresa = b.empresa
--     from zz_backups."GV_Backup_MovStock_empresa_nodual_20260916" b where b.id = m.id;
-- (2) trigger: sacar el bloque que agrega el paso 2 —
--   do $$ declare d text; begin
--     select pg_get_functiondef('public.trg_normalizar_empresa_stock()'::regprocedure) into d;
--     execute regexp_replace(d, '  -- v18\.95: un codigo NO DUAL.*?  END IF;\n', '');
--   end $$;
-- (3) `gv_ocupacion_lugar`: ejecutar sql/backups/gv_ocupacion_lugar_pre_v1895.sql
--     (ojo: esa es la versión CON el bug del problema 340; lo normal es dejar la nueva).
-- ⚠ El rollback de datos y el del trigger van JUNTOS, por el mismo motivo que la ida
--    (sección 3): mitad y mitad duplica el picking.
