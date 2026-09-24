-- v22.17 (Luis, 2026-09-24, problema 528) — CUARENTENA: freno también en la programación A MANO,
-- y el pedido liberado se REEVALÚA en vez de volver solo a su tanda previa.
--
-- Caso: LK 1475 · Oriental Party (LK 1618), retenido por deuda ($3.222.078,75). El 24/09 entre
-- 10:01:21 y 10:03:43 gv_cuarentena_marcar le dio 500 siete veces al navegador; A Programar lo
-- dibujó como sano y a las 10:03:38 se programó a mano (terminó en E92A). El freno de la v20.95
-- vivía SÓLO en el armado automático.
--
-- Tres cambios, los tres aplicados sobre la definición VIVA (pg_get_functiondef), idempotentes
-- (marcador `v22.17-cuar`) y con raise si el texto no matchea:
--   1. gv_ppp_web_tanda_programar: antes de programar, gv_cuarentena_retiene_lote sobre los
--      pedidos de la tanda. Retenido sin aprobación → error. Si no se pudo evaluar → error
--      (fail-closed, igual que el armador). Es el único camino manual de "tanda nueva".
--   2. gv_ppp_web_tanda_reusar: el mismo freno (devolver un retenido a su tanda previa a mano).
--   3. gv_cuarentena_liberar: al aprobar, se borra la memoria de GV_PPP_Web_Retenido de ese
--      pedido. Sin ella el pase (a0b) ya no lo saltea y el armador lo reprograma con la lógica
--      normal (día por grupo de zonas, tanda por camión), en vez de devolverlo a ciegas a la
--      tanda de la que salió.

do $apply$
declare
  d text; n text;
