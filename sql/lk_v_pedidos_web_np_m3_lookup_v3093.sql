-- v30.93 (15/10/2026) — proyecto LK (kwkclwhmoygunqmlegrg), vista public.v_pedidos_web_np.
-- Síntoma: A Programar quedaba en "Todavía controlando…" con "LK respondió 500".
-- Causa: con RLS (rol authenticated) el planner subestimaba las líneas (38 vs 20.9k) y unía
-- `LEFT JOIN vol v ON v.codigo = upper(btrim(i.art))` con nested loop: 20.9k × 1.503 = 31 M
-- comparaciones → 24 s, cortado a los 8 s (statement timeout) → 500.
-- Fix: el mapa de m³ se arma una vez como jsonb y cada línea lo consulta por clave.
-- Misma salida (md5 de toda la vista igual antes/después). 24 s → 2,7 s como admin.
-- Se aplicó sobre la definición VIVA con este bloque (no reescribe a mano la vista):
do $$ declare d text := pg_get_viewdef('public.v_pedidos_web_np'::regclass); d2 text; h1 text; h2 text; begin
select md5(string_agg(t::text, '|' order by t.empresa, t.order_id, t.np_idx)) into h1 from public.v_pedidos_web_np t;
d2 := regexp_replace(d, 'SELECT virgilio_volumen_map\.codigo,\s+virgilio_volumen_map\.m3\s+FROM virgilio_volumen_map\(\) virgilio_volumen_map\(codigo, m3\)', 'SELECT jsonb_object_agg(vm.codigo, vm.m3) AS m FROM virgilio_volumen_map() vm(codigo, m3) WHERE vm.codigo IS NOT NULL');
d2 := replace(d2, 'v.m3 AS m3_unit', '( SELECT ((vol.m ->> upper(btrim(i.art))))::numeric FROM vol) AS m3_unit');
d2 := replace(d2, 'COALESCE(v.m3, (0)::numeric)', 'COALESCE(( SELECT ((vol.m ->> upper(btrim(i.art))))::numeric FROM vol), (0)::numeric)');
d2 := replace(d2, E'\n                     LEFT JOIN vol v ON ((v.codigo = upper(btrim(i.art)))))', ')');
if d2 = d or d2 like '%vol v%' or d2 not like '%jsonb_object_agg(vm.codigo%' then raise exception 'reemplazo incompleto'; end if;
execute 'create or replace view public.v_pedidos_web_np with (security_invoker = true) as ' || d2;
select md5(string_agg(t::text, '|' order by t.empresa, t.order_id, t.np_idx)) into h2 from public.v_pedidos_web_np t;
if h1 is distinct from h2 then raise exception 'salida distinta % vs %', h1, h2; end if;
end $$;
-- ⚠ Si se vuelve a tocar la vista: NO volver al LEFT JOIN contra `vol`. Medir como admin
-- (set local role authenticated + request.jwt.claims), no como postgres: como postgres tarda 1,4 s
-- y no muestra el problema.
