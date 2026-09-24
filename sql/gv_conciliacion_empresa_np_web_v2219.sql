-- v22.20 (Luis, 2026-09-24) — Conciliación de Facturación: 81 NP con diferencia Gestión vs ISIS.
--
-- CAUSA 1 (65 NP web de LK, $9.364.457 en valor absoluto):
--   vista_facturacion_neto_items decidía la empresa con `np ~ '^9'`. Una NP web "LK 0131"
--   no empieza con 9 -> la tomaba como CHEF, y con eso:
--     · clientes_dto se buscaba con (empresa='chef', cod LK) -> el descuento de OTRO cliente
--       (Mandarín 2447: 22 % de Chef vs 8 % real) o 0 % si el código no existe en Chef
--       (Spillare 0 % vs 12 %, Muller 0 % vs 14 %, Torres y Liva 0 % vs 16 %);
--     · la cadena súper se buscaba con 'ch' -> Coto (LK 0049) no se reconocía como súper.
--   Medido: el dto de ISIS coincide EXACTO con clientes_dto de LK en todas las líneas.
--   Arreglo: la misma regla de gv_empresa_de_np_texto, escrita inline (una función con
--   SET search_path no se inlinea y la vista la llamaría 2 veces por fila).
--   Resultado: 61 de las 65 pasan a "✔ Corregido"; cambian 73 NP (todas web LK), 0 de ISIS.
--
-- CAUSA 2 (Cencosud 44609/44610/44611): el comparador no cruzaba 031 (Gestión) con 031L
--   (ISIS) y mostraba todo como "falta / no facturado". Se pela la L de LOS DOS lados
--   (regla v21.15: pelar un solo lado es no matchear nunca). Sólo afecta la pantalla 🔍 Comparar.
--
-- Rollback:
--   · vista: reemplazar el CASE por `WHEN (ent.np ~ '^9'::text) THEN 'lk'::text` (2 lugares).
--   · comparar: reemplazar la expresión regexp_replace(... '([0-9E])L$' ...) por canon_cod(i.cod)
--     y canon_cod(di.codigo_articulo).

do $p$
declare d text; nd text;
begin
  d := pg_get_viewdef('public.vista_facturacion_neto_items'::regclass, false);
  if position('~* ''^\s*LK''' in d) > 0 then raise notice 'vista ya aplicada'; return; end if;
  nd := replace(d, $$ent.np ~ '^9'::text) THEN 'lk'::text$$,
     $$ent.np ~* '^\s*LK'::text) OR ((ent.np !~* '^\s*CH'::text) AND (ent.np ~ '^9'::text)) THEN 'lk'::text$$);
  if nd = d then raise exception 'no matcheo el patron'; end if;
  execute 'create or replace view public.vista_facturacion_neto_items as ' || nd;
end $p$;

do $p$
declare d text; nd text; n1 int; n2 int;
begin
  d := pg_get_functiondef('public.gv_conciliacion_comparar(text)'::regprocedure);
  if position('v22.19-L' in d) > 0 then raise notice 'comparar ya aplicado'; return; end if;
  n1 := (length(d)-length(replace(d,'canon_cod(i.cod)','')))/length('canon_cod(i.cod)');
  n2 := (length(d)-length(replace(d,'canon_cod(di.codigo_articulo)','')))/length('canon_cod(di.codigo_articulo)');
  if n1<>2 or n2<>2 then raise exception 'conteo inesperado % %', n1, n2; end if;
  nd := replace(d, 'canon_cod(i.cod)', $$canon_cod(regexp_replace(upper(btrim(i.cod)), '([0-9E])L$', '\1'))$$);
  nd := replace(nd, 'canon_cod(di.codigo_articulo)', $$canon_cod(regexp_replace(upper(btrim(di.codigo_articulo)), '([0-9E])L$', '\1'))$$);
  nd := replace(nd, 'begin'||chr(10)||'  -- v18.88', 'begin'||chr(10)||'  -- v22.19-L: la L se pela de LOS DOS lados para cruzar 031 (Gestion) con 031L (ISIS), caso Cencosud.'||chr(10)||'  -- v18.88');
  if position('v22.19-L' in nd) = 0 then raise exception 'no entro el marcador'; end if;
  execute nd;
end $p$;

-- Chequeo
-- select case when np ~* '^\s*LK' then 'web LK' when np ~* '^\s*CH' then 'web CH'
--             when np ~ '^9' then 'isis LK' else 'isis CH' end t,
--        count(*) filter (where corregido) iguales_hoy, count(*) filter (where not corregido) siguen
--   from public.gv_conciliacion_lista(300,0,null,null) where estado='diff' group by 1;
