-- v24.83 (Luis, 30/09): la recepción de un importado que es INSUMO pregunta en la unidad del insumo.
-- gv_imp_recibir_contexto devuelve 'insumos_unidad' = {cod_insumo: unidad base de Insumos_Factores (sin fila = Uni)}.
-- Aplicado como parche por texto sobre pg_get_functiondef (idempotente, falla si no matchea):
do $$ declare d text; n text; begin
 d := pg_get_functiondef('public.gv_imp_recibir_contexto(bigint)'::regprocedure);
 if d like '%insumos_unidad%' then return; end if;
 n := replace(d, $a$'insumos_cods', v_ins_cods,$a$,
   $b$'insumos_cods', v_ins_cods,
    -- v24.83 (Luis 30/09): la unidad de medida de cada insumo (la base de Insumos_Factores; sin fila = Uni)
    'insumos_unidad', (select coalesce(jsonb_object_agg(_iu.x, coalesce((select f.unidad from public."Insumos_Factores" f
        where upper(f.cod_art) = upper(_iu.x) and f.es_base limit 1), 'Uni')), '{}'::jsonb)
      from jsonb_array_elements_text(v_ins_cods) _iu(x)),$b$);
 if n = d then raise exception 'no matcheo el texto de gv_imp_recibir_contexto'; end if;
 execute n;
end $$;
-- Rollback: volver a correr el create de gv_imp_recibir_contexto sin la clave (la clave extra no rompe a nadie).

-- ============================================================================
-- v24.93 (Luis 30/09: "es un insumo, no estoy recibiendo 323E ni nada de eso")
-- a) gv_imp_recibir_contexto: 'es_insumo' + insumo del canon por GV_Importados_Alias
--    (323E / 838E -> 323ES -> '323ES In'). Marcador v24.92.
-- b) gv_imp_recibir: el insumo se graba con la grafía de Insumos, no en mayúsculas
--    ('323ES In', antes '323ES IN' que no suma a ningún insumo). Marcador v24.93-ins-canon.
--    Parche aplicado sobre pg_get_functiondef (REGLA_CONFIRMADA_POR_USUARIO):
--      v_ins := coalesce((select vi.cod from public.vista_insumos vi
--        where upper(vi.cod) = upper(btrim(coalesce(d->>'cod_insumo', v_cod))) limit 1),
--        upper(btrim(coalesce(d->>'cod_insumo', v_cod))));
--    Probado en transacción abortada (bache 96, 1 u): movimiento '323ES In' en insumos.
-- c) gv_insumo_unidad_base había PERDIDO la regla Mixto de la v24.89 (otra sesión la
--    recreó desde la copia de la v24.69). Repuesta (marcador v24.89-mixto): antes del
--    return por unidad nula, new.empresa := 'Mixto'. Probado: LK entra Mixto.
