-- v18.93 — LA EMPRESA EN EL STOCK SÓLO TIENE SENTIDO EN LOS CÓDIGOS DUALES
--
-- ⚠⚠ ESTE ARCHIVO **NO ESTÁ APLICADO**. Está escrito, medido y probado, listo para correr.
-- Condición de Luis (2026-09-16): *"hacé 3527 ahora si no hay nadie pickeando"*. Al momento
-- de escribirlo había picking activo, así que no se ejecutó. Ver "CUÁNDO CORRERLO" abajo.
-- Tarea de Planify 3527, problema 337.
--
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- QUÉ ARREGLA
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Un código **NO DUAL tiene UNA SOLA PILA FÍSICA**: una góndola, un rack. Marcarle `empresa`
-- al movimiento no describe nada — no hay dos montones que distinguir. Pero hoy se marca, y
-- **de forma asimétrica**: las SALIDAS llevan LK/CH y las ENTRADAS históricas están en
-- 'Mixto', así que el − no cancela al +. Resultado al 16/09: **62 códigos / 1.709 cajas** con
-- el saldo partido (racks 1.105 · góndola 368 · excedente 236), y creciendo todos los días.
--
-- | | pasó a marcar LK/CH | lo que entró |
-- |---|---|---|
-- | `picking` | 11/09 (2.222 filas viejas 'Mixto' contra 204 nuevas) | recepción vieja: 'Mixto' |
-- | `baja_racks` | 14/09 (empresa del sector, `Racks_Planimetria`) | ingreso/inicial/traslado: 100 % 'Mixto' |
--
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- ⚠⚠ LO QUE HAY QUE SABER ANTES DE TOCARLO: `empresa` ES PARTE DE UNA CLAVE ÚNICA
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- No es sólo una etiqueta. Entra en dos índices únicos de deduplicación:
--
--   mov_stock_pipeline_dedup  UNIQUE (upper(trim(ref)), upper(trim(cod_art)),
--                                     COALESCE(empresa,''), deposito, tipo)
--                             WHERE tipo IN ('picking','separado','facturado')
--   mov_stock_aguardar_dedup  UNIQUE (upper(btrim(ref)), upper(btrim(cod_art)),
--                                     COALESCE(empresa,''), deposito)  WHERE tipo = 'aguardar'
--
-- y los reconciliadores los usan como `ON CONFLICT`. El propio código lo avisa, en
-- `reconciliar_pipeline_stock_etapa1` (v17.07), textual:
--
--     "SIN ESTO SE DUPLICA EL PICKING. Si la empresa no se puede derivar del evento pero la
--      fila YA existe con empresa real, hay que reusar ESA empresa. Si no, el ON CONFLICT
--      -que incluye coalesce(empresa,'')- no matchea contra la fila 'CH'/'LK'"
--
-- **Consecuencia operativa: el trigger y el backfill van JUNTOS, en la misma transacción.**
-- Cambiar sólo el trigger deja las filas viejas en LK/CH y las nuevas en 'Mixto' — que es
-- exactamente la condición que duplica el picking. Por eso los pasos 2 y 3 no se separan.
--
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- MEDIDO (2026-09-16, antes de aplicar)
-- ═══════════════════════════════════════════════════════════════════════════════════════
--   · filas de códigos NO duales con empresa LK/CH ....................... 5.794
--   · colisiones contra mov_stock_pipeline_dedup ......................... 3  (ver abajo)
--   · colisiones contra mov_stock_aguardar_dedup ......................... 0  (0 filas afectadas)
--   · costo del UPDATE: 200 filas en 231 ms → ~6,7 s las 5.794
--     ⚠ el `statement_timeout` ronda los 8 s, así que va POR LOTES de 1.000, no de una.
--     El costo lo pone `actualizar_saldo_trigger`, que corre una vez por fila y recalcula
--     el saldo completo del artículo.
--
-- Las 3 colisiones son **todas del mismo caso y benignas**: tanda D72A, artículo 520, donde
-- convive una fila 'Mixto' con **delta 0** y la fila CH con el delta real:
--     55638992:Mixto:0  63471807:CH:0     (excedente)
--     55634924:Mixto:0  63467166:CH:6     (separar_pedidos)
--     55643060:Mixto:0  63476448:CH:-6    (terminado)
-- Se resuelven dejando esas 3 filas CH como están (paso 3 las excluye). No cambia ningún
-- saldo: 520 no es dual, así que su total ya era correcto.
--
-- PROBADO el comportamiento del trigger nuevo, en transacción revertida:
--     505 (no dual)  con LK → Mixto · con CH → Mixto · sin empresa → Mixto   ✓
--     438E (dual)    con LK → LK    · con CH → CH                            ✓
--     505L           pela la L a 505, no es dual → Mixto                     ✓
--
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- CUÁNDO CORRERLO
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Con el depósito quieto. Chequeo (tiene que dar 0 filas):
--
--   select legajo, upper(btrim(split_part(texto,'|',1))) tanda,
--          round(extract(epoch from (now() - max(ts_cliente)))/60) hace_min
--     from public."Registros_Produccion_Virgilio"
--    where ts_cliente >= now() - interval '3 hours' and not public.es_legajo_test(legajo)
--    group by 1,2 having max(ts_cliente) > now() - interval '30 minutes';
--
-- y que no quede ningún picking/armado abierto (EP sin TP, AP sin TAP).
--
-- ═══════════════════════════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────────────────────────
-- PASO 1 — BACKUP (obligatorio: el paso 3 pisa datos reales)
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

