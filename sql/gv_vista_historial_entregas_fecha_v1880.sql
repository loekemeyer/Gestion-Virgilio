-- ============================================================================
-- v18.80 (2026-09-16, pedido de Luis) — HISTÓRICO DE RECEPCIÓN: la fecha, en UN solo formato
-- ============================================================================
-- Pedido: *"Histórico de recepción: fechas no están ordenadas y formato de fecha inconsistente.
-- Arreglalo."*
--
-- QUÉ PASABA
--   `vista_historial_entregas.fecha` es TEXT porque las dos tablas de origen la guardan como
--   texto: `"Entregas Prov AT".Dia_mes` y `"Entregas Tallerista Virgilio".Fecha`. La vista sólo
--   normalizaba UN formato — `dd-mm` (sin año) de Prov AT — y todo lo demás pasaba crudo.
--   Medido el 16/09, sobre 1.544 filas:
--
--     | origen     | formato    | filas |
--     |------------|------------|-------|
--     | prov_at    | dd-mm      |    34 |  ← la vista lo convertía (año en curso)
--     | prov_at    | dd/mm/aa   |   121 |  ← pasaba CRUDO ("01/07/26"), todo julio 2026
--     | tallerista | YYYY-MM-DD | 1.388 |
--     | tallerista | "|||"      |     1 |  ← basura, pasaba cruda
--
--   Eso rompía TRES cosas a la vez, y las tres se ven en la pantalla:
--     1. La columna Fecha mezclaba `01/07/26` con `15/09`.
--     2. El orden salía mal. Tanto el `order` del servidor como el `sort` del front comparan la
--        fecha como TEXTO, y `"01/07/26" < "2026-…"`, así que esas 121 filas se iban al fondo
--        sin importar su fecha real.
--     3. ⚠ Los filtros Desde/Hasta del histórico son `gte`/`lte` sobre ese mismo texto, así que
--        esas 121 filas quedaban INVISIBLES al filtrar por fecha — sin ningún aviso. Buscar
--        julio 2026 no devolvía las recepciones de julio 2026.
--   De yapa, el corte de 1.000 filas (`HARD`) dice "se muestran las más recientes" y, con el
--   orden roto, no era cierto.
--
-- EL ARREGLO — en el BACKEND, que es donde manda el protocolo
--   `gv_fecha_recepcion_norm(text)` lleva los cuatro formatos a `YYYY-MM-DD`, y lo que no es una
--   fecha devuelve **NULL** (no el texto crudo): así no ensucia ni el orden ni los filtros.
--   La vista la aplica a las dos mitades del UNION. El tipo de `fecha` NO cambia (sigue TEXT),
--   justamente para no tocar a ningún consumidor.
--
--   El `dd-mm` sin año se sigue resolviendo con el año en curso, pero ahora con un reparo: si
--   la fecha resultante cae más de 30 días en el futuro, es del año PASADO. Un `28-12` leído en
--   enero es de diciembre pasado, no del que viene. Antes eso daba un año de más en silencio.
--   (Con los datos de hoy —agosto y septiembre 2026— el resultado es idéntico al anterior.)
--
-- MEDICIÓN (2026-09-16)
--   Antes:   prov_at 121 crudas + 34 ymd · tallerista 1.388 ymd + 1 basura
--   Después: prov_at 155 ymd (2026-06-04 … 2026-09-15) · tallerista 1.388 ymd + 1 NULL
--   Total 1.544 = 1.544 — no se perdió ni se duplicó ninguna fila.
--   `security_invoker` conservado: `reloptions = {security_invoker=true}` (se vuelve a poner
--   explícito con el ALTER, porque un CREATE OR REPLACE VIEW puede borrar las reloptions).
--
-- CONSUMIDORES — ninguno cambia de resultado
--   · `gv_entregas_mensuales_cod(text,int)` y `_stkProyMes` de `index.html` ya traían su propio
--     parser de los tres formatos; ahora les llega siempre la rama `YYYY-MM-DD`, que da el MISMO
--     mes que antes (`01/07/26` → `2026-07` por su rama dd/mm/aa; ahora `2026-07-01` → `2026-07`).
--     Quedan como código muerto inofensivo.
--   · `ocFetchRecepcion` (`index.html`) pide `order=fecha.asc`: pasa a ordenar de verdad.
--   · `gv_lecturas_al_limite` sólo cuenta filas.
--
-- LOS DATOS DE ORIGEN NO SE TOCARON. `"Entregas Prov AT".Dia_mes` sigue con sus 121 `dd/mm/aa`
-- y la fila `|||` sigue donde estaba: el protocolo del repo pide no modificar datos sin permiso
-- explícito, y normalizar en la vista alcanza para las tres cosas que estaban mal. Si algún día
-- se quiere limpiar el origen, `gv_fecha_recepcion_norm` ya es la regla a aplicar.
-- ============================================================================

