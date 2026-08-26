-- reconciliar_pipeline_stock_etapa2.sql
-- v11.72: legajo real del TAP en vez de hardcodear 'pipeline'.
-- Extrae el legajo del último registro TAP de la tanda (ts_cliente DESC).
-- Se agrega CTE tap_leg y se joinea en alloc.
-- Fallback: coalesce(tl.leg, 'pipeline') si el TAP no tiene legajo.

CREATE OR REPLACE FUNCTION public.reconciliar_pipeline_stock_etapa2()
RETURNS int LANGUAGE plpgsql AS $$
declare n2 int := 0;
begin
  with base as (
    select upper(trim(ref)) tanda, cod_art art_raw,
           upper(regexp_replace(regexp_replace(trim(cod_art),' +(LK|CH)$',''),'^0+(?=.)','')) artn,
           sum(delta) net
    from "Movimientos_Stock" where deposito='separar_pedidos' group by 1,2,3
  ),
  elig as (
    select b.* from base b
    where b.net>0
      and not exists (select 1 from "Movimientos_Stock" m where m.tipo='separado' and upper(trim(m.ref))=b.tanda)
      and (exists (select 1 from "Registros_Produccion_Virgilio" r where r.opcion='TAP' and upper(trim(split_part(r.texto,'|',1)))=b.tanda)
           or exists (select 1 from "Entregas_Virgilio" e where upper(trim(e.tanda))=b.tanda))
  ),
  tap_leg as (
    select upper(trim(split_part(r.texto,'|',1))) as tanda,
           (array_agg(r.legajo::text order by r.ts_cliente desc nulls last))[1] as leg
    from "Registros_Produccion_Virgilio" r
    where r.opcion = 'TAP'
    group by 1
  ),
  ent_t as (select distinct upper(trim(tanda)) tanda from "Entregas_Virgilio"),
  deliv as (
    select upper(trim(tanda)) tanda,
           upper(regexp_replace(regexp_replace(trim(cod_art),' +(LK|CH)$',''),'^0+(?=.)','')) artn,
           sum(coalesce(cajas_entregadas,0)) entregado
    from "Entregas_Virgilio" group by 1,2
  ),
  alloc as (
    select e.tanda, e.art_raw, e.artn, e.net,
           coalesce(tl.leg, 'pipeline') as leg,
           case when et.tanda is not null then coalesce(d.entregado,0)
                else sum(e.net) over (partition by e.tanda,e.artn) end as entregado,
           sum(e.net) over (partition by e.tanda, e.artn order by e.art_raw rows between unbounded preceding and current row) as cum
    from elig e
    left join tap_leg tl on tl.tanda = e.tanda
    left join ent_t et on et.tanda=e.tanda
    left join deliv d on d.tanda=e.tanda and d.artn=e.artn
  )
  insert into "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, legajo)
  select a.art_raw, x.dep, x.delta, 'separado', a.tanda, a.leg
  from alloc a
  cross join lateral (values
    ('separar_pedidos', -a.net),
    ('a_facturar', greatest(0, least(a.net, a.entregado-(a.cum-a.net)))),
    ('terminado', a.net - greatest(0, least(a.net, a.entregado-(a.cum-a.net))))
  ) x(dep, delta)
  where x.delta <> 0
  on conflict do nothing;
  get diagnostics n2 = row_count;
  return n2;
end;
$$;
