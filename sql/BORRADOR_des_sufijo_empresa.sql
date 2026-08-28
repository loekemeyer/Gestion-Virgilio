-- =====================================================================
--  BORRADOR — Des-sufijo de empresa en cod_art del stock
--  Investigado 2026-08-28 (workflow des-sufijo-empresa wf_e98ab50a-77a).
--  Arquitecto FALLÓ por límite de sesión; este borrador sintetiza los
--  3 agentes investigadores. ⚠ NO APLICAR sin revisión completa + OKs.
--
--  OBJETIVO: reemplazar '437E LK'/'437E CH' por cod='437E' + empresa='LK'/'CH'
--  en Movimientos_Stock, Equivalencias_Codigos, Planimetria y satélites.
--
--  ESTADO: BORRADOR. Pendiente OK del dueño en 5 decisiones (ver abajo).
-- =====================================================================

-- =====================================================================
--  DECISIONES PENDIENTES DEL DUEÑO (no aplicar sin respuesta)
-- =====================================================================
-- D1. Saldos pelados vivos (nacieron de recepción sin sufijo post-split):
--     437E terminado 13, 438E terminado 13, 439E terminado 15 + excedente 19 cajas.
--     No hay OC/remito que pruebe la empresa (remitos 37831/37835 no están en Ordenes_Compra).
--     PROPUESTA: asignar LK (Equivalencias manda el pedido pelado de los 3 coladores
--     a stock LK F09/F13/H33; y cuando se identificó CH se marcó a mano con sufijo).
--     ¿Confirma LK?
--
-- D2. PKC históricos (71 eventos con sufijo en texto de Registros_Produccion_Virgilio):
--     No editar el texto. Neutralizarlos con filas PUENTE en Equivalencias_Codigos:
--     insertar cod_pedido='437E LK'→(cod_real='437E', empresa='LK'), etc.
--     Así el pipeline SQL los resuelve al pelado sin tocar los textos históricos.
--     ¿Confirma puente en lugar de editar textos?
--
-- D3. Stock_Ubicaciones tiene 2 filas '439E LK' (ids 151, 215).
--     ¿Pelar + empresa, o regenerar snapshot completo?
--
-- D4. Saldos pelados del 809E: 0 en terminado/racks. El '809' pelado (9 cajas
--     terminado) es el Corta Queso NACIONAL de Chef (artículo DISTINTO de 809E).
--     Asignarle empresa='CH' como monoproducto. ¿OK?
--
-- D5. Trigger de normalización BEFORE INSERT en Movimientos_Stock (para clientes
--     con HTML viejo que sigan mandando sufijo): ¿agregar normalización al entrar
--     (patrón normalizar_unidad_insumo), o confiar solo en la ventana de despliegue?
-- =====================================================================

-- =====================================================================
--  ORDEN CRÍTICO DE MIGRACIÓN (ningún paso antes que el anterior)
-- =====================================================================
-- ETAPA 0 — BACKUPS (protocolo CLAUDE.md obligatorio)
-- =====================================================================
-- Exportar ANTES:
--   Movimientos_Stock (al menos las 765 filas sufijadas + las ~54 peladas de los 5 cods)
--   Equivalencias_Codigos (8 filas)
--   Planimetria (9 filas con sufijo)
--   Stock_Ubicaciones (2 filas '439E LK')
--   stocks_carga_rapida (filas actuales)

-- =====================================================================
-- ETAPA 1 — Pausar cron job 22 (reconciliar-pipeline-stock, cada 10 min)
--            Y trigger trg_pkc_reconciliar_rt
-- =====================================================================
-- Sin pausar el cron, en ≤10 min re-inserta '809E LK' etc. (40 PKC forward
-- en 27 tandas que se re-upsertean en cada corrida). RIESGO #1 CRÍTICO.
--
-- select cron.unschedule('reconciliar-pipeline-stock');  -- re-schedulear al final
-- ALTER TABLE public."Registros_Produccion_Virgilio" DISABLE TRIGGER trg_pkc_reconciliar_rt;

