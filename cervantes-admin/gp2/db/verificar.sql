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
-- A2) Todo proveedor que entrega piezas con material asignado es un INYECTOR con ubicacion propia
--     (si no, crear_recepcion_insumo recibe la pieza pero NO descuenta la materia prima y el stock
--     de Virgilio queda inflado sin que nadie avise). 2026-09-10.
select 'A2_inyector_con_material_sin_ubicacion', count(*) from (
    select distinct c.proveedor from "GP2".componente c
     where c.material_id is not null and c.estado_compra is null and c.proveedor is not null
       and "GP2".ubic_de('inyector', (select pi.id from "GP2".proveedor_insumo pi where pi.nombre = c.proveedor)) is null) x
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
                         'recepcion_virgilio', 'actualizar_dolar_oficial', 'crear_recepcion_insumo',
                         -- mantenimiento: se corren desde una sesion con SQL, nunca desde una pantalla
                         'planilla_snapshot_nuevo', 'planilla_cargar', 'reprocesar_espejo_virgilio',
                         -- no es el motor de la entrega de tallerista (ese es gp2-motor.js), idea 7316
                         'crear_entrega_tallerista',
                         -- puerta unica interna: la llaman recepcion_virgilio y movimientos_bundle, no una pantalla
                         'comp_terminado_de'))
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
                         'recepcion_virgilio', 'actualizar_dolar_oficial', 'crear_recepcion_insumo',
                         -- mantenimiento: se corren desde una sesion con SQL, nunca desde una pantalla
                         'planilla_snapshot_nuevo', 'planilla_cargar', 'reprocesar_espejo_virgilio',
                         -- no es el motor de la entrega de tallerista (ese es gp2-motor.js), idea 7316
                         'crear_entrega_tallerista',
                         -- puerta unica interna: la llaman recepcion_virgilio y movimientos_bundle, no una pantalla
                         'comp_terminado_de'))
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
    'tara_pallet_max', 'tara_pallet_min', 'tipo_cambio_usd_pesos', 'tol_ctrl_peso_pct',
    'inyeccion_desperdicio_pct', 'material_plastico_kg_x_bolsa', 'oc_facturar_pct_loeke']) k
 where not exists (select 1 from "GP2".parametro p where p.clave = k)
union all
select 'Z2_parametro_que_nadie_lee', count(*) from "GP2".parametro p
 where p.clave not in (
    'caja_uni_x_paquete', 'carton_uni_x_paquete', 'charcas_kg_x_paquete', 'costo_segundo_pesos',
    'faltante_cajones_umbral', 'max_cajones_x_ubicacion', 'pliego_uni_x_paquete', 'registro_en_golpes',
    'tara_pallet_max', 'tara_pallet_min', 'tipo_cambio_usd_pesos', 'tol_ctrl_peso_pct',
    'inyeccion_desperdicio_pct', 'material_plastico_kg_x_bolsa', 'oc_facturar_pct_loeke')
union all
-- Z3) Un PS híbrido tiene una materia prima con proveedor de insumo: si no, crear_oc no puede
--     armar la OC gemela (Charcas → Altrak, Eclipse → Aperam).
select 'Z3_ps_hibrido_mp_sin_proveedor', count(*) from "GP2".proveedor_servicio ps
  join "GP2".componente c on c.id = ps.mp_componente_id
 where ps.hibrido and (c.proveedor is null or not exists (select 1 from "GP2".proveedor_insumo pi where pi.nombre = c.proveedor))
union all
-- AA) La cantidad de un paso de ingreso/insumo es la misma que dice la RECETA del articulo.
--     ruta_paso.cantidad duplica articulo_componente.cantidad y los dos ya divergieron una vez:
--     58 pasos habian quedado con cantidad 1 (las cajas piden 1/articulos_por_caja, los flejes
--     kilos por unidad, y en 4 casos la receta pedia 2). 2026-09-11.
select 'AA_paso_de_insumo_contradice_la_receta' regla, count(*) n
  from "GP2".ruta_paso p
  join "GP2".ruta r on r.id = p.ruta_id
  join "GP2".articulo_componente ac on ac.articulo_id = r.articulo_id and ac.componente_id = p.comp_entrada_id
 where p.tipo_paso in ('insumo','ingreso') and abs(p.cantidad - ac.cantidad) > 0.0001
