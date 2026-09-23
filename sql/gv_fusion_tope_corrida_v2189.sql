-- v21.89-tope (Luis, 2026-09-23) — el armado de LK cortaba por tiempo en CADA corrida desde ~12:25.
--
-- Medido: con 4 fusiones pendientes (E37B->E37A, E48G->E48C, E48F->E37D, E48A->E18C),
-- gv_ppp_web_fusionar_tandas en modo real tardaba 14.289 ms (~3,5 s por gv_ppp_tanda_renombrar).
-- El armado entero daba 12.673 ms contra el statement_timeout de 8 s -> 57014, se deshacia todo
-- (tambien las fusiones) y la corrida siguiente volvia a intentar lo mismo. LK sin programar
-- desde las 12:20.
--
-- Arreglo (aplicado sobre la definicion viva, idempotente, marcador 'v21.89-tope'):
--   1. gv_ppp_web_fusionar_tandas: en modo real, a lo sumo PPP_Web_Config.tanda_fusion_max_corrida
--      fusiones por llamada (sin fila = 1). Simular no tiene tope.
--   2. gv_ppp_web_armar_pendientes: el pase (e) de fusion corre solo si el armado lleva < 3 s.
-- Probado en transaccion abortada: armado LK 12.673 ms -> 3.413 ms.
--
-- Ver el cuerpo aplicado: select pg_get_functiondef('public.gv_ppp_web_fusionar_tandas'::regproc);

do $p$
declare v text := pg_get_functiondef('public.gv_ppp_web_fusionar_tandas'::regproc); nl text := chr(10);
begin
  if strpos(v, 'v21.89-tope') > 0 then raise notice 'ya'; return; end if;
  if strpos(v, '  v_m3    numeric;' || nl) = 0 or strpos(v, '        perform public.gv_ppp_tanda_renombrar(r_v.code, r_d.code, p_por);' || nl || '      end if;') = 0 then
    raise exception 'marcador no encontrado'; end if;
  v := replace(v, '  v_m3    numeric;' || nl,
    '  v_m3    numeric;' || nl ||
    '  -- v21.89-tope (23/09): cada renombre cuesta ~3,5 s; 4 juntas daban 14 s y el armado de LK' || nl ||
    '  --   cortaba por el statement_timeout de 8 s en CADA corrida (se deshacia todo y volvia a' || nl ||
    '  --   intentar lo mismo). Real: a lo sumo tanda_fusion_max_corrida (default 1) por llamada;' || nl ||
    '  --   las demas las hace la corrida siguiente (cada 5 min). Simular no tiene tope.' || nl ||
    '  v_cap   int := coalesce((select valor from public."PPP_Web_Config" where clave = ''tanda_fusion_max_corrida''), 1)::int;' || nl ||
    '  v_hechas int := 0;' || nl);
  v := replace(v, '        perform public.gv_ppp_tanda_renombrar(r_v.code, r_d.code, p_por);' || nl || '      end if;',
    '        perform public.gv_ppp_tanda_renombrar(r_v.code, r_d.code, p_por);' || nl ||
    '        v_hechas := v_hechas + 1;' || nl ||
    '        if v_hechas >= v_cap then return next; return; end if;' || nl ||
    '      end if;');
  execute v;
end $p$;

do $p$
declare v text := pg_get_functiondef('public.gv_ppp_web_armar_pendientes'::regproc); nl text := chr(10);
  m text := '  if coalesce((select valor from public."PPP_Web_Config" where clave = ''tanda_fusion_activa''), 0) <> 0 then';
begin
  if strpos(v, 'v21.89-tope') > 0 then raise notice 'ya'; return; end if;
  if strpos(v, m) = 0 then raise exception 'marcador no encontrado'; end if;
  v := replace(v, m,
    '  -- v21.89-tope: la fusion va sólo si al armado le sobra tiempo (timeout de 8 s): con más de' || nl ||
    '  --   3 s gastados se deja para la corrida siguiente.' || nl ||
    '  if coalesce((select valor from public."PPP_Web_Config" where clave = ''tanda_fusion_activa''), 0) <> 0' || nl ||
    '     and clock_timestamp() - v_t0 < interval ''3 seconds'' then');
  execute v;
end $p$;
