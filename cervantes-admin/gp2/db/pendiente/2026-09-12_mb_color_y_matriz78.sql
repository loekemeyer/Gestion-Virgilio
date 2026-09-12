-- =====================================================================
-- PENDIENTE DE APLICAR — quedo afuera porque Supabase empezo a dar
-- "Connection terminated due to connection timeout" (hasta un select 1 falla).
-- Correr esto cuando la base vuelva, EN ESTE ORDEN, y despues borrar el archivo.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) SIETE COLORES DE MASTER BACH dictados por el usuario el 2026-09-12:
--    "Pv14 rojo / Insertos mango de madera, negro / Mango chef blanco /
--     Pa1 rojo / Pc15b azul / Pv17 blanco / Pest2 negro"
--    Es idempotente: se puede correr las veces que haga falta.
-- ---------------------------------------------------------------------
update "GP2".componente set mb_color = case codigo
    when 'PV14'  then 'R'   -- Picos Reposteros
    when 'PEST1' then 'N'   -- Insertos Mango de Madera
    when 'PA19'  then 'B'   -- Mangos Chef
    when 'PA1'   then 'R'   -- Plaquita 3 en 1 LK
    when 'PC15B' then 'A'   -- Cuerpo Sac Aleta Plast Ch
    when 'PV17'  then 'B'   -- Pela Naranjas
    when 'PEST2' then 'N'   -- Insertos Pisa Papas
  end
 where codigo in ('PV14','PEST1','PA19','PA1','PC15B','PV17','PEST2');

-- y recalcular, que es lo que mueve los maximos del master:
select "GP2".recalcular_maximo_material();

-- ---------------------------------------------------------------------
-- 2) LA MATRIZ 78: ESTADO DESCONOCIDO. NO REAPLICAR A CIEGAS.
--    La migracion "la_matriz_78_pasa_a_ser_una_convergencia" se corto por el
--    mismo timeout y NO SE PUDO VERIFICAR si entro, si entro a medias o si no
--    entro. El bloque tiene un "update ruta_paso set orden = orden + 1", que NO
--    es idempotente: aplicarlo dos veces corre los pasos dos veces y rompe las
--    rutas del rompenueces.
--
--    PRIMERO leer el estado con esto:
--      select r.id ruta, rp.orden, rp.tipo_paso,
--             coalesce(m.n_matriz, t.nombre, pv.nombre,'') actor,
--             ce.codigo entra, cs.codigo sale
--        from "GP2".ruta_paso rp
--        join "GP2".ruta r on r.id = rp.ruta_id
--        left join "GP2".matriz m on m.id = rp.matriz_id
--        left join "GP2".tallerista t on t.id = rp.tallerista_id
--        left join "GP2".proveedor_servicio pv on pv.id = rp.proveedor_id
--        left join "GP2".componente ce on ce.id = rp.comp_entrada_id
--        left join "GP2".componente cs on cs.id = rp.comp_salida_id
--       where r.id in (45,46,47,48,300,411) order by r.id, rp.orden;
--      select id, codigo, descripcion from "GP2".componente where codigo like '%-M78';
--
--    COMO TIENE QUE QUEDAR (el patron de la M135 del art 521: las tres ramas
--    llevan el MISMO paso de matriz con la MISMA salida):
--      ruta 45  (507): ... Pedernera -> D6 -> [M78] -> D5-M78 -> Fabrica -> 507
--      ruta 46  (507): ... Pedernera -> D5 -> [M78] -> D5-M78 -> Fabrica -> 507
--      ruta 300 (507): CV4 -> Guazzaroni -> V4 -> [M78] -> D5-M78 -> Fabrica -> 507
--      ruta 47  (707): ... Jade -> B1 -> [M78] -> B1-M78 -> Fabrica -> 707
--      ruta 48  (707): ... Jade -> B2 -> [M78] -> B1-M78 -> Fabrica -> 707
--      ruta 411 (707): CV4 -> Guazzaroni -> V4 -> [M78] -> B1-M78 -> Fabrica -> 707
--    y D6-M78 (id 484) y B2-M78 (id 487) borrados, porque dejan de existir:
--    no se puede remachar media pieza.
--
--    ids: matriz 78 = 52 · D5=109 D6=110 B1=87 B2=88 V4=272
--         D5-M78=485 D6-M78=484 B1-M78=486 B2-M78=487
--
--    FOTO DE COSTOS DE ANTES (para comparar): 507 $887,53 · 707 $1.264,56 ·
--    521 $1.428,69 (el precedente, NO se tiene que mover) · D5=D6 $372,54 ·
--    B1=B2 $572,18 · D5-M78 $401,34 · B1-M78 $600,98 · V4 $30,01.
--    Se espera que el 507 BAJE ~$29: hoy la M78 se cobra dos veces, una por
--    cada mitad, y tiene que cobrarse una sola.
-- ---------------------------------------------------------------------
