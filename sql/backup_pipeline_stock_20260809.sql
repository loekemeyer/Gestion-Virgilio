-- =====================================================================
-- backup_pipeline_stock_20260809.sql — RESTORE POINT antes de v8.00
-- (descuento de picking incremental por PKC). Protocolo CLAUDE.md.
--
-- Estado previo: 8258 filas tipo='picking', 193 tandas, suma(delta)=0.
-- Para restaurar el comportamiento anterior: correr TODO este archivo (recrea
-- las funciones/trigger tal cual estaban) y dejar el cron como estaba.
-- =====================================================================

-- ── reconciliar_pipeline_stock_etapa1() [ORIGINAL: por tanda, gated en TP] ──
CREATE OR REPLACE FUNCTION public.reconciliar_pipeline_stock_etapa1()
 RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare v_cutoff timestamptz; n1 int := 0;
begin
  select coalesce((select valor::timestamptz from "Stock_Config" where clave='cutoff_ts'),
                  '2026-06-26 00:01:00-03'::timestamptz) into v_cutoff;
  with picks as (
    select upper(trim(split_part(r.texto,'|',1))) tanda,
           coalesce(e.cod_real, upper(trim(split_part(r.texto,'|',2)))) art,
           sum(coalesce(nullif(regexp_replace(split_part(r.texto,'|',4),'[^0-9-]','','g'),'')::int,0)) picked
    from "Registros_Produccion_Virgilio" r
    left join "Equivalencias_Codigos" e
      on regexp_replace(upper(btrim(e.cod_pedido)),'^0+(?=.)','')
       = regexp_replace(upper(btrim(split_part(r.texto,'|',2))),'^0+(?=.)','')
    where r.opcion='PKC' and coalesce(split_part(r.texto,'|',2),'')<>''
    group by 1,2
  ),
  lastpk as (
    select upper(trim(split_part(texto,'|',1))) tanda, max(ts_cliente) last_pk
    from "Registros_Produccion_Virgilio" where opcion='PKC' group by 1
  ),
  elig as (
    select p.tanda, p.art, p.picked
    from picks p join lastpk l on l.tanda=p.tanda
    where p.picked>0 and l.last_pk >= v_cutoff
      and exists (select 1 from "Registros_Produccion_Virgilio" r
                  where r.opcion='TP' and upper(trim(split_part(r.texto,'|',1)))=p.tanda)
      and not exists (select 1 from "Movimientos_Stock" m
                      where m.deposito='separar_pedidos' and upper(trim(m.ref))=p.tanda)
  ),
  exc_avail as (
    select upper(trim(cod_art)) art, greatest(0, sum(delta))::numeric exc
    from "Movimientos_Stock" where deposito='excedente' group by upper(trim(cod_art))
  ),
  alloc as (
    select e.tanda, e.art, e.picked,
           least(e.picked, greatest(0,
               coalesce(x.exc,0)
               - coalesce(sum(e.picked) over (partition by e.art order by e.tanda
                          rows between unbounded preceding and 1 preceding), 0))) as from_exc
    from elig e left join exc_avail x on x.art = e.art
  )
  insert into "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, legajo)
  select art, 'separar_pedidos', picked,             'picking', tanda, 'pipeline' from alloc
  union all
  select art, 'excedente',       -from_exc,          'picking', tanda, 'pipeline' from alloc where from_exc > 0
  union all
  select art, 'terminado',       -(picked-from_exc), 'picking', tanda, 'pipeline' from alloc where (picked-from_exc) > 0
  on conflict do nothing;
  get diagnostics n1 = row_count;
  return n1;
end;
$function$;

-- ── trg_tp_reconciliar_etapa1() [ORIGINAL] ──
CREATE OR REPLACE FUNCTION public.trg_tp_reconciliar_etapa1()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
begin
  begin perform public.reconciliar_pipeline_stock_etapa1();
  exception when others then null; end;
  return null;
end;
$function$;

-- Trigger original (solo TP):
--   CREATE TRIGGER trg_tp_reconciliar_stock AFTER INSERT ON public."Registros_Produccion_Virgilio"
--   FOR EACH ROW WHEN ((new.opcion='TP') AND (COALESCE(btrim(new.texto),'')<>'')) EXECUTE FUNCTION trg_tp_reconciliar_etapa1();
