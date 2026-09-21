-- v20.41 (Luis, 2026-09-21): en Clientes Nuevos y en Cuarentena el MONTO del pedido descuenta
-- los articulos IMPORTADOS ("los codigos que tienen E, que sabemos no hay en stock"), y la
-- columna de cliente muestra el CUIT.
--
-- Criterio de importado, medido el 21/09 sobre los 329 articulos que aparecen en pedidos web:
--   115 tienen E; de esos 1 no figura en `Importados` activo.
--   5 importados activos NO tienen E: 026, 027, 110, 111, 112, 113, 505C, 523C, 587C, 824, 825...
-- Por eso el criterio es la UNION de los dos (tabla `Importados` activo O el codigo con E):
-- con uno solo se escapa lo del otro lado, y lo que se busca es "lo que no hay en stock".
-- ⚠ Se pela la L de ruteo antes de mirar la tabla: la L no es parte del codigo (regla de Thomas).
create or replace function public.gv_art_es_importado(p_cod text)
returns boolean language sql stable set search_path to 'public', 'pg_temp' as $function$
  select case when nullif(btrim(coalesce(p_cod, '')), '') is null then false
              when upper(btrim(p_cod)) ~ 'E' then true
              else exists (select 1 from public."Importados" i
                            where i.activo
                              and upper(btrim(i.cod_art)) = regexp_replace(upper(btrim(p_cod)), '([0-9E])L$', '\1'))
         end;
$function$;

-- El CUIT por (empresa, cod), del padron que se importa en Config. Cuarentena
-- (`GV_Cuarentena_Fuente` tipo busqueda: 2.045 de 2.047 filas lo traen).
-- ⚠ Medido: la factura NO sirve de respaldo para un cliente nuevo — 0 de los 37 clientes nuevos
-- sin CUIT tiene factura (logico: nunca se le facturo). Esos quedan sin CUIT hasta el proximo
-- padron; no hay otra fuente en Gestion.
-- Usa gv_cuarentena_ident para respetar la regla de Tierra del Fuego (LK que se evalua con CH).
create or replace function public.gv_cuarentena_cuit_lote(p_clientes jsonb)
returns table(empresa text, cod text, cuit text)
language sql stable security definer set search_path to 'public' as $function$
  with pedido as (
    select distinct lower(coalesce(e->>'empresa','lk')) as empresa,
                    nullif(trim(e->>'cod'), '')         as cod
      from jsonb_array_elements(coalesce(p_clientes, '[]'::jsonb)) e
  )
  select p.empresa, p.cod,
         (select nullif(regexp_replace(coalesce(f.cuit,''), '\D', '', 'g'), '')
            from public."GV_Cuarentena_Fuente" f
           where f.tipo = 'busqueda' and f.empresa = id.empresa and f.cod = id.cod
             and nullif(btrim(f.cuit), '') is not null
           limit 1)
    from pedido p
    cross join lateral public.gv_cuarentena_ident(p.empresa, p.cod, true) id
   where p.cod is not null
     and (es_supervisor_virgilio() or gv_es_supervisor_o_servicio());
$function$;

revoke all on function public.gv_cuarentena_cuit_lote(jsonb) from public, anon;
grant execute on function public.gv_cuarentena_cuit_lote(jsonb) to authenticated;

-- El lote de valor deja fuera los importados ANTES de valorizar, y devuelve aparte cuanto se
-- descuento para que la pantalla lo pueda mostrar. gv_ppp_web_valor_items NO se toca: la usa
-- tambien el control de limite de credito, y ahi el pedido vale lo que vale.
drop function if exists public.gv_clientes_nuevos_valor_lote(jsonb);

create function public.gv_clientes_nuevos_valor_lote(p_pedidos jsonb)
returns table(order_id text, empresa text, valor numeric, valor_con_iva numeric,
              valor_importados numeric, items_importados integer)
language sql security definer set search_path to 'public' as $function$
  with _vl_src as (
    select nullif(trim(e->>'order_id'), '')     as order_id,
           lower(coalesce(e->>'empresa','lk'))  as empresa,
           nullif(trim(e->>'cod'), '')          as cod,
           e->'items'                           as items,
           nullif(e->>'cond','')                as cond
      from jsonb_array_elements(coalesce(p_pedidos, '[]'::jsonb)) e
  ),
  _vl_part as (
    select s.*,
           coalesce(jsonb_agg(i.e) filter (where not public.gv_art_es_importado(i.e->>'art')), '[]'::jsonb) as items_ok,
           coalesce(jsonb_agg(i.e) filter (where public.gv_art_es_importado(i.e->>'art')), '[]'::jsonb)     as items_imp,
           count(*) filter (where public.gv_art_es_importado(i.e->>'art'))::int                             as n_imp
      from _vl_src s
      left join lateral jsonb_array_elements(coalesce(s.items, '[]'::jsonb)) i(e) on true
     group by s.order_id, s.empresa, s.cod, s.items, s.cond
  ),
  -- ⚠ MATERIALIZED a proposito (v19.95): sin eso el planner aplana el CTE, repite la llamada a
  -- gv_ppp_web_valor_items en cada columna de salida y se duplica el trabajo sin que nada avise.
  _vl_val as materialized (
    select s.order_id, s.empresa, s.n_imp,
           public.gv_ppp_web_valor_items(s.empresa, s.cod, s.items_ok,  s.cond) as valor,
           public.gv_ppp_web_valor_items(s.empresa, s.cod, s.items_imp, s.cond) as valor_imp
      from _vl_part s
     where s.order_id is not null
       and (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
  )
  select v.order_id, v.empresa, round(v.valor, 2), round(v.valor * 1.21, 2),
         round(v.valor_imp, 2), v.n_imp
    from _vl_val v;
$function$;

revoke all on function public.gv_clientes_nuevos_valor_lote(jsonb) from public, anon;
grant execute on function public.gv_clientes_nuevos_valor_lote(jsonb) to authenticated;

-- Probado con pedidos reales (no leido):
--   chef 229: 6 items, 2 importados -> monto $817.620 y $1.613.520 descontados
--   chef 228: 8 items, 2 importados -> $499.171,20 y $150.638,40
--   chef 227: 19 items, 3 importados -> $679.113,60 y $221.654,40
-- y gv_art_es_importado: 505 y 501 no; 026, 027, 110, 505C, 437E, 438EL, 865ED si.
