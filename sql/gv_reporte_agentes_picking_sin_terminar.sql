-- idea 1471 (Gestión Virgilio, 2026-09-05): alerta "picking empezado sin terminar" (EP abierto
-- > 24 h sin TP), espejo de armado_sin_terminar (generar_reporte_agentes_v2.sql, bloque 15).
--
-- Por la regla del dueño sobre objetos compartidos NO se toca generar_reporte_agentes() (la usa
-- Producción): es una función NUEVA con prefijo gv_ y un cron PROPIO que corre 2 minutos después
-- del job 14 (generar_reporte_agentes borra reporte_agentes entera al arrancar, así que hay que
-- correr después). Sólo AGREGA filas a reporte_agentes; borra únicamente las de su categoría.
--
-- Producción: su panel Agentes no conoce la clave → no la muestra; el resumen Telegram de las
-- 22:00 (reporte_agentes_resumen_telegram) la lista por su clave, como "media".
-- Gestión: la renderiza en 🤖 Agentes (CATS, v13.00) y la suma al briefing "Hoy".
--
-- Apagar:  select cron.unschedule('gv-reporte-agentes-picking-sin-terminar');
-- Borrar:  drop function public.gv_reporte_agentes_picking_sin_terminar();
--          delete from public.reporte_agentes where categoria = 'picking_sin_terminar';
create or replace function public.gv_reporte_agentes_picking_sin_terminar()
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  delete from public.reporte_agentes where categoria = 'picking_sin_terminar';
  insert into public.reporte_agentes (categoria, severidad, titulo, detalle, valor, ts_evento)
  with ep as (
    select upper(btrim(split_part(texto, '|', 1))) as tanda, max(created_at) as ts, max(legajo) as legajo
    from public."Registros_Produccion_Virgilio"
    where opcion = 'EP' and created_at > now() - interval '7 days'
      and coalesce(legajo, '') not in ('0', '1') and btrim(split_part(texto, '|', 1)) <> ''
    group by upper(btrim(split_part(texto, '|', 1)))
  ),
  tp as (select distinct upper(btrim(split_part(texto, '|', 1))) as tanda
         from public."Registros_Produccion_Virgilio" where opcion = 'TP' and created_at > now() - interval '7 days')
  select 'picking_sin_terminar', 'media', 'Tanda ' || ep.tanda,
         'picking empezado hace ' || round(extract(epoch from (now() - ep.ts)) / 3600)
           || ' h y SIN terminar (TP) · legajo ' || coalesce(ep.legajo, '?'),
         round(extract(epoch from (now() - ep.ts)) / 3600), ep.ts
  from ep left join tp on tp.tanda = ep.tanda
  where tp.tanda is null and ep.ts < now() - interval '24 hours' order by ep.ts limit 20;
end $function$;

revoke all on function public.gv_reporte_agentes_picking_sin_terminar() from public, anon, authenticated;

-- Cron (UTC): 11:02, 15:02 y 19:02 = 08:02, 12:02 y 16:02 ART, 2 min después del job 14.
select cron.schedule('gv-reporte-agentes-picking-sin-terminar', '2 11,15,19 * * *',
  $$select public.gv_reporte_agentes_picking_sin_terminar();$$);
