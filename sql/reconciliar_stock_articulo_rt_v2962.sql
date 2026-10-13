-- reconciliar_stock_articulo_rt — v29.62-exc-fijo (aplicado 2026-10-13, problema 766, segunda mitad)
--
-- Es el reconciliador EN VIVO del PKC (trigger trg_pkc_reconciliar_rt / _upd): recalcula el
-- artículo entero cada vez que llega un PKC. Tenía la MISMA lógica vieja que el cron 68
-- (reconciliar_pipeline_stock_etapa1, arreglado en sql/reconciliar_pipeline_stock_etapa1_v2962.sql):
-- repartía TODAS las tandas desde etapa1_pkc_desde contra el excedente de HOY, así que un
-- excedente cargado por un conteo se lo comían las tandas de agosto en cuanto alguien pickeaba
-- ese código. Caso 13/10: F48D (16:03-16:08) vació 654, 501, 315 y 222 que el conteo P había
-- cargado a las 15:34 y que el cron de las 15:41 (ya arreglado) había respetado.
--
-- Regla (la misma que etapa1): una tanda que YA tiene fila de excedente conserva lo que tomó
-- (least(picked, greatest(tomado, 0))); sólo una tanda NUEVA toma del excedente LIBRE de hoy.
-- Centinela: patrón least\(f\.picked, greatest\(f\.tomado, 0\)\) (es código, no comentario).
-- Backup de la definición anterior: zz_backups."GV_Backup_ArtRt_def_20261013" (md5 85faf27c…).
-- Rollback: recrear desde ese backup.

CREATE OR REPLACE FUNCTION public.reconciliar_stock_articulo_rt(p_tanda text, p_cod_raw text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
declare
  v_desde timestamptz;
  v_norm_art text;
  v_dep_on boolean;
  v_emp_desde timestamptz;
begin
  v_norm_art := regexp_replace(upper(btrim(
    coalesce(
      (select cod_real from "Equivalencias_Codigos"
       where regexp_replace(upper(btrim(cod_pedido)),'^0+(?=.)','')
           = regexp_replace(upper(btrim(p_cod_raw)),'^0+(?=.)','')
       limit 1),
      p_cod_raw
    )
  )), '^0+(?=.)', '');

  if v_norm_art = '' or v_norm_art is null then return; end if;

  select coalesce((select valor::timestamptz from "Stock_Config" where clave='etapa1_pkc_desde'),
                  'infinity'::timestamptz) into v_desde;
  select coalesce((select valor from "Stock_Config" where clave='pkc_deposito_activo'),'1') <> '0'
    into v_dep_on;
  select coalesce((select valor::timestamptz from "Stock_Config" where clave='pkc_empresa_desde'),
                  'infinity'::timestamptz) into v_emp_desde;

  with picks as (
    select upper(trim(split_part(r.texto,'|',1))) tanda,
           sum(coalesce(nullif(regexp_replace(split_part(r.texto,'|',4),'[^0-9.\-]','','g'),'')::numeric,0)) picked,
           sum(coalesce(nullif(regexp_replace(split_part(r.texto,'|',5),'[^0-9.\-]','','g'),'')::numeric,0)) picked_exc,
           bool_or(coalesce(btrim(split_part(r.texto,'|',5)),'') <> '') as tiene_dep,
           case when bool_and(r.ts_cliente >= v_emp_desde)
                 and count(distinct nullif(upper(btrim(split_part(r.texto,'|',6))),'')) = 1
                 and bool_and(upper(btrim(split_part(r.texto,'|',6))) in ('LK','CH'))
                then max(nullif(upper(btrim(split_part(r.texto,'|',6))),''))
           end as emp
    from "Registros_Produccion_Virgilio" r
    where r.opcion = 'PKC'
      and r.ts_cliente >= v_desde
      and coalesce(
            (select cod_real from "Equivalencias_Codigos"
             where regexp_replace(upper(btrim(cod_pedido)),'^0+(?=.)','')
                 = regexp_replace(upper(btrim(split_part(r.texto,'|',2))),'^0+(?=.)','')
             limit 1),
            regexp_replace(upper(btrim(split_part(r.texto,'|',2))),'^0+(?=.)','')
          ) = v_norm_art
    group by 1
  ),
  fwd as (
    select p.tanda, p.picked, p.picked_exc, p.tiene_dep, p.emp from picks p
    where p.picked >= 0
  ),
  fwd_t as (select distinct tanda from fwd),
  -- v29.62-exc-fijo: lo que cada tanda YA tomó del excedente (fila viva de picking en excedente).
  ya_exc as (
    select upper(trim(m.ref)) tanda, -sum(m.delta) tomado
    from "Movimientos_Stock" m
    where m.deposito = 'excedente' and m.tipo = 'picking'
      and regexp_replace(upper(btrim(m.cod_art)),'^0+(?=.)','') = v_norm_art
      and upper(trim(m.ref)) in (select tanda from fwd_t)
    group by 1
  ),
  -- v29.62-exc-fijo: el excedente LIBRE de hoy (neto de todo, incluidas las tandas ya repartidas).
  exc_avail as (
    select greatest(0, sum(delta))::numeric exc
    from "Movimientos_Stock"
    where regexp_replace(upper(btrim(cod_art)),'^0+(?=.)','') = v_norm_art
      and deposito = 'excedente'
  ),
  fwd2 as (
    select f.*, y.tomado,
           case when (f.tiene_dep and v_dep_on) then least(f.picked, greatest(f.picked_exc, 0))
                else f.picked end as want_exc
    from fwd f left join ya_exc y on y.tanda = f.tanda
  ),
  alloc as (
    select f.tanda, f.picked, f.emp,
           case when f.tomado is not null then least(f.picked, greatest(f.tomado, 0))   -- ya repartida: queda
                else least(f.want_exc, greatest(0, coalesce((select exc from exc_avail), 0)
                       - coalesce(sum(f.want_exc) filter (where f.tomado is null) over (order by f.tanda
                                  rows between unbounded preceding and 1 preceding), 0))) end as from_exc
    from fwd2 f
  )
  insert into "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, legajo, empresa)
  select v_norm_art, 'separar_pedidos', picked, 'picking', tanda, 'pipeline', coalesce(emp,'Mixto') from alloc
  union all select v_norm_art, 'excedente', -from_exc, 'picking', tanda, 'pipeline', coalesce(emp,'Mixto') from alloc
  union all select v_norm_art, 'terminado', -(picked - from_exc), 'picking', tanda, 'pipeline', coalesce(emp,'Mixto') from alloc
  on conflict (upper(trim(ref)), upper(trim(cod_art)), coalesce(empresa,''), deposito, tipo) where tipo in ('picking','separado','facturado')
  do update set delta = excluded.delta;

end;
$function$;
