-- ============================================================================
-- El M1 desaparece: a Rafael se le manda el disco calado y el vástago sueltos
-- Artículos 121, 315 y 609 (Pisa Papas).  Pedido de Thomas, 2026-09-23.
--
-- ✅ APLICADO EL 2026-09-23, bloques A y B, con el "sí" de Thomas.
--   El bloque A es el cambio de producto. El bloque B es el precio del vástago.
--   Verificado: las 6 rutas sin el M1, las 3 recetas con M2 + V18, el M1 borrado,
--   el disco calado y el vástago con máximo 5.078 en la ubicación de Pettofrezza,
--   e invariantes de modelo de db/verificar.sql en 0 (la única fila > 0 es
--   AE_paso_virgilio_y_codigo_dan_distinto = 2, y es AJENA: los artículos 567
--   "Corta Palta" y 537 "Pela y Pica Ajo", que tienen componente terminado pero
--   0 rutas y 0 receta; ya estaba antes de tocar nada).
--
--   Costo por artículo, medido antes y después:
--     121  $397,49 -> $846,02      315  $561,26 -> $1.009,79
--     609  $500,00 -> $948,53      V18  $0,00   -> $448,54 (origen 'precio')
--   La planilla del dueño pone el 315 en $1.025,59: quedan $15,80 de diferencia,
--   con GP2 usando el tallerista de Pettofrezza ($140) donde la planilla usa el
--   de Cavallero ($85). Sin perseguir todavía.
--
-- Estado medido el 2026-09-23 antes de tocar nada:
--   M1  = componente 146 "Disco Inox C/Vastago Alu" (Sector Procesado)
--         0 stock, 0 movimientos. Lo referencian SOLO: 4 filas de inventario,
--         2 de componente_bom (M1 = M2 + V18C), 3 de articulo_componente y
--         12 de ruta_paso. Barrido hecho sobre las 28 FK a GP2.componente.
--   M2  = componente 147 "Disco Pisa Papa Calado" (Sector Procesado)
--   V18C= componente 282 "Vastago Alu" (Sector Remache, Bella Vista)
--   Artículos como componente: 121 -> 390, 315 -> 392, 609 -> 432
--   Rutas del fleje: 136 (121), 553 (315), 558 (609)
--   Rutas del vástago: 1057 (121), 1058 (315), 1059 (609)
--   Ubicaciones: 31 = Tallerista Pettofrezza Rafael, 24 = Tallerista Cavallero
--
-- Costo ANTES (GP2.v_costo_componente): 121 $397,49 · 315 $561,26 · 609 $500,00
-- ============================================================================


-- ============================================================================
-- BLOQUE A — el cambio de producto
-- ============================================================================
begin;

-- A1. V18C -> V18. El vástago se compra terminado, así que no lleva marca de
--     crudo. En GP2 los crudos de remache van con prefijo CV: el crudo de este
--     sería CV18, y no existe justamente porque no se fabrica. 'V18' está libre
--     y no pisa a V18D (Tornillo Sacafuente). Sigue en Sector Remache: el insumo
--     vive donde el dueño lo cuenta y lo pide.
--     estado_compra pasa de 'discontinuo' a NULL (comprado): la planilla vigente
--     lo sigue pidiendo a Bella Vista, así que 'discontinuo' es un dato viejo.
update "GP2".componente
   set codigo = 'V18', estado_compra = null
 where id = 282;

-- A2. Rutas del fleje (136, 553, 558): se va el paso M2 -> M1 y el armado
--     arranca directo del disco calado.
--     Antes: ingreso IB2 · matriz 349 (IB2->M2) · tall (M2->M1) · tall (M1->art) · virgilio
--     Ahora: ingreso IB2 · matriz 349 (IB2->M2) · tall (M2->art) · virgilio
delete from "GP2".ruta_paso
 where ruta_id in (136,553,558) and orden = 3 and comp_salida_id = 146;