-- Tiene que dar ~5.794. Si da muy distinto, PARAR y volver a medir.
select count(*) from zz_backups."GV_Backup_MovStock_empresa_nodual_20260916";

-- ───────────────────────────────────────────────────────────────────────────────────────
-- PASO 2 — EL TRIGGER: un código NO dual se escribe SIEMPRE 'Mixto'
-- ───────────────────────────────────────────────────────────────────────────────────────
-- Se aplica con `replace()` sobre la definición viva, insertando el bloque ANTES de los
-- bloques v18.24 y v18.86 — esos dos existen para elegir entre las DOS góndolas de un dual
-- y no tienen sentido en un código de una sola pila, así que dejan de correr para ellos.
do $mig$
declare d text; d0 text;
begin
  select pg_get_functiondef('public.trg_normalizar_empresa_stock()'::regprocedure) into d;
  d0 := d;
  d := replace(d,
    '  -- v18.24: una fila SIN empresa cuyo ref es una tanda ya pickeada hereda la empresa',
    '  -- v18.93: un codigo NO DUAL tiene UNA SOLA PILA FISICA (una gondola, un rack), asi que'  || chr(10) ||
    '  -- la empresa del movimiento no describe nada. Marcarla igual partia el saldo, porque se' || chr(10) ||
    '  -- marcaba ASIMETRICO: las salidas con LK/CH y las entradas historicas en Mixto, asi que' || chr(10) ||
    '  -- el - no cancelaba al +. Al 16/09 eran 62 codigos / 1.709 cajas y crecia todos los dias.'|| chr(10) ||
    '  -- Va ANTES de los bloques v18.24 y v18.86: esos dos eligen entre las DOS gondolas de un' || chr(10) ||
    '  -- dual, y aca no hay dos. Problema 337.'                                                 || chr(10) ||
    '  IF NOT COALESCE(v_dual,false) THEN'                                                       || chr(10) ||
    '    NEW.empresa := ''Mixto'';'                                                              || chr(10) ||
    '    RETURN NEW;'                                                                            || chr(10) ||
    '  END IF;'                                                                                  || chr(10) ||
    '  -- v18.24: una fila SIN empresa cuyo ref es una tanda ya pickeada hereda la empresa');
  if d = d0 then raise exception 'el ancla del bloque v18.24 no matcheo: la funcion cambio, revisar'; end if;
  execute d;
end $mig$;

-- ───────────────────────────────────────────────────────────────────────────────────────
-- PASO 3 — BACKFILL, POR LOTES DE 1.000 (correr hasta que devuelva 0)
-- ───────────────────────────────────────────────────────────────────────────────────────
-- Excluye las 3 filas de D72A/520 que chocarían con mov_stock_pipeline_dedup (arriba).
-- En lotes para no acercarse al statement_timeout ni tomar un lock largo.
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
-- PASO 4 — VERIFICAR
-- ───────────────────────────────────────────────────────────────────────────────────────
-- (a) el centinela: tiene que quedar vacío o sólo con es_dual = true
select es_dual, deposito, count(*) codigos, sum(fantasma) cajas
  from public.gv_stock_empresa_fantasma group by 1,2 order by 1 desc, 4 desc;

-- (b) no quedan códigos no duales con LK/CH (salvo las 3 de D72A/520)
with du as (select distinct regexp_replace(upper(btrim(cod)),'^0+(?=.)','') cod from public.codigos_duales)
select count(*) from public."Movimientos_Stock" m
  left join du on du.cod = regexp_replace(upper(btrim(m.cod_art)),'^0+(?=.)','')
 where du.cod is null and m.empresa in ('LK','CH');
-- esperado: 3

-- (c) los saldos POR CÓDIGO no se movieron (la etiqueta cambió, el total no)
--     Correr ANTES y DESPUÉS y comparar el md5:
select md5(string_agg(cod_art || '|' || deposito || '|' || s, ',' order by cod_art, deposito))
  from (select cod_art, deposito, sum(delta) s from public."Movimientos_Stock" group by 1,2) z;

-- ───────────────────────────────────────────────────────────────────────────────────────
-- ROLLBACK
-- ───────────────────────────────────────────────────────────────────────────────────────
-- (1) los datos:
--   update public."Movimientos_Stock" m set empresa = b.empresa
--     from zz_backups."GV_Backup_MovStock_empresa_nodual_20260916" b where b.id = m.id;
-- (2) el trigger: sacar el bloque que agrega el paso 2 —
--   do $$ declare d text; begin
--     select pg_get_functiondef('public.trg_normalizar_empresa_stock()'::regprocedure) into d;
--     execute regexp_replace(d, '  -- v18\.93: un codigo NO DUAL.*?  END IF;\n', '');
--   end $$;
--   (o volver a aplicar sql/backups/trg_normalizar_empresa_stock_pre_v1885.sql y después
--    sql/trg_normalizar_empresa_stock_v1886.sql, que es la versión anterior completa).
