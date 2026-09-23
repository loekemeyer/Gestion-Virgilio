-- v21.96 (Vivi, 2026-09-23) — "me llama la atencion el 590e que figura dos veces".
--
-- QUE SE MIDIO. El carrito de la pagina puede traer el MISMO codigo en DOS renglones. LK 1448
-- (Silvano, LK 4282) tiene en `order_items` de LK dos filas de 590E (3 + 3 cajas) y dos de 323E
-- (2 + 1). `lk_pedidos_match.items_string` los SUMA (`590Ex6`), pero los BLOQUES que arma el
-- front los llevan separados y `cuarItemsDe()` los aplana sin agrupar: el pop-up mostraba el
-- codigo dos veces.
--
-- Y LA MITAD QUE NO SE VE, QUE ES LA QUE IMPORTA. El reparto greedy de lo importado escaso
-- particiona por (codn, emp) ordenando por (fecha, hora, order_id). Las dos filas del MISMO
-- pedido comparten esa clave, asi que la hermana entra en `tomado_antes` y el cubierto sale de
-- MENOS. Agrupar antes del greedy arregla las dos cosas de una.
--
-- ⚠ `gv_clientes_nuevos_valor_lote` (la canonica) tiene el mismo agujero y NO se toca: es el
--   camino caliente del monto, la cuarentena y el limite de credito. Queda reportado. Hoy no se
--   nota porque el pedido tiene stock de sobra: medido sobre LK 1448 las dos dan 1.696.048,96 /
--   1.696.048,97 (1 centavo de redondeo, dentro del $1 que tolera el chequeo del pop-up).
--
-- Se aplica sobre pg_get_functiondef, es idempotente y falla con un raise si el texto no matchea.
-- Rollback: reaplicar sql/gv_clin_composicion_v2183.sql.

do $patch$
declare d text; nuevo text;
begin
  d := pg_get_functiondef('public.gv_clin_composicion(jsonb,text,text)'::regprocedure);
  if position('_cp_itg' in d) > 0 then
    raise notice 'ya tiene la agrupacion v21.96'; return;
  end if;
  if position('  _cp_prog as materialized (' in d) = 0
     or position('      from _cp_it it' in d) = 0 then
    raise exception 'el texto de gv_clin_composicion no matchea: NO se reescribe';
  end if;
  nuevo := replace(d,
    '  _cp_prog as materialized (',
    '  _cp_itg as (' || chr(10) ||
    '    select order_id, empresa, cod_cli, cond, art, sum(cajas) as cajas,' || chr(10) ||
    '           codn, emp, imp, f_ped, h_ped' || chr(10) ||
    '      from _cp_it' || chr(10) ||
    '     group by order_id, empresa, cod_cli, cond, art, codn, emp, imp, f_ped, h_ped' || chr(10) ||
    '  ),' || chr(10) ||
    '  _cp_prog as materialized (');
  nuevo := replace(nuevo, '      from _cp_it it', '      from _cp_itg it');
  execute nuevo;
end $patch$;

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_clin_composicion','funcion','_cp_itg',
        'La composicion agrupa los items por codigo ANTES del greedy: el carrito puede traer el mismo codigo en dos renglones (LK 1448: 590E y 323E). Sin agrupar se duplica la linea y la hermana entra en tomado_antes.',
        'Vivi','v21.96')
on conflict do nothing;

-- Chequeo: una fila por codigo, 590E con las 6 cajas juntas.
-- select art, cajas from public.gv_clin_composicion(
--   jsonb_build_array(jsonb_build_object('order_id','1448','empresa','lk','cod','4282','cond','8',
--     'items', jsonb_build_array(jsonb_build_object('art','590E','cajas',3),
--                                jsonb_build_object('art','590E','cajas',3)))), 'lk','1448');