update "GP2".ruta_paso
   set comp_entrada_id = 147, orden = 3
 where ruta_id in (136,553,558) and orden = 4 and comp_entrada_id = 146;

update "GP2".ruta_paso
   set orden = 4
 where ruta_id in (136,553,558) and orden = 5 and tipo_paso = 'virgilio';

-- A3. Rutas del vástago (1057, 1058, 1059): el V18 entra derecho al artículo,
--     igual que PA10B, PC11, I3C y A3.
--     Antes: insumo V18C · tall (V18C->M1) · tall (M1->art) · virgilio
--     Ahora: insumo V18  · tall (V18 ->art) · virgilio
update "GP2".ruta_paso p
   set comp_salida_id = m.art_comp_id
  from (values (1057, 390::bigint), (1058, 392), (1059, 432)) m(ruta_id, art_comp_id)
 where p.ruta_id = m.ruta_id and p.orden = 2 and p.comp_salida_id = 146;

delete from "GP2".ruta_paso
 where ruta_id in (1057,1058,1059) and orden = 3 and comp_entrada_id = 146;

update "GP2".ruta_paso
   set orden = 3
 where ruta_id in (1057,1058,1059) and orden = 4 and tipo_paso = 'virgilio';

update "GP2".ruta
   set nombre = replace(nombre, 'V18C', 'V18')
 where id in (1057,1058,1059);

-- A4. Receta: el M1 sale y entran el disco calado y el vástago, 1 de cada uno.
delete from "GP2".articulo_componente
 where componente_id = 146
   and articulo_id in (select id from "GP2".articulo where codigo in ('121','315','609'));

insert into "GP2".articulo_componente (articulo_id, componente_id, cantidad)
select a.id, v.cid, 1
  from "GP2".articulo a, (values (147::bigint),(282)) v(cid)
 where a.codigo in ('121','315','609');

-- A5. El M1 se va entero. Se puede: 0 stock y 0 movimientos, y después de A2-A4
--     no queda nada apuntándole. De paso se termina el código M1 duplicado
--     (quedaba el disco 146 y el Cartón 220 823 con el mismo código).
delete from "GP2".componente_bom where componente_padre_id = 146;
delete from "GP2".inventario     where componente_id = 146;   -- 4 filas, todas en 0
delete from "GP2".componente     where id = 146;

-- A6. Cavallero German quedó sin rutas el 2026-09-22: su fila de vástago se va
--     (está en 0). La de M1 ya se fue en A5.
delete from "GP2".inventario where componente_id = 282 and ubicacion_id = 24;

-- A7. El disco calado necesita su fila en la ubicación de Pettofrezza, si no el
--     Envío a Talleristas no le puede poner máximo ni sugerido:
--     recalcular_maximos_talleristas SÓLO actualiza filas que existen, no las crea.
insert into "GP2".inventario (componente_id, ubicacion_id, cantidad)
select 147, 31, 0
 where not exists (select 1 from "GP2".inventario
                    where componente_id = 147 and ubicacion_id = 31);

select "GP2".recalcular_maximos_talleristas(false, array[147,282]::bigint[], false);

commit;


-- ---------------------------------------------------------------------------
-- VERIFICACIÓN del bloque A (correr después del commit)
-- ---------------------------------------------------------------------------
-- 1) Las 6 rutas, paso por paso: ninguna debe nombrar al M1.
select a.codigo art, r.id ruta, p.orden, p.tipo_paso,
       ce.codigo entrada, cs.codigo salida, t.nombre tallerista, m.n_matriz matriz
  from "GP2".ruta r
  join "GP2".articulo a on a.id = r.articulo_id
  join "GP2".ruta_paso p on p.ruta_id = r.id
  left join "GP2".componente ce on ce.id = p.comp_entrada_id
  left join "GP2".componente cs on cs.id = p.comp_salida_id
  left join "GP2".tallerista t on t.id = p.tallerista_id
  left join "GP2".matriz m on m.id = p.matriz_id
 where r.id in (136,553,558,1057,1058,1059)
 order by a.codigo, r.id, p.orden;

