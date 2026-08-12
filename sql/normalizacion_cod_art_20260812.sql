-- ============================================================
-- Normalización de cod_art — 2026-08-12 (blindar a futuro)
-- Objetivo: que no vuelvan los códigos fantasma (ceros a la izquierda, formatos raros)
-- que partían saldos y ensuciaban la lista de Stock.
--
-- Qué hace:
--  (1) fn_canon_cod_art (BEFORE INSERT en Movimientos_Stock): canoniza el cod_art de
--      ARTÍCULOS DE STOCK al escribir → OC_Maximos curado, o numérico sin ceros a la izq
--      con mínimo 3 dígitos (NUNCA trunca). Saltea insumos (usan su propio catálogo, y su
--      espacio numérico choca con el de stock) y los tipos del pipeline (dedup del cron).
--  (2) vista_saldos_stock: agrupa por clave canónica → cualquier variante con cero a la izq
--      se suma en UNA sola fila. Con los datos de hoy es no-op (0 fusiones verificadas): solo
--      actúa de red de seguridad para lo nuevo.
--
-- IMPORTANTE: los insumos NO se canonizan a propósito. "Caja Nº 1" quedó con código 0027,
-- que canonizado sería 027 = Colador N°10 (¡otro artículo!). El espacio numérico de insumos
-- pisa el de stock. La prevención de insumos es el alta con código TMP-NNNN (ya vigente) +
-- la curación desde el admin de Stock y Compras (idea 5572).
--
-- Restore de la vista anterior: ver el bloque marcado "-- VIEW ANTERIOR" al final.
-- fn_canon_cod_art anterior (por si hay que volver): igual que esta pero SIN 'SET search_path'
-- y sin trigger enganchado (la función existía pero no estaba attachada).
-- ============================================================

-- (1) Función de canonicalización (idéntica a la previa + SET search_path para el advisor 2758)
CREATE OR REPLACE FUNCTION public.fn_canon_cod_art()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path = public, pg_temp
AS $function$
declare
  k text;
  c text;
begin
  if NEW.cod_art is null then return NEW; end if;
  -- insumos usa sus propios códigos (tabla Insumos.cod); su espacio numérico choca con stock
  if NEW.deposito = 'insumos' then return NEW; end if;
  if NEW.tipo in ('picking','separado','facturado') then return NEW; end if;   -- no tocar: dedup del cron
  k := regexp_replace(upper(btrim(NEW.cod_art)), '^0+(?=.)', '');               -- clave sin ceros a la izq
  if k = '' then return NEW; end if;
  -- 1) canónico curado desde OC_Maximos (misma clave normalizada)
  select o.cod into c
    from public."OC_Maximos" o
   where o.activo
     and regexp_replace(upper(btrim(o.cod)), '^0+(?=.)', '') = k
   limit 1;
  if c is not null then
    NEW.cod_art := c;
  -- 2) fallback SOLO numéricos: sin ceros + relleno a mínimo 3 (NUNCA trunca)
  elsif NEW.cod_art ~ '^[0-9]+$' then
    NEW.cod_art := case when length(k) >= 3 then k else lpad(k, 3, '0') end;
  end if;
  -- alfanuméricos (PP, FLEJE·…, ALAMBRE, 46B, H201Part) quedan intactos
  return NEW;
end;
$function$;

-- (1b) Enganchar el trigger (antes no estaba attachado)
DROP TRIGGER IF EXISTS trg_canon_cod_art ON "Movimientos_Stock";
CREATE TRIGGER trg_canon_cod_art
  BEFORE INSERT ON "Movimientos_Stock"
  FOR EACH ROW EXECUTE FUNCTION public.fn_canon_cod_art();

-- (2) Vista de saldos: agrupar por clave canónica (representante = forma cruda más corta/limpia,
--     así los códigos únicos NO cambian de forma; solo colapsan las variantes con cero a la izq)
create or replace view public.vista_saldos_stock as
 WITH cfg AS (
         SELECT ( SELECT "Stock_Config".valor
                    FROM "Stock_Config"
                   WHERE "Stock_Config".clave = 'cutoff_ts'::text
                   LIMIT 1) AS cutoff
        ), canon AS (
         SELECT m.*,
            CASE WHEN upper(btrim(m.cod_art)) ~ '^[0-9]+$'
                 THEN CASE WHEN length(regexp_replace(upper(btrim(m.cod_art)), '^0+(?=.)', '')) >= 3
                           THEN regexp_replace(upper(btrim(m.cod_art)), '^0+(?=.)', '')
                           ELSE lpad(regexp_replace(upper(btrim(m.cod_art)), '^0+(?=.)', ''), 3, '0') END
                 ELSE upper(btrim(m.cod_art))
            END AS ckey
           FROM "Movimientos_Stock" m
        )
 SELECT (array_agg(c.cod_art ORDER BY length(c.cod_art), c.cod_art))[1] AS cod_art,
    (array_agg(c.descripcion ORDER BY length(c.descripcion), c.descripcion) FILTER (WHERE COALESCE(TRIM(BOTH FROM c.descripcion), ''::text) <> ''::text))[1] AS descripcion,
    COALESCE(sum(c.delta) FILTER (WHERE c.deposito = 'terminado'::text), 0::numeric) AS terminado,
    COALESCE(sum(c.delta) FILTER (WHERE c.deposito = 'excedente'::text), 0::numeric) AS excedente,
    COALESCE(sum(c.delta) FILTER (WHERE c.deposito = 'separar_pedidos'::text), 0::numeric) AS separar_pedidos,
    COALESCE(sum(c.delta) FILTER (WHERE c.deposito = 'a_facturar'::text), 0::numeric) AS a_facturar,
    COALESCE(sum(c.delta) FILTER (WHERE c.deposito = 'a_guardar'::text), 0::numeric) AS a_guardar,
    COALESCE(sum(c.delta) FILTER (WHERE c.deposito = 'racks'::text), 0::numeric) AS racks,
    COALESCE(sum(c.delta) FILTER (WHERE c.deposito = 'insumos'::text), 0::numeric) AS insumos,
    COALESCE(sum(c.delta) FILTER (WHERE c.deposito = 'para_envasar'::text), 0::numeric) AS para_envasar,
    COALESCE(sum(c.delta) FILTER (WHERE c.deposito = 'racks_ch'::text), 0::numeric) AS racks_ch
   FROM canon c,
    cfg
  WHERE cfg.cutoff IS NULL OR c.tipo = 'inicial'::text OR c.ts >= cfg.cutoff::timestamp with time zone
  GROUP BY c.ckey;

-- ============================================================
-- VIEW ANTERIOR (restore) — agrupaba por cod_art crudo:
--   ... GROUP BY m.cod_art;  (ver git / backup_20260812)
-- ============================================================
