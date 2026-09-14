-- =====================================================================
--  Equivalencias_Codigos sin el sufijo de empresa — §3.4 del plan del sufijo
--  (v17.05, 2026-09-14)
--
--  POR QUÉ ERA URGENTE (y no simple higiene)
--  `reconciliar_pipeline_stock_etapa1` canoniza el código del picking contra esta
--  tabla. Mientras `437E` mapeara a `437E LK`, el cron tenía una vía viva para
--  **reintroducir el sufijo** en `Movimientos_Stock.cod_art` — justo lo que costó
--  cuatro tramos sacar (v16.16 → v16.30).
--
--  Hoy no estaba pasando (0 movimientos con sufijo), y la razón es incómoda: el
--  front escribe primero con el código pelado y el guard del cron (`not exists`
--  por tanda) hace que no reinserte. O sea que el sufijo sólo habría vuelto **el
--  día que el front fallara** — que es exactamente el caso para el que existe el
--  cron. Bomba latente.
--
--  LAS 6 FILAS NO ERAN 6 FILAS IGUALES
--  El plan decía "borrar las 6 filas de sufijo". Mirándolas una por una son dos
--  cosas distintas, y borrarlas todas habría perdido información:
--
--  | fila | qué es | qué se hizo |
--  |---|---|---|
--  | `437E` → `437E LK` | mapeo **identidad** + sufijo | **borrada** |
--  | `438E` → `438E LK` | ídem | **borrada** |
--  | `439E` → `439E LK` | ídem | **borrada** |
--  | `809E` → `809E CH` | ídem | **borrada** |
--  | `438EL` → `438E LK` | mapea la **variante L** al artículo base — eso SÍ sirve | **corregida** a `438E` |
--  | `439EL` → `439E LK` | ídem | **corregida** a `439E` |
--
--  Borrar las 4 de identidad es seguro porque `resolver_equiv` cae a `p_cod` y los
--  cuatro códigos ya están en `OC_Maximos` activos con esa misma grafía pelada
--  (`437E`, `438E`, `439E`, `809E`), así que el resultado no cambia.
--  `727` → `727E` y `727EN` → `727E` se conservan: son equivalencias de verdad.
--
--  MEDICIÓN (resolver_equiv, antes → después)
--    437E:  '437E LK' → '437E'      438EL: '438E LK' → '438E'
--    438E:  '438E LK' → '438E'      439EL: '439E LK' → '439E'
--    439E:  '439E LK' → '439E'      727:   '727E'    → '727E'   (sin cambio)
--    809E:  '809E CH' → '809E'      727EN: '727E'    → '727E'   (sin cambio)
--  Los 9 casos probados resuelven a un código que **existe en `OC_Maximos` activo**.
--  Después: 0 filas con sufijo, 0 movimientos con sufijo, 0 negativos, 0 multigrafía
--  en `Movimientos_Stock`, y `vista_pedidos_equivalencia` / `vista_nc_loeke_chef`
--  siguen respondiendo (2 y 36 filas).
--
--  Backup: zz_backups."GV_Backup_Equivalencias_20260914" (la tabla entera).
-- =====================================================================

-- (a) las 4 de mapeo IDENTIDAD + sufijo: se borran
delete from public."Equivalencias_Codigos"
 where cod_pedido in ('437E','438E','439E','809E') and cod_real ~ '\s(LK|CH)$';

-- (b) las 2 de la variante L: el mapeo SIRVE, sólo se le saca el sufijo al destino
update public."Equivalencias_Codigos"
   set cod_real = btrim(regexp_replace(cod_real, '\s(LK|CH)$', ''))
 where cod_pedido in ('438EL','439EL');

-- chequeo
select count(*) as filas_con_sufijo_restantes
  from public."Equivalencias_Codigos" where cod_real ~ '\s(LK|CH)$';   -- 0
