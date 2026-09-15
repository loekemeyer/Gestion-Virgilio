-- ============================================================================
-- v18.39 — El m³ se recalcula al modificar una NP de ISIS, y `vista_tanda_m3`
-- deja de ignorar los overrides.  PROYECTO: VIRGILIO.
--
-- Luis, 15/09: *"mas vale, recalcula m3"*. Hasta la v18.35 se le podía cambiar el
-- contenido a una NP de ISIS y el m³ seguía siendo el que trajo la importación,
-- así que el cupo del día quedaba corrido.
--
-- ⚠ SE RECALCULA POR **DELTA**, NO EN ABSOLUTO. Medido el 15/09 sobre las NP que
-- hoy tienen m³: multiplicar `cajas × m³ del artículo` NO reproduce exactamente el
-- m³ que trae ISIS (dif. de hasta 0,231 m³ en una NP de 3 m³; la mayoría < 0,05).
-- Recalcular de cero movería el número de NP que nadie tocó. Entonces: al m³
-- guardado se le suma sólo lo que cambió.
--
-- ⚠ Y SI ALGÚN ARTÍCULO QUE SE MOVIÓ NO TIENE m³ CARGADO, NO SE ESCRIBE NADA y la
-- pantalla lo dice. Un artículo sin medir suma 0 y el m³ sale de menos sin que
-- nadie se entere — la misma regla que ya usa el front para el m³ de la web.
-- ============================================================================

-- ── 1) El m³ pisado ────────────────────────────────────────────────────────
alter table public."GV_PPP_Prog_Override" add column if not exists m3 numeric;

-- y en `gv_ppp_programacion_diaria` la línea del m³ pasa a ser:
--     COALESCE(o.m3, p.m3) AS m3,
-- (el resto de la vista, igual que en §3.hd / sql/gv_pedido_mod_isis_v1835.sql).
-- Verificado: 123 filas antes y después.

-- ── 2) `vista_tanda_m3` leía la tabla CRUDA — problema 256 ─────────────────
-- Sumaba "GV_PPP_Programacion_Diaria" en vez de la vista, así que NO veía ningún
-- override: una NP movida de tanda seguía sumando su m³ en la tanda VIEJA, y una
-- desprogramada u oculta seguía sumando. Medido el 15/09, el arreglo mueve:
--   · 14 tandas viejas que se quedaban con m³ ajeno (D66B 4,041 · D69A 0,745 ·
--     D68B 0,483 · D68E 0,399 · D67I 0,437 · …)
--   · 14 tandas reales que figuraban sin m³ (E09A 4,041 · E07A 4,313 · E11A 0,745 · …)
--   · D56D, que contaba 0,598 con 4 de sus NP desprogramadas (real: 0,132)
-- Total: 1041,978 → 1045,631 m³ sobre 1203 tandas.
create or replace view public.vista_tanda_m3 as
 WITH ent AS (
         SELECT upper(btrim(m.tanda)) AS tanda, sum(m.m3) AS m3
           FROM "GV_PPP_Entregados_Historico" m
          WHERE m.m3 > 0::numeric AND btrim(COALESCE(m.tanda, ''::text)) <> ''::text
          GROUP BY (upper(btrim(m.tanda)))
        ), prog AS (
         SELECT upper(btrim(p_1.tanda)) AS tanda, sum(p_1.m3) AS m3
           FROM gv_ppp_programacion_diaria p_1          -- ← la VISTA, no la tabla
          WHERE p_1.m3 > 0::numeric AND btrim(COALESCE(p_1.tanda, ''::text)) <> ''::text
          GROUP BY (upper(btrim(p_1.tanda)))
        ), web AS (
         SELECT upper(btrim(w.tanda)) AS tanda, sum(w.m3) AS m3
           FROM "PPP_Web_Programacion" w
          WHERE w.m3 > 0::numeric AND btrim(COALESCE(w.tanda, ''::text)) <> ''::text
          GROUP BY (upper(btrim(w.tanda)))
        ), u AS (
         SELECT ent.tanda FROM ent
        UNION SELECT prog.tanda FROM prog
        UNION SELECT web.tanda FROM web
        )
 SELECT u.tanda, round(COALESCE(e.m3, p.m3, b.m3), 3) AS m3, e.m3 IS NOT NULL AS entregado
   FROM u
     LEFT JOIN ent e ON e.tanda = u.tanda
     LEFT JOIN prog p ON p.tanda = u.tanda
     LEFT JOIN web b ON b.tanda = u.tanda
  WHERE COALESCE(e.m3, p.m3, b.m3) > 0::numeric;
