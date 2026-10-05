-- v27.07 (Thomas, 05/10): el RESUMEN DE AGENTES de Telegram (cron 23, 19:00 ART) muestra SÓLO
-- lo de severidad 'alta' (problemas graves y errores de código). Lo media/baja (seguimiento del
-- día a día) sigue en la app, solapa 🤖 Agentes, pero no sale por Telegram.
-- Se aplica sobre la definición VIVA, idempotente (marcador v27.07-solo-alta), y falla si no matchea.
do $$
declare d text := pg_get_functiondef('public.reporte_agentes_resumen_telegram(boolean)'::regprocedure); n text;
begin
  if d like '%v27.07-solo-alta%' then raise notice 'ya aplicado'; return; end if;
  n := replace(d, $a$      where (generado_at at time zone 'America/Argentina/Buenos_Aires')::date = hoy
$a$, $a$      where (generado_at at time zone 'America/Argentina/Buenos_Aires')::date = hoy
        and severidad = 'alta'   -- v27.07-solo-alta: el día a día (media/baja) no sale por Telegram
$a$);
  n := replace(n, $a$msg := msg || '🔴 ' || n_a || ' alta · 🟡 ' || n_m || ' media · 🟢 ' || n_b || ' baja' || E'\n';$a$,
                  $a$msg := msg || '🔴 ' || n_a || ' problema(s) grave(s) o de código' || E'\n';$a$);
  n := replace(n, $a$✅ Sin alertas hoy. Todo en orden.$a$, $a$✅ Sin problemas graves ni de código hoy.$a$);
  if n = d or n not like '%v27.07-solo-alta%' or n not like '%problema(s) grave(s)%' then
    raise exception 'reporte_agentes_resumen_telegram: el texto vivo no matchea, no se aplicó';
  end if;
  execute n;
end $$;
-- prueba (no encola): select public.reporte_agentes_resumen_telegram(false);
-- rollback: sacar la línea "and severidad = 'alta'" y volver el encabezado a "alta · media · baja".
