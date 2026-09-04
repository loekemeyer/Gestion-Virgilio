-- ══════════════════════════════════════════════════════════════════════════
-- API de salida a ISIS — pedidos terminados → ERP (idea 5547 · ticket 1159666)
-- ══════════════════════════════════════════════════════════════════════════
-- Punto 18 del informe consolidado de ISIS: nos piden URL, token, endpoint y
-- estructura JSON. Se resuelve con la **Alternativa B** del §11 del informe:
-- ISIS consulta una API NUESTRA (Edge Function `isis-api` en Supabase). Es una
-- request SALIENTE desde la LAN de ISIS → NO hace falta Windows Server, IIS,
-- IP pública ni abrir puertos en el depósito (ver docs/ISIS-API-ESPECIFICACION.md).
--
-- Qué es un "pedido terminado": la NP que la operadora administrativa TILDÓ en
-- el módulo Facturación de Virgilio → fila en `Facturacion_NP`. Ese tick es el
-- único disparador (el mismo que hoy drena el stock a `facturado`).
--
-- Objetos:
--   isis_export_pedidos   — cola/ledger por NP (pendiente→entregado→procesado/error).
--   isis_api_tokens       — tokens de acceso (solo el SHA-256, nunca el token).
--   isis_api_log          — traza de cada request (lo que pide el §18 del informe).
--   isis_pedido_json(np)  — arma el JSON del pedido.
--   isis_api_*            — RPCs que consume la Edge Function (service_role).
--   trigger en Facturacion_NP (INSERT → encola / DELETE → anula).
--
-- Seguridad: las 3 tablas con RLS ON y sin policies (anon/authenticated NO
-- entran); las RPC son SECURITY DEFINER con EXECUTE solo para service_role.
-- La Edge Function corre con service_role y valida el token ANTES de tocar nada.
--
-- ⚠ El trigger de encolado NUNCA puede romper el tick de facturación: todo su
-- cuerpo va dentro de un BEGIN…EXCEPTION WHEN OTHERS → sigue de largo.
-- ══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────── tablas ──
CREATE TABLE IF NOT EXISTS public.isis_export_pedidos (
  np              text PRIMARY KEY,
  empresa         text,                       -- 'LK' | 'CH' (empresa_de_np)
  estado          text NOT NULL DEFAULT 'pendiente',
  terminado_en    timestamptz,                -- cuándo se tildó en Virgilio
  creado_en       timestamptz NOT NULL DEFAULT now(),
  actualizado_en  timestamptz NOT NULL DEFAULT now(),
  entregado_en    timestamptz,                -- cuándo lo bajó ISIS (GET)
  entregas        int NOT NULL DEFAULT 0,     -- cuántas veces lo bajó
  procesado_en    timestamptz,                -- cuándo acusó ISIS (POST)
  resultado       text,                       -- 'ok' | 'error'
  nro_comprobante text,
  cae             text,
  error_detalle   text,
  anulado_en      timestamptz,                -- destildado en Virgilio
  payload         jsonb,                      -- snapshot de lo entregado
  CONSTRAINT isis_export_pedidos_estado_chk
    CHECK (estado IN ('pendiente','entregado','procesado','error','anulado','historico'))
);
COMMENT ON TABLE public.isis_export_pedidos IS
  'Cola de pedidos terminados hacia ISIS. pendiente→entregado (GET de ISIS)→procesado|error (acuse). Una fila por NP.';

CREATE INDEX IF NOT EXISTS isis_export_pedidos_estado_idx
  ON public.isis_export_pedidos (estado, terminado_en);

CREATE TABLE IF NOT EXISTS public.isis_api_tokens (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre      text NOT NULL,
  token_hash  text NOT NULL UNIQUE,           -- SHA-256 hex del token en claro
  activo      boolean NOT NULL DEFAULT true,
  solo_lectura boolean NOT NULL DEFAULT false,
  creado_en   timestamptz NOT NULL DEFAULT now(),
  ultimo_uso  timestamptz,
  usos        bigint NOT NULL DEFAULT 0,
  nota        text
);
COMMENT ON TABLE public.isis_api_tokens IS
  'Tokens de la API ISIS. Se guarda SOLO el SHA-256 — el token en claro se entrega una vez y no se puede recuperar.';

