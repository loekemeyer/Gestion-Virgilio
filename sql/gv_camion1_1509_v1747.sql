-- gv_camion1_1509_v1747.sql — APLICADO 2026-09-14 (v17.47).
--
-- Marianela: *"quiero que la tanda D67N, D67B y E01A pasen al camión número 1"* … *"del día 15/09"*,
-- y eligió la opción 1: mover las tres **llevándose el armado** de D67B.
--
-- ── POR QUÉ HAY QUE RENUMERAR ────────────────────────────────────────────────────────────
-- El camión agrupa por el NÚMERO de la tanda (`_pppCamiones`, key `n<tn>`), y los camiones se
-- numeran 1, 2, 3 según el orden de la pantalla (v13.13). El 15/09 el camión 1 era `E01A`
-- (número 01), así que para que las otras dos viajen con ella tienen que entrar a la serie E01.
--
--   D67B → E01E   (Miguel Addoumie SRL, Villa Soldati, NP 44607 y 44608, 0,121 m³)
--   D67N → E01J   (Veronesi Alcira Elena, La Boca, NP 98694, 0,160 m³)
--   E01A          (Torres Y Liva, Barracas, 0,985 m³) — ya estaba, no se tocó
--
-- ⚠ **D67B ya estaba ARMADA** (TAP del 11/09 11:26) con 17 líneas en `Entregas_Virgilio`. El
-- estado de armado se resuelve POR CÓDIGO DE TANDA (`_pppEstadoPed` mira `_pppArmadoDone.has(t)`),
-- así que cambiarle el código sólo en la programación la habría mostrado **"Sin empezar"** el día
-- que sale. Por eso se repuntaron también sus registros de producción y sus entregas.
--
-- ── BACKUPS ──────────────────────────────────────────────────────────────────────────────
--   zz_backups."GV_Backup_ProgOverride_20260914b"   (120 filas, la tabla entera)
--   zz_backups."GV_Backup_D67B_Registros_20260914"  (5 filas)
--   zz_backups."GV_Backup_D67B_Entregas_20260914"   (17 filas)

update public."GV_PPP_Prog_Override"
   set tanda = 'E01E', tanda_previa = coalesce(tanda_previa, 'D67B'),
       nota = coalesce(nota,'') || ' | v17.47 2026-09-14 · Marianela: al camion 1 del 15/09 …'
 where np in ('44607','44608');

update public."GV_PPP_Prog_Override"
   set tanda = 'E01J', tanda_previa = coalesce(tanda_previa, 'D67N'),
       nota = coalesce(nota,'') || ' | v17.47 2026-09-14 · Marianela: al camion 1 del 15/09 …'
 where np = '98694';

-- ⚠ TABLA COMPARTIDA con Producción Virgilio: ver docs/ROLLBACK-PRODUCCION.md
update public."Registros_Produccion_Virgilio" set texto = 'E01E' where upper(btrim(texto)) = 'D67B';
update public."Entregas_Virgilio"             set tanda = 'E01E' where upper(btrim(tanda)) = 'D67B';

-- ── MEDICIÓN ─────────────────────────────────────────────────────────────────────────────
--   El 15/09 queda con camión 1 = E01A + E01E + E01J (zona 1 · Barracas, Villa Soldati, La Boca,
--   1,266 m³), camión 2 = D56D (zona 1 · Soldati) y camión 3 = D67E/F/G/J/L/M (zona 2).
--   El armado viajó: `Registros_Produccion_Virgilio` tiene el TAP del 11/09 11:26 bajo E01E, y
--   las 17 líneas de `Entregas_Virgilio` también. No quedó ninguna fila con D67B.
--   Centinelas después: gv_ppp_super_mezclado 0 · gv_endpoints_rotos 0 · gv_np_prog_sin_base 0.
--
-- ── ROLLBACK ─────────────────────────────────────────────────────────────────────────────
-- update public."Registros_Produccion_Virgilio" set texto = 'D67B' where upper(btrim(texto)) = 'E01E';
-- update public."Entregas_Virgilio"             set tanda = 'D67B' where upper(btrim(tanda)) = 'E01E';
-- update public."GV_PPP_Prog_Override" o set tanda = b.tanda, tanda_previa = b.tanda_previa, nota = b.nota
--   from zz_backups."GV_Backup_ProgOverride_20260914b" b
--  where o.np = b.np and o.np in ('44607','44608','98694');
