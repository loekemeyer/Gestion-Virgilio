-- v16.51 — Problema 80: el detector de NP dobles sacaba la fecha de UNA sola tabla
--
-- `public.gv_np_web_dobles` avisa cuando el mismo cliente tiene, para la MISMA fecha de
-- recepción, un pedido web programado por Gestión y una NP de ISIS: o sea, el pedido cargado
-- dos veces. Para saber de qué fecha es la NP de ISIS miraba sólo `GV_PPP_Base_Pedidos.fecha`.
--
-- Esa tabla está congelada el 2026-09-04 (última NP 98700), así que cualquier NP de ISIS
-- posterior no tenía fecha, el `join np_fecha` la descartaba y el detector no la podía ver.
--
-- Ahora la fecha sale de DOS fuentes, con `UNION` (no con `min()`): alcanza con que una de las
-- dos coincida con la fecha de recepción del pedido web.
--   1. `GV_PPP_Base_Pedidos.fecha`            — 833 pares (np, fecha), el histórico
--   2. `GV_PPP_Programacion_Diaria.fecha_recep` — 133 pares, el mismo dato desde la programación
-- De los de la segunda, 2 no están en la primera: son los que el detector no veía.
--
-- Medición: la vista devolvía 20 filas y sigue devolviendo 20. El cambio no agrega ni saca
-- nada hoy — hace que el detector siga sirviendo si ISIS vuelve a cargar.
--
-- Se le agregó `DISTINCT`: con dos fuentes de fecha una misma NP puede aparecer por las dos.
--
-- ⚠ LO QUE SE DESCUBRIÓ MIRANDO ESTO, y es más grande que el bug:
-- **el espejo de ISIS entero se congeló el 04/09**, no sólo `GV_PPP_Base_Pedidos`.
-- `GV_PPP_Programacion_Diaria` también: su última NP es la 98704 (Salvetti, D60G) y su
-- `fecha_recep` máxima es 2026-09-04. **No hay ningún cron que las alimente** — las dos se
-- escriben desde afuera por PostgREST (anon tiene INSERT/UPDATE con policy `*`), o sea desde el
-- Apps Script de la hoja PPP. Y esa hoja ya no existe (dueño, 2026-09-12). Así que el espejo
-- congelado es la consecuencia esperada de haber pasado todo a Gestión, no una falla nueva.
-- Queda escrito para que nadie lo lea como una fuente viva: si ISIS volviera a cargar pedidos
-- propios, Gestión no se enteraría hasta que alguien vuelva a alimentar esas dos tablas.
--
-- BACKUP: zz_backups."GV_Backup_np_web_dobles_20260913" (la definición previa, ya como
--         `create or replace view`, con sus `reloptions`).

create or replace view public.gv_np_web_dobles with (security_invoker = true) as
 WITH corte AS (
         SELECT gv_espejo_corte.lk, gv_espejo_corte.chef
           FROM gv_espejo_corte() gv_espejo_corte(lk, chef)
        ), np_prod AS (
         SELECT regexp_replace(btrim(x.np), '\.0+$'::text, ''::text) AS np,
            btrim(x.cod) AS cod
           FROM ( SELECT "GV_PPP_Programacion_Diaria".np, "GV_PPP_Programacion_Diaria".cod
                   FROM "GV_PPP_Programacion_Diaria"
                UNION ALL
                 SELECT "Facturacion_NP".np, "Facturacion_NP".cod_cliente FROM "Facturacion_NP"
                UNION ALL
                 SELECT "GV_PPP_Entregados_Historico".np, "GV_PPP_Entregados_Historico".cod
                   FROM "GV_PPP_Entregados_Historico"
                UNION ALL
                 SELECT "Entregas_Virgilio".np, "Entregas_Virgilio".cod_cliente FROM "Entregas_Virgilio") x
             CROSS JOIN corte c
          WHERE x.np IS NOT NULL AND NULLIF(btrim(x.cod), ''::text) IS NOT NULL
            AND gv_espejo_np_pasa(x.np, c.lk, c.chef)
        ), np_fecha AS (
         SELECT regexp_replace(btrim("GV_PPP_Base_Pedidos".pedido), '\.0+$'::text, ''::text) AS np,
                "GV_PPP_Base_Pedidos".fecha::date AS fecha
           FROM "GV_PPP_Base_Pedidos"
          WHERE NULLIF(btrim("GV_PPP_Base_Pedidos".fecha), ''::text) IS NOT NULL
         UNION
         SELECT regexp_replace(btrim("GV_PPP_Programacion_Diaria".np), '\.0+$'::text, ''::text),
                NULLIF(btrim("GV_PPP_Programacion_Diaria".fecha_recep), ''::text)::date
           FROM "GV_PPP_Programacion_Diaria"
          WHERE NULLIF(btrim("GV_PPP_Programacion_Diaria".fecha_recep), ''::text) IS NOT NULL
        )
 SELECT DISTINCT gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) AS np_web,
    w.empresa, w.order_id, w.np_idx, w.tanda, w.fecha_entrega,
    w.cod_cliente, w.razon_social, w.fecha_recep, n.np AS np_isis
   FROM "PPP_Web_Programacion" w
     JOIN np_prod n ON n.cod = btrim(w.cod_cliente)
     JOIN np_fecha f ON f.np = n.np AND f.fecha = w.fecha_recep
  WHERE w.np IS NOT NULL
    AND (w.empresa = 'lk'::text AND n.np ~ '^9'::text OR w.empresa = 'chef'::text AND n.np ~ '^4'::text);