CREATE TABLE IF NOT EXISTS public.isis_api_log (
  id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ts       timestamptz NOT NULL DEFAULT now(),
  token_id bigint,
  nombre   text,
  metodo   text,
  ruta     text,
  np       text,
  status   int,
  ms       int,
  ip       text,
  detalle  jsonb
);
CREATE INDEX IF NOT EXISTS isis_api_log_ts_idx ON public.isis_api_log (ts DESC);

ALTER TABLE public.isis_export_pedidos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.isis_api_tokens     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.isis_api_log        ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.isis_export_pedidos FROM anon, authenticated;
REVOKE ALL ON public.isis_api_tokens     FROM anon, authenticated;
REVOKE ALL ON public.isis_api_log        FROM anon, authenticated;

-- ────────────────────────────────────────────────── JSON de un pedido ──
-- Devuelve NULL si la NP no está tildada como terminada en Facturación.
CREATE OR REPLACE FUNCTION public.isis_pedido_json(p_np text)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
WITH npn AS (
  SELECT regexp_replace(coalesce(p_np,''), '\.0+$', '') AS np
),
f AS (
  SELECT fn.* FROM public."Facturacion_NP" fn, npn
   WHERE regexp_replace(fn.np, '\.0+$', '') = npn.np
   LIMIT 1
),
-- lo REALMENTE armado (código real, ya resuelto por equivalencias en el depósito)
ent AS (
  SELECT public.canon_cod(e.cod_art)              AS cod,
         SUM(coalesce(e.cajas_pedidas,0))         AS cajas_ped,
         SUM(coalesce(e.cajas_entregadas,0))      AS cajas_ent,
         SUM(coalesce(e.cajas_falto,0))           AS cajas_falto
    FROM public."Entregas_Virgilio" e, npn
   WHERE regexp_replace(e.np, '\.0+$', '') = npn.np
   GROUP BY 1
),
-- líneas del pedido original (para avisar cuándo se armó OTRO código)
base AS (
  SELECT DISTINCT public.canon_cod(b.articulo) AS cod_pedido
    FROM public."PPP_Base_Pedidos" b, npn
   WHERE regexp_replace(b.pedido, '\.0+$', '') = npn.np
),
items AS (
  SELECT ent.cod                                                AS articulo,
         coalesce(eq.cod_pedido, ent.cod)                       AS articulo_pedido,
         pv.descripcion                                         AS descripcion,
         pv.uxb                                                 AS unidades_x_caja,
         ent.cajas_ped, ent.cajas_ent, ent.cajas_falto
    FROM ent
    LEFT JOIN public.precios_venta pv
           ON public.canon_cod(pv.cod) = ent.cod
    LEFT JOIN LATERAL (
      SELECT public.canon_cod(ec.cod_pedido) AS cod_pedido
        FROM public."Equivalencias_Codigos" ec
        JOIN base ON base.cod_pedido = public.canon_cod(ec.cod_pedido)
       WHERE public.canon_cod(ec.cod_real) = ent.cod
         AND public.canon_cod(ec.cod_pedido) <> ent.cod
       LIMIT 1
    ) eq ON true
   WHERE ent.cajas_ped > 0 OR ent.cajas_ent > 0 OR ent.cajas_falto > 0
),
tot AS (
  SELECT count(*)                        AS n_items,
         coalesce(sum(cajas_ped),0)      AS cajas_ped,
         coalesce(sum(cajas_ent),0)      AS cajas_ent,
         coalesce(sum(cajas_falto),0)    AS cajas_falto
    FROM items
)
SELECT CASE WHEN f.np IS NULL THEN NULL ELSE jsonb_build_object(
  'np',              nullif(regexp_replace(f.np,'\D','','g'),'')::bigint,
  'empresa',         public.empresa_de_np(f.np),
  'cod_cliente',     nullif(regexp_replace(coalesce(f.cod_cliente,''),'\D','','g'),''),
  'razon_social',    f.razon_social,
  'tanda',           f.tanda,
  'fecha_entrega',   to_char(f.fecha_salida, 'YYYY-MM-DD'),
  'terminado_en',    to_char(f.facturado_at AT TIME ZONE 'America/Argentina/Buenos_Aires',
                             'YYYY-MM-DD"T"HH24:MI:SS') || '-03:00',
  'm3',              f.m3,
  'estado',          'terminado',
  'completo',        (tot.cajas_falto = 0),
  'totales',         jsonb_build_object(
                       'items',            tot.n_items,
                       'cajas_pedidas',    tot.cajas_ped,
                       'cajas_a_facturar', tot.cajas_ent,
                       'cajas_falto',      tot.cajas_falto),
  'items',           coalesce((
                       SELECT jsonb_agg(jsonb_build_object(
                                'articulo',         i.articulo,
                                'articulo_pedido',  i.articulo_pedido,
                                'descripcion',      i.descripcion,
                                'unidades_x_caja',  i.unidades_x_caja,
                                'cajas_pedidas',    i.cajas_ped,
                                'cajas',            i.cajas_ent,
                                'cajas_falto',      i.cajas_falto,
                                'unidades',         CASE WHEN i.unidades_x_caja IS NOT NULL
                                                         THEN i.cajas_ent * i.unidades_x_caja END,
                                'completo',         (i.cajas_falto = 0))
                              ORDER BY i.articulo)
                         FROM items i WHERE i.cajas_ent > 0), '[]'::jsonb),
  'faltantes',       coalesce((
                       SELECT jsonb_agg(jsonb_build_object(
                                'articulo',    i.articulo,
                                'cajas_falto', i.cajas_falto)
                              ORDER BY i.articulo)
                         FROM items i WHERE i.cajas_falto > 0), '[]'::jsonb),
  'control',         jsonb_build_object(
                       'neto_estimado', (SELECT round(v.neto,2) FROM public.vista_facturacion_neto v, npn
                                          WHERE v.np = npn.np LIMIT 1),
                       'moneda', 'ARS',
                       'nota', 'Informativo, solo para control. El importe a facturar lo determina ISIS con su lista de precios.')
) END
FROM npn
LEFT JOIN f ON true
CROSS JOIN tot;
$$;
COMMENT ON FUNCTION public.isis_pedido_json(text) IS
  'JSON del pedido terminado para ISIS. cajas = lo ARMADO (a facturar); articulo = el código realmente preparado.';

