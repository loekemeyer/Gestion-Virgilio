-- =====================================================================
--  reporte_semanal.sql — Reporte SEMANAL por Telegram (v4.80)
--
--  Lunes 8:00 AR (cron 'reporte-semanal-telegram', 0 11 * * 1 UTC) manda el resumen
--  de la semana que terminó: total del equipo (m³, armadas, pickeadas), mejor
--  pickeando / armando (piso 5 tandas), y una TABLA monoespaciada por operario con
--  m³ pick/arm, ritmo m³/h pick/arm, y TENDENCIA vs la semana anterior (↑/↓/=).
--  Usa vista_productividad_semanal (m³ válido, mismo método que la pantalla 📊).
--
--  reporte_semanal_telegram(p_lunes date default null, p_enqueue boolean default true)
--  Probar:  select public.reporte_semanal_telegram(date '2026-06-22', false);
--  Cuerpo completo aplicado por migración. Tabla vía parse_mode=HTML (<pre>).
-- =====================================================================

select cron.schedule('reporte-semanal-telegram', '0 11 * * 1',
  'select public.reporte_semanal_telegram();');
