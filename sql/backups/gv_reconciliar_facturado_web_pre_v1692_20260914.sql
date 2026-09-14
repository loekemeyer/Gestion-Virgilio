-- =====================================================================
--  BACKUP — definición VIVA de public.gv_reconciliar_facturado_web() ANTES
--  de la v16.92 (2026-09-14). Para revertir: ejecutar tal cual.
--
--  Tenía el mismo bug que la etapa 3 de reconciliar_pipeline_stock(): `src`
--  suma sólo 'separado' + 'facturado', así que un `ajuste` manual sobre
--  a_facturar es invisible y la misma caja se drena dos veces. Tampoco mira
--  el saldo disponible, así que nada impide dejar a_facturar en negativo.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.gv_reconciliar_facturado_web()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$

declare n3 int := 0;
begin
  with src as (
    select case when tipo = 'separado' then upper(trim(ref))
                else upper(trim(split_part(ref, '|', 1))) end as tanda,
           cod_art as art, coalesce(empresa, 'Mixto') as empresa, sum(delta) as net
      from public."Movimientos_Stock"
     where deposito = 'a_facturar' and tipo in ('separado', 'facturado')
     group by 1, 2, 3
  ),
  tandanp as (
    select upper(btrim(w.tanda)) as tanda,
           upper(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx)) as np
      from public."PPP_Web_Programacion" w
     where coalesce(nullif(btrim(w.tanda), ''), '') <> '' and w.np is not null
  )
  insert into public."Movimientos_Stock" (cod_art, deposito, delta, tipo, ref, legajo, empresa)
  select s.art, 'a_facturar', -s.net, 'facturado', s.tanda, 'pipeline', s.empresa
    from src s
   where s.net > 0
     and exists (select 1 from tandanp pp where pp.tanda = s.tanda)
     and not exists (select 1 from public."Movimientos_Stock" m
                      where m.tipo = 'facturado' and m.deposito = 'a_facturar'
                        and (upper(trim(m.ref)) = s.tanda or upper(trim(split_part(m.ref, '|', 1))) = s.tanda))
     and not exists (select 1 from tandanp pp
                      where pp.tanda = s.tanda
                        and not exists (select 1 from public."Facturacion_NP" f where upper(trim(f.np)) = pp.np))
  on conflict do nothing;
  get diagnostics n3 = row_count;
  return format('ok facturado_web=%s', n3);
exception when others then
  return 'error: ' || sqlerrm;
end
$function$;
