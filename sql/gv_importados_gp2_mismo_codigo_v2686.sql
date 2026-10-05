-- v26.86 (Luis, 05/10/2026): el stock GP2 de un importado suma TAMBIÉN el componente de GP2
-- con el MISMO código (el artículo terminado: 323E además de GRJ31), aunque no esté cargado en
-- GV_Importados_Equiv_GP2. Factor 1. No se suma dos veces si la tabla ya lo lista (942E…948E),
-- y no se aplica a un código que es principal activo en LK y en CH a la vez (no se sabe a cuál va).
-- Bodegas: gv_gp2_stock_componente ya cuenta sector, análisis, artículo terminado, talleristas,
-- proveedores de servicio / AT e inyectores, y saca lo que GP2 tiene EN Virgilio (v26.05).
-- Impacto al 05/10: 0 u (los componentes 026, 027, 590E, 824, 825, 941E, 946E existen en GP2 sin stock).
-- Se aplica sobre pg_get_viewdef, idempotente, y falla si el texto no matchea.
-- REGLA_CONFIRMADA_POR_USUARIO (Luis lo pidió el 05/10)
do $patch$
declare d text; n text;
begin
  d := pg_get_viewdef('public.gv_importados_ordenes'::regclass, true);
  if position('e_mismo' in d) > 0 then raise notice 'ya aplicado'; return; end if;
  n := regexp_replace(d,
    'FROM "GV_Importados_Equiv_GP2" e\s+JOIN gv_gp2_stock_componente sc ON upper\(sc\.codigo\) = upper\(e\.componente_codigo\)\s+WHERE upper\(e\.importado_cod\) = upper\(i\.cod_art\) AND i\.principal AND i\.activo\) g2 ON true',
    'FROM ( SELECT e0.componente_codigo, e0.factor FROM "GV_Importados_Equiv_GP2" e0 WHERE upper(e0.importado_cod) = upper(i.cod_art)
                 UNION ALL
                 SELECT i.cod_art AS componente_codigo, 1::numeric AS factor
                  WHERE NOT (EXISTS ( SELECT 1 FROM "GV_Importados_Equiv_GP2" e1 WHERE upper(e1.importado_cod) = upper(i.cod_art) AND upper(e1.componente_codigo) = upper(i.cod_art)))
                    AND NOT (EXISTS ( SELECT 1 FROM dup WHERE dup.cod_norm = gv_cod_stock(i.cod_art)))) e_mismo
             JOIN gv_gp2_stock_componente sc ON upper(sc.codigo) = upper(e_mismo.componente_codigo)
          WHERE i.principal AND i.activo) g2 ON true');
  if n = d then raise exception 'gv_importados_ordenes: el texto del LATERAL g2 no matchea, no se aplica'; end if;
  n := replace(n, 'sum(sc.cantidad * e.factor) AS stock_gp2', 'sum(sc.cantidad * e_mismo.factor) AS stock_gp2');
  execute 'create or replace view public.gv_importados_ordenes as ' || n;
  execute 'alter view public.gv_importados_ordenes set (security_invoker = true)';
end $patch$;

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_importados_ordenes','vista','e_mismo\.componente_codigo',
        'el stock GP2 de un importado suma tambien el componente de GP2 con el MISMO codigo (articulo terminado), factor 1, sin duplicar el de GV_Importados_Equiv_GP2',
        'Luis','v26.85');  -- etiqueta con la que se aplico (05/10)

-- ROLLBACK: volver al LATERAL que sólo lee GV_Importados_Equiv_GP2
-- do $rb$ declare d text; n text; begin
--   d := pg_get_viewdef('public.gv_importados_ordenes'::regclass, true);
--   n := regexp_replace(d, 'FROM \( SELECT e0\.componente_codigo.*?\) e_mismo\s+JOIN gv_gp2_stock_componente sc ON upper\(sc\.codigo\) = upper\(e_mismo\.componente_codigo\)\s+WHERE i\.principal AND i\.activo\) g2 ON true',
--        'FROM "GV_Importados_Equiv_GP2" e JOIN gv_gp2_stock_componente sc ON upper(sc.codigo) = upper(e.componente_codigo) WHERE upper(e.importado_cod) = upper(i.cod_art) AND i.principal AND i.activo) g2 ON true');
--   n := replace(n, 'sum(sc.cantidad * e_mismo.factor)', 'sum(sc.cantidad * e.factor)');
--   execute 'create or replace view public.gv_importados_ordenes as ' || n;
--   execute 'alter view public.gv_importados_ordenes set (security_invoker = true)';
-- end $rb$;
-- delete from public."GV_Reglas_Centinela" where objeto='gv_importados_ordenes' and version='v26.85';