union all
-- AB) Toda ruta arranca en algo que se PUEDE comprar o que otra ruta produce. Si un componente
--     entra como insumo, no es comprable y nadie lo fabrica, la cadena arranca en el aire y el
--     circuito del articulo no puede ni empezar (paso 1 y 2 del recorrido productivo).
--     Paso el 2026-09-11 con las 4 piezas importadas del Sector Procesado (C13, D1, Z23A, Z23B):
--     17 rutas de 16 articulos bloqueadas.
select 'AB_ruta_que_arranca_en_el_aire', count(*) from (
    select distinct p.comp_entrada_id cid
      from "GP2".ruta_paso p
     where p.tipo_paso in ('insumo','ingreso')
       and not "GP2"._es_comprable(p.comp_entrada_id)
       and not exists (select 1 from "GP2".ruta_paso q
                        where q.comp_salida_id = p.comp_entrada_id
                          and q.comp_salida_id is distinct from q.comp_entrada_id)
       and not exists (select 1 from "GP2".componente_bom b where b.componente_padre_id = p.comp_entrada_id)) x
union all
-- AC) El vocabulario de movimiento es una tabla y movimiento.tipo_mov es FK contra ella: ningun
--     tipo_mov puede quedar fuera del catalogo (antes era un CHECK de literales copiado en el JS).
select 'AC_tipo_mov_fuera_del_catalogo', count(*) from "GP2".movimiento m
 where not exists (select 1 from "GP2".tipo_movimiento t where t.clave = m.tipo_mov)
union all
-- AD) Todo articulo resuelve su componente terminado por la unica puerta (comp_terminado_de).
--     Si da null, el circuito no cierra: recepcion_virgilio explota al entregarlo y
--     movimientos_bundle no sabe a que articulo pertenece lo que entra a Virgilio.
select 'AD_articulo_sin_componente_terminado', count(*) from "GP2".articulo a
 where "GP2".comp_terminado_de(a.id) is null
union all
-- AE) Y los dos criterios que antes convivian (el paso 'virgilio' de la ruta y el codigo en el
--     sector 12) siguen dando LO MISMO. Si se separan, la puerta unica elige la ruta y el que
--     mire por codigo (una pantalla, un informe) va a ver otro componente. Idea 7322.
select 'AE_paso_virgilio_y_codigo_dan_distinto', count(*) from "GP2".articulo a
 where (select rp.comp_entrada_id from "GP2".ruta r join "GP2".ruta_paso rp on rp.ruta_id = r.id
         where r.articulo_id = a.id and rp.tipo_paso = 'virgilio' and rp.comp_entrada_id is not null
         order by rp.ruta_id limit 1)
   is distinct from
       (select c.id from "GP2".componente c where c.sector_id = 12 and c.codigo = a.codigo
         order by c.id limit 1)
) chequeos
order by regla;

