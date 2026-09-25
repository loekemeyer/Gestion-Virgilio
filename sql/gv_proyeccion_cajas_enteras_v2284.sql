-- v22.84 (Luis, 25/09/2026): "proyeccion en todos lados siempre en cajas redondas".
-- Ej: 437E CH 3,18 cajas = 76,32 u  ->  3 cajas = 72 u. Redondeo al entero mas cercano.
-- Retira el round(...,2) de la v22.73 como criterio: ahora la FUENTE ya viene en cajas enteras.
--
-- 1) gv_proyeccion_articulo: la definicion viva queda como CTE crudo_cajas y afuera se redondea
--    proy_lk y proy_ch por separado; proy_cajas_mes = round(lk) + round(ch) (asi el dual LK+CH
--    suma lo mismo en todas las pantallas). proy_propia, proy_familia y detalle_familia tambien.
do $$
declare d text;
begin
  d := pg_get_viewdef('public.gv_proyeccion_articulo'::regclass, true);
  if d ~ 'crudo_cajas' then return; end if;
  d := regexp_replace(d, ';\s*$', '');
  execute 'create or replace view public.gv_proyeccion_articulo with (security_invoker = true) as
  with crudo_cajas as (' || d || ')
  select cod, round(proy_lk) as proy_lk, round(proy_ch) as proy_ch,
         round(proy_lk) + round(proy_ch) as proy_cajas_mes,
         round(proy_propia) as proy_propia, round(proy_familia) as proy_familia,
         (select jsonb_agg(jsonb_build_object(''cod'', e.v->>''cod'', ''lk'', round((e.v->>''lk'')::numeric),
                 ''ch'', round((e.v->>''ch'')::numeric)) order by e.n)
            from jsonb_array_elements(crudo_cajas.detalle_familia) with ordinality e(v, n)) as detalle_familia,
         es_secundario, principal
    from crudo_cajas';
end $$;
-- 2) vista_generador_oc: el dual partia el total por la proporcion lk/(lk+ch) y dejaba
--    33,00000000000000000012; con indice 1,5 un 22,0000...014 daba ceil 34 en vez de 33.
--    Ahora toma proy_lk / proy_ch directo (reemplazo exacto sobre la definicion viva).
-- Medido al aplicar: 314 codigos con proyeccion, 14 quedan en 0 (todos < 0,5 caja/mes),
-- Importados 0 filas fuera de multiplo de caja, Stock 0 con decimales, generador 0.
-- Rollback: zz_backups."GV_Backup_gpa_def_20260925c" y zz_backups."GV_Backup_genoc_def_20260925".

-- v22.86 (Luis, 25/09/2026): "minimo 1 caja si venden algo".
-- Si round(lk)+round(ch) da 0 pero la venta cruda es > 0, va 1 caja al lado que mas vende.
-- Medido: los 14 que quedaban en 0 pasan a 1; 0 codigos que venden quedan en 0.
-- GASTOTRRECH y TRANSFRECH (administrativos) tambien quedan en 1, pero no tienen proveedor: no generan OC.
do $$
declare d text; m text := '(round(proy_lk) + round(proy_ch) = 0::numeric AND (proy_lk + proy_ch) > 0::numeric)';
  a1 text := '    round(proy_lk) AS proy_lk,
    round(proy_ch) AS proy_ch,
    round(proy_lk) + round(proy_ch) AS proy_cajas_mes,';
begin
  d := pg_get_viewdef('public.gv_proyeccion_articulo'::regclass, true);
  if d ~ 'minimo_1_caja' then return; end if;
  if position(a1 in d) = 0 then raise exception 'no matchea'; end if;
  d := replace(d, a1, '    CASE WHEN ' || m || ' AND proy_lk >= proy_ch THEN 1::numeric ELSE round(proy_lk) END AS proy_lk,
    CASE WHEN ' || m || ' AND proy_ch > proy_lk THEN 1::numeric ELSE round(proy_ch) END AS proy_ch,
    CASE WHEN ' || m || ' THEN 1::numeric ELSE round(proy_lk) + round(proy_ch) END AS proy_cajas_mes,');
  d := regexp_replace(d, ';\s*$', '');
  d := replace(d, 'WITH crudo_cajas AS (', 'WITH crudo_cajas AS ( -- minimo_1_caja v22.86' || chr(10));
  execute 'create or replace view public.gv_proyeccion_articulo with (security_invoker = true) as ' || d;
end $$;
