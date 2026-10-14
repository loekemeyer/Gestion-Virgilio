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
