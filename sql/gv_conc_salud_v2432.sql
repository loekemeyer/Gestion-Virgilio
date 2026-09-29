-- v24.32 — tablero de la CONCILIACION: cuanto de cada extracto quedo identificado
--
-- Luis (29/09): "crea una pestaña que se llame conciliación … quiero darte el manual, asi
-- como los extractos, para que determines las reglas de la conciliacion y la pueda hacer el
-- programa por su cuenta a futuro".
--
-- Hoy la conciliacion se hace A MANO en cuatro Excel (Credicoop y Santander, LK y Chef):
-- alguien mira el extracto y le escribe al renglon el cliente y el recibo. Esa planilla entra
-- por la macro y se lee en gv_conciliacion_bancaria. Estas dos funciones son el tablero de eso;
-- el motor de reglas todavia NO existe.
--
-- MEDIDO el 29/09 (gv_conc_salud):
--   banco       emp   entradas   con cliente   %      sin identificar
--   credicoop   lk      13.845      12.689     92 %      1.110  ($1.031.493.020)
--   credicoop   chef       606          12      2 %        589  ($1.022.438.804)   <- agujero
--   santander   chef     1.085       1.020     94 %         62  ($  315.800.781)
--   santander   lk         170          96     56 %         54  ($  758.788.754)
-- En los ultimos 90 dias quedan 35 entradas sin identificar: la carga a mano esta al dia
-- salvo Credicoop Chef, que directamente no se carga.

create or replace function public.gv_conc_salud()
returns table(banco text, empresa text, movimientos bigint, entradas bigint,
              con_cliente bigint, con_recibo bigint, sin_identificar bigint,
              monto_sin_identificar numeric, primera date, ultima date, cargado_en timestamptz, archivo text)
language sql stable security definer set search_path to 'public' as $fn$
  select c.banco, c.empresa,
         count(*)::bigint,
         count(*) filter (where coalesce(c.entrada,0) > 0)::bigint,
         count(*) filter (where coalesce(c.entrada,0) > 0 and coalesce(c.cod_cliente,'') <> '')::bigint,
         count(*) filter (where coalesce(c.entrada,0) > 0 and coalesce(c.nro_recibo,'') <> '')::bigint,
         count(*) filter (where coalesce(c.entrada,0) > 0 and coalesce(c.cod_cliente,'') = '' and coalesce(c.nro_recibo,'') = '')::bigint,
         coalesce(sum(c.entrada) filter (where coalesce(c.entrada,0) > 0 and coalesce(c.cod_cliente,'') = '' and coalesce(c.nro_recibo,'') = ''),0),
         min(c.fecha), max(c.fecha),
         max(g.cargado_en), (array_agg(g.archivo order by g.cargado_en desc nulls last))[1]
    from public.gv_conciliacion_bancaria c
    left join public."GV_Conc_Cargas" g on g.id = c.carga_id
   where (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio())
   group by 1,2
   order by 1,2;
$fn$;

-- las entradas que hoy alguien identifica a mano: el `detalle` es el texto del extracto,
-- que es de donde van a salir las reglas del motor
create or replace function public.gv_conc_sin_identificar(p_dias integer default 120, p_limit integer default 200)
returns table(banco text, empresa text, fecha date, entrada numeric, detalle text, operacion text, nro_op text, tipo text, observacion text)
language sql stable security definer set search_path to 'public' as $fn$
  select c.banco, c.empresa, c.fecha, c.entrada,
         coalesce(nullif(btrim(c.detalle),''), c.det), c.operacion, c.nro_op, c.tipo, c.observacion
    from public.gv_conciliacion_bancaria c
   where coalesce(c.entrada,0) > 0
     and coalesce(c.cod_cliente,'') = '' and coalesce(c.nro_recibo,'') = ''
     and c.fecha >= current_date - greatest(coalesce(p_dias,120),1)
     and (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio())
   order by c.fecha desc, c.entrada desc
   limit greatest(coalesce(p_limit,200),1);
$fn$;

revoke all on function public.gv_conc_salud() from public;
revoke all on function public.gv_conc_sin_identificar(integer,integer) from public;
grant execute on function public.gv_conc_salud() to anon, authenticated, service_role;
grant execute on function public.gv_conc_sin_identificar(integer,integer) to anon, authenticated, service_role;

-- chequeo
-- select * from public.gv_conc_salud();
-- select banco, empresa, count(*), round(sum(entrada)) from public.gv_conc_sin_identificar(90,5000) group by 1,2;

-- ROLLBACK (las dos son nuevas y solo leen):
-- drop function if exists public.gv_conc_salud();
-- drop function if exists public.gv_conc_sin_identificar(integer,integer);