begin
  ------------------------------------------------------------------ 1) tanda_programar
  d := pg_get_functiondef('public.gv_ppp_web_tanda_programar(text,text,date,jsonb,text)'::regprocedure);
  if position('v22.17-cuar' in d) = 0 then
    n := replace(d,
      '  v_min    date := public.gv_ppp_web_dia_minimo();',
      '  v_min    date := public.gv_ppp_web_dia_minimo();' || chr(10) ||
      '  _cq_filas jsonb;' || chr(10) ||
      '  _cq_msg   text;' || chr(10) ||
      '  _cq_err   boolean;');
    n := replace(n,
      '  if v_n = 0 then raise exception ''La tanda % está vacía.'', p_codigo; end if;',
      '  if v_n = 0 then raise exception ''La tanda % está vacía.'', p_codigo; end if;' || chr(10) || chr(10) ||
      '  -- v22.17-cuar (Luis, 24/09, problema 528): la programación A MANO tampoco puede meter un pedido' || chr(10) ||
      '  -- retenido por Cuarentena / Cliente nuevo sin aprobación humana. Mismo criterio que el armador' || chr(10) ||
      '  -- (gv_cuarentena_retiene_lote, fail-closed): si no se puede evaluar, no se programa.' || chr(10) ||
      '  select jsonb_agg(distinct jsonb_build_object(''order_id'', i.order_id::text, ''cod'', btrim(i.cod_cliente),' || chr(10) ||
      '                                             ''razon_social'', i.razon_social))' || chr(10) ||
      '    into _cq_filas' || chr(10) ||
      '    from public."PPP_Web_Tanda_Items" i where i.empresa = p_empresa and i.codigo = p_codigo;' || chr(10) ||
      '  select string_agg(distinct ''web '' || upper(p_empresa) || '' '' || _cq_q.order_id || coalesce('' · '' || _cq_i.razon_social, '''') ||' || chr(10) ||
      '                    '' ('' || array_to_string(_cq_q.motivos, '', '') || '')'', ''; ''),' || chr(10) ||
      '         bool_or(''no_se_pudo_evaluar'' = any(_cq_q.motivos) or ''sin_permiso'' = any(_cq_q.motivos))' || chr(10) ||
      '    into _cq_msg, _cq_err' || chr(10) ||
      '    from public.gv_cuarentena_retiene_lote(p_empresa, coalesce(_cq_filas, ''[]''::jsonb)) _cq_q' || chr(10) ||
      '    left join public."PPP_Web_Tanda_Items" _cq_i' || chr(10) ||
      '      on _cq_i.empresa = p_empresa and _cq_i.codigo = p_codigo and _cq_i.order_id = _cq_q.order_id;' || chr(10) ||
      '  if _cq_msg is not null then' || chr(10) ||
      '    if _cq_err then' || chr(10) ||
      '      raise exception ''No se pudo verificar la cuarentena en este momento: no se programó nada. Probá de nuevo en unos segundos.'' using errcode = ''P0001'';' || chr(10) ||
      '    end if;' || chr(10) ||
      '    raise exception ''CUARENTENA: % está retenido y nadie lo aprobó. Liberalo desde Cuarentena (o el pipeline de Clientes nuevos) antes de programarlo.'', _cq_msg using errcode = ''P0001'';' || chr(10) ||
      '  end if;');
    if n = d or position('_cq_err   boolean' in n) = 0 then
      raise exception 'tanda_programar: el texto vivo no matchea, no se aplicó';
    end if;
    execute n;
  end if;

  ------------------------------------------------------------------ 2) tanda_reusar
  d := pg_get_functiondef('public.gv_ppp_web_tanda_reusar(text,bigint,date,text)'::regprocedure);
  if position('v22.17-cuar' in d) = 0 then
    n := replace(d,
      '  v_n int := 0; v_tandas text; r record;',
      '  v_n int := 0; v_tandas text; r record;' || chr(10) ||
      '  _cq_msg text; _cq_err boolean;');
    n := replace(n,
      '  if p_fecha is null then raise exception ''Falta el dia de entrega.''; end if;',
      '  if p_fecha is null then raise exception ''Falta el dia de entrega.''; end if;' || chr(10) || chr(10) ||
      '  -- v22.17-cuar (Luis, 24/09, problema 528): devolver a su tanda un pedido retenido por' || chr(10) ||
      '  -- Cuarentena / Cliente nuevo sin aprobación tampoco se puede. Mismo criterio que el armador.' || chr(10) ||
      '  select string_agg(distinct array_to_string(_cq_q.motivos, '', ''), '', ''),' || chr(10) ||
      '         bool_or(''no_se_pudo_evaluar'' = any(_cq_q.motivos) or ''sin_permiso'' = any(_cq_q.motivos))' || chr(10) ||
      '    into _cq_msg, _cq_err' || chr(10) ||
      '    from public.gv_cuarentena_retiene_lote(v_emp,' || chr(10) ||
      '           (select jsonb_agg(distinct jsonb_build_object(''order_id'', w.order_id::text, ''cod'', btrim(w.cod_cliente)))' || chr(10) ||
      '              from public."PPP_Web_Programacion" w where w.empresa = v_emp and w.order_id = p_order_id)) _cq_q;' || chr(10) ||
      '  if _cq_msg is not null then' || chr(10) ||
      '    if _cq_err then' || chr(10) ||
      '      raise exception ''No se pudo verificar la cuarentena en este momento: no se programó nada. Probá de nuevo en unos segundos.'' using errcode = ''P0001'';' || chr(10) ||
      '    end if;' || chr(10) ||
      '    raise exception ''CUARENTENA: el pedido web % % está retenido (%) y nadie lo aprobó. Liberalo desde Cuarentena antes de programarlo.'', upper(v_emp), p_order_id, _cq_msg using errcode = ''P0001'';' || chr(10) ||
      '  end if;');
    if n = d or position('_cq_msg text; _cq_err boolean;' in n) = 0 or position('v22.17-cuar' in n) = 0 then
      raise exception 'tanda_reusar: el texto vivo no matchea, no se aplicó';
    end if;
    execute n;
  end if;

  ------------------------------------------------------------------ 3) cuarentena_liberar
  d := pg_get_functiondef('public.gv_cuarentena_liberar(text,text,text[],text,text,text,text)'::regprocedure);
  if position('v22.17-cuar' in d) = 0 then
    n := replace(d,
      '  select l.np, l.cod, l.razon_social into v_np, v_cod, v_rs',
      '  -- v22.17-cuar (Luis, 24/09): "si lo libero dice que lo va a volver a poner en E92A. Debería' || chr(10) ||
      '  -- reevaluar". Aprobado, el pedido olvida la tanda de la que lo sacaron: sin la fila de' || chr(10) ||
      '  -- GV_PPP_Web_Retenido el pase (a0b) ya no lo saltea y el armador lo programa con la lógica' || chr(10) ||
      '  -- normal (día por grupo de zonas, tanda por camión). Sólo pedidos web (order_id numérico).' || chr(10) ||
      '  if v_clave ~ ''^[0-9]+$'' then' || chr(10) ||
      '    delete from public."GV_PPP_Web_Retenido" t' || chr(10) ||
      '     where t.empresa = lower(p_empresa) and t.order_id = v_clave::bigint;' || chr(10) ||
      '  end if;' || chr(10) || chr(10) ||
      '  select l.np, l.cod, l.razon_social into v_np, v_cod, v_rs');
    if n = d then raise exception 'cuarentena_liberar: el texto vivo no matchea, no se aplicó'; end if;
    execute n;
  end if;
end $apply$;

-- Centinelas (las tres reglas no se pueden perder)
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
select * from (values
  ('gv_ppp_web_tanda_programar','funcion','gv_cuarentena_retiene_lote',
   'la programacion a mano no mete un pedido retenido por cuarentena/cliente nuevo sin aprobacion','Luis','v22.17'),
  ('gv_ppp_web_tanda_reusar','funcion','gv_cuarentena_retiene_lote',
   'devolver un retenido a su tanda a mano tambien pasa por el freno de cuarentena','Luis','v22.17'),
  ('gv_cuarentena_liberar','funcion','delete from public\."GV_PPP_Web_Retenido"',
   'al liberar de cuarentena el pedido se reevalua: no vuelve solo a su tanda previa','Luis','v22.17')
) v(objeto, clase, patron, regla, quien_pidio, version)
where not exists (select 1 from public."GV_Reglas_Centinela" c where c.objeto = v.objeto and c.patron = v.patron);