-- =====================================================================
-- ETAPA 2 — Equivalencias_Codigos: agregar columna empresa + pelar cod_real
--           + filas puente para PKC históricos
-- =====================================================================
ALTER TABLE public."Equivalencias_Codigos"
  ADD COLUMN IF NOT EXISTS empresa text CHECK (empresa IN ('LK', 'CH'));

-- Pelar cod_real + setear empresa en las 6 filas sufijadas:
UPDATE public."Equivalencias_Codigos" SET cod_real='437E', empresa='LK' WHERE cod_pedido='437E';
UPDATE public."Equivalencias_Codigos" SET cod_real='438E', empresa='LK' WHERE cod_pedido='438E';
UPDATE public."Equivalencias_Codigos" SET cod_real='439E', empresa='LK' WHERE cod_pedido='439E';
UPDATE public."Equivalencias_Codigos" SET cod_real='809E', empresa='CH' WHERE cod_pedido='809E';
UPDATE public."Equivalencias_Codigos" SET cod_real='438E', empresa='CH' WHERE cod_pedido='438EL';
UPDATE public."Equivalencias_Codigos" SET cod_real='439E', empresa='CH' WHERE cod_pedido='439EL';

-- Filas puente para los 71 PKC con sufijo en texto (D2):
INSERT INTO public."Equivalencias_Codigos" (cod_pedido, cod_real, empresa) VALUES
  ('437E LK', '437E', 'LK'),
  ('437E CH', '437E', 'CH'),
  ('438E LK', '438E', 'LK'),
  ('438E CH', '438E', 'CH'),
  ('439E LK', '439E', 'LK'),
  ('439E CH', '439E', 'CH'),
  ('809E LK', '809E', 'LK'),
  ('809E CH', '809E', 'CH')
ON CONFLICT (cod_pedido) DO NOTHING;

-- =====================================================================
-- ETAPA 3 — Planimetria: PK (cod) → PK (cod, empresa) + pelar cod
-- =====================================================================
-- La PK actual es (cod) SOLO. Con pelado, '437E LK' y '437E CH' colisionan.
-- La columna empresa ya existe y está cargada (LK/CH) en las 8 filas sufijadas.

ALTER TABLE public."Planimetria" DROP CONSTRAINT IF EXISTS "Planimetria_pkey";
-- Pelar los 8 cods sufijados:
UPDATE public."Planimetria" SET cod = regexp_replace(cod, '\s+(LK|CH|LOKE)$', '')
  WHERE cod ~ '\s+(LK|CH|LOKE)$';
ALTER TABLE public."Planimetria" ADD PRIMARY KEY (cod, empresa);

-- =====================================================================
-- ETAPA 4 — Movimientos_Stock: agregar columna empresa + índice + UPDATE datos
-- =====================================================================
ALTER TABLE public."Movimientos_Stock"
  ADD COLUMN IF NOT EXISTS empresa text CHECK (empresa IN ('LK', 'CH'));

-- UPDATE de las 765 filas sufijadas → cod pelado + empresa:
-- (Verificado: 0 colisiones en dedup con los datos actuales)
UPDATE public."Movimientos_Stock"
  SET empresa = CASE WHEN cod_art ~ ' LK$' THEN 'LK' WHEN cod_art ~ ' CH$' THEN 'CH' END,
      cod_art  = regexp_replace(cod_art, '\s+(LK|CH|LOKE)$', '')
  WHERE cod_art ~ '\s+(LK|CH|LOKE)$';

-- Saldos pelados vivos (decisión D1 — asignar LK, confirmación pendiente):
-- UPDATE public."Movimientos_Stock"
--   SET empresa = 'LK'
--   WHERE cod_art IN ('437E','438E','439E') AND empresa IS NULL
--     AND deposito != 'insumos';  -- los de 437E CH insumos ya tienen empresa

-- Recrear índice dedup incluyendo empresa:
DROP INDEX IF EXISTS mov_stock_pipeline_dedup;
CREATE UNIQUE INDEX mov_stock_pipeline_dedup
  ON public."Movimientos_Stock" (upper(trim(ref)), upper(trim(cod_art)), coalesce(empresa,''), deposito, tipo)
  WHERE tipo IN ('picking','separado','facturado');

