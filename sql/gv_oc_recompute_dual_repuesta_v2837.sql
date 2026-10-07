-- v28.37 (Luis, 07/10/2026) — se REPUSO la regla v22.37 (OC de un dual "437E CH" se imputa con la
-- entrega del código base y de la MISMA empresa) en gv_oc_recompute_recibido.
-- Cómo se perdió: otra sesión volvió a correr una copia vieja de la función (la de
-- sql/gv_oc_recibido_externo_v2198.sql, que NO tiene la regla dual) con CREATE OR REPLACE, y eso pisa
-- el cuerpo entero sin avisar. El centinela gv_reglas_perdidas lo marcó.
-- ⚠ NO volver a correr sql/gv_oc_recibido_externo_v2198.sql: está viejo. La definición vigente es la viva.
-- Se aplicó como parche por texto sobre pg_get_functiondef (falla si algún paso no matchea):
--   cod_filtro / entregas / oc / propio / ext / cand  →  cruce por cod_b (código sin " LK"/" CH")
--   y, si la OC tiene empresa, exige e.emp = emp_oc (Entregas Tallerista Virgilio.gv_empresa).
-- Verificado: gv_reglas_perdidas vacía; recompute(437E) y recompute(todas) → 0 OC cambian (no hubo daño).
-- Parche aplicado (idempotente: no corre si ya tiene emp_oc):
do $p$
declare d text; i int;
  pares text[][] := array[
   array['cod_filtro := case when p_cod is not null then norm_cod(p_cod) end;',
         'cod_filtro := case when p_cod is not null then regexp_replace(norm_cod(p_cod), ''\s+(LK|CH)$'', '''') end;  -- v22.37-dual (repuesta v28.37)'],
   array['select ''T''||id as eid, norm_cod("Cod") as cod, gv_norm_prov_keys("Nombre_Tall") as pk,',
         'select ''T''||id as eid, regexp_replace(norm_cod("Cod"), ''\s+(LK|CH)$'', '''') as cod, nullif(upper(btrim(coalesce(gv_empresa, ''''))), '''') as emp, gv_norm_prov_keys("Nombre_Tall") as pk,'],
   array['select ''P''||id, norm_cod("Cod_Art"), gv_norm_prov_keys("Proveedor"),',
         'select ''P''||id, regexp_replace(norm_cod("Cod_Art"), ''\s+(LK|CH)$'', ''''), null::text, gv_norm_prov_keys("Proveedor"),'],
   array['norm_cod(o.codigo) as cod_n,',
         'norm_cod(o.codigo) as cod_n, regexp_replace(norm_cod(o.codigo), ''\s+(LK|CH)$'', '''') as cod_b, substring(norm_cod(o.codigo) from ''\s(LK|CH)$'') as emp_oc,'],
   array['and (cod_filtro is null or norm_cod(o.codigo) = cod_filtro)',
         'and (cod_filtro is null or regexp_replace(norm_cod(o.codigo), ''\s+(LK|CH)$'', '''') = cod_filtro)'],
   array['where e.cod = w.cod_n and e.f is not null',
         'where e.cod = w.cod_b and (w.emp_oc is null or e.emp = w.emp_oc) and e.f is not null'],
   array['where w.cod_n = e.cod and e.f >= w.fecha',
         'where w.cod_b = e.cod and (w.emp_oc is null or e.emp = w.emp_oc) and e.f >= w.fecha'],
   array['where norm_cod(m.cod) = p.cod_n limit 1', 'where norm_cod(m.cod) = p.cod_b limit 1'],
   array['join propio p on p.cod_n = x.cod and p.es_ultima',
         'join propio p on p.cod_b = x.cod and (p.emp_oc is null or x.emp = p.emp_oc) and p.es_ultima']];
begin
  d := pg_get_functiondef('public.gv_oc_recompute_recibido(text,text)'::regprocedure);
  if d ~ 'emp_oc' then return; end if;
  for i in 1..array_length(pares,1) loop
    if position(pares[i][1] in d) = 0 then raise exception 'no matchea el paso %: %', i, pares[i][1]; end if;
    d := replace(d, pares[i][1], pares[i][2]);
  end loop;
  execute d;
end $p$;
