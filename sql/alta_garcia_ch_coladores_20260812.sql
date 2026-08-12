-- =====================================================================
--  alta_garcia_ch_coladores_20260812.sql
--  Recepción de remitos: habilitar los coladores 437E / 438E / 439E al
--  tallerista GARCIA en la línea CHEF (CH).
--
--  PEDIDO
--    "agregar a recepcion de remitos al tallerista bryan garcia en chef
--     el art 438E 437E y 439E"
--
--  QUIÉN ES (confirmado por el usuario el 2026-08-12)
--    "Bryan Garcia" es el MISMO "Garcia" que ya estaba en el maestro
--    `Codigos X Tallerista`:   CH → código 3915     LK → código 4317
--    No hay que dar de alta ningún tallerista nuevo. El maestro guarda solo el
--    apellido (Poly, Martin, Lucho, Carlos, Garcia…), por eso "Bryan" no
--    figura; y Garcia LK ya tenía exactamente estos tres códigos — o sea ya
--    hacía los coladores, y ahora también para Chef.
--
--  QUÉ SE HACE
--    Espejar a CH las 3 filas que Garcia ya tiene en LK, cambiando Linea y
--    Cod_Tallerista (4317 → 3915). Descripción, Uni_x_Caja, Cajas_x_Master y
--    destino_entrega se copian tal cual del LK.
--
--    Cod_Art  Desc              Uni_x_Caja  Cajas_x_Master
--    437E     Colador N°16      24          3
--    438E     Colador N°20      24          3
--    439E     Colador Pasta      6          4
--
--  NO hace falta tocar `Codigos X Tallerista`: Garcia ya tiene código CH
--  (3915) y ya figura en ORDEN_TALL de recepcion.js, así que aparece en la
--  lista de talleristas con el botón Chef habilitado. Hoy en CH solo tenía
--  700 y 839; con esto pasa a tener 5 códigos.
--
--  ESTADO PREVIO
--    Garcia CH (3915) en "Articulos Virgilio X Tallerista": 700, 839.
--    437E/438E/439E en CH: no los tenía NADIE.
-- =====================================================================

-- ---------- APLICAR (idempotente: no duplica si ya están) ----------
INSERT INTO "Articulos Virgilio X Tallerista"
  ("Linea", "Cod_Art", "Desc", "Tallerista", "Uni_x_Caja", "Cod_Tallerista",
   "Kg Recibido", "destino_entrega", "sector_factura", "Cajas_x_Master")
SELECT 'CH', v."Cod_Art", v."Desc", 'Garcia', v."Uni_x_Caja", '3915',
       0, 'virgilio', NULL, v."Cajas_x_Master"
FROM (VALUES
        ('437E', 'Colador N°16', 24, 3::numeric),
        ('438E', 'Colador N°20', 24, 3::numeric),
        ('439E', 'Colador Pasta', 6, 4::numeric)
     ) AS v("Cod_Art", "Desc", "Uni_x_Caja", "Cajas_x_Master")
WHERE NOT EXISTS (
  SELECT 1 FROM "Articulos Virgilio X Tallerista" x
  WHERE x."Linea" = 'CH'
    AND upper(trim(x."Cod_Art")) = v."Cod_Art"
    AND x."Cod_Tallerista" = '3915'
);

-- ---------- REVERTIR (restore) ----------
-- Sólo-inserción: no toca ni borra ninguna fila existente, así que revertir
-- es exacto.
--
--   DELETE FROM "Articulos Virgilio X Tallerista"
--   WHERE "Linea" = 'CH' AND "Cod_Tallerista" = '3915'
--     AND upper(trim("Cod_Art")) IN ('437E', '438E', '439E');

-- ---------- VERIFICAR ----------
--   SELECT "Linea", "Cod_Art", "Desc", "Uni_x_Caja", "Cajas_x_Master"
--   FROM "Articulos Virgilio X Tallerista"
--   WHERE "Cod_Tallerista" = '3915' AND "Linea" = 'CH'
--   ORDER BY "Cod_Art";      -- debe dar 5 filas: 437E, 438E, 439E, 700, 839
