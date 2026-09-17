-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- v19.53 (2026-09-17) — EL CRON 57 BLOQUEABA LA PANTALLA DE STOCK 1,3 s CADA 5 MINUTOS
--
-- Segunda mitad de la respuesta a Luis (*"¿qué pasa con los benditos crons?"*). La primera es
-- `sql/gv_reconciliar_pipeline_etapa1_v1953.sql`.
--
-- `refresh_stocks_carga_rapida()` (cron **57**, `*/5 * * * *`) empezaba con:
--
--     REFRESH MATERIALIZED VIEW public.vista_stock_procesada;
--
-- **Sin `CONCURRENTLY`**, y ahí está el problema: un refresh no concurrente toma
-- **ACCESS EXCLUSIVE** sobre la matview, o sea que mientras dura **nadie puede leerla**. Y esa
-- matview es la que alimenta la pantalla de stock: `vista_saldos_stock` es la segunda consulta
-- más llamada de todo el proyecto (**15.984 llamadas, media 1.246 ms, máx 7.869 ms** — a 131 ms
-- del `statement_timeout` de 8 s).
--
-- **Medido:** el refresh bloqueante tarda **1.267 ms**, y era el **95 %** del tiempo de la
-- función.
--
-- ⚠ NO SE PUEDE ARREGLAR AGREGÁNDOLE `CONCURRENTLY` ACÁ: `REFRESH MATERIALIZED VIEW
-- CONCURRENTLY` no se puede ejecutar dentro de una transacción, y el cuerpo de una función
-- plpgsql siempre corre dentro de una. Por eso el cron 55 lo hace como comando suelto.
--
-- Y no hace falta: **es redundante.** El cron **55** (`refresh-vista-stock-procesada`,
-- `*/2 * * * *`) ya refresca esa misma matview **cada 2 minutos y CON `CONCURRENTLY`** (60
-- corridas en 2 h, 0 fallidas, 1,76 s de media). El cron 57 corre cada 5 minutos, así que la
-- matview que lee nunca tiene más de 2 minutos de atraso — menos que la frecuencia del propio
-- cron. Se saca la línea y listo.
--
-- **Verificación:** las dos versiones corridas sobre los datos reales en transacciones
-- abortadas, comparando el md5 de las 370 filas de `stocks_carga_rapida`
-- (`cod` + los 10 depósitos + total):
--
-- | | tiempo | filas | md5 |
-- |---|---|---|---|
-- | con el refresh bloqueante | 1.270 ms | 370 | `b3896f66eded33c465cd861440b1d106` |
-- | **sin el refresh** | **67 ms** | 370 | `b3896f66eded33c465cd861440b1d106` |
--
-- Idéntico, **19× más rápido**.
--
-- ⚠ LA DEPENDENCIA QUE ESTO CREA, ESCRITA PARA QUE NO SORPRENDA: el cron 57 ahora **depende del
-- cron 55** para tener la matview fresca. Si alguien apaga el 55, el 57 sigue andando pero
-- sincroniza saldos viejos, y **nada lo avisa**. Si hay que apagar el 55, volver a poner la
-- línea del REFRESH acá (o hacer el CONCURRENTLY desde un cron aparte).
--
-- **Lo que se vio en producción, y es el motivo real del cambio:** el 57 corre cada 5 min y el
-- 68 cada 10, así que **coinciden en :00 / :10 / :20 / :30…**, y los dos toman el mismo
-- `pg_advisory_xact_lock(5768)`. Corrida de las 17:20 del 17/09, medida:
--
-- | cron | duración |
-- |---|---|
-- | 68 `reconciliar-pipeline-stock` | 20,09 s |
-- | **57 `refresh_stocks_carga_rapida`** | **38,89 s** ← 20 s esperando el lock del 68 |
--
-- Contra 1,69 s del mismo cron 57 a las 17:15, cuando corrió solo. Por eso
-- `pg_advisory_xact_lock($1)` acumulaba **10.402 s de espera pura** (media 4,6 s, máx 67,6 s).
--
-- Problema 384. Rollback: poner de nuevo la línea `REFRESH MATERIALIZED VIEW
-- public.vista_stock_procesada;` como primera sentencia del `BEGIN`.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.refresh_stocks_carga_rapida()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- v19.53 — EL REFRESH BLOQUEANTE SALIO DE ACA. Estaba como
  --   REFRESH MATERIALIZED VIEW public.vista_stock_procesada;
  -- (sin CONCURRENTLY), o sea ACCESS EXCLUSIVE sobre la matview: 1.267 ms cada 5 minutos
  -- en los que NADIE puede leerla, y la lee la pantalla de stock (vista_saldos_stock).
  -- CONCURRENTLY no se puede usar desde una funcion (corre dentro de una transaccion), y
  -- ademas es redundante: el cron 55 ya refresca la matview cada 2 min CON concurrently.
  -- Medido: la funcion paso de 1.270 ms a 67 ms con stocks_carga_rapida identica
  -- (md5 b3896f66eded33c465cd861440b1d106 en las dos, 370 filas).
  -- Para volver atras: poner de nuevo la linea del REFRESH.

  -- v12.41: además de los campos derivados, resincronizar las COLUMNAS DE SALDO
  -- desde la matview (fuente calculada correcta). Antes solo se refrescaban los
  -- derivados y las columnas de saldo quedaban a merced del trigger; una fila que
  -- el trigger dejaba de tocar (ej. un cod pelado tras reatribuir empresa) quedaba
  -- congelada con un saldo viejo (el fantasma 809E -2). Ahora se auto-cura.
  UPDATE public.stocks_carga_rapida scr
  SET
    terminado         = COALESCE(vsp.terminado, 0),
    excedente         = COALESCE(vsp.excedente, 0),
    separar_pedidos   = COALESCE(vsp.separar_pedidos, 0),
    a_facturar        = COALESCE(vsp.a_facturar, 0),
    a_guardar         = COALESCE(vsp.a_guardar, 0),
    racks             = COALESCE(vsp.racks, 0),
    racks_ch          = COALESCE(vsp.racks_ch, 0),
    para_envasar      = COALESCE(vsp.para_envasar, 0),
    insumos_dep       = COALESCE(vsp.insumos_dep, 0),
    stock_total       = COALESCE(vsp.stock_total, 0),
    cajas_pedidas     = COALESCE(vsp.cajas_pedidas, 0),
    proy_cajas_mes    = COALESCE(vsp.proy_cajas_mes, 0),
    capacidad_gondola = COALESCE(vsp.capacidad_gondola, 0),
    es_insumo         = COALESCE(vsp.es_insumo, false),
    visible_en_stock  = COALESCE(vsp.visible_en_stock, true),
    descripcion       = COALESCE(vna.descripcion, vsp.descripcion, scr.descripcion),
    linea             = COALESCE(vsp.linea, scr.linea),
    cod_base          = COALESCE(vsp.cod_base, scr.cod_base),
    familia_principal = COALESCE(vsp.familia_principal, scr.familia_principal),
    es_secundario     = COALESCE(vsp.es_secundario, false)
  FROM public.vista_stock_procesada vsp
  LEFT JOIN public.vista_nombres_articulos vna
    ON UPPER(REGEXP_REPLACE(vna.cod, '^0+(?=.)', '')) = UPPER(REGEXP_REPLACE(vsp.cod, '^0+(?=.)', ''))
  WHERE scr.cod = vsp.cod;

  -- Insertar códigos nuevos que existan en la matview pero no en carga_rapida
  INSERT INTO public.stocks_carga_rapida
    (cod, cod_base, descripcion, linea, familia_principal, es_secundario,
     terminado, excedente, separar_pedidos, a_facturar, a_guardar, racks,
     racks_ch, para_envasar, insumos_dep, stock_total,
     cajas_pedidas, proy_cajas_mes, capacidad_gondola, es_insumo, visible_en_stock)
  SELECT
    vsp.cod, vsp.cod_base,
    COALESCE(vna.descripcion, vsp.descripcion),
    vsp.linea, vsp.familia_principal, vsp.es_secundario,
    COALESCE(vsp.terminado,0), COALESCE(vsp.excedente,0), COALESCE(vsp.separar_pedidos,0),
    COALESCE(vsp.a_facturar,0), COALESCE(vsp.a_guardar,0), COALESCE(vsp.racks,0),
    COALESCE(vsp.racks_ch,0), COALESCE(vsp.para_envasar,0), COALESCE(vsp.insumos_dep,0),
    COALESCE(vsp.stock_total,0),
    COALESCE(vsp.cajas_pedidas,0), COALESCE(vsp.proy_cajas_mes,0),
    COALESCE(vsp.capacidad_gondola,0), COALESCE(vsp.es_insumo,false), COALESCE(vsp.visible_en_stock,true)
  FROM public.vista_stock_procesada vsp
  LEFT JOIN public.vista_nombres_articulos vna
    ON UPPER(REGEXP_REPLACE(vna.cod, '^0+(?=.)', '')) = UPPER(REGEXP_REPLACE(vsp.cod, '^0+(?=.)', ''))
  WHERE NOT EXISTS (SELECT 1 FROM public.stocks_carga_rapida WHERE cod = vsp.cod);

  -- v12.41: eliminar filas HUÉRFANAS (existen en carga_rapida pero ya no en la matview)
  DELETE FROM public.stocks_carga_rapida scr
  WHERE NOT EXISTS (SELECT 1 FROM public.vista_stock_procesada vsp WHERE vsp.cod = scr.cod);

  UPDATE public.stocks_carga_rapida SET fc_sin_salida = 0;
  UPDATE public.stocks_carga_rapida scr
  SET fc_sin_salida = COALESCE(fc.cajas, 0)
  FROM public.vista_fc_sin_salida fc
  WHERE scr.cod = fc.cod;
END;
$function$;
