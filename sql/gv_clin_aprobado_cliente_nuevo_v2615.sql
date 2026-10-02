-- v26.15 (Luis, 02/10/2026): «si está aprobado, ¿por qué sigue apareciendo ahí?»
--
-- El pipeline de Clientes nuevos decía «✅ Aprobado — ya está en «Pedidos a programar»» con
-- CUALQUIER fila de GV_Cuarentena_Liberados, sin mirar QUÉ motivo levantó esa liberación.
--
-- Caso LK 1576 · Hsu Ya Wen (LK 4172), 3.er pedido de cliente nuevo:
--   30/09 11:05  entra a Cuarentena por límite de crédito + cliente nuevo
--   30/09 11:41  Vivi libera SÓLO el límite (motivos = {limite_credito}) — correcto, regla v20.86:
--                el botón de Cuarentena nunca libera cliente_nuevo
--   30/09 11:42  vuelve a entrar, ya sólo por cliente_nuevo → cae al pipeline (correcto)
--   el pipeline ve la fila de Liberados y lo pinta «Aprobado», SIN botones. El armador, en cambio,
--   lo sigue reteniendo (gv_cuarentena_marcar_calc resta sólo el límite). Resultado: 2 días parado,
--   sin ninguna acción posible, con un cartel que decía lo contrario.
--
-- La regla: «Aprobado» en el pipeline = liberación que LEVANTA cliente_nuevo. Es el mismo criterio
-- que ya usa gv_cuarentena_marcar_calc: motivos NULL o vacío (liberación vieja, sin detalle = libera
-- todo) o motivos que incluyen 'cliente_nuevo'.
--
-- Se aplica sobre la definición VIVA (pg_get_functiondef), es idempotente (marcador v26.15-clin-aprob)
-- y falla con un raise si el texto no matchea, en vez de escribir una versión vieja encima.
-- Las reglas de GV_Reglas_Centinela de estas dos funciones (decision_ef, ped_prev >= 1,
-- GV_Clientes_Nuevos_Contacto, referenciado) no se tocan.

do $patch$
declare
  v_def text; v_new text;
begin
  -- 1) gv_clin_pipeline_lote: la columna `aprobado`
  v_def := pg_get_functiondef('public.gv_clin_pipeline_lote(jsonb)'::regprocedure);
  if position('v26.15-clin-aprob' in v_def) = 0 then
    v_new := regexp_replace(v_def,
      '(and public\.gv_cuarentena_clave\(lb\.order_id\) = p\.order_id)\) as aprobado,',
      E'\\1\n                      -- v26.15-clin-aprob (Luis, 02/10): sólo la liberación que levanta cliente_nuevo\n'
      || E'                      and (lb.motivos is null or coalesce(array_length(lb.motivos, 1), 0) = 0\n'
      || E'                           or ''cliente_nuevo'' = any (lb.motivos))) as aprobado,');
    if v_new = v_def then
      raise exception 'gv_clin_pipeline_lote: el texto de `aprobado` no matchea, no se aplica nada';
    end if;
    execute v_new;
  end if;

  -- 2) gv_clin_evento: v_apro (la etapa que devuelve después de cada botón)
  v_def := pg_get_functiondef('public.gv_clin_evento(text,text,text,text,text,text,text,text,text)'::regprocedure);
  if position('v26.15-clin-aprob' in v_def) = 0 then
    v_new := regexp_replace(v_def,
      '(where lb\.empresa = v_emp and public\.gv_cuarentena_clave\(lb\.order_id\) = v_clave)\);',
      E'\\1\n                       -- v26.15-clin-aprob (Luis, 02/10): sólo la liberación que levanta cliente_nuevo\n'
      || E'                       and (lb.motivos is null or coalesce(array_length(lb.motivos, 1), 0) = 0\n'
      || E'                            or ''cliente_nuevo'' = any (lb.motivos)));');
    if v_new = v_def then
      raise exception 'gv_clin_evento: el texto de `v_apro` no matchea, no se aplica nada';
    end if;
    execute v_new;
  end if;
end
$patch$;

-- 3) Las dos vistas hermanas tenían el MISMO criterio (cualquier fila de Liberados = aprobado):
--    gv_clin_vencidos escondía de la alarma de vencidos al pedido liberado sólo por otro motivo, y
--    gv_clin_prioritarios lo listaba como «tiene que salir en 2 días hábiles» estando retenido.
--    No están en GV_Reglas_Centinela. CREATE OR REPLACE VIEW borra las reloptions: se repone
--    security_invoker en el mismo bloque.
do $patch_vistas$
declare
  v_def text; v_new text;
begin
  v_def := pg_get_viewdef('public.gv_clin_vencidos'::regclass, true);
  if position('cliente_nuevo' in v_def) = 0 then
    v_new := regexp_replace(v_def,
      '(WHERE lb\.empresa = p\.empresa AND gv_cuarentena_clave\(lb\.order_id\) = p\.order_id)\)\)\) AS etapa',
      '\1 AND (lb.motivos IS NULL OR COALESCE(array_length(lb.motivos, 1), 0) = 0 OR ''cliente_nuevo''::text = ANY (lb.motivos))))) AS etapa');
    if v_new = v_def then raise exception 'gv_clin_vencidos: no matchea, no se aplica nada'; end if;
    execute 'create or replace view public.gv_clin_vencidos as ' || v_new;
    execute 'alter view public.gv_clin_vencidos set (security_invoker = true)';
  end if;

  v_def := pg_get_viewdef('public.gv_clin_prioritarios'::regclass, true);
  if position('cliente_nuevo' in v_def) = 0 then
    v_new := regexp_replace(v_def,
      '(JOIN "GV_Cuarentena_Liberados" lb ON lb\.empresa = p\.empresa AND gv_cuarentena_clave\(lb\.order_id\) = p\.order_id)',
      '\1 AND (lb.motivos IS NULL OR COALESCE(array_length(lb.motivos, 1), 0) = 0 OR ''cliente_nuevo''::text = ANY (lb.motivos))');
    if v_new = v_def then raise exception 'gv_clin_prioritarios: no matchea, no se aplica nada'; end if;
    execute 'create or replace view public.gv_clin_prioritarios as ' || v_new;
    execute 'alter view public.gv_clin_prioritarios set (security_invoker = true)';
  end if;
end
$patch_vistas$;

-- Centinela (patrón del CÓDIGO, no del comentario: el comentario no dice 'cliente_nuevo' = any):
-- insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version) values
--  ('gv_clin_pipeline_lote','funcion','''cliente_nuevo'' = any \(lb\.motivos\)',
--   'Aprobado en el pipeline = liberacion que levanta cliente_nuevo, no cualquier fila de Liberados (LK 1576: liberado por limite quedo sin botones).',
--   'Luis','v26.15'),
--  ('gv_clin_evento','funcion','''cliente_nuevo'' = any \(lb\.motivos\)',
--   'Aprobado en el pipeline = liberacion que levanta cliente_nuevo, no cualquier fila de Liberados (LK 1576).',
--   'Luis','v26.15');

-- Chequeo: LK 1576 tiene que salir en 'no_referenciado' (recurrente, 2 pedidos previos), no 'aprobado'.
-- select etapa, aprobado from public.gv_clin_pipeline_lote('[{"empresa":"lk","order_id":"1576","cod":"4172"}]'::jsonb);
-- select * from public.gv_reglas_perdidas;   -- vacía = todo bien

-- Rollback: volver a correr el bloque sacando la línea `and (lb.motivos ...)` (o pg_get_functiondef y
-- quitar las tres líneas con el marcador v26.15-clin-aprob).
