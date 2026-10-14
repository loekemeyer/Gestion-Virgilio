-- v30.56 · 2026-10-14 · CONTEO DE SC y SP (celdas IN-), primera tanda (Luis, Virgilio). Aplicado por MCP en la sesión.
-- Luis: "lo que cuento es canónico". Backup: zz_backups."GV_Backup_InsUbic_SCP_20261014" (las 55 filas IN- de antes).
--
-- | celda | pieza                                  | cajones | sistema antes | qué se hizo                         |
-- |-------|----------------------------------------|--------:|---------------|-------------------------------------|
-- | B2+B3 | A1 Mgo Plano 501 Pint. (s/marca)       |   3 + 4 | 7, sin lugar  | posición                            |
-- | B4+B5 | A4 Mgo Plano 501 Serig (c/marca)       |   4 + 4 | 8             | posición (B1 sigue sin contar)      |
-- | B6    | B4B Cpo Sacacorcho Pint Azul S/marca CH|       4 | no existía    | ALTA + equivalencia GP2 529 + ajuste|
-- | A2    | C9 Resorte U Crom                      |       2 | 2             | posición (E5 sigue sin contar)      |
-- | A3    | D14 Resorte 520 Niq.                   |       3 | 3             | posición (F6 sigue sin contar)      |
-- | A4    | C15 C Sacacorcho 520                   |       6 | 0             | ajuste +6 (A1/C5 siguen sin contar) |
-- | A6    | B13 Malas (cartel «malas»)             |       5 | B13 5         | ALTA aparte, sin GP2; B13 −5 / +5   |
--
-- Salieron de esas 9 celdas: B13 (A2, A3), C6 (A6, B6), A4 (B2), A7 (B3), A9 (B4), C5 (B5).
-- Movimientos con ref 'CONTEO SCP 14/10'.
--
-- Verificación:
select sector, cod, cantidad, stock from public.gv_scp_celda where sector ~ '^IN-(A[2-6]|B[2-6])$' order by sector;
--
-- Rollback: borrar los movimientos ref 'CONTEO SCP 14/10', reponer las filas IN- desde el backup,
-- borrar Insumos B4B / 'B13 Malas' y GP2.insumo_equivalencia B4B.

-- ===================== v30.57 · 2026-10-14 (segunda tanda, Luis) =====================
-- | celda | pieza (lo que dijo Luis)                         | cajones | qué se hizo                          |
-- |-------|--------------------------------------------------|--------:|--------------------------------------|
-- | C5+C6 | A1 (mgo plano pint. s/marca 501 p/serigrafiar)   |   3 + 4 | ajuste +7 (A1 total 14 con B2/B3)    |
-- | C3    | B4B (cuerpo azul ch)                             |       4 | ajuste +4 (B4B total 8 con B6)       |
-- | F2    | D3 Aleta Izquierda Inox                          |       1 | ALTA + equivalencia GP2 107 + ajuste |
-- | C1    | DISC1 (mgo plano s/arito estampado chef)         |       5 | sólo posición; total 26 sin contar   |
-- | E1    | DISC1 (s/arito estampado ch p/702 cromado)       |       6 | sólo posición (A15 sale de E1)       |
-- | F1    | DISC5 cuerpo sacacorcho verde                    |       1 | coincide; sale de D1                 |
-- | F3    | DISC3 mango plano blanco                         |       3 | coincide; sale de D6                 |
-- | F4    | DISC2 mango plano verde                          |       4 | coincide; sale de D5                 |
-- | F5    | A10 (abrelata uña pint azul c/marca)             |       1 | coincide; sale de E6                 |
-- Salieron de las celdas: C15 (C5), B9 (C6, queda 2 cajones sin lugar), GRJ9 (F1, F2; stock 0).
select sector, cod, cantidad, stock from public.gv_scp_celda where sector ~ '^IN-(C[1-6]|E1|F[1-5])$' order by sector;
-- Rollback: igual que arriba + borrar Insumos D3 y GP2.insumo_equivalencia D3.

-- ===================== v30.58 · 2026-10-14 (tercera tanda, Luis) =====================
-- B1: D4 Cabezal Crom. (cabezal cromado p/sacacorcho) 2 cajones; sistema 0 -> ajuste +2.
--     Sale A4 de B1 (A4 queda 8 = B4 4 + B5 4, coincide). D4 conserva IN-D4 hasta contar la columna D.
select sector, cod, cantidad, stock from public.gv_scp_celda where sector in ('IN-B1','IN-D4');

