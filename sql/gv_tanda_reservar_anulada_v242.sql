-- v24.2 (29/09, Marianela, problema 623): anular picking/armado no liberaba el candado de la tanda.
-- D69H: TP/TAP del 16/09 (de LK 0058) anulados como TPX/TAPX, pero GV_Tandas_Lock quedó 'completada':
-- gv_tanda_reservar contestaba ya_completada y nadie podía pickear LK 0083.
-- Arreglo: si la fase está 'completada', NO hay TP/TAP vivo de la tanda y SÍ hay TPX/TAPX, el candado
-- se vuelve a tomar como nuevo. Con TP/TAP vivo sigue 'ya_completada' (probado: E51A -> propia, F17D -> ya_completada).
-- Centinela: GV_Reglas_Centinela patrón '_tr_anulada'. El candado de D69H se borró a mano antes
-- (backup zz_backups."GV_Backup_TandasLock_D69H_20260929").
do $x$ declare d text; n text;
begin
  d := pg_get_functiondef('public.gv_tanda_reservar(text,text,text,text)'::regprocedure);
  if d ~ '_tr_anulada' then raise notice 'ya aplicado'; return; end if;
  n := replace(d, $o$  select * into r from public."GV_Tandas_Lock" where tanda = t and fase = f;

  if r.estado = 'completada' then$o$,
  $n$  select * into r from public."GV_Tandas_Lock" where tanda = t and fase = f;

  if r.estado = 'completada'
     and not exists (select 1 from public."Registros_Produccion_Virgilio" _tr_vivo
                      where _tr_vivo.opcion = case f when 'picking' then 'TP' else 'TAP' end
                        and upper(btrim(split_part(_tr_vivo.texto,'|',1))) = t)
     and exists (select 1 from public."Registros_Produccion_Virgilio" _tr_anulada
                  where _tr_anulada.opcion = case f when 'picking' then 'TPX' else 'TAPX' end
                    and upper(btrim(split_part(_tr_anulada.texto,'|',1))) = t) then
    update public."GV_Tandas_Lock"
       set estado = 'tomada', legajo = nullif(l,''), nombre = nullif(btrim(coalesce(p_nombre,'')),''),
           ts = now(), ts_estado = now()
     where tanda = t and fase = f;
    select * into r from public."GV_Tandas_Lock" where tanda = t and fase = f;
  end if;

  if r.estado = 'completada' then$n$);
  if n = d then raise exception 'no matchea'; end if;
  execute n;
end $x$;
