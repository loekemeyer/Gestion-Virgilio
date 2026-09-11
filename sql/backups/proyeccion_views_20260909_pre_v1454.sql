-- BACKUP pre-v14.54 (2026-09-09) — defs ORIGINALES de las 3 vistas de proyección,
-- antes de meter gv_cod_stock (pelar la L). Rollback = correr esto tal cual (drop gv_cod_stock
-- aparte si se quiere). Las 3 eran security_invoker=true.

create or replace view public.vista_venta_mensual with (security_invoker=true) as
  SELECT regexp_replace(upper(btrim(cod_art)), '^0+(?=.)', '') AS cod,
    to_char(date_trunc('month', fecha_salida::date::timestamp with time zone), 'YYYY-MM') AS mes,
    sum(COALESCE(cajas_entregadas, 0)) AS cajas,
    count(DISTINCT np) AS nps
   FROM "Entregas_Virgilio"
  WHERE fecha_salida ~ '^\d{4}-\d{2}-\d{2}' AND COALESCE(cajas_entregadas, 0) <> 0
  GROUP BY (regexp_replace(upper(btrim(cod_art)), '^0+(?=.)', '')),
           (to_char(date_trunc('month', fecha_salida::date::timestamp with time zone), 'YYYY-MM'));

create or replace view public.vista_recepcion_mensual with (security_invoker=true) as
  WITH seg AS (
    SELECT cmo.fecha::date AS f, cmo.tipo, cmo.nombre,
      regexp_replace(upper(btrim(split_part(s.s, '→', 1))), '^0+(?=.)', '') AS cod,
      NULLIF(regexp_replace(split_part(s.s, '→', 2), '[^0-9-]', '', 'g'), '')::numeric AS cajas
     FROM "Control_Modo_OP" cmo,
      LATERAL regexp_split_to_table(COALESCE(cmo.detalle, ''), '·') s(s)
    WHERE cmo.detalle IS NOT NULL AND cmo.fecha ~ '^\d{4}-\d{2}-\d{2}'
  )
  SELECT cod, to_char(date_trunc('month', f::timestamp with time zone), 'YYYY-MM') AS mes,
    COALESCE(NULLIF(btrim(nombre), ''), '(s/nombre)') AS proveedor,
    COALESCE(NULLIF(btrim(tipo), ''), '') AS tipo,
    sum(cajas) AS cajas, count(*) AS envios
   FROM seg
  WHERE cod IS NOT NULL AND cod <> '' AND cajas IS NOT NULL AND cajas <> 0
  GROUP BY cod, (to_char(date_trunc('month', f::timestamp with time zone), 'YYYY-MM')),
           (COALESCE(NULLIF(btrim(nombre), ''), '(s/nombre)')), (COALESCE(NULLIF(btrim(tipo), ''), ''));

create or replace view public.vista_stock_vs_pedidos with (security_invoker=true) as
  WITH stk AS (
    SELECT regexp_replace(upper(btrim(cod_art)), '^0+(?=.)', '') AS cod,
      sum(COALESCE(terminado,0)) AS terminado, sum(COALESCE(excedente,0)) AS excedente,
      sum(COALESCE(separar_pedidos,0)) AS separar_pedidos, sum(COALESCE(a_facturar,0)) AS a_facturar,
      sum(COALESCE(a_guardar,0)) AS a_guardar, sum(COALESCE(racks,0)) AS racks,
      sum(COALESCE(racks_ch,0)) AS racks_ch, sum(COALESCE(para_envasar,0)) AS para_envasar,
      sum(COALESCE(terminado,0)+COALESCE(excedente,0)+COALESCE(separar_pedidos,0)+COALESCE(a_facturar,0)+COALESCE(a_guardar,0)+COALESCE(racks,0)+COALESCE(racks_ch,0)+COALESCE(para_envasar,0)) AS stock_total
     FROM vista_saldos_stock
     GROUP BY (regexp_replace(upper(btrim(cod_art)), '^0+(?=.)', ''))
  ), pend_np AS (
    SELECT DISTINCT btrim(np) AS np FROM "PPP_Programacion_Diaria"
     WHERE NOT (btrim(np) IN (SELECT btrim(np) FROM "Facturacion_NP"))
  ), dem AS (
    SELECT regexp_replace(upper(btrim(b.articulo)), '^0+(?=.)', '') AS cod,
      sum(COALESCE(b.cajas,0)) AS pedidos_ped, count(DISTINCT b.pedido) AS nps_ped
     FROM "PPP_Base_Pedidos" b JOIN pend_np p ON btrim(b.pedido) = p.np
     WHERE NULLIF(btrim(b.articulo), '') IS NOT NULL
     GROUP BY (regexp_replace(upper(btrim(b.articulo)), '^0+(?=.)', ''))
  )
  SELECT COALESCE(s.cod, d.cod) AS cod, COALESCE(s.stock_total,0) AS stock_total,
    COALESCE(s.terminado,0) AS terminado, COALESCE(s.excedente,0) AS excedente,
    COALESCE(s.separar_pedidos,0) AS separar_pedidos, COALESCE(s.a_facturar,0) AS a_facturar,
    COALESCE(s.a_guardar,0) AS a_guardar, COALESCE(s.racks,0) AS racks,
    COALESCE(s.racks_ch,0) AS racks_ch, COALESCE(s.para_envasar,0) AS para_envasar,
    COALESCE(d.pedidos_ped,0) AS pedidos_ped, COALESCE(d.nps_ped,0) AS nps_ped,
    GREATEST(COALESCE(d.pedidos_ped,0) - COALESCE(s.stock_total,0), 0) AS falta
   FROM stk s FULL JOIN dem d ON d.cod = s.cod
  WHERE COALESCE(s.stock_total,0) <> 0 OR COALESCE(d.pedidos_ped,0) <> 0;
