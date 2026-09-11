-- v15.75 — El depósito INSUMOS deja de sumar al stock de los TERMINADOS que nadie revisó
-- Proyecto Supabase: hrxfctzncixxqmpfhskv — 2026-09-11
-- Problema github_repo_problemas #29.
--
-- SÍNTOMA (Thomas, 11/09): en Pedidos Importación, 584E "Aceitera 400 Ml" muestra stock **1.290**
-- (90 del módulo + 1.200 del depósito insumos) cuando en la pantalla de Stock hay **19 cajas**
-- (15 terminado + 4 a facturar) = 114 u, con 9 cajas ya pedidas → 10 cajas = 60 u libres.
--
-- CAUSA RAÍZ: la v15.27 engancha insumo → importado por DOS vías:
--   (1) `GV_Importados_Insumo_Map`, los que el dueño revisó uno por uno, y
--   (2) una regla AUTOMÁTICA por **código igual**.
-- La (2) estaba pensada para partes y sueltos, pero no lo verificaba: entraron solos 5 artículos
-- TERMINADOS (584E, 035E, 440E, y 437E/439E·CH). El stock inflado **apaga el repedido**.
--
-- DECISIÓN DEL DUEÑO (11/09), sobre las dos preguntas:
--   1. *"1200 uni hay en insumos"* → el saldo es correcto. **No se toca ningún dato.**
--   2. *"sí"* → esas unidades **no cuentan como stock del artículo terminado**.
-- 437E/439E·CH sí son intencionales (§3.bm.19: "en Chef el 437E/439E arranca como insumo"), así que
-- en vez de quedar colgados de la regla automática pasan al MAPA, que es donde se escribe lo decidido.
--
-- EL ARREGLO: la vía automática por código igual queda **sólo para PARTES**
-- (las de `Importados_Partes_Map`: 505C, 523C, 587C, 1000900, 1546903). Cualquier TERMINADO que
-- tenga que contar el depósito insumos hay que escribirlo en `GV_Importados_Insumo_Map`.
-- Así el próximo código igual que aparezca en insumos no se engancha solo.

-- ---------- BACKUP de la definición anterior ----------
create table if not exists public."GV_bkp_def_gv_importados_stock_insumos_20260911" as
  select 'gv_importados_stock_insumos'::text as objeto,
         pg_get_viewdef('public.gv_importados_stock_insumos'::regclass, true) as def,
         now() as guardado;

-- ---------- 1) lo que SÍ tiene que contar, escrito en el mapa ----------
insert into public."GV_Importados_Insumo_Map" (insumo_cod, importado_cod, nota)
values
  ('437E', '437E', 'Paquete A: en Chef el colador 16cm arranca como insumo y se reenvasa (§3.bm.19). Estaba colgado de la regla automática; se escribe acá, v15.75'),
  ('439E', '439E', 'Paquete A: en Chef el colador de pastas arranca como insumo y se reenvasa (§3.bm.19). Estaba colgado de la regla automática; se escribe acá, v15.75')
on conflict do nothing;

-- ---------- 2) la vía automática, sólo para PARTES ----------
create or replace view public.gv_importados_stock_insumos as
 WITH sal AS (
         SELECT s.cod_art,
            COALESCE(NULLIF(btrim(s.unidad), ''::text), '(s/u)'::text) AS unidad,
            s.saldo
           FROM vista_saldos_insumos_x_unidad s
        ), map AS (
         SELECT "GV_Importados_Insumo_Map".insumo_cod,
            "GV_Importados_Insumo_Map".importado_cod
           FROM "GV_Importados_Insumo_Map"
        ), partes AS (
         -- v15.75: la única puerta automática. Un TERMINADO no entra por acá: va al mapa.
         SELECT DISTINCT upper("Importados_Partes_Map".parte) AS cod
           FROM "Importados_Partes_Map"
        ), link AS (
         SELECT map.insumo_cod,
            map.importado_cod
           FROM map
        UNION
         SELECT s.cod_art,
            i.cod_art
           FROM ( SELECT DISTINCT sal.cod_art
                   FROM sal) s
             JOIN ( SELECT DISTINCT "Importados".cod_art
                   FROM "Importados"
                  WHERE "Importados".principal AND "Importados".activo) i ON upper(i.cod_art) = upper(s.cod_art)
             JOIN partes pt ON pt.cod = upper(i.cod_art)          -- <<< v15.75
          WHERE NOT (s.cod_art IN ( SELECT map.insumo_cod
                   FROM map))
        ), det AS (
         SELECT l.importado_cod,
            s.cod_art AS insumo_cod,
            s.unidad,
            s.saldo,
                CASE
                    WHEN lower(s.unidad) = ANY (ARRAY['uni'::text, 'unidad'::text, 'unidades'::text, '(s/u)'::text]) THEN 1::numeric
                    ELSE COALESCE(f.factor,
                    CASE
                        WHEN lower(s.unidad) = ANY (ARRAY['mc'::text, 'master'::text, 'cajas'::text, 'caja'::text]) THEN v.uni_master
                        ELSE NULL::numeric
                    END)
                END AS factor
           FROM link l
             JOIN sal s ON s.cod_art = l.insumo_cod
             LEFT JOIN "Insumos_Factores" f ON f.cod_art = s.cod_art AND lower(f.unidad) = lower(s.unidad)
             LEFT JOIN ( SELECT upper("Importados_Volumen".cod) AS cod,
                    "Importados_Volumen".uni_master
                   FROM "Importados_Volumen") v ON v.cod = upper(l.importado_cod)
        )
 SELECT importado_cod AS cod,
    round(sum(saldo * COALESCE(factor, 1::numeric)), 0) AS stock_uni,
    bool_or(factor IS NULL) AS sin_factor,
    jsonb_agg(jsonb_build_object('insumo', insumo_cod, 'unidad', unidad, 'saldo', saldo, 'factor', factor, 'uni', round(saldo * COALESCE(factor, 1::numeric), 0)) ORDER BY insumo_cod, unidad) AS detalle
   FROM det
  GROUP BY importado_cod;

alter view public.gv_importados_stock_insumos set (security_invoker = true);

-- ---------- CHEQUEO ----------
-- Tienen que quedar SÓLO: las partes (505C, 523C, 1000900, 1546903) + las del mapa (522E, 437E, 439E).
-- Y desaparecer 584E (1.200), 035E (528), 440E (192), 102E (0) y 590E (0):
--   select cod, stock_uni from public.gv_importados_stock_insumos order by cod;
--   select cod_art, marca, stock_actual, stock_insumos, stock_total
--     from public.v_importados_ordenes where cod_art in ('584E','035E','440E','437E','439E');
-- 584E queda con stock_total = 90 y pasa a pedir 1.580 u (antes 380).
--
-- ---------- ROLLBACK ----------
--   delete from public."GV_Importados_Insumo_Map" where insumo_cod in ('437E','439E');
--   -- y recrear la vista con la def guardada en GV_bkp_def_gv_importados_stock_insumos_20260911
--   -- (es la de sql/gv_importados_stock_insumos_v1527.sql, sin el join a partes).