create or replace function public.gv_fecha_recepcion_norm(p_txt text)
returns text language sql immutable
set search_path to 'public'
as $$
  select case
    -- ya normalizada
    when s ~ '^\d{4}-\d{2}-\d{2}$' then s
    when s ~ '^\d{4}-\d{2}-\d{2}[T ]' then left(s, 10)
    -- dd/mm/aa  y  dd/mm/aaaa  (y con guiones)
    when s ~ '^\d{1,2}[/-]\d{1,2}[/-]\d{4}$' then
      to_char(to_date(replace(s,'-','/'), 'DD/MM/YYYY'), 'YYYY-MM-DD')
    when s ~ '^\d{1,2}[/-]\d{1,2}[/-]\d{2}$' then
      to_char(to_date(replace(s,'-','/'), 'DD/MM/YY'), 'YYYY-MM-DD')
    -- dd-mm / dd/mm SIN año: es del año en curso, salvo que caiga en el futuro
    -- (un 28-12 leído en enero es del año pasado, no del que viene).
    when s ~ '^\d{1,2}[/-]\d{1,2}$' then
      to_char(
        case when make_date(extract(year from current_date)::int,
                            split_part(replace(s,'-','/'),'/',2)::int,
                            split_part(replace(s,'-','/'),'/',1)::int)
                  > current_date + 30
             then make_date(extract(year from current_date)::int - 1,
                            split_part(replace(s,'-','/'),'/',2)::int,
                            split_part(replace(s,'-','/'),'/',1)::int)
             else make_date(extract(year from current_date)::int,
                            split_part(replace(s,'-','/'),'/',2)::int,
                            split_part(replace(s,'-','/'),'/',1)::int)
        end, 'YYYY-MM-DD')
    else null
  end
  from (select nullif(btrim(coalesce(p_txt,'')), '') as s) _;
$$;
comment on function public.gv_fecha_recepcion_norm(text) is
  'v18.80 (pedido de Luis, 2026-09-16) - normaliza a YYYY-MM-DD las fechas TEXTO de recepcion ("Entregas Prov AT".Dia_mes y "Entregas Tallerista Virgilio".Fecha), que conviven en 4 formatos. Lo que no es una fecha devuelve NULL, para que no ensucie el orden ni los filtros. La usa vista_historial_entregas.';
grant execute on function public.gv_fecha_recepcion_norm(text) to anon, authenticated, service_role;


create or replace view public.vista_historial_entregas
with (security_invoker = true) as
 SELECT 'tallerista'::text AS fuente,
    public.gv_fecha_recepcion_norm(t."Fecha") AS fecha,     -- v18.80 (antes: t."Fecha" cruda)
    t.created_at,
    t."Cod" AS cod_art,
    ''::text AS descripcion,
    t."Cajas"::numeric AS cajas,
    t."Nombre_Tall" AS quien,
    t."Remito" AS remito,
    cmo.llegada,
    cmo.carga,
        CASE
            WHEN cmo.llegada IS NOT NULL AND cmo.carga IS NOT NULL THEN round(EXTRACT(epoch FROM cmo.carga - cmo.llegada) / 3600.0, 2)
            ELSE NULL::numeric
        END AS demora_hs
   FROM "Entregas Tallerista Virgilio" t
     LEFT JOIN LATERAL ( SELECT c.created_at AS llegada,
            c.procesado_at AS carga
           FROM "Control_Modo_OP" c
          WHERE c.estado = 'procesado'::text AND c.procesado_at IS NOT NULL AND NULLIF(btrim(c.remito), ''::text) = NULLIF(btrim(t."Remito"), ''::text) AND lower(btrim(c.nombre)) = lower(btrim(t."Nombre_Tall"))
          ORDER BY c.procesado_at DESC
         LIMIT 1) cmo ON true
