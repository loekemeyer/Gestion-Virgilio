-- =====================================================================================
-- sync_proyeccion_madre_virgilio() — VIVE EN EL PROYECTO DE LK (kwkclwhmoygunqmlegrg),
-- no en Virgilio. Se guarda acá porque es el unico camino por el que la Estadistica Madre
-- llega a Gestion, y el 12/09 quedo ROTO sin que nadie lo viera (ver gv_est_madre_una_sola_v1688.sql).
-- Cron: sync-proyeccion-madre-virgilio, '20 9 * * 3' (miercoles 09:20).
-- =====================================================================================
create or replace function public.sync_proyeccion_madre_virgilio()
 returns integer
 language plpgsql
 security definer
 set search_path to 'public'
 set statement_timeout to '120s'
as $function$
declare
  v_n integer;
  v_calc integer;
begin
  -- 1) Calcular primero en una temporal. Si el motor falla o devuelve vacio, se ABORTA
  --    sin tocar Virgilio: mejor una proyeccion vieja que una tabla vaciada.
  --    v16.88: se deja de mandar `uxb`. En Virgilio esa columna se renombro a
  --    uxb_obsoleto_v1629 el 12/09 y la foreign table seguia apuntando a `uxb`, que ya no
  --    existe: este sync estaba ROTO y habria fallado el miercoles 16/09 (ultima corrida
  --    buena, 09/09). En su lugar viaja la DESCRIPCION, para que el nombre del articulo
  --    salga del mismo lugar que el numero y Virgilio pueda dejar de leer las
  --    "E. Madre LK/CH", que nadie refrescaba desde agosto y marzo.
  create temp table _proy_tmp on commit drop as
    select p.cod, p.proy_cajas_mes, p.proy_uni_mes,
           nullif(btrim(c.descripcion), '') as gv_descripcion
    from public.fn_proyeccion_oc_virgilio() p
    left join lateral (
      select e.descripcion
        from public.estadistica_madre_cache e
       where upper(regexp_replace(btrim(e.cod), '^0+(.)', '\1'))
           = upper(regexp_replace(btrim(p.cod), '^0+(.)', '\1'))
         and nullif(btrim(coalesce(e.descripcion,'')),'') is not null
       limit 1) c on true
    where p.proy_cajas_mes > 0 and coalesce(btrim(p.cod),'') <> '';

  select count(*) into v_calc from _proy_tmp;
  if v_calc = 0 then
    raise exception 'sync_proyeccion_madre_virgilio: el motor devolvio 0 filas, no se toca Virgilio';
  end if;

  -- 2) Reemplazo total. La fuente es amnesica: lo que no viene, no va.
  --    WHERE real y no un DELETE pelado: supautils bloquea DELETE sin WHERE.
  delete from virgilio.proyeccion_madre where cod is not null;

  insert into virgilio.proyeccion_madre (cod, proy_cajas_mes, proy_uni_mes, actualizado, gv_descripcion)
  select upper(btrim(cod)), proy_cajas_mes, proy_uni_mes, now(), gv_descripcion
  from _proy_tmp;

  get diagnostics v_n = row_count;
  return v_n;
end;
$function$;

-- la foreign table tambien se ajusto:
-- alter foreign table virgilio.proyeccion_madre drop column uxb;
-- alter foreign table virgilio.proyeccion_madre add column gv_descripcion text;