-- ===================== v30.59 · 2026-10-14 (corrección, Luis) =====================
-- Luis: "IN-A4 cuerpo uña cromado 6 cajones · IN-A5 cuerpo sacacorcho 520 cromado 3 cajones".
-- IN-A4: C15 -> A15 Cpo Uña Inox LK C/M 6 (sólo posición; A15 sistema 7, IN-E2 sin contar).
-- IN-A5: C6 sale -> C15 3 cajones. C15 ajuste -3 (6 -> 3). C15 conserva IN-A1 hasta contarla.
select sector, cod, cantidad, stock from public.gv_scp_celda where sector in ('IN-A1','IN-A4','IN-A5','IN-E2') order by 1;

-- ===================== v30.60 · 2026-10-14 (respuestas D5/D6, Luis) =====================
-- D5: IN-C3 es cuerpo azul CON marca CH -> B7 Cpo Sacacorcho CH Serig (alta + equivalencia GP2 90).
--     B4B -4 (queda 4, IN-B6) · B7 +4 (IN-C3).
-- D6: IN-E1 ya cromado -> DISC1 confirmado, sin cambios.
select sector, cod, cantidad, stock from public.gv_scp_celda where sector in ('IN-B6','IN-C3') order by 1;

-- ===================== v30.61 · 2026-10-14 (columna G, Luis) =====================
-- D7/D8 confirmados (IN-F2 = D3 aleta izq. inox · IN-A4 = A15 cuerpo uña inox LK c/M). D4 (B13): no volver a preguntar.
-- IN-G1 3 + IN-G2 1: Z33 Cremallera p/Cromar = 4 (sistema 3) -> +1. G10 Remaches de afila sale de IN-G2 (1 cajón, sin lugar).
-- IN-G3: 4 cajones «mgo plano 512 crudo». Figuraban como Z26 (Mgo Plano 702 Doblado c/Marca, 4): Z26 -4, alta
--   'Mgo Plano 512 Crudo' (partes_crudo, SIN componente en GP2: no existe un 512 crudo) +4.
-- IN-G4: «HF6» 2 cajones, código inexistente en Virgilio y en GP2; queda H15 (2 cajones) hasta aclararlo.
select sector, cod, cantidad, stock from public.gv_scp_celda where sector ~ '^IN-G[1-4]$' order by 1;

-- ===================== v30.62 · 2026-10-14 (revisión completa, Luis) =====================
-- Luis: "son conteos completos, no para que sumes. si el sistema tenia otra cosa, remplazalo por lo que te digo
-- (tanto codigo como cantidades)". Se cruzaron las 25 celdas contadas contra Insumos_Ubicaciones y el saldo.
-- Diferencias corregidas:
--   IN-G2: era G10 Remaches de afila 1 (no cremallera) -> Z33 queda 3 (-1).
--   IN-G4: H15 Varilla c/curva, cantidad 0 -> 2 (el saldo ya era 2).
--   A7 (estaba en IN-B3) -4 y B9 (estaba en IN-C6) -2: desplazados por el conteo y sin otra posición -> 0.
-- Quedan con saldo distinto del contado porque tienen posiciones en celdas AÚN NO CONTADAS:
--   DISC1 contado 11 (IN-C1, IN-E1) vs saldo 26 (IN-C2, IN-L1..L4) · A15 contado 6 vs saldo 7 (IN-E2).

-- ===================== v30.63 · 2026-10-14 (IN-C2 / IN-C4, Luis) =====================
-- IN-C4: C16 C Sacacorcho 521 Crom 3 (alta + equivalencia GP2 105).
-- IN-C2: 'Cpo Sacacorcho 521 S/marca' 2 (alta, SIN componente en GP2). Sale DISC1 de IN-C2 (le quedan IN-L1..L4 sin contar).
select sector, cod, cantidad, stock from public.gv_scp_celda where sector in ('IN-C2','IN-C4');

-- ===================== v30.64 · 2026-10-14 (D10 / D11, Luis) =====================
-- D11: IN-C2 «sin marcar y sin cromar» -> el alta 'Cpo Sacacorcho 521 S/marca' se RENOMBRA a G4 «Cpo Sacacorcho 521
--      p/cromar» (partes_crudo) en Insumos, su movimiento y su posición; equivalencia GP2 G4 -> componente 8.
-- D10: 'Mgo Plano 512 Crudo' queda sólo en Virgilio (Luis: "si no aparece no, puede que sea muy viejo").
select sector, cod, categoria, cantidad, stock from public.gv_scp_celda where sector='IN-C2';