alter view public.vista_tanda_m3 set (security_invoker = true);
grant select on public.vista_tanda_m3 to anon, authenticated, lk_ppp_reader, ch_ppp_reader;

-- `gv_ppp_web_m3_isis` (el m³ de ISIS del día, que alimenta el cupo) YA leía la
-- vista, así que el m³ pisado le llega solo. No hay que tocarla.

-- ── 3) El bloque que se le agregó a `gv_pedido_mod_isis` ───────────────────
-- Va DESPUÉS de calcular `v_despues` (la foto de cómo quedó el pedido) y antes de
-- armar el detalle. ⚠ Ponerlo antes de `v_despues` fue el primer intento y estaba
-- mal: sin la foto nueva, el delta daba todo negativo y el m³ se iba a 0.
--
--   if p_items is not null then
--     select sum(d.dcajas * v.m3), count(*) filter (where v.m3 is null),
--            string_agg(distinct d.cod, ', ') filter (where v.m3 is null)
--       into v_dm3, v_faltan, v_m3_sin
--       from (select coalesce(n.cod, a.cod) cod,
--                    coalesce(n.cajas,0) - coalesce(a.cajas,0) dcajas
--               from (select value->>'cod_art' cod, (value->>'cajas')::numeric cajas
--                       from jsonb_array_elements(v_despues)) n
--               full join (select value->>'cod_art' cod, (value->>'cajas')::numeric cajas
--                       from jsonb_array_elements(v_antes)) a on a.cod = n.cod) d
--       left join public.vista_volumen_articulo_resuelto v on btrim(v.codigo) = d.cod
--      where d.dcajas <> 0;
--     v_m3_old := coalesce(v_prog.m3, 0);
--     if coalesce(v_faltan,0) = 0 and coalesce(v_dm3,0) <> 0 then
--       v_m3_new := round(greatest(v_m3_old + v_dm3, 0), 3);
--       insert into public."GV_PPP_Prog_Override" (np, m3, nota, creado_en)
--       values (v_np, v_m3_new, 'm3 recalculado desde Modificar Pedidos', now())
--       on conflict (np) do update set m3 = excluded.m3;
--     end if;
--   end if;
--
-- y el detalle devuelve además: 'm3_de', 'm3_a', 'm3_sin_dato'.
-- (La función entera, con este bloque ya adentro, está en la base; el archivo
--  sql/gv_pedido_mod_isis_v1835.sql tiene el resto del cuerpo.)

-- ── Prueba (15/09, transacción abortada, NP 98664 · tanda E12J) ────────────
-- +10 cajas del artículo 034 (0,0051 m³/caja) → esperado +0,051.
--   m³ de la NP:    0,100 → 0,151
--   m³ de la TANDA: 0,437 → 0,488   ← la cadena entera, hasta vista_tanda_m3
-- Tras el rollback: 0 overrides, 0 log, la NP de vuelta en 0,1 y gv_endpoints_rotos vacía.
--
-- ── Rollback ───────────────────────────────────────────────────────────────
-- Volver `vista_tanda_m3` a leer "GV_PPP_Programacion_Diaria" (pero ojo: eso
-- restaura el problema 256), y sacar el bloque del m³ de `gv_pedido_mod_isis`.
-- La columna `m3` del override puede quedarse: es nullable y sin ella el COALESCE
-- devuelve el valor original.
