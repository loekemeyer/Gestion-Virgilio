-- =====================================================================
-- alertas_pedidos_web.sql — Detección de pedidos web anómalos (v8.82)
--
-- Dos piezas:
-- (A) MAYORISTA (kwkclwhmoygunqmlegrg): detectar_pedidos_anomalos() + pg_cron
-- (B) VIRGILIO (hrxfctzncixxqmpfhskv): Alertas_Pedidos_Web + trigger Telegram
--
-- ⚠ ARCHIVO REFERENCIA — las funciones VIVAS están en cada Supabase.
-- =====================================================================

-- =================================================================
-- (A) MAYORISTA — Tabla de log + función de detección + cron
-- =================================================================

-- Tracking: qué pedidos ya se chequearon (evita re-alertar)
CREATE TABLE IF NOT EXISTS public.alertas_pedidos_log (
  id          bigint generated always as identity primary key,
  order_id    bigint NOT NULL UNIQUE,
  score       integer NOT NULL DEFAULT 0,
  motivo      text,
  alertado    boolean NOT NULL DEFAULT false,
  creado_en   timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.alertas_pedidos_log ENABLE ROW LEVEL SECURITY;

-- Función que corre cada 5 min (pg_cron). Escanea pedidos de los últimos
-- 15 min, puntúa señales de anomalía y, si score >= 5, POSTea a Virgilio.
--
-- Señales:
--   1. Ratio total/promedio histórico: >3x (+2), >5x (+4), >10x (+6)
--   2. Units-as-boxes: >70% de líneas con cajas%uxb==0 (+4)
--   3. Cliente nuevo + pedido > $3M (+3)
--   4. Cajas/línea > 30 (+2)
--
-- Score >= 5 → POST a Virgilio (Alertas_Pedidos_Web via REST + anon key).
CREATE OR REPLACE FUNCTION public.detectar_pedidos_anomalos()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE
  r record;
  score int;
  motivo text[];
  hist_avg numeric;
  hist_count int;
  lineas_total int;
  lineas_sospechosas int;
  pct_sospechoso numeric;
  total_cajas int;
  cajas_por_linea numeric;
  virgilio_url text := 'https://hrxfctzncixxqmpfhskv.supabase.co/rest/v1/Alertas_Pedidos_Web';
  virgilio_key text := 'sb_publishable_BqpAgZH6ty-9wft10_YMhw_0rcIPuWT';
  ratio numeric;
  payload jsonb;
BEGIN
  FOR r IN
    SELECT o.id AS order_id, o.total, o.created_at,
           c.cod_cliente, c.business_name, c.id AS customer_uuid
    FROM orders o
    JOIN customers c ON c.id = o.customer_id
    WHERE o.created_at >= now() - interval '15 minutes'
      AND c.cod_cliente NOT IN (1, 3878)
      AND NOT EXISTS (SELECT 1 FROM alertas_pedidos_log l WHERE l.order_id = o.id)
    ORDER BY o.created_at
  LOOP
    score := 0;
    motivo := ARRAY[]::text[];

    -- Signal 1: Ratio vs historical average
    SELECT count(*), coalesce(avg(o2.total), 0)
    INTO hist_count, hist_avg
    FROM orders o2 JOIN customers c2 ON c2.id = o2.customer_id
    WHERE c2.cod_cliente = r.cod_cliente AND o2.id <> r.order_id;

    IF hist_count >= 1 AND hist_avg > 0 THEN
      ratio := r.total / hist_avg;
      IF ratio > 10 THEN score := score + 6; motivo := array_append(motivo, format('Total %sx vs promedio histórico', round(ratio, 1)));
      ELSIF ratio > 5 THEN score := score + 4; motivo := array_append(motivo, format('Total %sx vs promedio histórico', round(ratio, 1)));
      ELSIF ratio > 3 THEN score := score + 2; motivo := array_append(motivo, format('Total %sx vs promedio histórico', round(ratio, 1)));
      END IF;
    ELSE ratio := NULL;
    END IF;

    -- Signal 2: Units-as-boxes smell
    SELECT count(*),
           count(*) FILTER (WHERE oi.uxb > 1 AND (oi.cajas % oi.uxb) = 0),
           coalesce(sum(oi.cajas), 0)
    INTO lineas_total, lineas_sospechosas, total_cajas
    FROM order_items oi WHERE oi.order_id = r.order_id;

    pct_sospechoso := CASE WHEN lineas_total > 0 THEN (lineas_sospechosas::numeric / lineas_total) * 100 ELSE 0 END;
    IF pct_sospechoso > 70 AND lineas_total >= 3 THEN
      score := score + 4;
      motivo := array_append(motivo, format('%s%% líneas con cajas÷uxb exacto (unidades como cajas)', round(pct_sospechoso, 0)));
    END IF;

    -- Signal 3: New customer + large order
    IF hist_count = 0 AND r.total > 3000000 THEN
      score := score + 3;
      motivo := array_append(motivo, 'Cliente nuevo con pedido grande');
    END IF;

    -- Signal 4: Extremely high cajas per line
    IF lineas_total > 0 THEN
      cajas_por_linea := total_cajas::numeric / lineas_total;
      IF cajas_por_linea > 30 AND lineas_total >= 3 THEN
        score := score + 2;
        motivo := array_append(motivo, format('%s cajas/línea promedio', round(cajas_por_linea, 1)));
      END IF;
    END IF;

    -- Log (even if not alerted)
    INSERT INTO alertas_pedidos_log (order_id, score, motivo, alertado)
    VALUES (r.order_id, score, array_to_string(motivo, ' | '), score >= 5);

    -- POST to Virgilio if score >= 5
    IF score >= 5 THEN
      payload := jsonb_build_object(
        'order_id', r.order_id, 'cod_cliente', r.cod_cliente,
        'cliente', r.business_name,
        'total_pedido', round(r.total::numeric, 2),
        'total_historico', CASE WHEN hist_avg > 0 THEN round(hist_avg::numeric, 2) ELSE NULL END,
        'ratio', CASE WHEN ratio IS NOT NULL THEN round(ratio::numeric, 2) ELSE NULL END,
        'cajas', total_cajas, 'lineas', lineas_total,
        'score', score, 'motivo', array_to_string(motivo, ' | '),
        'origen', 'mayorista_detector', 'estado', 'pendiente'
      );
      PERFORM net.http_post(
        url := virgilio_url,
        headers := jsonb_build_object(
          'apikey', virgilio_key, 'Authorization', 'Bearer ' || virgilio_key,
          'Content-Type', 'application/json', 'Prefer', 'return=minimal'),
        body := jsonb_build_array(payload));
    END IF;
  END LOOP;
END;
$fn$;

-- pg_cron: cada 5 minutos
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'detectar-pedidos-anomalos';
SELECT cron.schedule('detectar-pedidos-anomalos', '*/5 * * * *',
  $$SELECT public.detectar_pedidos_anomalos()$$);


-- =================================================================
-- (B) VIRGILIO — Tabla de alertas + trigger Telegram
-- =================================================================

CREATE TABLE IF NOT EXISTS public."Alertas_Pedidos_Web" (
  id               bigint generated always as identity primary key,
  order_id         bigint UNIQUE,
  cod_cliente      text,
  cliente          text,
  total_pedido     numeric,
  total_historico  numeric,
  ratio            numeric,
  cajas            integer,
  lineas           integer,
  score            integer,
  motivo           text,
  origen           text,
  estado           text NOT NULL DEFAULT 'pendiente',
  revisado_en      timestamptz,
  revisado_por     text,
  creado_en        timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public."Alertas_Pedidos_Web" ENABLE ROW LEVEL SECURITY;
-- anon puede INSERT (el mayorista POSTea con la publishable key),
-- SELECT (el front lee las alertas) y UPDATE (el supervisor las revisa).
CREATE POLICY "anon_insert" ON "Alertas_Pedidos_Web" FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "anon_select" ON "Alertas_Pedidos_Web" FOR SELECT TO anon USING (true);
CREATE POLICY "anon_update" ON "Alertas_Pedidos_Web" FOR UPDATE TO anon USING (true) WITH CHECK (true);

-- Trigger: al insertar una alerta, encola mensaje Telegram
CREATE OR REPLACE FUNCTION public.notificar_alerta_pedido_web()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE
  msg text;
BEGIN
  msg := '🚨 PEDIDO ANÓMALO — Revisar' || E'\n\n'
      || '📋 Pedido #' || new.order_id || ' · ' || coalesce(new.cliente, '?')
      || ' (cód ' || coalesce(new.cod_cliente, '?') || ')' || E'\n'
      || '💰 Total: $' || to_char(coalesce(new.total_pedido, 0), 'FM999G999G999')  || E'\n'
      || '📊 Promedio anterior: $' || to_char(coalesce(new.total_historico, 0), 'FM999G999G999') || E'\n'
      || '📈 Ratio: ' || coalesce(new.ratio::text, '—') || 'x' || E'\n'
      || '📦 Cajas: ' || coalesce(new.cajas::text, '—')
      || ' · Líneas: ' || coalesce(new.lineas::text, '—')
      || ' · Score: ' || coalesce(new.score::text, '—') || E'\n'
      || '⚡ Motivo: ' || coalesce(new.motivo, '—') || E'\n\n'
      || '👉 Revisá en PPP (Administración).';

  PERFORM public.tg_enqueue(msg, 'alerta_pedido_' || new.order_id);
  RETURN new;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_alerta_pedido_telegram ON "Alertas_Pedidos_Web";
CREATE TRIGGER trg_alerta_pedido_telegram
  AFTER INSERT ON "Alertas_Pedidos_Web"
  FOR EACH ROW EXECUTE FUNCTION public.notificar_alerta_pedido_web();