-- ===================== v30.65 · 2026-10-14 (vacías + columnas H, I, J; Luis) =====================
-- VACÍAS: IN-A1, IN-D1..D6, IN-E2..E6, IN-F6 (se borran sus posiciones). C1 Abrelata Pie Uña Serig (IN-D3) -5 -> 0;
--   A15 (IN-E2) -1 -> 6 (sólo IN-A4).
-- IN-H1 A7 Mgo Plano 701 Crom. 4 (c/arito estampado chef, cromado) · IN-H2/H3/H4 N7 Pinza Corta 3+5+5 = 13 (coincide)
-- IN-H5 alta 'Puntas Espiral Disc' 1 · IN-H6/H7 Z26 Mgo Plano 702 crudo 2+5 = 7; I11 (701 doblado) sin posición -> 0
-- IN-I1 alta 'Espiral Nacional Disc' 1 · IN-I2 G4 (521 sin cromar) 4 -> G4 total 6
-- IN-I3..I6 alta I14 Cuchilla Abrelata p/Templar (hierro p/cementar) 1+5+5+5 = 16, equivalencia GP2 19
-- IN-J1..J3 alta 'Batidor Pera p/Cromar' 15 (sin componente GP2) · IN-J4 G13 3 (coincide)
-- IN-J5 Z2B Pza Grande Sacaf Art LK p/Cromar 5 (cabezal sacafuente; sale de IN-J6)
-- Pendientes por celdas sin contar: G11 (IN-K4), Z39 (IN-K5), Z37 (IN-K6, L5, L6), DISC1 (IN-L1..L4), DISC4 (IN-G5, G6).
select sector, cod, cantidad, stock from public.gv_scp_celda where sector ~ '^IN-(H.|I.|J.)$' order by col, fila;

-- ===================== v30.66 · 2026-10-14 (C2 / C4 / I2 definitivo, Luis) =====================
-- Luis: "C4 cuerpo con marca y cromado · I2 cuerpo con marca y sin cromar · C2 sacacorchos completo sin marca".
-- IN-C4 C16 3 (sin cambio) · IN-I2 G4 4 · IN-C2 alta 'Sacacorcho 521 Completo S/M' 2 (sin componente GP2); G4 -2.
select sector, cod, cantidad, stock from public.gv_scp_celda where sector in ('IN-C2','IN-C4','IN-I2') order by 1;

-- ===================== v30.82 · 2026-10-14 (columnas K y L con códigos TEMPORALES, Luis) =====================
-- Luis: "vamos a cargar lo que falta con codigos temporales. despues naza me ayuda a cruzarlo con codigos de cervantes".
-- Backup: zz_backups."GV_Backup_InsUbic_KL_20261014" (las 9 filas K/L de antes). Altas por nuevo_insumo_tmp (partes_crudo):
-- | celdas            | código   | pieza (Luis)                  | cajones | candidato a cruzar (sin confirmar)            |
-- |-------------------|----------|-------------------------------|--------:|-----------------------------------------------|
-- | IN-L1..L4         | TMP-0042 | mango plano 702 grabado chef  | 5+5+3+2 | Z26 (702 doblado c/marca) o DISC1             |
-- | IN-K1, K2         | TMP-0038 | manija                        |   5 + 5 | H1 Manija Redonda p/cromar (10, sin posición) |
-- | IN-K5, L5, L6     | TMP-0041 | espaditas                     | 2+2+4   | —                                             |
-- | IN-K3             | TMP-0039 | batidor pera                  |       5 | 'Batidor Pera p/Cromar' (IN-J1..J3)           |
-- | IN-K4             | TMP-0040 | palitos                       |       4 | —                                             |
-- Desplazados (conteo completo, sin otra posición -> 0, criterio v30.62): G11 −20 (era IN-K4) · Z39 −5 (IN-K5) ·
--   DISC1 −15 (IN-L1..L4) -> queda 11 (IN-C1 5 + IN-E1 6, coincide con lo contado).
-- Z37 pierde L5/L6 y queda sólo en IN-K6 (sin contar): saldo 9 sin tocar.
select sector, cod, cantidad, stock from public.gv_scp_celda where sector ~ '^IN-[KL][0-9]' order by 1;
