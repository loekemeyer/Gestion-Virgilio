-- v20.67 — lo que YA SALIÓ no parte al cliente en dos días
--
-- Luis, 2026-09-21, sobre Riondini figurando en `gv_ppp_cliente_dos_dias`: *"ya salio así que la
-- macana ya esta hecha"* · y sobre taparlo: *"Y si, como te dije, ya esta hecho"*.
--
-- Qué se midió: el centinela compara las fechas de entrega de un mismo cliente y marca si caen en
-- días distintos. Pero una NP con **carga de camión o remito controlado** ya se entregó: su
-- `fecha_entrega` es la que tenía programada, no una entrega pendiente. Contarla como tal inventa
-- un choque que no existe.
--
-- El caso: Riondini Federico (LK 4105, Guardia Nacional 141, Villa Luro).
--   · pedido del 26/08 por el Cotizador -> 98605/98606/98607, tanda E12E, fecha 22/09.
--     Cargado al camión el 21/09 10:18 (chofer Guillermo, remitos 17, 18 y 19). YA SALIÓ.
--   · pedido web del 16/09 -> LK 0118, tanda E37F. Estaba el 22/09 y la redistribución del día
--     sin reparto lo movió al 23/09.
-- Los dos estaban el mismo día hasta esa tarde. El centinela marcaba 4 filas por algo que ya no
-- se puede arreglar ni hace falta arreglar.
--
-- Cuánto pesa, medido el 21/09: de las **179 NP programadas a futuro, 34 ya habían salido**. O
-- sea que el centinela venía contando 34 entregas hechas como si estuvieran pendientes.
--
-- Mismo criterio de salida que usan `gv_ppp_tanda_mover` y `gv_dia_sin_reparto_ocupado`: CCN o
-- CRN, sin los legajos de prueba.

create or replace view public.gv_ppp_cliente_dos_dias as
 WITH salidos AS (
         SELECT regexp_replace(upper(btrim(split_part(r.texto, '|'::text, 1))), '\.0+$'::text, ''::text) AS np
           FROM "Registros_Produccion_Virgilio" r
          WHERE r.opcion = ANY (ARRAY['CCN'::text, 'CRN'::text])
            AND COALESCE(btrim(r.legajo), ''::text) <> ALL (ARRAY['0'::text, '1'::text])
            AND btrim(COALESCE(r.texto, ''::text)) <> ''::text
          GROUP BY 1
        ), base AS (
         SELECT lower(COALESCE(w.empresa, 'lk'::text)) AS empresa,
            btrim(COALESCE(w.cod_cliente, ''::text)) AS cod,
            btrim(COALESCE(w.razon_social, ''::text)) AS razon_social,
            w.fecha_entrega AS dia,
            btrim(w.tanda) AS tanda,
            gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) AS np,
            COALESCE(w.zona, ''::text) AS zona,
            COALESCE(w.m3, 0::numeric) AS m3
           FROM "PPP_Web_Programacion" w
          WHERE COALESCE(NULLIF(btrim(w.tanda), ''::text), ''::text) <> ''::text AND w.fecha_entrega IS NOT NULL AND w.fecha_entrega >= CURRENT_DATE
        UNION ALL
         SELECT
                CASE
                    WHEN btrim(i.np) ~ '^4'::text THEN 'chef'::text
                    ELSE 'lk'::text
                END AS "case",
            btrim(COALESCE(i.cod, ''::text)) AS btrim,
            btrim(COALESCE(i.razon_social, ''::text)) AS btrim,
            "left"(btrim(i.fecha_entrega), 10)::date AS "left",
            btrim(i.tanda) AS btrim,
            btrim(i.np) AS btrim,
            COALESCE(i.zona, ''::text) AS "coalesce",
            COALESCE(i.m3, 0::numeric) AS "coalesce"
           FROM gv_ppp_programacion_diaria i
          WHERE COALESCE(NULLIF(btrim(i.tanda), ''::text), ''::text) <> ''::text AND btrim(i.fecha_entrega) ~ '^\d{4}-\d{2}-\d{2}'::text AND "left"(btrim(i.fecha_entrega), 10)::date >= CURRENT_DATE
        ), limpia AS (
         SELECT b.empresa,
            b.cod,
            b.razon_social,
            b.dia,
            b.tanda,
            b.np,
            b.zona,
            b.m3,
            NULLIF(upper(regexp_replace(COALESCE(NULLIF(b.razon_social, ''::text), b.cod), '[^A-Za-z0-9]'::text, ''::text, 'g'::text)), ''::text) AS k
           FROM base b
          WHERE b.zona !~* 'super|retira|expo'::text
            AND NOT EXISTS (SELECT 1 FROM salidos s
                             WHERE s.np = regexp_replace(upper(btrim(b.np)), '\.0+$'::text, ''::text))
        ), choque AS (
         SELECT DISTINCT a.k,
            a.dia
           FROM limpia a
             JOIN limpia b ON b.k = a.k AND b.dia <> a.dia
          WHERE abs(b.dia - a.dia) <= 7
        )
 SELECT l.k AS cliente_key,
    l.razon_social,
    l.cod,
    l.empresa,
    l.np,
    l.tanda,
    l.dia,
    l.zona,
    l.m3,
    ( SELECT count(DISTINCT c2.dia) AS count
           FROM choque c2
          WHERE c2.k = l.k) AS dias_distintos
   FROM limpia l
     JOIN choque c ON c.k = l.k AND c.dia = l.dia
  ORDER BY l.k, l.dia, l.np;

alter view public.gv_ppp_cliente_dos_dias set (security_invoker = true);

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version) values
 ('gv_ppp_cliente_dos_dias','vista','salidos',
  'Lo que YA SALIO (carga de camion o remito controlado) no parte al cliente en dos dias: su fecha es historia, no una entrega pendiente. Sin esto el centinela contaba 34 de 179 NP ya entregadas como si fueran pendientes (caso Riondini, 21/09).',
  'Luis','v20.67');

-- ── CHEQUEOS ─────────────────────────────────────────────────────────────────────────────────
--   select * from public.gv_ppp_cliente_dos_dias;   -- vacia el 21/09 (eran 4, todas de Riondini)
--   select * from public.gv_reglas_perdidas;        -- vacia = la regla sigue puesta
