-- v19.95 (Thomas, 2026-09-18) — UNA sola llamada a gv_ppp_web_valor_items por pedido.
--
-- Antes la función la llamaba DOS veces por pedido: una para el neto y otra para el ×1,21.
-- No es una función barata: arma 5 CTE y pega contra precios_venta, precios_venta_chef,
-- cobranzas_precios_super, clientes_dto y GV_UxB. Medido con 20 pedidos de 3 artículos:
-- 74 ms antes, 36 ms después (−51 %), con los 20 montos idénticos (0 filas distintas).
--
-- ⚠ El CTE va MATERIALIZED a propósito: sin eso el planner lo aplana, copia la llamada en las
--   dos columnas de salida y volvemos a las dos llamadas sin que nada lo avise. Lo cuida el
--   centinela `GV_Reglas_Centinela` (objeto gv_clientes_nuevos_valor_lote, patrón `as\s+materialized`):
--   `select * from public.gv_reglas_perdidas;` vacía = la regla sigue.
--
-- Backup de la definición anterior: zz_backups."GV_Backup_ValorLote_20260918"
-- Resultados de control (antes): zz_backups."GV_Backup_ValorLote_Res_20260918"

CREATE OR REPLACE FUNCTION public.gv_clientes_nuevos_valor_lote(p_pedidos jsonb)
 RETURNS TABLE(order_id text, empresa text, valor numeric, valor_con_iva numeric)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- v19.95 (Thomas, 2026-09-18): gv_ppp_web_valor_items se llamaba DOS veces por pedido — una
  -- para el neto y otra para el ×1,21 —, o sea el doble de trabajo para el mismo número. Y no es
  -- una función barata: arma 5 CTE y pega contra precios_venta, precios_venta_chef,
  -- cobranzas_precios_super, clientes_dto y GV_UxB. Ahora se llama UNA vez por pedido y el IVA
  -- sale de multiplicar ese resultado.
  -- ⚠ El CTE va MATERIALIZED a propósito: sin eso el planner lo aplana, copia la llamada en las
  -- dos columnas de salida y volvemos a las dos llamadas sin que nada lo avise.
  -- El candado de supervisor queda ADENTRO del CTE (en el WHERE, que se evalúa antes que la
  -- lista de selección): a un no-supervisor no se le valoriza nada, igual que antes.
  with _vl_src as (
    select nullif(trim(e->>'order_id'), '')     as order_id,
           lower(coalesce(e->>'empresa','lk'))  as empresa,
           nullif(trim(e->>'cod'), '')          as cod,
           e->'items'                           as items,
           nullif(e->>'cond','')                as cond
      from jsonb_array_elements(coalesce(p_pedidos, '[]'::jsonb)) e
  ),
  _vl_val as materialized (
    select s.order_id, s.empresa,
           public.gv_ppp_web_valor_items(s.empresa, s.cod, s.items, s.cond) as valor
      from _vl_src s
     where s.order_id is not null
       and (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
  )
  select v.order_id, v.empresa, round(v.valor, 2), round(v.valor * 1.21, 2)
    from _vl_val v;
$function$;

-- centinela
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_clientes_nuevos_valor_lote','funcion','as\s+materialized',
        'El CTE que valoriza va MATERIALIZED: sin eso el planner lo aplana, copia gv_ppp_web_valor_items en las dos columnas de salida y la funcion vuelve a llamarla DOS veces por pedido (el doble de trabajo para el mismo numero).',
        'Thomas','v19.95');

-- ROLLBACK: la definición anterior está completa en
--   select def from zz_backups."GV_Backup_ValorLote_20260918";
