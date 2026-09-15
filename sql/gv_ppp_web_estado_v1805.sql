-- v18.05 — `gv_ppp_web_estado`: un pedido ANULADO deja de decir "sin_programar"
--
-- Luis, 2026-09-15: *"si se anula un pedido ahora, ¿qué pasa con el código de NP? queda
-- registrado que fue a ese pedido anulado, no? Fijate a lo largo de la PPP cuando se anula un
-- pedido que siga esa lógica"*.
--
-- SE MIDIÓ toda la PPP con control positivo (anular el pedido lk/1375 dentro de un
-- `DO … raise exception`, y contar en qué vistas seguía apareciendo su NP "LK 0052"):
--
--   ANTES de anular  → gv_np_prog=1 · gv_ppp_detalle_dia=1 · gv_ppp_web_estado=1
--   DESPUÉS          → gv_ppp_web_estado=1     ← el único que quedaba mal
--
-- Todas las demás lo sueltan solas al perder la tanda. Ésta no: mostraba `sin_programar`, que es
-- lo mismo que dice de un pedido que todavía NO se programó. Un pedido anulado no está esperando
-- turno: no va a salir nunca.
--
-- ⚠⚠ `CREATE OR REPLACE VIEW` SIN `WITH (...)` **BORRA las reloptions**, o sea que se come el
-- `security_invoker = true` y la vista pasa a correr como `postgres`, salteando la RLS. Pasó acá
-- y por eso va el `alter view` del final. Comprobado: un `create or replace` de `gv_np_prog` con
-- su propia definición dejó `reloptions = (null)`.
--
-- ROLLBACK: sacar las dos ramas `WHEN c.order_id IS NOT NULL …` y el LEFT JOIN a
-- `GV_Web_Cancelados`, y volver a correr el `alter view`.

create or replace view public.gv_ppp_web_estado as
 WITH ev AS (
         SELECT r.texto AS tanda,
            max(CASE WHEN r.opcion = 'EP'::text  THEN r.created_at ELSE NULL::timestamp with time zone END) AS ep,
            max(CASE WHEN r.opcion = 'TP'::text  THEN r.created_at ELSE NULL::timestamp with time zone END) AS tp,
            max(CASE WHEN r.opcion = 'AP'::text  THEN r.created_at ELSE NULL::timestamp with time zone END) AS ap,
            max(CASE WHEN r.opcion = 'TAP'::text THEN r.created_at ELSE NULL::timestamp with time zone END) AS tap
           FROM "Registros_Produccion_Virgilio" r
          WHERE (r.opcion = ANY (ARRAY['EP'::text, 'TP'::text, 'AP'::text, 'TAP'::text]))
            AND (r.texto IN ( SELECT DISTINCT g_1.tanda FROM "PPP_Web_Programacion" g_1 WHERE g_1.tanda IS NOT NULL))
          GROUP BY r.texto
        )
 SELECT g.empresa,
    g.order_id,
    g.np_idx,
    g.np,
    gv_ppp_web_np_label(g.empresa, g.np, g.np_idx) AS np_label,
    g.cod_cliente,
    g.razon_social,
    g.tanda,
    g.zona,
    g.fecha_entrega,
    g.m3,
    g.cajas,
    g.lineas,
    g.es_agregado,
    g.agregado_a_np,
    g.agregado_en,
    g.prioridad,
        CASE
            WHEN f.np IS NOT NULL THEN 'facturado'::text
            WHEN e.tap IS NOT NULL THEN 'armado'::text
            WHEN e.ap IS NOT NULL THEN 'en_armado'::text
            WHEN e.tp IS NOT NULL THEN 'pickeado'::text
            WHEN e.ep IS NOT NULL THEN 'en_picking'::text
            WHEN g.tanda IS NOT NULL THEN 'programado'::text
            -- v18.05 (Luis) — un pedido ANULADO no es "sin programar": es un pedido que no va a
            -- salir nunca. El motivo dice cual de las tres cosas fue (anular / cancelar /
            -- desarmar), que son distintas aunque las tres terminen en GV_Web_Cancelados.
            -- Va DESPUES de los estados de trabajo a proposito: si la NP llego a pickearse o
            -- facturarse, eso es lo que hay que ver, no la marca.
            WHEN c.order_id IS NOT NULL AND c.motivo LIKE 'desarmado:%' THEN 'desarmado'::text
            WHEN c.order_id IS NOT NULL THEN 'anulado'::text
            ELSE 'sin_programar'::text
        END AS estado,
    COALESCE(e.tap, e.ap, e.tp, e.ep) AS estado_desde,
    f.np IS NULL AS puede_agregar,
    false AS puede_quitar,
    f.np IS NULL AND COALESCE(e.ep, e.tp, e.ap, e.tap) IS NOT NULL AS agregado_seria_urgente
   FROM "PPP_Web_Programacion" g
     LEFT JOIN ev e ON e.tanda = g.tanda
     LEFT JOIN "Facturacion_NP" f ON f.np = gv_ppp_web_np_label(g.empresa, g.np, g.np_idx)
     LEFT JOIN "GV_Web_Cancelados" c ON c.empresa = g.empresa AND c.order_id = g.order_id;

-- ⚠ OBLIGATORIO despues de cualquier create or replace de esta vista (ver la cabecera)
alter view public.gv_ppp_web_estado set (security_invoker = true);

-- ── Lo que NO se tocó, y por qué ──────────────────────────────────────────────────────────────
-- `gv_pedido_web_estado_pagina` (lo que ve el CLIENTE en la pagina de LK) mapea el estado a un
-- rango 1..8 y devuelve el nombre por indice; un estado que no conoce cae en el ELSE 1, o sea
-- que un pedido anulado le sigue diciendo al cliente "sin_programar". NO se cambio: que el
-- cliente vea "anulado" en la pagina es una decision comercial del dueno, no tecnica.
