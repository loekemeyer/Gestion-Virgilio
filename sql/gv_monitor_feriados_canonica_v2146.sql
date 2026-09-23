-- v21.46 · `gv_monitor_horas_operario_dia` deja de tener la lista de feriados adentro
--
-- ⚠ SE PARTE DE LA DEFINICIÓN VIVA, NUNCA DE UNA COPIA. Varias sesiones tocan esta
-- función; un `CREATE OR REPLACE` desde un archivo del repo le borra a otro su cambio
-- sin decir una palabra (problema 390). Por eso esto es un parche de TEXTO sobre
-- `pg_get_functiondef`, es IDEMPOTENTE (si ya lee la canónica no hace nada) y **falla
-- con un `raise` si el texto no matchea**, en vez de escribir una versión vieja encima.

do $mig$
declare def text; nuevo text; viejo text;
begin
  select pg_get_functiondef('public.gv_monitor_horas_operario_dia(date)'::regprocedure) into def;

  if position('GV_Feriados' in def) > 0 then
    raise notice 'ya lee la canonica: no hago nada (idempotente)';
    return;
  end if;

  viejo := substring(def from 'select unnest\(array\[[^]]*\]::date\[\]\) as d');
  if viejo is null then
    raise exception 'no matcheo la lista hardcodeada de feriados: NO escribo una version vieja encima';
  end if;

  nuevo := 'select f.fecha as d from public."GV_Feriados" f where f.tipo = ''feriado''';
  def := replace(def, viejo, nuevo);
  def := replace(def,
    'Espejo de FERIADOS_AR de index.html.',
    'v21.46: lee la CANONICA public."GV_Feriados" (antes era un espejo a mano de FERIADOS_AR de index.html, y las dos listas terminaban el 25/12/2026).');

  execute def;
  raise notice 'OK: la funcion lee GV_Feriados';
end $mig$;

-- ── Y sus centinelas, que es lo que avisa si otra sesión la pisa ──────────────
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version) values
 ('gv_monitor_horas_operario_dia','funcion','GV_Feriados',
  'Los feriados salen de la CANONICA public."GV_Feriados", no de una lista escrita a mano adentro de la funcion. Las tres copias que habia terminaban el 25/12/2026.',
  'Thomas','v21.46'),
 ('gv_monitor_horas_operario_dia','funcion','prod_otros_s',
  'hs_prod = picking + armado + CC/CR/RR. Los tres se miden por DURACION, sin pedir texto y sin deduplicar por tanda. El monitor grande (index.html, PROD_OTROS_CODES) hace lo mismo y tests/mon-vs-vista.cjs compara los dos.',
  'Thomas','v21.46')
on conflict do nothing;

-- Medido: la función devuelve los MISMOS números para el 15/09 leyendo la tabla
-- (5 operarios × 7 columnas), así que `tests/tools/vista-15.json` siguió valiendo.
-- select * from public.gv_reglas_perdidas;    -- vacía = todo bien
-- select * from public.gv_huellas_cambiadas;  -- vacía = todo bien
