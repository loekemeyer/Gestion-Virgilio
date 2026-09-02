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
--  ESTADO: nucleo VALIDADO en el schema stock_v2 (ver mas abajo "YA VALIDADO").
--          Este archivo es el paquete de cutover. NO aplicar sin OK del dueno.
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
