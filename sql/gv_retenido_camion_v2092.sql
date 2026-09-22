-- ═══════════════════════════════════════════════════════════════════════════════
-- v20.92 (Thomas, 2026-09-22) — EL RETENIDO NO VUELVE A UNA TANDA DE OTRO CAMION
--
-- Problema 489. `gv_ppp_web_retenido` decidia si un pedido retenido vuelve a su tanda
-- previa mirando SOLO el estado de esa tanda (v20.56) y el codigo reservado (v20.60).
-- **No miraba la zona.**
--
-- Caso LK 1448 (Silvano Lucas Martin, 4282), medido el 22/09:
--
--   | NP retenida        | zona                 | camion     |
--   |--------------------|----------------------|------------|
--   | LK 0094 / LK 0095  | Zona 6 - GBA Norte   | GBA Norte  |
--   | su tanda D69H      | Zona 2 - CABA Centro | **Capital**|
--
-- El chip del badge decia textual *"esa tanda sale el 23/09 y no se empezo: vuelve ahi"*.
-- El supervisor que siguiera ese consejo partia la tanda en dos camiones y ponia
-- `gv_ppp_tanda_camion_mezclado` en rojo — la regla de Luis de la v18.87 (*"la tanda de un
-- cliente se parte por camion"*). Es el mismo hueco que la v20.56 tapo para el ESTADO de la
-- tanda y dejo abierto para la ZONA.
--
-- ⚠ El corte va ANTES de 'sin empezar' y DESPUES de los estados que ya frenan: si la tanda
-- esta armada o facturada ya no vuelve por ese motivo, y el camion no agrega nada.
--
-- ⚠ Una tanda YA MEZCLADA (dos camiones adentro) tambien sale 'otro camion', porque
-- `camion_tanda` queda 'Capital + GBA Norte' y nunca va a coincidir. Es lo correcto: no se le
-- suma nada a una tanda que ya esta mal. Mismo criterio que `gv_ppp_web_tanda_abierta_cliente`
-- (v18.87), que solo devuelve la tanda si TODAS sus NP son del camion pedido.
--
-- ⚠ El corte es la ETIQUETA de `gv_ppp_web_camion` (Capital / GBA Sur / GBA Oeste / GBA
-- Norte), NO el numero de zona: una tanda de CABA mezcla Zona 1+2 a proposito y va en el
-- mismo camion.
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace view public.gv_ppp_web_retenido
with (security_invoker = true) as
 SELECT t.empresa,
    t.order_id,
    t.np_idx,
    t.np,
    t.tanda_previa,
    t.fecha_previa,
    COALESCE(e.pick, false) AS ya_pickeada,
    COALESCE(e.arm, false) AS ya_armada,
    t.motivo,
    t.por,
    t.creado_at,
        CASE
            WHEN t.np IS NOT NULL THEN gv_ppp_web_np_label(t.empresa, t.np, t.np_idx)
            ELSE NULL::text
        END AS np_label,
    COALESCE(v.nps, 0::bigint) > 0 AS tanda_viva,
    v.fecha AS tanda_fecha,
    COALESCE(v.nps, 0::bigint) AS tanda_nps,
        CASE
            WHEN s.n > 0 THEN 'salio'::text
            WHEN f.n > 0 THEN 'facturada'::text
            WHEN COALESCE(e.arm, false) THEN 'armada'::text
            WHEN COALESCE(e.pick, false) THEN 'pickeada'::text
            -- v20.92 — la tanda esta sana pero es de OTRO camion: no vuelve ahi.
            WHEN COALESCE(v.nps, 0::bigint) > 0
             AND cn.camion_np IS NOT NULL AND ct.camion_tanda IS NOT NULL
             AND ct.camion_tanda <> cn.camion_np THEN 'otro camion'::text
            WHEN COALESCE(v.nps, 0::bigint) > 0 THEN 'sin empezar'::text
            WHEN gv_ppp_web_codigo_vivo(t.tanda_previa, t.empresa, t.order_id) THEN 'codigo tomado'::text
            ELSE 'no existe'::text
        END AS tanda_estado,
    -- columnas nuevas AL FINAL (create or replace view no deja meterlas en el medio)
    cn.camion_np,
    ct.camion_tanda
   FROM "GV_PPP_Web_Retenido" t
     LEFT JOIN LATERAL ( SELECT bool_or(r.opcion = ANY (ARRAY['TP'::text, 'EP'::text])) AS pick,
            bool_or(r.opcion = 'TAP'::text) AS arm
           FROM "Registros_Produccion_Virgilio" r
          WHERE upper(btrim(r.texto)) = upper(btrim(t.tanda_previa)) AND (r.opcion = ANY (ARRAY['EP'::text, 'TP'::text, 'AP'::text, 'TAP'::text])) AND (COALESCE(btrim(r.legajo), ''::text) <> ALL (ARRAY['0'::text, '1'::text]))) e ON true
     LEFT JOIN LATERAL ( SELECT count(*) AS nps,
            min(w.fecha_entrega) AS fecha
           FROM "PPP_Web_Programacion" w
          WHERE upper(btrim(COALESCE(w.tanda, ''::text))) = upper(btrim(t.tanda_previa))) v ON true
     LEFT JOIN LATERAL ( SELECT count(*) AS n
           FROM "Facturacion_NP" f2
          WHERE upper(btrim(COALESCE(f2.tanda, ''::text))) = upper(btrim(t.tanda_previa))) f ON true
     LEFT JOIN LATERAL ( SELECT count(*) AS n
           FROM "Registros_Produccion_Virgilio" r
          WHERE upper(btrim(split_part(r.texto, '|'::text, 1))) = upper(btrim(t.tanda_previa)) AND (r.opcion = ANY (ARRAY['CCN'::text, 'CRN'::text])) AND (COALESCE(btrim(r.legajo), ''::text) <> ALL (ARRAY['0'::text, '1'::text]))) s ON true
     -- el camion de ESTA NP retenida, por su zona
     LEFT JOIN LATERAL ( SELECT gv_ppp_web_camion(w.zona, NULL::date) AS camion_np
           FROM "PPP_Web_Programacion" w
          WHERE w.empresa = t.empresa AND w.order_id = t.order_id AND w.np = t.np
            AND COALESCE(w.zona, ''::text) ~ '^\s*Zona\s*[0-9]+'::text
          LIMIT 1) cn ON true
     -- el camion de la TANDA previa: si tiene dos, se concatenan y nunca coincide (a proposito)
     LEFT JOIN LATERAL ( SELECT string_agg(DISTINCT gv_ppp_web_camion(w.zona, NULL::date), ' + '::text) AS camion_tanda
           FROM "PPP_Web_Programacion" w
          WHERE upper(btrim(COALESCE(w.tanda, ''::text))) = upper(btrim(t.tanda_previa))
            AND COALESCE(w.zona, ''::text) ~ '^\s*Zona\s*[0-9]+'::text) ct ON true;

alter view public.gv_ppp_web_retenido set (security_invoker = true);

-- ── el chip tiene que DECIRLO, no sólo saberlo ────────────────────────────────
-- (sólo cambia el bloque `retenido_sin_fecha` de gv_ppp_avisos_detalle; el resto va igual)

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values
 ('gv_ppp_web_retenido', 'vista', 'otro camion',
  'Un pedido retenido NO vuelve a su tanda previa si esa tanda es de otro camion: partiria la tanda en dos recorridos (regla v18.87). Caso LK 1448 GBA Norte contra D69H Capital.',
  'Thomas', 'v20.92'),
 ('gv_ppp_avisos_detalle', 'vista', 'otro camión',
  'El chip del retenido tiene que decir cuando la tanda previa es de otro camion, o el supervisor la parte siguiendo el consejo.',
  'Thomas', 'v20.92')
on conflict do nothing;
