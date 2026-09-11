-- =====================================================================
-- INVARIANTES del schema GP2 — chequeo de salud en una sola consulta (solo lectura).
-- Cada fila es una regla que la base tiene que cumplir SIEMPRE; la columna n tiene que ser 0.
-- Salieron de la auditoría de arquitectura del 2026-09-04/05 (REFACTOR_GP2.md): cada una es un
-- bug que ya pasó una vez (PS sin ubicación → crear_envio_ps explotaba; ledger e inventario
-- desfasados; función interna ejecutable por anon; secuencia con USAGE para anon; …).
-- Cómo usarla: correrla entera (Supabase MCP / SQL editor) y mirar sólo las filas con n > 0.
-- El agente diario la corre al empezar; si algo da > 0 es lo primero que se arregla.
-- =====================================================================

with ledger as (
  -- lo que dice el libro (movimiento) por componente y ubicación, con la misma regla que
  -- fn_movimiento_aplicar: el destino recibe +_delta_dest en el componente transformado
  -- (o el mismo), el origen pierde _delta_orig en el componente original
  select comp, ubic, sum(d) d from (
    select coalesce(comp_transformado_id, comp_id) comp, ubic_destino_id ubic, sum(_delta_dest) d
      from "GP2".movimiento where ubic_destino_id is not null group by 1, 2
    union all
    select comp_id, ubic_origen_id, -sum(_delta_orig)
      from "GP2".movimiento where ubic_origen_id is not null group by 1, 2) l
   group by 1, 2
)
select * from (

-- A) Toda contraparte que puede recibir o entregar stock tiene SU ubicación (ubic_de la resuelve).
select 'A_contrapartes_sin_ubicacion' regla, count(*) n from (
    select id from "GP2".proveedor_servicio ps where "GP2".ubic_de('proveedor_servicio', ps.id) is null
    union all select id from "GP2".tallerista t where t.activo and "GP2".ubic_de('tallerista', t.id) is null
    union all select id from "GP2".proveedor_at p where p.activo and "GP2".ubic_de('proveedor_at', p.id) is null
    union all select id from "GP2".sector s where s.es_insumo and "GP2".ubic_de('sector', s.id) is null) x
union all
-- B) El inventario es exactamente la suma del libro (el motor vive en los triggers).
select 'B_inventario_distinto_del_ledger', count(*)
  from ledger s full join "GP2".inventario i on i.componente_id = s.comp and i.ubicacion_id = s.ubic
 where abs(coalesce(i.cantidad, 0) - coalesce(s.d, 0)) > 0.0005
union all
-- C) Ninguna función interna (triggers, helpers, recálculos) es ejecutable por anon.
select 'C_funciones_internas_con_execute_anon', count(*) from pg_proc p
 where p.pronamespace = '"GP2"'::regnamespace and has_function_privilege('anon', p.oid, 'EXECUTE')
   and (p.prorettype = 'trigger'::regtype or p.proname like '\_%' or p.proname like 'fn\_%'
        or p.proname like 'relev\_%' or p.proname like 'recalcular\_%'
        or p.proname in ('to_canonical', 'inv_delta', 'ubic_de', 'ubic_de_componente', 'recepcion_tara',
                         'recepcion_virgilio', 'actualizar_dolar_oficial', 'crear_recepcion_insumo'))
union all
-- D) Toda tabla tiene RLS y una policy; ninguna policy es de escritura (la escritura va por RPC).
select 'D_tablas_sin_rls_o_sin_policy', count(*) from pg_class c
 where c.relnamespace = '"GP2"'::regnamespace and c.relkind = 'r'
   and (not c.relrowsecurity or not exists (select 1 from pg_policies p where p.schemaname = 'GP2' and p.tablename = c.relname))
union all
select 'D2_policies_de_escritura', count(*) from pg_policies p where p.schemaname = 'GP2' and p.cmd <> 'SELECT'
union all
-- E/F) Ni secuencias ni tablas aceptan escritura de anon/authenticated.
select 'E_secuencias_con_usage_anon', count(*) from pg_class c
 where c.relnamespace = '"GP2"'::regnamespace and c.relkind = 'S'
   and (has_sequence_privilege('anon', c.oid, 'USAGE') or has_sequence_privilege('authenticated', c.oid, 'USAGE'))
union all
select 'F_tablas_con_escritura_anon', count(*) from information_schema.role_table_grants g
 where g.table_schema = 'GP2' and g.grantee in ('anon', 'authenticated') and g.privilege_type in ('INSERT', 'UPDATE', 'DELETE')
union all
-- G) Un PS híbrido sin materia prima configurada no puede recibir compras (cargar_compra_mp).
select 'G_ps_hibrido_sin_mp_componente', count(*) from "GP2".proveedor_servicio where hibrido and mp_componente_id is null
union all
-- H) Un proveedor de materia prima alimenta a UN solo PS híbrido (si no, cargar_compra_mp es ambigua).
select 'H_proveedor_mp_ambiguo', count(*) from (
    select c.proveedor from "GP2".proveedor_servicio ps join "GP2".componente c on c.id = ps.mp_componente_id
     where ps.hibrido group by c.proveedor having count(*) > 1) d