-- ──────────────────────────────────────── encolado desde Facturación ──
CREATE OR REPLACE FUNCTION public.isis_encolar_facturado()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  BEGIN
    INSERT INTO public.isis_export_pedidos (np, empresa, estado, terminado_en)
    VALUES (regexp_replace(NEW.np, '\.0+$', ''),
            public.empresa_de_np(NEW.np),
            'pendiente',
            coalesce(NEW.facturado_at, now()))
    ON CONFLICT (np) DO UPDATE
      SET estado = CASE WHEN isis_export_pedidos.estado = 'anulado'
                        THEN 'pendiente' ELSE isis_export_pedidos.estado END,
          anulado_en = NULL,
          terminado_en = coalesce(EXCLUDED.terminado_en, isis_export_pedidos.terminado_en),
          actualizado_en = now();
  EXCEPTION WHEN OTHERS THEN
    NULL;  -- jamás romper el tick de facturación por la integración
  END;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.isis_anular_facturado()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  BEGIN
    UPDATE public.isis_export_pedidos
       SET estado = CASE WHEN estado = 'pendiente' THEN 'anulado' ELSE estado END,
           anulado_en = now(),
           actualizado_en = now()
     WHERE np = regexp_replace(OLD.np, '\.0+$', '');
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
  RETURN OLD;
END $$;

DROP TRIGGER IF EXISTS trg_isis_encolar_facturado ON public."Facturacion_NP";
CREATE TRIGGER trg_isis_encolar_facturado
  AFTER INSERT ON public."Facturacion_NP"
  FOR EACH ROW EXECUTE FUNCTION public.isis_encolar_facturado();

DROP TRIGGER IF EXISTS trg_isis_anular_facturado ON public."Facturacion_NP";
CREATE TRIGGER trg_isis_anular_facturado
  AFTER DELETE ON public."Facturacion_NP"
  FOR EACH ROW EXECUTE FUNCTION public.isis_anular_facturado();