-- =====================================================================
-- INFORMATIVAS (no son invariantes: dan > 0 por datos que faltan o decisiones pendientes del
-- usuario; sirven para ver si crecen). Cada una dice a qué pregunta/idea pertenece.
-- =====================================================================
-- RECETA vs RUTA (2026-09-11). Sale de la prueba de conservacion de "GP2".__sim_articulo: se
-- simulan las 189 producciones enteras y se mira que no quede nada colgado en una contraparte.
-- Da 13 pares hoy y NINGUNO se puede arreglar sin el usuario, por eso es informativa:
--   * 6 son del tallerista "Fábrica" (507, 570, 707, 858): no se manda nada a uno mismo, es correcto.
--   * 508/518/708 listan D13 (virola) en la receta, pero la ruta dice que Maspoli SRL se la lleva y
--     devuelve PC12 con la virola adentro -- o la receta cobra la virola dos veces, o Martin recibe
--     las dos cosas. Lo tiene que decir el usuario.
--   * 103 (caja A11), 120 (caja A9) y 564 (mango PC12) no tienen NINGUN paso de ruta para esa parte.
--   * 547 tiene DOS A4 en la receta: la Caja N°10 (bien) y el "Mgo Plano 501 Serig" del Sector
--     Procesado con cantidad de caja (1/12) -- el clasico codigo repetido en dos sectores.
-- select 'receta_sin_rama_que_la_lleve' que, count(*) n, '(13; ver el informe de la sesion)' ref from (
--   with final as (select distinct ru.articulo_id aid,
--            case when rp.proveedor_at_id is not null then 'proveedor_at' else 'tallerista' end tipo,
--            coalesce(rp.proveedor_at_id, rp.tallerista_id) ref
--       from "GP2".ruta_paso rp join "GP2".ruta ru on ru.id = rp.ruta_id
--       join "GP2".componente c on c.id = rp.comp_salida_id
--      where c.sector_id = 12 and rp.tipo_paso in ('tallerista','proveedor_at')),
--   entregado as (select distinct ru.articulo_id aid, rp.comp_entrada_id cid,
--            case when rp.proveedor_at_id is not null then 'proveedor_at' else 'tallerista' end tipo,
--            coalesce(rp.proveedor_at_id, rp.tallerista_id) ref
--       from "GP2".ruta_paso rp join "GP2".ruta ru on ru.id = rp.ruta_id
--      where rp.tipo_paso in ('tallerista','proveedor_at') and rp.comp_entrada_id is not null)
--   select ac.articulo_id, ac.componente_id from "GP2".articulo_componente ac join final f on f.aid = ac.articulo_id
--    where not exists (select 1 from entregado e where e.aid=ac.articulo_id and e.cid=ac.componente_id
--                        and e.tipo=f.tipo and e.ref=f.ref)) z
-- union all select 'hijo_de_bom_que_entra_solo_al_mismo_destino' que, count(*) n, '(idea 7298: se cobra dos veces, por la caminata y por la receta. Hoy 1 par, C12 <- BOM10 hacia 515 y 615, y BOM10 no tiene precio asi que no hay plata en juego)' ref from "GP2".componente_bom b join (select distinct rp.comp_entrada_id ent, rp.comp_salida_id sal from "GP2".ruta_paso rp where rp.comp_entrada_id is not null and rp.comp_salida_id is not null and rp.comp_entrada_id <> rp.comp_salida_id and rp.tipo_paso in ('matriz','proveedor_servicio','tallerista')) eh on eh.ent = b.componente_hijo_id join (select distinct rp.comp_entrada_id ent, rp.comp_salida_id sal from "GP2".ruta_paso rp where rp.comp_entrada_id is not null and rp.comp_salida_id is not null and rp.comp_entrada_id <> rp.comp_salida_id and rp.tipo_paso in ('matriz','proveedor_servicio','tallerista')) ep on ep.ent = b.componente_padre_id and ep.sal = eh.sal
-- union all select 'proveedor_servicio_proceso_fuera_del_catalogo' que, count(*) n, '(14 de 15: la columna es un ROTULO libre en Title Case y la relacion real PS<->proceso, que es 1:N, vive en tarifa_servicio; pintores_bundle ya no depende de como este escrito)' ref from "GP2".proveedor_servicio ps where ps.proceso is not null and not exists (select 1 from "GP2".proceso p where p.nombre = ps.proceso)
-- union all select 'uni_x_caja_LK_contradice_articulo' que, count(*) n, '(idea 7330: el 508 Sacafuentes Articulado dice 6 en articulo y 12 en uni_x_articulo_x_caja; lo tiene que decir el usuario)' ref from "GP2".uni_x_articulo_x_caja u join "GP2".articulo a on a.codigo = u.cod_art where u.empresa = 'LK' and a.articulos_por_caja is not null and a.articulos_por_caja <> u.uni_x_caja
-- union all select 'catalogo_prov_at_sin_descripcion' que, count(*) n, '(1: el cod_art 193 de Kuffo no es un articulo de GP2 todavia)' ref from "GP2".articulo_prov_at where nullif(btrim(coalesce(descripcion,'')),'') is null
-- union all select 'espejo_virgilio_sin_reprocesar', count(*), '(entregas de Virgilio que no cruzaron; reprocesar_espejo_virgilio(null, true) dice cuales ya se pueden)' from "GP2".virgilio_espejo_pend where resuelto_en is null
-- union all select 'stock_negativo' que, count(*) n, '(pregunta 8.3: stock inicial de talleristas no cargado)' ref from "GP2".inventario where cantidad < -0.0005
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
