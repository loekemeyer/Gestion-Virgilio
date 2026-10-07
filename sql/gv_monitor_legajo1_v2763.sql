-- v27.63 (Thomas, D13, 06/10/2026): el legajo 1 (prueba) CUENTA en el monitor.
-- Desde la v27.58 cada registro con legajo 1 se confirma en el celular («¿querés que esto se REGISTRE de
-- verdad?»), así que lo que entra es a propósito. gv_monitor_horas_operario_dia deja de excluirlo
-- (eventos y movimientos de racks). El 0 sigue excluido. NO cambia: gv_horas_operario_detalle_v2 (planilla de
-- horas de Elías), productividad, alarma de inactividad ni reportes: ahí el 1 sigue siendo prueba.
-- Historia: el legajo 1 tiene 19 eventos viejos (may-sep); sólo aparecen si se mira ese día en el monitor.
-- Idempotente sobre la definición viva; falla si el texto no matchea. Huella re-congelada abajo.
-- REGLA_CONFIRMADA_POR_USUARIO
do $q$ declare d text; v text := $v$not in ('', '0', '1')$v$; n int;
begin
  d := pg_get_functiondef('public.gv_monitor_horas_operario_dia(date)'::regprocedure);
  if position('v27.59-leg1' in d) > 0 then return; end if;
  n := (length(d) - length(replace(d, v, ''))) / length(v);
  if n <> 2 then raise exception 'esperaba 2 apariciones, hay %', n; end if;
  d := replace(d, v, $v$not in ('', '0')  /* v27.59-leg1: el 1 cuenta (Thomas D13) */$v$);
  execute d;
end $q$;
-- Rollback: el mismo bloque con los textos intercambiados (y la huella al md5 anterior).
