-- =====================================================================
--  MIGRACION — Stock por empresa (codigo pelado + columna empresa)
--  Reemplaza a BORRADOR_des_sufijo_empresa.sql (intento previo sin validar).
--
--  MODELO (confirmado por el dueno):
--    * cod_art SIEMPRE pelado (438E). La empresa va en columna aparte.
--    * empresa IN ('LK','CH','Mixto'). Mixto = comportamiento por defecto.
--    * Solo los codigos DUALES se separan por empresa (LK/CH). El resto es Mixto.
--    * Lista de duales = stock_v2.codigos_duales (hoy: 437E,438E,439E,809E).
--    * La empresa del pedido/picking se deriva del rango de NP (>90000=LK).
--    * 809 (Corta Queso Nacional) es un codigo propio, separado de 809E (D4).
--
--  ESTADO: >>> APLICADO EN PRODUCCION 2026-09-01 <<<  (cutover del BACK completo)
--          Backup recuperable en stock_v2.bkp_* (mov_stock, equivalencias,
--          planimetria, stock_ubic, carga_rapida, defs, cron).
--
--  Que se aplico (difiere del plan en 3 puntos, por menor riesgo):
--    1) Movimientos_Stock: columna empresa + trigger zz_normalizar_empresa +
--       backfill (sufijados->pelado+empresa; limbo 437E/438E/439E->LK) + indice
--       dedup con empresa. Resultado: 0 cod_art sufijados, 48670 con empresa.
--    2) El trigger consulta codigos_duales: fuerza Mixto para no-duales (backend
--       fuente de verdad); el front no necesita conocer la lista de duales.
--    3) vista_saldos_stock RECONSTRUYE el sufijo para duales en cod_art (438E CH)
--       + expone columna empresa. Asi la matview y todos los consumidores siguen
--       viendo el formato viejo -> NO se reescribio la matview de 200 lineas ni
--       los satelites (Planimetria/Equivalencias/Stock_Ubicaciones): esos van con
--       la migracion del FRONT (pendiente, desacoplada; el front viejo funciona
--       porque el trigger normaliza toda insercion).
--    Funciones: reconciliar_pipeline_stock_etapa1 (3 ON CONFLICT + subqueries B.3)
--       y reconciliar_stock_articulo_rt (1 ON CONFLICT) con coalesce(empresa,'').
--       actualizar_saldo_trigger reescrito (clave sufijada + filtro empresa).
--    e2e: los 4 duales conservan stock_total exacto; reconciliacion corre sin abortar.
--
--  AJUSTE POST-CUTOVER 2026-09-01: filas fantasma de codigos-alias + insumos.
--    (1) Los codigos con Equivalencias_Codigos (438EL->438E CH reenvasado x24,
--        y los pelados 437E/438E/439E/809E->su empresa) aparecian como fila
--        fantasma en la tabla (demanda con stock 0). FIX: funcion
--        public.resolver_equiv(cod) + la matview vista_stock_procesada resuelve
--        la equivalencia en dem_raw/dem_oc_raw (la demanda se consolida en el
--        destino, la fila alias desaparece). El front ya resolvia asi (ocgDemanda);
--        esto alinea el backend.
--    (2) Residuo del cutover: 7 movimientos de INSUMO de duales quedaron sufijados
--        (el backfill excluyo insumos) y colisionaban con el stock del mismo cod.
--        FIX: el trigger ahora pela el sufijo tambien en insumos (sin empresa) +
--        backfill de los 7 existentes. Sin este fix, (1) generaba duplicado de cod.
--    Matview reemplazada por DROP CASCADE + recrear (indice unico + Stock_Saldos).
--
--  PENDIENTE (mejora, no urgente): migrar el FRONT (mostrar pelado+empresa, pelar
--    Planimetria/Equivalencias/Stock_Ubicaciones) y el conteo fino de los 4 (D1=LK).
--
--  Decisiones del dueno (resueltas):
--    D1: saldos pelados 437E/438E/439E -> empresa='LK' (editable despues).
--    D2: PKC historicos con sufijo -> filas puente en Equivalencias_Codigos.
--    D3: Stock_Ubicaciones (col 'codigo') -> pelar + empresa.
--    D4: 809 y 809E son codigos distintos (primario/secundario). 809 queda
--        como base propio (Mixto, mono); 809E es el dual CH/LK. Coexisten.
--    D5: trigger de normalizacion BEFORE INSERT (red de seguridad fronts viejos).
-- =====================================================================

