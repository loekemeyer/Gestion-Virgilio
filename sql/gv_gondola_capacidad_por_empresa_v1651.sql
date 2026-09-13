-- v16.51 — Problema 92, lo que faltaba del tramo 4: la CAPACIDAD de góndola de un dual
-- también es la de SU empresa, no la suma de las dos.
--
-- La v16.30 (tramo 4) arregló el SALDO: para un dual, el aviso de "no devolver a góndola"
-- pasó a mirar la góndola de la empresa de la recepción. Pero dejó anotado, textual, lo que
-- no había tocado: *"La CAPACIDAD de góndola de un dual sigue siendo la suma de las dos
-- góndolas. Capacidad_Sector tiene columna empresa pero no se filtra todavía."*
--
-- Consecuencia: el chequeo comparaba UNA góndola contra la capacidad de DOS.
--
--   809E, 400 cajas recibidas          capacidad   umbral 1,20×   góndola   ¿avisa?
--   antes (capacidad sumada)  por LK        388          465,6        28      NO   ← el bug
--   antes                     por CH        388          465,6       120      sí
--   ahora                     por LK        100          120,0        28      SÍ
--   ahora                     por CH        288          345,6       120      sí
--
-- Por LK no avisaba nunca: la góndola de Loeke aguanta 100 cajas y el umbral estaba puesto
-- en 465,6 porque le sumaba las 288 de la góndola de Chef, que es otro producto (el 809E en
-- J13-J14 es un Corta Pizza; en M13-M15, un Corta Queso).
--
-- El filtro se aplica SÓLO a los duales (`gv_stock_clave` los delata: para un dual la clave
-- difiere del código), así que para el resto la conducta es idéntica — control con el 505:
-- capacidad 3340 y góndola 2719 con LK y con CH, igual que antes.
--
-- `LOKE` cuenta como `LK`: así está cargado el 439E en Ñ53-Ñ54. Capacidad de los 4 duales
-- al 13/09:  437E LK 120 / CH 48 · 438E LK 64 / CH 30 · 439E LK 66 / CH 0 · 809E LK 100 / CH 288.
-- El 439E no tiene ninguna celda de Chef (es el problema 88): por CH la capacidad da 0 y el
-- chequeo no avisa, que es la conducta correcta mientras no se le cargue el lugar.
--
-- La firma de 1 argumento (sin empresa) queda igual: con `p_empresa` nulo ningún código es
-- dual para `gv_stock_clave`, así que suma todas las celdas como siempre.
--
-- FRONT (el camino vivo): `recepcion.js` hace este mismo cálculo sin pasar por la RPC. Se le
-- agregaron dos funciones puras, `gondDualesDe` y `gondCapPorCod`, testeadas de verdad en
-- tests/gond-exceso-dual.cjs (19 chequeos) con los mismos números que devuelve el backend.
-- De paso se arregló `_opPrefetchGond` (el cartel "cap / góndola" de la pantalla de cajas),
-- que pedía `vista_saldos_stock.clave = <código pelado>`: para un dual eso no matchea ninguna
-- fila y el cartel decía "s/dato" siempre.
--
-- BACKUP: zz_backups."GV_Backup_gondola_return_check_20260913", fila
--         'DDL v16.50 public.gondola_return_check(jsonb,text)' — la definición previa, ya
--         viene como CREATE OR REPLACE y se ejecuta tal cual para volver atrás.

create or replace function public.gondola_return_check(p_items jsonb, p_empresa text)
returns table(cod text, cajas integer, cap numeric, gond numeric, proy numeric, razon text)
language sql
stable
as $function$
  WITH items AS (
    SELECT norm_cod(elem->>'cod') AS cod_n,
           norm_cod(public.gv_stock_clave(elem->>'cod', p_empresa)) AS clave_n,
           (norm_cod(public.gv_stock_clave(elem->>'cod', p_empresa)) IS DISTINCT FROM norm_cod(elem->>'cod')) AS es_dual,
           (elem->>'cajas')::int AS cajas
    FROM jsonb_array_elements(p_items) AS elem
    WHERE norm_cod(elem->>'cod') <> ''
  ),
  cap AS (
    SELECT i.cod_n, sum(COALESCE(c.cajas_max, 0)) AS capacidad
    FROM items i
    JOIN "Capacidad_Sector" c ON norm_cod(c.cod) = i.cod_n
    WHERE NOT i.es_dual
       OR CASE WHEN upper(btrim(coalesce(c.empresa,''))) IN ('LK','LOKE') THEN 'LK'
               WHEN upper(btrim(coalesce(c.empresa,''))) = 'CH' THEN 'CH' END
          = upper(btrim(coalesce(p_empresa,'')))
    GROUP BY i.cod_n
  ),
  gond AS (
    SELECT norm_cod(s.clave) AS clave_n, sum(COALESCE(s.terminado, 0)) AS terminado
    FROM vista_saldos_stock s
    WHERE norm_cod(s.clave) IN (SELECT clave_n FROM items)
    GROUP BY norm_cod(s.clave)
  ),
  proy AS (
    SELECT norm_cod(p.cod) AS cod_n, sum(COALESCE(p.proy_cajas_mes, 0)) AS proy_cajas_mes
    FROM proyeccion_madre p
    WHERE norm_cod(p.cod) IN (SELECT cod_n FROM items)
    GROUP BY norm_cod(p.cod)
  )
  SELECT i.cod_n AS cod, i.cajas,
    COALESCE(c.capacidad, 0) AS cap,
    COALESCE(g.terminado, 0) AS gond,
    COALESCE(p.proy_cajas_mes, 0) AS proy,
    CASE
      WHEN COALESCE(c.capacidad, 0) > 0 AND COALESCE(p.proy_cajas_mes, 0) < 50
        AND (COALESCE(g.terminado, 0) + i.cajas) > COALESCE(c.capacidad, 0) * 1.2 THEN 'exceso_baja_rotacion'
      WHEN COALESCE(c.capacidad, 0) > 0
        AND (COALESCE(g.terminado, 0) + i.cajas) > COALESCE(c.capacidad, 0) * 1.2 THEN 'exceso_gondola'
      WHEN COALESCE(p.proy_cajas_mes, 0) < 50 AND COALESCE(p.proy_cajas_mes, 0) > 0 THEN 'baja_rotacion'
      ELSE NULL
    END AS razon
  FROM items i
  LEFT JOIN cap c ON c.cod_n = i.cod_n
  LEFT JOIN gond g ON g.clave_n = i.clave_n
  LEFT JOIN proy p ON p.cod_n = i.cod_n
  WHERE COALESCE(c.capacidad, 0) > 0
    AND ( (COALESCE(g.terminado, 0) + i.cajas) > COALESCE(c.capacidad, 0) * 1.2
       OR (COALESCE(p.proy_cajas_mes, 0) < 50 AND COALESCE(p.proy_cajas_mes, 0) > 0) );
$function$;

-- Verificación (lo de arriba, medido):
--   select 'LK', * from public.gondola_return_check('[{"cod":"809E","cajas":400}]','LK')
--   union all select 'CH', * from public.gondola_return_check('[{"cod":"809E","cajas":400}]','CH')
--   union all select '505 LK', * from public.gondola_return_check('[{"cod":"505","cajas":5000}]','LK')
--   union all select '505 CH', * from public.gondola_return_check('[{"cod":"505","cajas":5000}]','CH');
