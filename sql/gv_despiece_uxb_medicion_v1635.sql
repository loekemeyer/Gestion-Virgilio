-- gv_despiece_uxb_medicion_v1635.sql — MEDICIÓN, 2026-09-12. **Nada corregido todavía.**
--
-- Reemplaza a `gv_despiece_uxb_alinear_PENDIENTE.sql`, que se escribió a ciegas (con la
-- conexión caída) y proponía alinear la tabla entera contra `GV_UxB`. Con los datos a la vista
-- eso habría sido un error: la nota vieja hablaba de **21 códigos** y en realidad **154 de 236
-- difieren**, y no todos por el mismo motivo. Alinearlos en bloque habría pisado datos buenos.
--
-- QUÉ ALIMENTA: `cajasUsadas = ceil(eMadre / uniXCaja)`, el consumo mensual de cajas de CARTÓN
--   · cervantes-admin/{entero,gp2}/Compras/cajas.html:405 y :432
--   · cervantes-admin/entero/Inicio/index.html:1480 y :1493
-- Con el UxB al doble, el consumo se calcula a la MITAD y la alerta de compra no salta. Al
-- revés, se compra de más.
--
-- ── LO MEDIDO ────────────────────────────────────────────────────────────────────────────
-- 754 filas, 238 códigos distintos (`COD` NO es único: cuidado con los joins, el primer intento
-- dio 3.821 filas por multiplicar). 236 cruzan con `GV_UxB`. De los 154 que difieren:
--
-- | evidencia | códigos | qué hacer |
-- |---|--:|---|
-- | la columna VIEJA `Uni x Cja` **coincide con `GV_UxB`** | **67** | dos fuentes independientes contra el valor actual → error casi seguro |
-- | no hay columna vieja para corroborar | 72 | sólo `GV_UxB` lo contradice; evidencia más floja |
-- | las tres discrepan | 15 | ambiguo, mirar uno por uno |
--
-- Los 67 tienen un patrón limpio: casi todos están **multiplicados o divididos por exactamente
-- 2**, que es lo que pasa cuando se carga la caja MASTER en vez de la interna.
--
--     cod        en Despiece   GV_UxB + col. vieja   efecto sobre el consumo
--     101, 114        12               6             la MITAD
--     333, 336        24              12             la MITAD
--     859,862,863,908 24              12             la MITAD
--     501,504,508         12           6             la MITAD
--     701, 708        12               6             la MITAD
--     307, 390-394    12              24             el DOBLE
--     550             12              36             el TRIPLE
--
-- ⚠ Y de los 15 ambiguos, **A10, A15, C1, C10, GRJ9 y V9 dicen 30 en las DOS columnas de la
--   tabla** contra 12 de `GV_UxB`. No parecen artículos de LK/Chef sino códigos propios de
--   Cervantes: probablemente **otro dominio**, igual que `Articulos_Cajas.Uni_x_Caja`. Ésos
--   NO se tocan.
--
-- ── POR QUÉ NO SE CORRIGIÓ ───────────────────────────────────────────────────────────────
-- Es modificación de datos reales, y el protocolo de `CLAUDE.md` es explícito: *"SOLO reportá
-- el problema… NO modificar nada en Supabase sin permiso directo y explícito del usuario"*.
-- Queda en la auditoría como problema abierto.
--
-- ── SI EL DUEÑO DA EL OK ─────────────────────────────────────────────────────────────────
-- Corregir **sólo los 67 corroborados**, no los 154. Los backups y los mapas ya están hechos:
--   zz_backups."GV_Despiece_uxc_20260912"  (COD + las dos columnas, 754 filas)
--   zz_backups."GV_tmp_despiece_map"       (COD → gv_cod_stock, con índice)
--   zz_backups."GV_tmp_gvuxb_map"          (gv_cod_stock → max(uxb), con índice)
--
--   update public."Despiece x Articulo" d
--      set "Uni_x_Caja" = g.u
--     from zz_backups."GV_tmp_despiece_map" m, zz_backups."GV_tmp_gvuxb_map" g
--    where m.cod = d."COD"::text and g.c = m.cn
--      and d."Uni_x_Caja"::numeric is distinct from g.u
--      and d."Uni x Cja"::numeric = g.u;          -- ← el corroborado, esto es lo que acota a 67
--
--   Rollback:
--   update public."Despiece x Articulo" d set "Uni_x_Caja" = b."Uni_x_Caja"
--     from zz_backups."GV_Despiece_uxc_20260912" b where b."COD" = d."COD";

-- ── Las consultas de la medición, para repetirla ─────────────────────────────────────────
-- (una por llamada; los joins con gv_cod_stock() sobre esta tabla tumbaron la conexión antes
--  de materializar los mapas)

with d as (
  select m.cn, max(b."Uni_x_Caja"::text) nueva, max(b."Uni x Cja"::text) vieja
    from zz_backups."GV_Despiece_uxc_20260912" b
    join zz_backups."GV_tmp_despiece_map" m on m.cod = b."COD"::text
   group by 1
)
select case when d.vieja::numeric = g.u then 'la VIEJA coincide con GV_UxB'
            when d.vieja is null        then 'sin columna vieja'
            else 'ninguna de las dos coincide' end as caso,
       count(*) cods
  from d join zz_backups."GV_tmp_gvuxb_map" g on g.c = d.cn
 where d.nueva::numeric is distinct from g.u
 group by 1 order by 2 desc;
-- esperado: 72 sin vieja · 67 la vieja coincide · 15 ninguna
