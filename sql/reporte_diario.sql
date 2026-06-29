-- =====================================================================
--  reporte_diario.sql — Reporte diario por Telegram (v4.78)
--
--  Cada día a las 18:00 AR (cron 'reporte-diario-telegram', 0 21 * * * UTC) manda
--  al grupo de Telegram un resumen del día con:
--    • Producción del día: m³ totales (picking + armado).
--    • PPP pendiente (m³ + pedidos) y hasta qué fecha llega la PPP (días hábiles)
--      + cuánto hay sin fecha asignada.
--    • Ritmo necesario (m³/día = pendiente ÷ días hasta la última fecha) y si la
--      producción del día lo cubrió / sobrepasó / quedó por debajo.
--    • Días para terminar la PPP al ritmo REAL (m³ armado/día) y si alcanza vs PPP.
--    • Pedidos con fecha muy lejana (outliers > hoy+21d) — los "viejos" a revisar.
--    • Rendimiento por operario (sólo los que trabajaron ese día): m³ pick/arm + m³/h,
--      como TABLA monoespaciada (HTML <pre>) para que las columnas queden alineadas.
--
--  Decisiones (confirmadas con el dueño):
--    • "Cubrir lo proyectado" = contra el RITMO NECESARIO (no contra lo del día solo).
--    • "Días según PPP" = hasta la última fecha programada (sin outliers) + lo sin fecha.
--    • Hora de envío: 18:00 AR.
--    • m³ VOLUMEN (producción + tabla) = todo lo cerrado en el día (incluye cierres
--      cross-day como C57A=10,3 m³). El m³/h (ritmo) usa sólo cierres mismo-día válidos
--      (no se puede medir el ritmo de un armado que cruzó la noche).
--
--  Probar un día puntual (sin enviar):  select public.reporte_diario_telegram(date '2026-06-26', false);
--  Mandarlo ahora:                      select public.reporte_diario_telegram(date '2026-06-26', true); select public.tg_outbox_flush();
--
--  Piezas: vista_productividad_diaria (m³ y tiempo efectivo por legajo×día),
--  _es (formato es-AR), reporte_diario_telegram(p_dia, p_enqueue). Ver el cuerpo
--  completo aplicado en Supabase (migraciones vista_productividad_diaria* y
--  reporte_diario_telegram*). Acá queda sólo el enganche del cron como referencia.
-- =====================================================================

-- Cron: 18:00 AR = 21:00 UTC, todos los días.
select cron.schedule('reporte-diario-telegram', '0 21 * * *',
  'select public.reporte_diario_telegram();');

-- Para Lun–Sáb (saltear domingo), sería:  '0 21 * * 1-6'

-- parse_mode: tg_enqueue gana un 4º arg p_parse_mode (default null) y telegram_outbox
-- una columna parse_mode; tg_outbox_flush la agrega al body sólo si está seteada. Así el
-- reporte usa HTML (<pre>) sin tocar las demás alertas (que siguen yendo en texto plano).
-- Escapar SIEMPRE el texto dinámico con _h() cuando se manda con parse_mode=HTML.
