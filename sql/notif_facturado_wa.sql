-- ══════════════════════════════════════════════════════════════════════════
-- Aviso WhatsApp proactivo al cliente cuando la operadora tilda "facturó"
-- ══════════════════════════════════════════════════════════════════════════
-- Cuando se INSERTa una fila en Facturacion_NP (el ✓ "facturó" del módulo de
-- Facturación), se dispara un WhatsApp al cliente: "mañana sale tu pedido por
-- $XXX (IVA incluido)".  total = neto (vista_facturacion_neto, sobre lo armado)
-- × 1,21.  fecha_salida = el día que sale (mañana).
--
-- Cross-project: postea a la Edge Function `lk_notif-facturado` del proyecto LK
-- (kwkclwhmoygunqmlegrg), que resuelve el teléfono (bot_customer_whatsapps por
-- cod_cliente), deduplica por NP y encola en wa_outbox con un template de Meta.
-- Mismo patrón/secret (vault `virgilio_entrega_sync_secret`, header x-sync-secret)
-- que fn_virgilio_entrega_to_formato.
--
-- AFTER INSERT → dispara sólo en el 1er tilde (el re-tilde por upsert es UPDATE).
-- Depende de: vista_facturacion_neto (sql/facturacion_neto.sql), extensión pg_net,
-- y el secret en vault.  El envío real requiere el template aprobado en Meta.
-- ══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_facturado_notif_wa()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'net'
AS $function$
declare
  v_url    text := 'https://kwkclwhmoygunqmlegrg.supabase.co/functions/v1/lk_notif-facturado';
  v_secret text;
  v_neto   numeric;
  v_total  numeric;
begin
  if coalesce(NEW.cod_cliente, '') = '' then return NEW; end if;

  select neto into v_neto
    from public.vista_facturacion_neto
   where np = regexp_replace(NEW.np, '\.0+$', '')
   limit 1;
  if v_neto is null or v_neto <= 0 then return NEW; end if;
  v_total := round(v_neto * 1.21, 2);

  select decrypted_secret into v_secret
    from vault.decrypted_secrets
   where name = 'virgilio_entrega_sync_secret'
   limit 1;
  if v_secret is null then
    raise warning 'fn_facturado_notif_wa: secret no encontrado en vault — aviso omitido';
    return NEW;
  end if;

  perform net.http_post(
    url     := v_url,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-sync-secret', v_secret),
    body    := jsonb_build_object(
                 'np',           NEW.np,
                 'cod_cliente',  NEW.cod_cliente,
                 'razon_social', NEW.razon_social,
                 'total',        v_total,
                 'fecha_salida', NEW.fecha_salida
               )
  );
  return NEW;
end;
$function$;

DROP TRIGGER IF EXISTS trg_facturado_notif_wa ON public."Facturacion_NP";
CREATE TRIGGER trg_facturado_notif_wa
  AFTER INSERT ON public."Facturacion_NP"
  FOR EACH ROW EXECUTE FUNCTION public.fn_facturado_notif_wa();
