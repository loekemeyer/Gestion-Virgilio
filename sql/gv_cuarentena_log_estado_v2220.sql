-- v22.20 (Luis, 24/09): el log de Cuarentena (Configuracion Cuarentena) calcula el estado al leer.
-- Hasta hoy solo se cerraba con un evento explicito (aprobado/devuelto/anulado) o una cancelacion.
-- Un pedido que salio igual, o que dejo de retener solo (pago la deuda, entro una excepcion),
-- quedaba "retenido" para siempre: al 24/09 eran 7 de los 10 "retenidos".
-- Estados nuevos (no se escribe nada, se calculan):
--   salio          -> tiene Facturacion_NP (por la NP o por la clave de ISIS)
--   liberado_solo  -> hoy gv_cuarentena_marcar_calc ya no lo retiene
-- `vivos` evalua TODOS los abiertos en UNA llamada (por fila tardaba 7,8 s; asi 1,6 s, y baja
-- cuando se aplique sql/gv_cuar_mismo_pedido_rapido_v2217.sql).
-- Parche sobre pg_get_functiondef (definicion viva), idempotente, falla si no matchea.
do $parche$
declare d text; n text; old_case text; new_case text; old_cte text; new_cte text;
begin
  d := pg_get_functiondef('public.gv_cuarentena_log(integer)'::regprocedure);
  if d ~ 'liberado_solo' then raise notice 'ya aplicado'; return; end if;
  old_cte := $o$    from det d
  )
  select r.empresa, r.k,$o$;
  new_cte := $o$    from det d
  ),
  -- v22.20: lo que HOY sigue retenido, UNA sola evaluación para todos los abiertos (el mismo
  -- criterio que la pantalla: gv_cuarentena_marcar_calc).
  vivos as (
    select x.empresa, public.gv_cuarentena_clave(x.order_id) as k
      from public.gv_cuarentena_marcar_calc((
        select coalesce(jsonb_agg(jsonb_build_object(
                 'order_id', case when r.es_isis or r.k ~ '^[0-9]{5,}$' then 'np' || r.k else r.k end,
                 'empresa', r.empresa, 'cod', r.cod_r)), '[]'::jsonb)
          from res r
         where coalesce(r.ult_evento, '') not in ('aprobado', 'devuelto', 'anulado'))) x
  )
  select r.empresa, r.k,$o$;
  old_case := $o$              when r.ult_evento = 'devuelto' then 'devuelto'
              else 'retenido' end,$o$;
  new_case := $o$              when r.ult_evento = 'devuelto' then 'devuelto'
              -- v22.20 (Luis, 24/09): el log sólo se cerraba con un evento explícito. Un pedido que
              -- salió igual, o que dejó de retener solo (pagó la deuda, entró una excepción), quedaba
              -- "retenido" para siempre. Se calcula al leer, no se escribe nada.
              when exists (select 1 from public."Facturacion_NP" f
                            where upper(btrim(f.np)) in (upper(btrim(coalesce(r.np, ''))), r.k)) then 'salio'
              when not exists (select 1 from vivos v where v.empresa = r.empresa and v.k = r.k) then 'liberado_solo'
              else 'retenido' end,$o$;
  if position(old_case in d) = 0 or position(old_cte in d) = 0 then
    raise exception 'gv_cuarentena_log: el texto no matchea (la toco otra sesion)';
  end if;
  n := replace(replace(d, old_case, new_case), old_cte, new_cte);
  execute n;
end $parche$;

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_cuarentena_log','funcion','liberado_solo',
        'el log calcula al leer si un retenido ya salio o se libero solo','Luis','v22.20');
