-- =====================================================================
-- refresh_proyeccion_madre.sql — la proyección que alimenta el generador de OCs
--
-- El Máximo del generador de OCs (manual y automático) es `proyección × índice`
-- topado a capacidad. La PROYECCIÓN vive en la tabla `proyeccion_madre`
-- (cod, proy_cajas_mes, uxb, proy_uni_mes, actualizado) y NO se calcula en este
-- proyecto: se trae del proyecto Supabase **"loekemeyer's web"** (PáginaLK,
-- ref `kwkclwhmoygunqmlegrg`), donde vive el registro de ventas.
--
-- ── DE DÓNDE SALE (PáginaLK) ─────────────────────────────────────────────────
-- Función `fn_proyeccion_oc_virgilio()` sobre `public.sales_lines` (228k+ líneas de venta,
-- 2020→hoy). COMBINA Loekemeyer + Chef, ventana PRIMARIA de 6 meses con fallback a 12
-- (si un producto proyecta 0 en 6m usa 12m; si sigue en 0, queda en 0), con el suavizado de
-- anomalías integrado. Detalle en `sql/fn_proyeccion_oc_virgilio.sql`. (Antes se usaba
-- `fn_proyeccion_madre_emp(p_emp)`, LK-only 24m — sigue existiendo pero el refresh ya no la
-- usa.) Aplica remaps (`sales_item_remap`), exclusiones (`sales_excluded_items`) y clientes basura
-- ('1','3878'); toma uxb de `products`/`loke_products`. Corre en ~2 s.
--   → O sea: ventas + clientes + artículos ya están en Supabase; la proyección se
--     calcula de ahí, no de ningún Excel. (El Excel `OC_Maximos.max_cajas` sólo queda
--     de fallback para los pocos códigos SIN historial de ventas.)
--
-- ── EL PIPELINE (Virgilio) ───────────────────────────────────────────────────
-- `refresh_proyeccion_madre()` hace un GET REST a esa función (con la anon key de
-- PáginaLK), borra `proyeccion_madre` y la recarga con la respuesta. Un cron la corre.
--
-- ── EL BUG (arreglado 2026-08-05) ────────────────────────────────────────────
-- La función corre en ~2 s, pero por REST la mataba el `statement_timeout` corto del
-- rol anon de PáginaLK (con caché fría superaba el límite → HTTP 500 / 57014). Entonces
-- `refresh_proyeccion_madre()` devolvía **-1 sin recargar** y NADIE se enteraba (el cron
-- marcaba "succeeded"). Resultado: `proyeccion_madre` quedó **CONGELADA desde el 21/07**
-- y una porción creciente del catálogo caía al Excel (cobertura 112/190 = 59%).
--
-- ── LOS DOS ARREGLOS ─────────────────────────────────────────────────────────
-- (A) PáginaLK — se le subió el techo SÓLO a esa función (no cambia resultados):
--        alter function public.fn_proyeccion_madre_emp(text) set statement_timeout to '60s';
--     (migración `proyeccion_madre_emp_statement_timeout` en el proyecto kwkclwhmoygunqmlegrg).
-- (B) Virgilio — `refresh_proyeccion_madre()` (abajo):
--        • si el GET falla (HTTP<>200 o vacío) AVISA por Telegram y NO pisa la proyección
--          buena (el generador sigue con la última válida) — se acabó el fallo en silencio;
--        • cron pasó de MENSUAL (día 5) a SEMANAL los miércoles 06:00 AR, 1 h antes de la
--          generación de OCs (07:00 AR) → la proyección llega fresca a cada generación.
--
-- Tras el arreglo: refresco a **357 códigos** (antes 216, frozen) y la cobertura del
-- generador saltó a **165/190 = 87%** (quedan 25 sin ventas → fallback Excel, inevitable
-- porque para esos no hay demanda en ningún lado).
--
-- ⚠ La definición VIVA está en las migraciones de Supabase; esta es la copia del repo.
-- =====================================================================
create or replace function public.refresh_proyeccion_madre()
returns integer language plpgsql security definer set search_path to 'public' as $fn$
declare
  resp public.http_response;
  body jsonb;
  n integer;
  v_err text;
  v_dia text := to_char((now() at time zone 'America/Argentina/Buenos_Aires'), 'YYYYMMDD');
  k constant text := '<ANON_KEY_DE_PAGINALK>';   -- misma anon key que ya usaba la función
begin
  begin
    resp := public.http(('GET',
      'https://kwkclwhmoygunqmlegrg.supabase.co/rest/v1/rpc/fn_proyeccion_oc_virgilio',
      array[ public.http_header('apikey', k), public.http_header('Authorization', 'Bearer ' || k) ],
      null, null)::public.http_request);
  exception when others then
    resp := null; v_err := 'excepción HTTP: ' || coalesce(sqlerrm, '?');
  end;

  if resp is null or resp.status <> 200 then
    v_err := coalesce(v_err, 'HTTP ' || coalesce(resp.status::text, '?') || ' — ' || left(coalesce(resp.content, ''), 180));
    begin
      perform public.tg_enqueue(
        '🚨 PROYECCIÓN NO ACTUALIZADA — ' || to_char((now() at time zone 'America/Argentina/Buenos_Aires'), 'DD/MM') || E'\n' ||
        'El generador de OCs sigue con la última proyección buena. Motivo: ' || v_err || E'\n' ||
        'Revisá el motor fn_proyeccion_oc_virgilio en "loekemeyer''s web".',
        'projmadre_fail_' || v_dia);
      perform public.tg_outbox_flush();
    exception when others then null; end;
    raise notice 'refresh_proyeccion_madre: %', v_err;
    return -1;
  end if;

  body := resp.content::jsonb;
  if jsonb_typeof(body) <> 'array' or jsonb_array_length(body) = 0 then
    begin
      perform public.tg_enqueue(
        '🚨 PROYECCIÓN NO ACTUALIZADA — ' || to_char((now() at time zone 'America/Argentina/Buenos_Aires'), 'DD/MM') || E'\n' ||
        'El motor de proyección devolvió una respuesta vacía o inesperada. El generador de OCs sigue con la última proyección buena.',
        'projmadre_fail_' || v_dia);
      perform public.tg_outbox_flush();
    exception when others then null; end;
    raise notice 'refresh_proyeccion_madre: respuesta vacia/inesperada';
    return -1;
  end if;

  delete from public.proyeccion_madre;
  insert into public.proyeccion_madre (cod, proy_cajas_mes, uxb, proy_uni_mes, actualizado)
  select upper(btrim(x.cod)), x.proy_cajas_mes, x.uxb, x.proy_uni_mes, now()
  from jsonb_to_recordset(body) as x(cod text, proy_cajas_mes numeric, uxb integer, proy_uni_mes numeric)
  where x.proy_cajas_mes > 0 and coalesce(btrim(x.cod), '') <> '';
  get diagnostics n = row_count;
  return n;
end $fn$;

-- Semanal, miércoles 06:00 AR (09:00 UTC), 1 h antes de la generación de OCs (07:00 AR).
select cron.unschedule('refresh_proyeccion_madre');
select cron.schedule('refresh_proyeccion_madre', '0 9 * * 3', $$select public.refresh_proyeccion_madre();$$);
