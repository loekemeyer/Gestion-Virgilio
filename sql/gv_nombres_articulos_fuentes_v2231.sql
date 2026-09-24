-- v22.31 (Luis, 24/09): "690E / 828 ... tiene nombre en algún lado evidentemente".
-- vista_nombres_articulos (el padrón de nombres que usa artNombre en toda la app) miraba
-- sólo proyeccion_madre > Articulos Virgilio X Tallerista > OC_Maximos > histórico. Un
-- importado (Importados), el UxB curado (GV_UxB) o un artículo de la lista de precios de
-- Chef/LK no figuraban: 690E "Mariposa Magnetica" salía con el código como descripción.
-- Se agregan esas cuatro fuentes AL FINAL de la prioridad (no pisan ningún nombre existente).
-- Se aplica sobre la definición viva (idempotente: marcador norm_imp) y conserva security_invoker.
do $$ declare d text; n text; begin
  d := pg_get_viewdef('public.vista_nombres_articulos'::regclass, true);
  if d ~ 'norm_imp' then raise notice 'ya estaba'; return; end if;
  n := d;
  -- 1) CTEs nuevas, antes de keys_l
  n := replace(n, '), keys_l AS (',
    '), norm_imp AS (' || chr(10) ||
    '         SELECT DISTINCT ON ((upper(regexp_replace(COALESCE(btrim(i.cod_art), ''''::text), ''^0+(.)''::text, ''\1''::text)))) upper(regexp_replace(COALESCE(btrim(i.cod_art), ''''::text), ''^0+(.)''::text, ''\1''::text)) AS k, NULLIF(btrim(i.descripcion), ''''::text) AS d' || chr(10) ||
    '           FROM "Importados" i WHERE NULLIF(btrim(COALESCE(i.descripcion, ''''::text)), ''''::text) IS NOT NULL AND upper(btrim(i.descripcion)) <> upper(btrim(COALESCE(i.cod_art, ''''::text)))' || chr(10) ||
    '          ORDER BY (upper(regexp_replace(COALESCE(btrim(i.cod_art), ''''::text), ''^0+(.)''::text, ''\1''::text))), i.activo DESC, i.principal DESC, i.id' || chr(10) ||
    '        ), norm_uxb AS (' || chr(10) ||
    '         SELECT DISTINCT ON ((upper(regexp_replace(COALESCE(btrim(u.cod), ''''::text), ''^0+(.)''::text, ''\1''::text)))) upper(regexp_replace(COALESCE(btrim(u.cod), ''''::text), ''^0+(.)''::text, ''\1''::text)) AS k, NULLIF(btrim(u.descripcion), ''''::text) AS d' || chr(10) ||
    '           FROM "GV_UxB" u WHERE NULLIF(btrim(COALESCE(u.descripcion, ''''::text)), ''''::text) IS NOT NULL AND upper(btrim(u.descripcion)) <> upper(btrim(COALESCE(u.cod, ''''::text)))' || chr(10) ||
    '          ORDER BY (upper(regexp_replace(COALESCE(btrim(u.cod), ''''::text), ''^0+(.)''::text, ''\1''::text))), u.curado DESC NULLS LAST, u.actualizado DESC NULLS LAST' || chr(10) ||
    '        ), norm_pv AS (' || chr(10) ||
    '         SELECT DISTINCT ON (x.k) x.k, x.d FROM (' || chr(10) ||
    '           SELECT upper(regexp_replace(COALESCE(btrim(p.cod), ''''::text), ''^0+(.)''::text, ''\1''::text)) AS k, NULLIF(btrim(p.descripcion), ''''::text) AS d, 1 AS o FROM precios_venta p' || chr(10) ||
    '           UNION ALL SELECT upper(regexp_replace(COALESCE(btrim(c.cod), ''''::text), ''^0+(.)''::text, ''\1''::text)), NULLIF(btrim(c.descripcion), ''''::text), 2 FROM precios_venta_chef c) x' || chr(10) ||
    '          WHERE x.d IS NOT NULL AND upper(x.d) <> x.k ORDER BY x.k, x.o' || chr(10) ||
    '        ), keys_l AS (');
  -- 2) keys
  n := replace(n, '        UNION' || chr(10) || '         SELECT keys_l.k',
    '        UNION SELECT norm_imp.k FROM norm_imp UNION SELECT norm_uxb.k FROM norm_uxb UNION SELECT norm_pv.k FROM norm_pv' || chr(10) ||
    '        UNION' || chr(10) || '         SELECT keys_l.k');
  -- 3) coalesce + fuente
  n := replace(n, 'COALESCE(pm.d, v.d, o.d, h.d) AS d', 'COALESCE(pm.d, v.d, o.d, h.d, im.d, ux.d, pv.d) AS d');
  n := replace(n, '                    ELSE ''historico''::text',
    '                    WHEN h.d IS NOT NULL THEN ''historico''::text' || chr(10) ||
    '                    WHEN im.d IS NOT NULL THEN ''importados''::text' || chr(10) ||
    '                    WHEN ux.d IS NOT NULL THEN ''uxb''::text' || chr(10) ||
    '                    ELSE ''precios_venta''::text');
  n := replace(n, 'LEFT JOIN norm_hist h ON h.k = kk.k',
    'LEFT JOIN norm_hist h ON h.k = kk.k' || chr(10) ||
    '             LEFT JOIN norm_imp im ON im.k = kk.k LEFT JOIN norm_uxb ux ON ux.k = kk.k LEFT JOIN norm_pv pv ON pv.k = kk.k');
  if n !~ 'norm_imp im' or n !~ 'im\.d, ux\.d, pv\.d' or n !~ 'SELECT norm_pv\.k' or n !~ '''importados''' then
    raise exception 'no matcheó algún tramo';
  end if;
  execute 'create or replace view public.vista_nombres_articulos with (security_invoker = true) as ' || n;
end $$;
-- Chequeo: select * from public.vista_nombres_articulos where cod in ('690E','828','763','55289');
