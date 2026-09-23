-- v21.58 (Marianela, 2026-09-23): CANDADO al código de una tanda EMPEZADA.
-- "Cuando tengamos una tanda en proceso de picking o armado y la cambio para otro día de
--  programación necesito que le coloques un candado al número de tanda y no deje cambiar el
--  nombre porque los operarios trabajan por nombre de tanda, luego no la encuentran."
--
-- gv_ppp_tanda_mover: si la tanda tiene eventos de operario reales (legajo <> 0/1) y el destino
-- le cambia el código (tanda nueva o fusión adentro de otra), se frena con TANDA_CANDADO.
-- Cambiarle SÓLO el día (p_tanda_destino = null → 'mantiene') sigue andando igual.
-- Se aplica sobre la definición VIVA (pg_get_functiondef), idempotente, y falla si no matchea.
do $$
declare v_def text; v_new text; v_ancla text :=
  E'  select count(*) filter (where n.web), count(*) filter (where not n.web) into v_web, v_isis from _tm_nps n;';
begin
  select pg_get_functiondef('public.gv_ppp_tanda_mover(text,date,text,boolean,text)'::regprocedure) into v_def;
  if v_def like '%TANDA_CANDADO%' then raise notice 'ya aplicado'; return; end if;
  if position(v_ancla in v_def) = 0 then raise exception 'gv_ppp_tanda_mover: no encontré el ancla, no se aplica'; end if;
  v_new := replace(v_def, v_ancla,
    '  -- v21.58 (Marianela): CANDADO. Una tanda con picking/armado empezado NO cambia de código:' || chr(10) ||
    '  -- los operarios la buscan por nombre. Sólo se le cambia el día (modo ''mantiene'').' || chr(10) ||
    '  if v_dest <> v_t and exists (select 1 from public."Registros_Produccion_Virgilio" r' || chr(10) ||
    '       where upper(btrim(split_part(r.texto, ''|'', 1))) = v_t' || chr(10) ||
    '         and coalesce(btrim(r.legajo), '''') not in (''0'',''1'')) then' || chr(10) ||
    '    raise exception ''TANDA_CANDADO: la tanda % ya está en picking o armado y los operarios la buscan por ese nombre. Se le puede cambiar el DÍA, pero conserva el código % (no pasa a %).'', v_t, v_t, v_dest;' || chr(10) ||
    '  end if;' || chr(10) || chr(10) || v_ancla);
  execute v_new;
end $$;

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_ppp_tanda_mover', 'funcion', 'TANDA_CANDADO',
        'una tanda con picking/armado empezado no cambia de código al moverla de día', 'Marianela', 'v21.58');

-- Rollback: volver a crear la función desde pg_get_functiondef sacando el bloque "v21.58 (Marianela): CANDADO".
