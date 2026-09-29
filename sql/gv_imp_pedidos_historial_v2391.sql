-- ══════════════════════════════════════════════════════════════════════════════
-- v23.91 — IMPORTADOS: la solapa «📜 Historial recepción» pasa a «📜 Historial»
-- y muestra las dos mitades del circuito (Luis, 29/09: "debería pasar a ser
-- «Historial» y mostrar recepción y pedidos").
--
-- Lo que se RECIBIÓ ya lo daba gv_imp_recepcion_historial. Lo que se PIDIÓ vivía
-- sólo por artículo (los baches) y no había forma de ver un pedido entero.
-- ══════════════════════════════════════════════════════════════════════════════
create or replace function public.gv_imp_pedidos_historial(p_dias integer default 365)
returns table(
  pedido_ref text, proveedor text, creado timestamptz, creado_por text,
  embarque date, reingreso date, estado text,
  items integer, unidades numeric, llegadas numeric, anulados integer,
  codigos text, usd numeric
) language sql stable security definer set search_path to 'public' as $fn$
-- Un renglón por (pedido, proveedor): lo pedido, lo llegado y en qué estado está.
-- ⚠ El pedido sin PI se agrupa por su DÍA de carga. La clave se arma en el subselect
--   porque un agregado no puede ir adentro del GROUP BY (error 42803 en el 1.er intento).
-- ⚠ El estado del GRUPO: si queda alguna línea en curso, el pedido está en curso; si no
--   y alguna llegó, llegado; si todas están anuladas, anulado. Las anuladas no suman
--   unidades ni u$s, pero se cuentan aparte para que se vea que existieron.
  select coalesce(z.ref, '(sin PI · ' || to_char(z.creado at time zone 'America/Argentina/Buenos_Aires','dd/mm/yy') || ')') as pedido_ref,
         z.proveedor, z.creado, z.creado_por, z.embarque, z.reingreso, z.estado,
         z.items, z.unidades, z.llegadas, z.anulados, z.codigos, z.usd
    from (
      select nullif(btrim(b.pedido_ref),'') as ref,
             coalesce(nullif(btrim(b.proveedor),''),'(sin proveedor)') as proveedor,
             (case when nullif(btrim(b.pedido_ref),'') is null
                   then (b.creado at time zone 'America/Argentina/Buenos_Aires')::date::text else '' end) as dia,
             min(b.creado) as creado,
             (array_agg(b.creado_por order by b.creado) filter (where nullif(btrim(b.creado_por),'') is not null))[1] as creado_por,
             min(b.fecha_embarque) as embarque,
             min(b.fecha_reingreso) filter (where b.estado <> 'anulado') as reingreso,
             case when count(*) filter (where b.estado = 'en_curso') > 0 then 'en curso'
                  when count(*) filter (where b.estado = 'llegado')  > 0 then 'llegado'
                  else 'anulado' end as estado,
             count(*) filter (where b.estado <> 'anulado')::int as items,
             coalesce(sum(b.unidades) filter (where b.estado <> 'anulado'), 0) as unidades,
             coalesce(sum(b.unidades_llegadas) filter (where b.estado <> 'anulado'), 0) as llegadas,
             count(*) filter (where b.estado = 'anulado')::int as anulados,
             string_agg(distinct upper(btrim(b.cod_art)), ' · ') as codigos,
             coalesce(sum(b.unidades * coalesce(i.fob_uni,0)) filter (where b.estado <> 'anulado'), 0) as usd
        from public."GV_Importados_Baches" b
        left join public."Importados" i on i.id = b.importado_id
       where b.creado >= now() - make_interval(days => greatest(coalesce(p_dias,365), 1))
       group by 1, 2, 3
    ) z
   order by z.creado desc;
$fn$;
revoke all on function public.gv_imp_pedidos_historial(integer) from public;
grant execute on function public.gv_imp_pedidos_historial(integer) to anon, authenticated, service_role;

-- Chequeo: al 29/09 devuelve 13 pedidos (9 en curso, 3 llegados, 1 anulado).
-- select pedido_ref, proveedor, estado, items, unidades, llegadas, round(usd) from public.gv_imp_pedidos_historial(400);

-- Rollback: drop function if exists public.gv_imp_pedidos_historial(integer);