-- =====================================================================
--  YA VALIDADO en stock_v2 (cuadre contra produccion, cero diferencias):
--    - stock_v2.empresa_de_np(np)            -> LK/CH/NULL segun rango
--    - stock_v2.codigos_duales               -> 4 filas
--    - stock_v2.vista_saldos_stock           -> raiz por (cod_base, empresa);
--          cuadre EXCEPT vs public.vista_saldos_stock EN VIVO = 0 diferencias
--    - stock_v2.vista_stock_procesada        -> matview + columna empresa
--          (4 CH / 4 LK / 4 SIN / 355 Mixto), columnas de saldo/OC intactas
--    - stock_v2.trg_normalizar_empresa()     -> pela sufijo + setea empresa
--          (front viejo '438E CH' y nuevo '438E'+CH convergen a 438E+CH)
--    - Mecanica probada: pedido CH descuenta solo gondola CH del dual;
--          compartido (Mixto) es pila comun; sin cruce entre empresas.
--    - Caso borde tandas mixtas (D47B) resuelto: la empresa vive en el
--          evento de picking (sufijo del cod en PKC), no en la tanda.
-- =====================================================================

-- =====================================================================
--  ORDEN DE CUTOVER (estricto; ningun paso antes que el anterior)
-- =====================================================================

-- ---------- ETAPA 0 · BACKUPS (protocolo CLAUDE.md) ----------
-- Exportar ANTES (guardar como backup_YYYYMMDD_hhmmss_*.sql):
--   Movimientos_Stock (filas sufijadas + peladas de los duales)
--   Equivalencias_Codigos (8), Planimetria (sufijadas), Stock_Ubicaciones,
--   stocks_carga_rapida, y las definiciones actuales de las 4 funciones de
--   reconciliacion + vista_saldos_stock + vista_stock_procesada.
-- La foto stock_v2.saldo_baseline ya congela el saldo de referencia.

