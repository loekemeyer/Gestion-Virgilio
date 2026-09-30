-- v24.67 (Thomas, 30/09/2026) — Pincel silicona: se importa SUELTO (MC de 600) y Garcia envasa
-- 590E, 590ES y 890E. La compra a China es un INSUMO: fila 590E de Importados como PARTE.
-- Aplicado en hrxfctzncixxqmpfhskv con el sí de Thomas (D20 y D21).

-- 1) D20: el insumo 590E se usa para los tres terminados; 590ES y 890E salen de Pedidos Importación
insert into public."Importados_Partes_Map"(parte, terminado)
select v.p, v.t from (values ('590E','590E'),('590E','590ES'),('590E','890E')) v(p,t)
where not exists (select 1 from public."Importados_Partes_Map" m where m.parte=v.p and m.terminado=v.t);
update public."Importados" set principal = false, actualizado = now() where cod_art in ('590ES','890E');
-- (antes: FOB 590ES 0,446 y 890E 0,045 -> 0,082 los dos, mismo día)
-- Rollback D20:
--   delete from public."Importados_Partes_Map" where parte='590E';
--   update public."Importados" set principal = true where cod_art in ('590ES','890E');

-- 2) D21: vista_importados_partes contaba la venta de CHEF a 1 unidad por caja
--    (proyeccion_madre.proy_uni_mes: 890E 6,83 cajas = 7 u; 713 125,83 cajas = 126 u).
--    Ahora pasa proy_cajas_chef a unidades con la caja de Chef (GV_UxB).
--    Medido: 1000900 9.204 -> 10.081 · 505C 11.817 -> 14.669 · 523C 1.663 -> 1.982 ·
--    590E 1.132 -> 1.207 · 1546903 y 587C sin cambio.
create or replace view public.vista_importados_partes with (security_invoker = on) as
 WITH dep AS (
         SELECT ltrim(upper(split_part(btrim(s.cod_art), ' '::text, 1)), '0'::text) AS ckey,
            sum(COALESCE(s.terminado, 0::numeric) + COALESCE(s.excedente, 0::numeric) + COALESCE(s.separar_pedidos, 0::numeric) + COALESCE(s.a_facturar, 0::numeric) + COALESCE(s.a_guardar, 0::numeric) + COALESCE(s.racks, 0::numeric) + COALESCE(s.racks_ch, 0::numeric) + COALESCE(s.para_envasar, 0::numeric)) AS cajas
           FROM vista_saldos_stock s
          GROUP BY (ltrim(upper(split_part(btrim(s.cod_art), ' '::text, 1)), '0'::text))
        ), uxc AS (
         SELECT ltrim(upper(btrim(vista_uni_x_caja.codn)), '0'::text) AS ckey,
            max(vista_uni_x_caja.uni_x_caja) AS uni_x_caja
           FROM vista_uni_x_caja
          GROUP BY (ltrim(upper(btrim(vista_uni_x_caja.codn)), '0'::text))
        ), _pt_sup AS (
         SELECT ltrim(upper(btrim("Equivalencias_Super".super_cod)), '0'::text) AS s,
            btrim("Equivalencias_Super".base_cod) AS base_cod
           FROM "Equivalencias_Super"
        ), _pt_ux AS (
         SELECT CASE WHEN "GV_UxB".empresa = 'CH'::text THEN 'CH'::text ELSE 'LK'::text END AS emp,
            ltrim(upper(btrim(gv_cod_stock("GV_UxB".cod))), '0'::text) AS c,
            max("GV_UxB".uxb) AS u
           FROM "GV_UxB"
          WHERE "GV_UxB".uxb > 1::numeric
          GROUP BY 1, 2
        ), _pt_proy AS (
         SELECT ltrim(upper(btrim(COALESCE(x.base_cod, p.cod))), '0'::text) AS ck,
            sum(CASE WHEN COALESCE(p.proy_cajas_chef, 0::numeric) = 0::numeric THEN p.proy_uni_mes
                     ELSE COALESCE(p.proy_cajas_lk, 0::numeric) * COALESCE(ul.u, 1::numeric) + p.proy_cajas_chef * COALESCE(uc.u, 1::numeric) END) AS proy
           FROM proyeccion_madre p
             LEFT JOIN _pt_sup x ON x.s = ltrim(upper(btrim(p.cod)), '0'::text)
             LEFT JOIN _pt_ux ul ON ul.emp = 'LK'::text AND ul.c = ltrim(upper(btrim(p.cod)), '0'::text)
             LEFT JOIN _pt_ux uc ON uc.emp = 'CH'::text AND uc.c = ltrim(upper(btrim(p.cod)), '0'::text)
          GROUP BY 1
        ), t AS (
         SELECT m.parte, m.terminado, ltrim(upper(btrim(m.terminado)), '0'::text) AS tkey
           FROM "Importados_Partes_Map" m
        ), det AS (
         SELECT t.parte, t.terminado,
            ( SELECT max(pp.proy) FROM _pt_proy pp WHERE pp.ck = t.tkey) AS proy,
            COALESCE(d.cajas, 0::numeric) AS stock_cajas,
            u.uni_x_caja,
            round(COALESCE(d.cajas, 0::numeric) * COALESCE(u.uni_x_caja, 0::numeric)) AS stock_uni
           FROM t
             LEFT JOIN dep d ON d.ckey = t.tkey
             LEFT JOIN uxc u ON u.ckey = t.tkey
        )
 SELECT parte AS cod,
    round(sum(COALESCE(proy, 0::numeric)), 0) AS proy_uni_mes,
    jsonb_agg(jsonb_build_object('cod', terminado, 'proy', round(COALESCE(proy, 0::numeric), 0), 'stock_cajas', stock_cajas, 'uxc', uni_x_caja, 'stock_uni', stock_uni) ORDER BY terminado) AS detalle,
    round(sum(stock_uni), 0) AS stock_term_uni
   FROM det
  GROUP BY parte;
-- Rollback D21: el det.proy viejo era
--   ( SELECT max(p.proy_uni_mes) FROM vista_proyeccion_super p WHERE ltrim(upper(btrim(p.cod)), '0') = t.tkey)
