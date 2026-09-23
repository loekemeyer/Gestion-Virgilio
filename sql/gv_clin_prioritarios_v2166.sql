-- v21.66: gv_clin_prioritarios filtraba decision in (referenciado, valido); desde la v20.89 los
-- estados son referenciado / no_referenciado, asi que el no referenciado que PAGO nunca entraba.
create or replace view public.gv_clin_prioritarios with (security_invoker = true) as
 WITH cfg AS (
         SELECT COALESCE(( SELECT "PPP_Web_Config".valor FROM "PPP_Web_Config"
                  WHERE "PPP_Web_Config".clave = 'clin_prioridad_dias'::text), 2::numeric)::integer AS d
        )
 SELECT p.empresa, p.order_id, p.np, p.cod, p.razon_social,
    p.decision AS via,
    COALESCE(p.pagado_at, p.decision_at) AS listo_desde,
    lb.liberado_at,
    ( SELECT max(q.d) AS max
           FROM ( SELECT g.g::date AS d, row_number() OVER (ORDER BY g.g) AS rn
                   FROM generate_series(COALESCE(lb.liberado_at, now())::date::timestamp with time zone, (COALESCE(lb.liberado_at, now())::date + 20)::timestamp with time zone, '1 day'::interval) g(g)
                  WHERE gv_es_dia_habil(g.g::date)) q, cfg
          WHERE q.rn <= cfg.d) AS salir_antes_de
   FROM "GV_Cliente_Nuevo_Pipeline" p
     JOIN "GV_Cuarentena_Liberados" lb ON lb.empresa = p.empresa AND gv_cuarentena_clave(lb.order_id) = p.order_id
  WHERE p.cerrado_at IS NULL
    AND (p.decision = 'referenciado'::text
      OR (p.decision = ANY (ARRAY['no_referenciado'::text, 'valido'::text]) AND p.pagado_at IS NOT NULL));
alter view public.gv_clin_prioritarios set (security_invoker = true);
