-- v27.79 (Luis, 07/10) — proyecto LK (kwkclwhmoygunqmlegrg). APLICADO.
-- Modificar Pedidos mostraba el pedido 1450 (Matiz, LK 0098) como 6 renglones "552 Bombilla Bolita"
-- cuando el pedido real es 55219 x 1000 + 55289 x 2000.
-- Causa: lpad(x, 3) en Postgres TRUNCA ('55219' -> '552'). Todo código de 4+ dígitos se partía,
-- y el join al catálogo multiplicaba filas (2 renglones x 3 productos 552/55219/55289 = 6).
-- Lo usan gv_pedido_mod_ctx(_chef) y gv_pedido_mod_guardar(_chef): guardar habría reescrito el
-- pedido con '552'. Medido: 0 pedidos guardados así (GV_Pedido_Mod_Log sin códigos de 4+ dígitos).
-- Con la corrección no hay dos códigos del catálogo (products / loke_products) que normalicen igual.
CREATE OR REPLACE FUNCTION public.gv_pedido_mod_cod(p text)
 RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO 'public', 'pg_temp'
AS $function$
  -- v27.79: lpad(x,3) TRUNCA en Postgres ('55219' -> '552'). Sólo se rellena si tiene < 3 dígitos.
  select case
    when (regexp_match(coalesce(p,''), '\d+'))[1] is null then null
    else case when length((regexp_match(p, '\d+'))[1]) >= 3 then (regexp_match(p, '\d+'))[1]
              else lpad((regexp_match(p, '\d+'))[1], 3, '0') end
         || upper(coalesce((regexp_match(p, '[a-zA-Z]+'))[1], ''))
  end;
$function$;
-- Chequeo: select gv_pedido_mod_cod('55219'), gv_pedido_mod_cod('26'), gv_pedido_mod_cod('438EL');
--          -> 55219 · 026 · 438EL
-- Rollback (vuelve el bug): reemplazar el case interno por lpad((regexp_match(p,'\d+'))[1], 3, '0').