union all
-- I) Dentro de un sector el código de componente es único (entre sectores puede repetirse:
--    A1/A4/A8/A9/Z22 son piezas y cajas con el mismo código, ver IDEAS 7244).
select 'I_codigo_repetido_en_el_mismo_sector', count(*) from (
    select sector_id, lower(btrim(codigo)) from "GP2".componente group by 1, 2 having count(*) > 1) d
union all
-- J) Todo movimiento toca al menos una ubicación, y el inventario no tiene pares repetidos.
select 'J_movimientos_sin_ubicacion', count(*) from "GP2".movimiento where ubic_origen_id is null and ubic_destino_id is null
union all
select 'K_inventario_par_repetido', count(*) from (
    select componente_id, ubicacion_id from "GP2".inventario group by 1, 2 having count(*) > 1) d
union all
-- L) Toda ruta tiene pasos y todo paso pertenece a una ruta con artículo.
select 'L_rutas_sin_pasos', count(*) from "GP2".ruta r where not exists (select 1 from "GP2".ruta_paso p where p.ruta_id = r.id)
union all
-- M) Las RPC de pantalla (todo lo que no es interno) tienen EXECUTE para anon: si falta, la
--    pantalla muestra "permission denied" (pasó con «Desmarcar», ciclo 2l).
select 'M_rpc_de_pantalla_sin_execute_anon', count(*) from pg_proc p
 where p.pronamespace = '"GP2"'::regnamespace and not has_function_privilege('anon', p.oid, 'EXECUTE')
   and not (p.prorettype = 'trigger'::regtype or p.proname like '\_%' or p.proname like 'fn\_%'
        or p.proname like 'relev\_%' or p.proname like 'recalcular\_%'
        or p.proname in ('to_canonical', 'inv_delta', 'ubic_de', 'ubic_de_componente', 'recepcion_tara',
                         'recepcion_virgilio', 'actualizar_dolar_oficial', 'crear_recepcion_insumo'))
union all
-- N) Ninguna funcion GP2 resuelve nombres en public (search_path = GP2 solo), salvo las dos que
--    lo necesitan a proposito (get_role_for_email delega en public; actualizar_dolar_oficial usa http).
select 'N_funciones_con_public_en_search_path', count(*) from pg_proc p
 where p.pronamespace = '"GP2"'::regnamespace and array_to_string(p.proconfig, ';') ilike '%public%'
   and p.proname not in ('actualizar_dolar_oficial', 'get_role_for_email')
union all
-- O) El espejo de Virgilio no dejo entregas sin cruzar por un ERROR (los "sin equivalente" y
--    "contraparte sin resolver" son datos pendientes del usuario, pregunta 8; un 'error:' es un bug).
select 'O_espejo_virgilio_con_error', count(*) from "GP2".virgilio_espejo_pend where motivo like 'error%'
union all
-- P/Q/R) Recepcion y ledger van juntos: toda recepcion tiene su movimiento de compra con la
--    misma cantidad (el control la cambia en los dos lados) y toda compra tiene su recepcion.
select 'P_recepcion_sin_movimiento', count(*) from "GP2".recepcion_insumo where movimiento_id is null
union all
select 'Q_recepcion_y_movimiento_con_distinta_cantidad', count(*) from "GP2".recepcion_insumo r
  join "GP2".movimiento m on m.id = r.movimiento_id where abs(coalesce(r.cantidad, 0) - m.cantidad) > 0.0005
union all
select 'R_compra_sin_recepcion', count(*) from "GP2".movimiento m
 where m.tipo_mov = 'compra' and not exists (select 1 from "GP2".recepcion_insumo r where r.movimiento_id = m.id)
union all
-- S..Y) Estructura de recetas y rutas: un terminado no es parte de una receta (abm_bom_guardar lo
--    rechaza), el BOM no tiene ciclos, los pasos de una ruta no repiten orden ni quedan sin actor,
--    las cantidades de receta son positivas y todo componente tiene sector.
select 'S_receta_con_terminado', count(*) from "GP2".articulo_componente ac join "GP2".componente c on c.id = ac.componente_id where c.sector_id = 12
union all
select 'T_bom_ciclo_directo', count(*) from "GP2".componente_bom b where b.componente_padre_id = b.componente_hijo_id
union all
select 'T2_bom_ciclo_indirecto', count(*) from "GP2".componente_bom a join "GP2".componente_bom b
  on a.componente_hijo_id = b.componente_padre_id and b.componente_hijo_id = a.componente_padre_id
union all
select 'U_ruta_paso_orden_repetido', count(*) from (select ruta_id, orden from "GP2".ruta_paso group by 1, 2 having count(*) > 1) d
union all
select 'W_paso_sin_actor', count(*) from "GP2".ruta_paso rp
 where rp.tipo_paso in ('matriz', 'proveedor_servicio', 'tallerista') and coalesce(rp.matriz_id, rp.proveedor_id, rp.tallerista_id) is null