UNION ALL
 SELECT 'prov_at'::text AS fuente,
    public.gv_fecha_recepcion_norm(p."Dia_mes") AS fecha,   -- v18.80 (antes: sólo el CASE de dd-mm)
    NULL::timestamp with time zone AS created_at,
    p."Cod_Art" AS cod_art,
    COALESCE(p."Descripcion", ''::text) AS descripcion,
    p."Cantidad"::numeric AS cajas,
    p."Proveedor" AS quien,
    p."Remito" AS remito,
    cmo.llegada,
    cmo.carga,
        CASE
            WHEN cmo.llegada IS NOT NULL AND cmo.carga IS NOT NULL THEN round(EXTRACT(epoch FROM cmo.carga - cmo.llegada) / 3600.0, 2)
            ELSE NULL::numeric
        END AS demora_hs
   FROM "Entregas Prov AT" p
     LEFT JOIN LATERAL ( SELECT c.created_at AS llegada,
            c.procesado_at AS carga
           FROM "Control_Modo_OP" c
          WHERE c.estado = 'procesado'::text AND c.procesado_at IS NOT NULL AND NULLIF(btrim(c.remito), ''::text) = NULLIF(btrim(p."Remito"), ''::text) AND lower(btrim(c.nombre)) = lower(btrim(p."Proveedor"))
          ORDER BY c.procesado_at DESC
         LIMIT 1) cmo ON true;

-- ⚠ OBLIGATORIO: un CREATE OR REPLACE VIEW puede resetear las reloptions, y una vista sin
-- `security_invoker` corre como `postgres` y saltea la RLS.
alter view public.vista_historial_entregas set (security_invoker = true);


-- ── CHEQUEOS ───────────────────────────────────────────────────────────────
--   select case when fecha ~ '^\d{4}-\d{2}-\d{2}$' then 'ymd'
--               when fecha is null then '(null)' else 'otro' end forma,
--          count(*) from public.vista_historial_entregas group by 1;
--   -- esperado: ymd 1.543 · (null) 1 · otro 0
--   select relname, reloptions from pg_class where oid = 'public.vista_historial_entregas'::regclass;
--   -- esperado: {security_invoker=true}
--
-- ── ROLLBACK ───────────────────────────────────────────────────────────────
--   Volver a poner, en las dos mitades del UNION, lo que había antes:
--     tallerista →  t."Fecha" AS fecha
--     prov_at    →  CASE WHEN p."Dia_mes" ~ '^\d{1,2}-\d{1,2}$'
--                        THEN ((EXTRACT(year FROM CURRENT_DATE)::int::text || '-') ||
--                              lpad(split_part(p."Dia_mes", '-', 2), 2, '0') || '-') ||
--                              lpad(split_part(p."Dia_mes", '-', 1), 2, '0')
--                        ELSE p."Dia_mes" END AS fecha
--   …con el mismo `alter view … set (security_invoker = true)` al final, y después
--   `drop function public.gv_fecha_recepcion_norm(text);`
--
-- ── FRONT (recepcion.js, v18.80) ───────────────────────────────────────────
--   `histYmd` repite esta misma regla en el navegador, SÓLO como red de seguridad (si alguna
--   fila llegara sin normalizar, la pantalla la ordena y la muestra bien igual), y
--   `histFechaTxt` decide la etiqueta: `dd/mm`, o `dd/mm/aa` en TODAS las filas si lo filtrado
--   cruza de año — nunca mezclado. Test: `tests/rcp-hist-fecha.cjs`.