-- ───────────────────────────────────────────── RPCs de la Edge Function ──
-- Valida el token (recibe el SHA-256 hex, nunca el token en claro).
CREATE OR REPLACE FUNCTION public.isis_api_token_check(p_hash text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE r record;
BEGIN
  SELECT id, nombre, solo_lectura INTO r
    FROM public.isis_api_tokens
   WHERE token_hash = lower(coalesce(p_hash,'')) AND activo
   LIMIT 1;
  IF NOT FOUND THEN RETURN NULL; END IF;
  UPDATE public.isis_api_tokens
     SET ultimo_uso = now(), usos = usos + 1
   WHERE id = r.id;
  RETURN jsonb_build_object('id', r.id, 'nombre', r.nombre, 'solo_lectura', r.solo_lectura);
END $$;

-- Listado de pedidos por estado (cabeceras, liviano).
CREATE OR REPLACE FUNCTION public.isis_api_pendientes(
  p_estado  text        DEFAULT 'pendiente',
  p_empresa text        DEFAULT NULL,
  p_desde   timestamptz DEFAULT NULL,
  p_limit   int         DEFAULT 100)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
SELECT coalesce(jsonb_agg(x ORDER BY x->>'terminado_en'), '[]'::jsonb)
FROM (
  SELECT jsonb_build_object(
           'np',            nullif(regexp_replace(q.np,'\D','','g'),'')::bigint,
           'empresa',       q.empresa,
           'estado',        q.estado,
           'razon_social',  f.razon_social,
           'cod_cliente',   nullif(regexp_replace(coalesce(f.cod_cliente,''),'\D','','g'),''),
           'tanda',         f.tanda,
           'fecha_entrega', to_char(f.fecha_salida,'YYYY-MM-DD'),
           'terminado_en',  to_char(q.terminado_en AT TIME ZONE 'America/Argentina/Buenos_Aires',
                                    'YYYY-MM-DD"T"HH24:MI:SS') || '-03:00',
           'm3',            f.m3
         ) AS x
    FROM public.isis_export_pedidos q
    LEFT JOIN public."Facturacion_NP" f
           ON regexp_replace(f.np,'\.0+$','') = q.np
   WHERE q.estado = coalesce(nullif(p_estado,''), 'pendiente')
     AND (p_empresa IS NULL OR q.empresa = upper(p_empresa))
     AND (p_desde   IS NULL OR q.terminado_en >= p_desde)
   ORDER BY q.terminado_en
   LIMIT greatest(1, least(coalesce(p_limit,100), 500))
) s;
$$;

-- Devuelve el JSON completo de una NP. p_marcar=true la pasa a 'entregado'.
CREATE OR REPLACE FUNCTION public.isis_api_pedido(p_np text, p_marcar boolean DEFAULT true)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_np   text := regexp_replace(coalesce(p_np,''), '\.0+$', '');
  v_json jsonb;
  v_q    record;
BEGIN
  SELECT * INTO v_q FROM public.isis_export_pedidos WHERE np = v_np;
  IF NOT FOUND THEN RETURN NULL; END IF;

  v_json := public.isis_pedido_json(v_np);
  IF v_json IS NULL THEN RETURN NULL; END IF;

  v_json := v_json
    || jsonb_build_object('estado_integracion', v_q.estado)
    || CASE WHEN v_q.anulado_en IS NOT NULL
            THEN jsonb_build_object('anulado', true) ELSE '{}'::jsonb END;

  IF p_marcar THEN
    UPDATE public.isis_export_pedidos
       SET estado = CASE WHEN estado = 'pendiente' THEN 'entregado' ELSE estado END,
           entregado_en = coalesce(entregado_en, now()),
           entregas = entregas + 1,
           payload = coalesce(payload, v_json),
           actualizado_en = now()
     WHERE np = v_np;
  END IF;

  RETURN v_json;
END $$;

-- Acuse de ISIS. Idempotente: si ya hay un acuse OK con OTRO comprobante, no
-- pisa nada y devuelve duplicado=true (control de duplicados del §17).
CREATE OR REPLACE FUNCTION public.isis_api_acuse(
  p_np        text,
  p_resultado text,
  p_nro       text DEFAULT NULL,
  p_cae       text DEFAULT NULL,
  p_error     text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_np  text := regexp_replace(coalesce(p_np,''), '\.0+$', '');
  v_res text := lower(coalesce(p_resultado,''));
  v_q   record;
BEGIN
  IF v_res NOT IN ('ok','error') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'resultado debe ser "ok" o "error"');
  END IF;

  SELECT * INTO v_q FROM public.isis_export_pedidos WHERE np = v_np;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'NP desconocida');
  END IF;

  IF v_q.resultado = 'ok' THEN
    RETURN jsonb_build_object(
      'ok', true, 'duplicado', true,
      'np', v_np,
      'nro_comprobante', v_q.nro_comprobante,
      'cae', v_q.cae,
      'procesado_en', v_q.procesado_en,
      'nota', 'La NP ya estaba procesada. No se registró un segundo comprobante.');
  END IF;

  UPDATE public.isis_export_pedidos
     SET estado         = CASE WHEN v_res = 'ok' THEN 'procesado' ELSE 'error' END,
         resultado      = v_res,
         nro_comprobante= nullif(p_nro,''),
         cae            = nullif(p_cae,''),
         error_detalle  = nullif(p_error,''),
         procesado_en   = now(),
         actualizado_en = now()
   WHERE np = v_np;

  RETURN jsonb_build_object('ok', true, 'duplicado', false, 'np', v_np,
                            'estado', CASE WHEN v_res='ok' THEN 'procesado' ELSE 'error' END);