union all
select 'X_receta_cantidad_no_positiva', count(*) from "GP2".articulo_componente where coalesce(cantidad, 0) <= 0
union all
select 'Y_componente_sin_sector', count(*) from "GP2".componente where sector_id is null
union all
-- Z) Configuración: toda clave de parametro que lee el código existe (si falta, la función cae a
--    un default escrito en el código y nadie se entera) y no hay claves que nadie lee (una clave
--    muerta es una regla que el usuario cree que manda y no manda). La lista es la de los
--    `clave = '...'` de db/funciones_GP2.sql y db/vistas_GP2.sql: al agregar una clave en el
--    código se agrega acá, a propósito.
select 'Z_parametro_que_lee_el_codigo_faltante', count(*) from unnest(array[
    'caja_uni_x_paquete', 'carton_uni_x_paquete', 'charcas_kg_x_paquete', 'costo_segundo_pesos',
    'faltante_cajones_umbral', 'max_cajones_x_ubicacion', 'pliego_uni_x_paquete', 'registro_en_golpes',
    'tara_pallet_max', 'tara_pallet_min', 'tipo_cambio_usd_pesos', 'tol_ctrl_peso_pct']) k
 where not exists (select 1 from "GP2".parametro p where p.clave = k)
union all
select 'Z2_parametro_que_nadie_lee', count(*) from "GP2".parametro p
 where p.clave not in (
    'caja_uni_x_paquete', 'carton_uni_x_paquete', 'charcas_kg_x_paquete', 'costo_segundo_pesos',
    'faltante_cajones_umbral', 'max_cajones_x_ubicacion', 'pliego_uni_x_paquete', 'registro_en_golpes',
    'tara_pallet_max', 'tara_pallet_min', 'tipo_cambio_usd_pesos', 'tol_ctrl_peso_pct')
union all
-- Z3) Un PS híbrido tiene una materia prima con proveedor de insumo: si no, crear_oc no puede
--     armar la OC gemela (Charcas → Altrak, Eclipse → Aperam).
select 'Z3_ps_hibrido_mp_sin_proveedor', count(*) from "GP2".proveedor_servicio ps
  join "GP2".componente c on c.id = ps.mp_componente_id
 where ps.hibrido and (c.proveedor is null or not exists (select 1 from "GP2".proveedor_insumo pi where pi.nombre = c.proveedor))
) chequeos
order by regla;

-- =====================================================================
-- INFORMATIVAS (no son invariantes: dan > 0 por datos que faltan o decisiones pendientes del
-- usuario; sirven para ver si crecen). Cada una dice a qué pregunta/idea pertenece.
-- =====================================================================
-- select 'stock_negativo' que, count(*) n, '(pregunta 8.3: stock inicial de talleristas no cargado)' ref from "GP2".inventario where cantidad < -0.0005
-- union all select 'minimo_mayor_que_maximo', count(*), '(pregunta 27: 56 legítimas de 5 cajones + parámetros meses de 3 ubicaciones)' from "GP2".inventario where minimo is not null and maximo is not null and minimo > maximo
-- union all select 'espejo_virgilio_pendiente_datos', count(*), '(pregunta 8.17: artículos de Virgilio sin equivalente en GP2)' from "GP2".virgilio_espejo_pend where motivo not like 'error%'
-- union all select 'est_madre_sin_articulo_gp2', count(*), '(idea 7244: familias que GP2 no modela)' from "GP2".est_madre em where not exists (select 1 from "GP2".articulo a where regexp_replace(a.codigo,'^0+','') = regexp_replace(em.cod,'^0+',''))
-- union all select 'componentes_discontinuos_en_rutas', count(distinct c.id), '(pregunta 8.4)' from "GP2".componente c join "GP2".ruta_paso rp on rp.comp_entrada_id = c.id or rp.comp_salida_id = c.id where c.estado_compra = 'discontinuo'
-- union all select 'contrapartes_sin_partes_en_rutas', count(*), '(PS sin pasos: Rec Color, Daniel, Esther, Eclipse...)' from "GP2".proveedor_servicio ps where not exists (select 1 from "GP2".v_contraparte_parte v where v.tipo = 'proveedor_servicio' and v.ref_id = ps.id)
-- union all select 'rutas_sin_articulo', count(*), '(rutas de intermedios: es un modelo valido, no un error; 13 al 2026-09-05)' from "GP2".ruta where articulo_id is null;

-- ---------------------------------------------------------------------
-- PENDIENTE (pregunta 27 de PREGUNTAS_ARQUITECTURA_GP2.md). OJO: "mínimo ≤ máximo" NO es un
-- invariante — el usuario decidió el 2026-09-02 que mínimo > máximo puede ser correcto (es la
-- planta; CONOCIMIENTO §2e-bis). El que sí sirve es este: una ubicación con meses_minimo >
-- meses_stock hace mínimo > máximo por aritmética en todo lo que consume. Hoy da 3 (Crudo,
-- Procesado, Bombilla); entra en la lista de arriba cuando el usuario corrija los parámetros.
-- select 'P_ubicacion_meses_minimo_mayor_que_stock' regla, count(*) n from "GP2".ubicacion
--  where meses_minimo is not null and meses_stock is not null and meses_minimo > meses_stock;