-- Stock_Ubicaciones (D3 — 2 filas '439E LK'):
UPDATE public."Stock_Ubicaciones"
  SET cod_art = '439E', empresa = 'LK'
  WHERE cod_art = '439E LK';

-- =====================================================================
-- ETAPA 5 — Funciones SQL: actualizar ON CONFLICT + propagar empresa
-- =====================================================================
-- Las 4 funciones que tienen ON CONFLICT explícito contra mov_stock_pipeline_dedup:
--   reconciliar_pipeline_stock_etapa1 (3 ON CONFLICT en ramas B.1, B.2, B.3)
--   reconciliar_stock_articulo_rt (1 ON CONFLICT)
--   reconciliar_pipeline_stock_etapa2 (agrupación por empresa)
--   reconciliar_pipeline_stock etapas 3 y 4 (inline en la función principal)
--
-- Si el índice cambia (ETAPA 4) SIN actualizar estas funciones, ABORTAN
-- con "no unique or exclusion constraint matching ON CONFLICT specification".
-- Estas funciones son largas; se actualizan con CREATE OR REPLACE completo
-- (ver sql/ para las versiones actuales). PENDIENTE: redactar el CREATE OR REPLACE.

-- =====================================================================
-- ETAPA 6 — Vistas y matview
-- =====================================================================
-- vista_saldos_stock: GROUP BY debe incluir empresa
-- vista_stock_procesada (MATVIEW): reemplazar derivación regex por columna empresa;
--   UNIQUE INDEX (cod, empresa) en lugar de (cod)
-- stocks_carga_rapida: PK a (cod, empresa); actualizar actualizar_saldo_trigger
-- vista_nc_loeke_chef: reescribir split (Planimetria GROUP BY cod HAVING ambas empresas)
-- vista_faltante_demanda/real: dejar de reconstruir el sufijo, emitir columna empresa
-- vista_faltante_catalogo: decidir si suma por cod pelado o incorpora empresa

-- =====================================================================
-- ETAPA 7 — Reanudar cron + trigger
-- =====================================================================
-- select cron.schedule('reconciliar-pipeline-stock', '*/10 * * * *',
--   'select public.reconciliar_pipeline_stock();');
-- ALTER TABLE public."Registros_Produccion_Virgilio" ENABLE TRIGGER trg_pkc_reconciliar_rt;

-- =====================================================================
-- ETAPA 8 — Front (index.html): ~30 call sites
-- =====================================================================
-- Ver lista completa en el hallazgo del agente 'front'.
-- Hub principal: stockFetchSaldos (10083) + stockComputeSaldos (10108).
-- Cambio de indexar por cod_art sufijado → indexar por 'COD|EMP' compuesta.
-- Todos los POST a Movimientos_Stock: agregar campo empresa, mandar cod pelado.
-- loadPlanimetriaRemote (7319): agregar empresa al select y armar GONDOLA[cod|emp].
-- Tests a reescribir: emp-np.cjs, ssg-familia-empresa.cjs, dual-ubic-mg-draft.cjs,
--   ppp-chk-gondola.cjs, stk-base-split-oculta.cjs.
-- =====================================================================

-- =====================================================================
--  RIESGOS CRÍTICOS (resumen)
-- =====================================================================
-- R1. Sin pausar cron 22, los 40 PKC forward re-insertan filas sufijadas en ≤10 min.
-- R2. Fronts viejos en celulares siguen escribiendo sufijado después de despliegue.
-- R3. Sin empresa en índice dedup, dos pickings LK+CH del mismo cod colapsan.
-- R4. vista_nc_loeke_chef devuelve vacío en silencio si no se reescribe.
-- R5. stocks_carga_rapida + vista_stock_procesada REFRESH falla por dup de cod.
-- R6. El editor de planimetría del front hace DELETE+INSERT total sin empresa:
--     puede borrar la empresa de las 8 filas si se despliega el front viejo.
-- R7. Si se asigna empresa incorrecta a los saldos pelados, reproduce el bug 809.
-- =====================================================================