-- 2) La receta de los tres.
select a.codigo art, c.codigo, c.descripcion, ac.cantidad
  from "GP2".articulo a
  join "GP2".articulo_componente ac on ac.articulo_id = a.id
  join "GP2".componente c on c.id = ac.componente_id
 where a.codigo in ('121','315','609') order by a.codigo, c.codigo;

-- 3) El M1 no existe más y el V18 sí (debe dar 0 filas para M1 disco).
select id, codigo, descripcion, estado_compra from "GP2".componente
 where id in (146,282) or codigo in ('M1','V18');

-- 4) El disco calado y el vástago, con su stock y máximo por ubicación.
select c.codigo, u.nombre ubicacion, i.cantidad, i.maximo, i.maximo_origen
  from "GP2".inventario i
  join "GP2".componente c on c.id = i.componente_id
  join "GP2".ubicacion u on u.id = i.ubicacion_id
 where i.componente_id in (147,282) order by c.codigo, u.nombre;

-- 5) Costo de los tres (sin el bloque B tienen que quedar casi iguales: el
--    vástago sigue en $0 hasta que se cargue el precio).
select comp_id, codigo, round(material_pesos,2) material, round(servicios_pesos,2) servicios,
       round(total_pesos,2) total, faltan_precios
  from "GP2".v_costo_componente where comp_id in (390,392,432,147,282) order by codigo;

-- 6) Invariantes de la base: cada fila tiene que dar n = 0.
--    \i db/verificar.sql


-- ============================================================================
-- BLOQUE B — el precio del vástago  ✅ APLICADO (precio_proveedor id 378)
-- ============================================================================
-- Hoy el vástago se costea en $0 y por eso los tres artículos salen baratos.
-- La planilla del dueño (A_Costos_VIGENTES) lo costea en 448,5373 POR UNIDAD:
--   GP2.v_planilla_costo, códigos 121 y 315 -> columna "remaches" = 448,5373,
--   con la fórmula ='Lista de Precios '!L171, o sea la fila 171 del bloque
--   890 Bella Vista, "Remache Pisapapas 8 x 97", cod ISIS 0885, lista 2026-07-08.
-- Efecto en cadena: los tres artículos suben ~$448,54 cada uno. El 315 pasa de
-- $561,26 a ~$1.010, que es la dirección de los $1.025,59 de la planilla.
--
insert into "GP2".precio_proveedor
  (rubro, cod_prov, producto, precio, moneda, fecha_lista, componente_id, precio_por_kg)
values ('Materiales', '890',
  'Remache Pisapapas 8 x 97 (Bella Vista) — planilla A Costos VIGENTES, hoja "Lista de Precios ", fila 171, cod ISIS 0885. Por UNIDAD: v_planilla_costo de los codigos 121 y 315 lo suma tal cual en la columna remaches',
  448.5373, 'ARS', '2026-07-08', 282, false);
-- Medido después: V18 pasa a $448,54 con origen 'precio', y los tres artículos
-- suben ese mismo monto. Si algún día se descubre que era por kilo, se corrige
-- con precio_por_kg = true (el costo quedaría en $6,44/uni) — pero la fórmula
-- de la planilla ='Lista de Precios '!L171 lo suma sin multiplicar por kg_x_uni.


-- ============================================================================
-- LO QUE NO SE TOCA ACÁ, PORQUE FALTA EL DATO
-- ============================================================================
-- · Pettofrezza no tiene precio para el 121. El $85 que hay es de Cavallero
--   German, que quedó sin rutas. El 315 y el 609 tienen $140 "AyE".
--   Con el M1 afuera el trabajo de Rafael es UN solo paso, así que el "AyE"
--   ya cubre poner el vástago en el disco — pero el número del 121 lo dice él.