END $$;

-- Traza de requests (§18 del informe: qué se pidió, cuándo, con qué resultado).
CREATE OR REPLACE FUNCTION public.isis_api_log_write(
  p_token_id bigint, p_nombre text, p_metodo text, p_ruta text,
  p_np text, p_status int, p_ms int, p_ip text, p_detalle jsonb DEFAULT NULL)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  INSERT INTO public.isis_api_log (token_id, nombre, metodo, ruta, np, status, ms, ip, detalle)
  VALUES (p_token_id, p_nombre, p_metodo, p_ruta, p_np, p_status, p_ms, p_ip, p_detalle);
$$;

-- Retención del log (90 días). Programar por pg_cron si se quiere.
CREATE OR REPLACE FUNCTION public.isis_api_log_purge()
RETURNS int
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH d AS (DELETE FROM public.isis_api_log WHERE ts < now() - interval '90 days' RETURNING 1)
  SELECT count(*)::int FROM d;
$$;

-- ────────────────────────────────────────────────────────────── grants ──
REVOKE ALL ON FUNCTION public.isis_pedido_json(text)                                   FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.isis_api_token_check(text)                               FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.isis_api_pendientes(text,text,timestamptz,int)           FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.isis_api_pedido(text,boolean)                            FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.isis_api_acuse(text,text,text,text,text)                 FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.isis_api_log_write(bigint,text,text,text,text,int,int,text,jsonb) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.isis_api_log_purge()                                     FROM public, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.isis_pedido_json(text)                                   TO service_role;
GRANT EXECUTE ON FUNCTION public.isis_api_token_check(text)                               TO service_role;
GRANT EXECUTE ON FUNCTION public.isis_api_pendientes(text,text,timestamptz,int)           TO service_role;
GRANT EXECUTE ON FUNCTION public.isis_api_pedido(text,boolean)                            TO service_role;
GRANT EXECUTE ON FUNCTION public.isis_api_acuse(text,text,text,text,text)                 TO service_role;
GRANT EXECUTE ON FUNCTION public.isis_api_log_write(bigint,text,text,text,text,int,int,text,jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.isis_api_log_purge()                                     TO service_role;

-- ───────────────────────────────────────────────── alta de un token ──
-- El token en claro se genera AFUERA y solo se guarda su SHA-256:
--   INSERT INTO public.isis_api_tokens (nombre, token_hash, nota)
--   VALUES ('ISIS producción', '<sha256 hex del token>', 'Entregado a Sistemas ISIS');
-- Para revocarlo: UPDATE public.isis_api_tokens SET activo = false WHERE nombre = '...';

-- ─────────────────────────────────────── backfill (NO ejecutar a ciegas) ──
-- Las NP ya facturadas ANTES de encender la integración NO se le deben mandar a
-- ISIS (ya se facturaron a mano). Para que queden registradas pero invisibles
-- para la API, se cargan como 'historico':
--   INSERT INTO public.isis_export_pedidos (np, empresa, estado, terminado_en)
--   SELECT regexp_replace(np,'\.0+$',''), public.empresa_de_np(np), 'historico', facturado_at
--     FROM public."Facturacion_NP"
--   ON CONFLICT (np) DO NOTHING;

-- Los trigger functions tampoco deben ser invocables vía REST (advisor 0028).
REVOKE ALL ON FUNCTION public.isis_encolar_facturado() FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.isis_anular_facturado()  FROM public, anon, authenticated;
