-- v23.61 (Luis 28/09): el aviso "tanda con paradas de dos recorridos" mostraba E44A (21/09), que ya habia
-- salido y se habia entregado (CCN/CRN de las 6 NP con texto "NP|tanda"). Lo que ya salio es historia.
create or replace view public.gv_ppp_tanda_camion_mezclado with (security_invoker = true) as
 SELECT fecha_entrega AS fecha,
    upper(btrim(tanda)) AS tanda,
    count(*)::integer AS nps,
    count(DISTINCT btrim(cod_cliente))::integer AS clientes,
    string_agg(DISTINCT gv_ppp_web_camion(zona, NULL::text), ' + '::text) AS camiones,
    string_agg(DISTINCT COALESCE(zona, '(sin zona)'::text), ' + '::text) AS zonas
   FROM "PPP_Web_Programacion" w
  WHERE COALESCE(NULLIF(btrim(tanda), ''::text), ''::text) <> ''::text AND COALESCE(zona, ''::text) ~ '^\s*Zona\s*[0-9]+'::text
    AND NOT EXISTS (SELECT 1 FROM "Registros_Produccion_Virgilio" r
                     WHERE r.opcion = ANY (ARRAY['CCN'::text, 'CRN'::text])
                       AND upper(btrim(split_part(r.texto, '|', 1))) = upper(gv_ppp_web_np_label(w.empresa, w.np, w.np_idx))
                       AND NOT es_legajo_test(r.legajo))
  GROUP BY fecha_entrega, (upper(btrim(tanda)))
 HAVING count(DISTINCT gv_ppp_web_camion(zona, NULL::text)) > 1;