-- ---------- ETAPA 1 · PAUSAR cron + trigger RT (RIESGO #1) ----------
-- El cron 'reconciliar-pipeline-stock' corre cada 10 min y re-inserta filas
-- sufijadas (PKC forward). Sin pausarlo, deshace la migracion en <=10 min.
--   select cron.unschedule('reconciliar-pipeline-stock');
--   ALTER TABLE public."Registros_Produccion_Virgilio" DISABLE TRIGGER trg_pkc_reconciliar_rt;

-- ---------- ETAPA 2 · Movimientos_Stock: columna + trigger + backfill ----------
ALTER TABLE public."Movimientos_Stock"
  ADD COLUMN IF NOT EXISTS empresa text
  CHECK (empresa IN ('LK','CH','Mixto')) DEFAULT 'Mixto';

-- Requisito: public.empresa_de_np y public.codigos_duales (mover desde stock_v2).
CREATE TABLE IF NOT EXISTS public.codigos_duales (
  cod text PRIMARY KEY, nota text, creado timestamptz DEFAULT now());
INSERT INTO public.codigos_duales(cod,nota) VALUES
  ('437E','Colador 16cm — LK y CH productos distintos'),
  ('438E','Colador 20cm — LK y CH productos distintos'),
  ('439E','Colapasta/Colador pasta — LK y CH distintos'),
  ('809E','CH=Corta Queso / LK=Corta Pizza Familiar — distintos')
ON CONFLICT (cod) DO NOTHING;

CREATE OR REPLACE FUNCTION public.empresa_de_np(p_np text)
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
  SELECT CASE
    WHEN regexp_replace(coalesce(p_np,''),'\D','','g') = '' THEN NULL
    WHEN (regexp_replace(p_np,'\D','','g'))::bigint > 90000 THEN 'LK'
    ELSE 'CH' END;
$fn$;

-- Trigger de normalizacion (D5): el BACKEND es la fuente de verdad de la empresa.
-- Pela sufijo (fronts viejos); si el codigo NO es dual, FUERZA Mixto (ignora lo
-- que mande el front). Asi el front nunca necesita conocer la lista de duales,
-- y las funciones de reconciliacion siguen insertando sufijado sin reescribir logica.
-- (Validado en stock_v2: 355+CH->Mixto, 438E+CH->CH, 809+CH->Mixto, '438E CH'->438E+CH.)
CREATE OR REPLACE FUNCTION public.trg_normalizar_empresa_stock()
RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE v_base text; v_dual boolean;
BEGIN
  IF NEW.deposito = 'insumos' THEN RETURN NEW; END IF;   -- insumos no llevan empresa
  IF NEW.cod_art ~ '\s+(LK|LOKE)$' THEN
    NEW.empresa := 'LK'; NEW.cod_art := regexp_replace(NEW.cod_art,'\s+(LK|LOKE)$','');
  ELSIF NEW.cod_art ~ '\s+CH$' THEN
    NEW.empresa := 'CH'; NEW.cod_art := regexp_replace(NEW.cod_art,'\s+CH$','');
  END IF;
  v_base := regexp_replace(upper(btrim(NEW.cod_art)),'^0+(?=.)','');
  SELECT true INTO v_dual FROM public.codigos_duales
    WHERE regexp_replace(upper(btrim(cod)),'^0+(?=.)','') = v_base LIMIT 1;
  IF NOT COALESCE(v_dual,false) THEN
    NEW.empresa := 'Mixto';            -- no-dual: siempre Mixto
  ELSIF NEW.empresa IS NULL THEN
    NEW.empresa := 'Mixto';            -- dual sin empresa (raro); D1 lo corrige
  END IF;
  RETURN NEW;
END;
$fn$;
-- Debe correr DESPUES de fn_canon_cod_art (que canoniza el codigo). Nombre 'zz_'
-- para orden alfabetico al final de los BEFORE INSERT.
DROP TRIGGER IF EXISTS zz_normalizar_empresa ON public."Movimientos_Stock";
CREATE TRIGGER zz_normalizar_empresa BEFORE INSERT ON public."Movimientos_Stock"
  FOR EACH ROW EXECUTE FUNCTION public.trg_normalizar_empresa_stock();

-- Backfill de las filas sufijadas historicas -> pelado + empresa:
UPDATE public."Movimientos_Stock"
  SET empresa = CASE WHEN cod_art ~ '\s+(LK|LOKE)$' THEN 'LK'
                     WHEN cod_art ~ '\s+CH$' THEN 'CH' END,
      cod_art = regexp_replace(cod_art,'\s+(LK|CH|LOKE)$','')
  WHERE cod_art ~ '\s+(LK|CH|LOKE)$' AND deposito <> 'insumos';

-- D1: limbo pelado de los duales (nacio de recepcion sin sufijo) -> LK.
-- (Sus gondolas son F09/F13/H33 = las LK; editable despues si hace falta.)
UPDATE public."Movimientos_Stock"
  SET empresa = 'LK'
  WHERE regexp_replace(upper(btrim(cod_art)),'^0+(?=.)','') IN ('437E','438E','439E')
    AND deposito <> 'insumos'
    AND (empresa IS NULL OR empresa = 'Mixto');

-- Indice dedup con empresa (si no, las funciones con ON CONFLICT abortan):
DROP INDEX IF EXISTS mov_stock_pipeline_dedup;
CREATE UNIQUE INDEX mov_stock_pipeline_dedup
  ON public."Movimientos_Stock" (upper(trim(ref)), upper(trim(cod_art)), coalesce(empresa,''), deposito, tipo)
  WHERE tipo IN ('picking','separado','facturado');

-- ---------- ETAPA 3 · Satelites (D2/D3) ----------
-- Equivalencias_Codigos: columna empresa + pelar cod_real + filas puente PKC.
ALTER TABLE public."Equivalencias_Codigos"
  ADD COLUMN IF NOT EXISTS empresa text CHECK (empresa IN ('LK','CH','Mixto'));
-- (Pelar cod_real y puentes: reconstruir desde los datos reales al momento del
--  cutover — el borrador tenia mapeos que hay que re-verificar sobre las 8 filas.)

-- Stock_Ubicaciones (col 'codigo'):
ALTER TABLE public."Stock_Ubicaciones"
  ADD COLUMN IF NOT EXISTS empresa text CHECK (empresa IN ('LK','CH','Mixto')) DEFAULT 'Mixto';
UPDATE public."Stock_Ubicaciones"
  SET empresa = CASE WHEN codigo ~ '\s+(LK|LOKE)$' THEN 'LK'
                     WHEN codigo ~ '\s+CH$' THEN 'CH' ELSE 'Mixto' END,
      codigo  = regexp_replace(codigo,'\s+(LK|CH|LOKE)$','')
  WHERE codigo ~ '\s+(LK|CH|LOKE)$';

-- Planimetria: PK (cod) -> (cod, empresa) + pelar cod.
ALTER TABLE public."Planimetria" ADD COLUMN IF NOT EXISTS empresa text DEFAULT 'Mixto';
UPDATE public."Planimetria"
  SET empresa = CASE WHEN cod ~ '\s+(LK|LOKE)$' THEN 'LK'
                     WHEN cod ~ '\s+CH$' THEN 'CH' ELSE 'Mixto' END,
      cod     = regexp_replace(cod,'\s+(LK|CH|LOKE)$','')
  WHERE cod ~ '\s+(LK|CH|LOKE)$';
ALTER TABLE public."Planimetria" DROP CONSTRAINT IF EXISTS "Planimetria_pkey";
ALTER TABLE public."Planimetria" ADD PRIMARY KEY (cod, empresa);

-- ---------- ETAPA 4 · Funciones de reconciliacion ----------
-- Cambio MINIMO (gracias al trigger de normalizacion): solo el ON CONFLICT.
-- En reconciliar_pipeline_stock_etapa1 (ramas B.1/B.2/B.3),
--    reconciliar_stock_articulo_rt, y reconciliar_pipeline_stock_etapa2:
--    ON CONFLICT (upper(trim(ref)), upper(trim(cod_art)), deposito, tipo)
--  ->ON CONFLICT (upper(trim(ref)), upper(trim(cod_art)), coalesce(empresa,''), deposito, tipo)
-- La logica interna NO cambia: el trigger pela+setea empresa al insertar.
-- (CREATE OR REPLACE completos: se generan en el paso de verificacion e2e,
--  copiando la definicion actual y ajustando SOLO esa clausula.)

-- ---------- ETAPA 5 · Vistas + matview + saldos ----------
-- vista_saldos_stock: GROUP BY por (cod_base, empresa) con
--    empresa = COALESCE(columna, derivar del sufijo)  [transicion].
--    Version validada = stock_v2.vista_saldos_stock (adaptar la fuente de empresa).
-- vista_stock_procesada (MATVIEW): usar columna empresa; UNIQUE (cod, empresa).
-- stocks_carga_rapida: PK (cod) -> (cod, empresa); actualizar_saldo_trigger
--    debe agrupar por (cod_base, empresa).
-- vista_nc_loeke_chef: reescribir el split (Planimetria por (cod) HAVING ambas).
-- 4 vistas dependientes (faltantes/importados/insumos): emitir empresa, no sufijo.

-- ---------- ETAPA 6 · REANUDAR cron + trigger RT ----------
--   ALTER TABLE public."Registros_Produccion_Virgilio" ENABLE TRIGGER trg_pkc_reconciliar_rt;
--   select cron.schedule('reconciliar-pipeline-stock','*/10 * * * *',
--     'select public.reconciliar_pipeline_stock();');

-- ---------- ETAPA 7 · Front (index.html + recepcion.js) ----------
-- pkCodEmpresa: dejar de sufijar cod_art; mandar cod pelado + campo empresa.
-- recepcion.js: adjuntar opState.linea como empresa en el POST (ya tiene el dato).
-- Todos los POST a Movimientos_Stock: agregar campo empresa (o confiar en el
--    trigger para lo sufijado durante la transicion).
-- Tabla de stock: separar "marca" (artMarca) de "empresa" (columna) y agrupar
--    por (cod, empresa). loadPlanimetriaRemote: leer empresa, key GONDOLA[cod|emp].
-- Tests a reescribir: emp-np.cjs, ssg-familia-empresa.cjs, dual-ubic-mg-draft.cjs,
--    ppp-chk-gondola.cjs, stk-base-split-oculta.cjs.

-- =====================================================================
--  ROLLBACK
-- =====================================================================
-- Restore de los backups de ETAPA 0 + DROP de la columna empresa + indice viejo
-- + CREATE OR REPLACE de las funciones/vistas previas. El trigger de
-- normalizacion se puede dejar (es idempotente y no rompe lo viejo).

-- =====================================================================
--  RIESGOS (del borrador previo, vigentes)
-- =====================================================================
-- R1. Sin pausar cron 22, re-inserta sufijado en <=10 min. -> ETAPA 1 obligatoria.
-- R2. Fronts viejos siguen mandando sufijo. -> mitigado por el trigger (ETAPA 2).
-- R3. Sin empresa en el indice dedup, dos pickings LK+CH del mismo cod colapsan.
-- R4. vista_nc_loeke_chef devuelve vacio si no se reescribe.
-- R5. stocks_carga_rapida/matview REFRESH falla por dup de cod sin empresa en PK.
-- R6. El editor de planimetria del front (DELETE+INSERT total) puede borrar la
--     empresa si se despliega el front viejo -> desplegar front junto con ETAPA 3.
-- R7. Empresa incorrecta en el limbo reproduce el bug 809 -> D1 LK (editable).

-- =====================================================================
--  ADENDA v12.39 (2026-09-02) — Regla "L" completa (backend + front)
-- =====================================================================
-- Contexto: los codigos terminados en "L" (438EL/439EL) son articulos de
-- LOEKEMEYER que VENDE Chef -> el pedido entra como NP de Chef pero el stock
-- se agarra de la gondola de Loeke (438E LK). Verificado 2026-09-02: NINGUN
-- codigo de Loekemeyer termina en "L" (loke_products, chef_articulos_activos,
-- milver_products, chef_item_remap, todo el pipeline) -> regla sin excepcion.
-- Backup defs viejas: stock_v2.bkp_defs_20260902_lcodes.
--
-- (1) Equivalencias_Codigos: 438EL->438E LK, 439EL->439E LK (antes ...CH).
-- (2) Trigger trg_normalizar_empresa_stock: agrega, DESPUES del manejo del
--     sufijo " LK"/" CH", la normalizacion de la "L" final:
--       IF NEW.cod_art ~ '[0-9E]L$' THEN
--         NEW.empresa := 'LK';
--         NEW.cod_art := regexp_replace(NEW.cod_art,'([0-9E])L$','\1');
--       END IF;
--     Asi CUALQUIER movimiento que llegue con 438EL (front viejo, armado,
--     reconciliacion) se guarda cod_art='438E', empresa='LK'. Verificado con
--     insert de test (438EL/empresa CH -> 438E/LK).
-- (3) Vista v_cajas_pedidas: pela la "L" al agrupar
--       regexp_replace(articulo,'([0-9Ee])[Ll]$','\1')
--     en el SELECT y en el GROUP BY -> la demanda de 438EL consolida en 438E
--     (que la fila 438E LK absorbe por codBase) y no aparece renglon fantasma
--     al refrescar tras cancelar NP.
-- (4) Front (v12.37/v12.39, duplicado UX): pkEmpresaArt (L->LK), pkResolveArt
--     (pkCodEmpresa(pkStripL, np, pkEmpresaArt)) en aggFrom + armado (n.codes);
--     codEmpSplit pela L + fuerza LK; popup "Cajas pedidas" trae articulo
--     IN (base, baseL) y cuenta la variante L en la fila LK. El codigo del
--     PEDIDO en Entregas_Virgilio/factura queda crudo (438EL).
--
-- NOTA de arquitectura: en el STORAGE la empresa es una COLUMNA aparte
-- (cod_art='438E' + empresa='LK'). El "438E LK" que maneja el front es una
-- CLAVE COMPUESTA transitoria (lookup en GONDOLA/_stk.dem, key = cod+' '+emp),
-- reconstruida por vista_saldos_stock para compatibilidad. Al escribirse un
-- movimiento con ese string, el trigger lo PARTE de vuelta en las dos columnas.
-- El string concatenado nunca persiste. (Refactor front a par (cod,empresa)
-- en todos los call sites = pendiente opcional, sin ganancia funcional.)

-- =====================================================================
--  ADENDA v12.40 (2026-09-02) — Empresa en TODO el recorrido de la reconciliación
-- =====================================================================
-- Bug detectado por el usuario: tanda D55A / 809E tenía picking en LK pero el
-- 'separado' que genera la reconciliación cayó en 'Mixto' (split-brain): el +2
-- del picking quedaba pegado en separar_pedidos LK y aparecía un -2 fantasma en
-- Mixto. Causa: etapa1 (picking) era empresa-aware desde el cutover, pero las
-- etapas 2 (separado), 3 (facturado) y 4 (CP) escribían los duales SIN empresa
-- -> el trigger los mandaba a Mixto.
--
-- Fix (SECURITY: solo agrega 'empresa' al agrupado/insert; para no-duales no
-- cambia nada porque el trigger igual fuerza Mixto):
--  (1) reconciliar_pipeline_stock_etapa2: base agrupa por empresa; guard por
--      (tanda, artn, empresa); ventanas particionadas por empresa; el INSERT del
--      'separado' lleva la columna empresa (a.empresa).
--  (2) reconciliar_pipeline_stock etapa3 (facturado): src agrupa por empresa;
--      guard por empresa; INSERT lleva empresa.
--  (3) reconciliar_pipeline_stock etapa4 (CP): grp agrupa por empresa; INSERT
--      lleva empresa.
--  (4) Data D55A: las 2 filas 'separado' Mixto -> LK (ids 29694578/79), así
--      netea con el picking LK. Backup: stock_v2.bkp_d55a_20260902.
--
-- Verificado: 0 tandas con picking/separado en empresas distintas; 809E
-- separar_pedidos = 0 en las 3 empresas (ledger balanceado); Movimientos_Stock
-- NO crece al re-correr (49228->49228, el 'etapa1=NNNN' del return es un
-- row_count engañoso de ON CONFLICT DO NOTHING, no inserta). Residuo: la matview
-- deja un renglón pelado '809E' net-cero (separar -2 / a_facturar +2 /
-- stock_total 0) con visible_en_stock=false -> NO se muestra en el front. Son
-- movimientos Mixto históricos (pre-cutover, tanda entera Mixto); su limpieza
-- fina (atribuir cada tanda vieja a su empresa por NP) queda para el conteo
-- (Tarea #6), con cuidado porque 809E es producto ambiguo LK/CH.
-- Backup defs viejas: stock_v2.bkp_defs_20260902_lcodes.
