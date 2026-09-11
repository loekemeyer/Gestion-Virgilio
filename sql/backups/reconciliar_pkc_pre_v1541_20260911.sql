-- BACKUP 2026-09-11 (pre v15.41) — definiciones ORIGINALES de las dos funciones que
-- reparten el picking entre góndola y excedente ADIVINANDO por saldos vivos.
-- Para deshacer el cambio de v15.41: correr este archivo entero en el SQL editor.
-- Ver docs/ROLLBACK-PRODUCCION.md.

CREATE OR REPLACE FUNCTION public.reconciliar_pipeline_stock_etapa1()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
declare v_cutoff timestamptz; v_desde timestamptz; n1 int := 0; n1b int := 0;
begin
  select coalesce((select valor::timestamptz from "Stock_Config" where clave='cutoff_ts'),
                  '2026-06-26 00:01:00-03'::timestamptz) into v_cutoff;
  select coalesce((select valor::timestamptz from "Stock_Config" where clave='etapa1_pkc_desde'),
                  'infinity'::timestamptz) into v_desde;

  with picks as (
    select upper(trim(split_part(r.texto,'|',1))) tanda,
           coalesce(e.cod_real, upper(trim(split_part(r.texto,'|',2)))) art,
           sum(coalesce(nullif(regexp_replace(split_part(r.texto,'|',4),'[^0-9.\-]','','g'),'')::numeric,0)) picked,
           (array_agg(r.legajo::text ORDER BY r.ts_cliente DESC NULLS LAST))[1] AS leg
    from "Registros_Produccion_Virgilio" r
    left join "Equivalencias_Codigos" e
      on regexp_replace(upper(btrim(e.cod_pedido)),'^0+(?=.)','')
       = regexp_replace(upper(btrim(split_part(r.texto,'|',2))),'^0+(?=.)','')
    where r.opcion='PKC' and coalesce(split_part(r.texto,'|',2),'')<>''
      and r.ts_cliente >= v_cutoff
    group by 1,2
  ),
  lastpk as (select upper(trim(split_part(texto,'|',1))) tanda, max(ts_cliente) last_pk
             from "Registros_Produccion_Virgilio" where opcion='PKC'
               and ts_cliente >= v_cutoff
             group by 1),
  elig as (
    select p.tanda, p.art, p.picked, p.leg from picks p join lastpk l on l.tanda=p.tanda
    where p.picked>0 and l.last_pk >= v_cutoff and l.last_pk < v_desde
      and exists (select 1 from "Registros_Produccion_Virgilio" r
                  where r.opcion='TP' and upper(trim(split_part(r.texto,'|',1)))=p.tanda)
      and not exists (select 1 from "Movimientos_Stock" m
                      where m.deposito='separar_pedidos' and upper(trim(m.ref))=p.tanda)
  ),
  exc_avail as (select upper(trim(cod_art)) art, greatest(0, sum(delta))::numeric exc
                from "Movimientos_Stock" where deposito='excedente' group by upper(trim(cod_art))),
  alloc as (
    select e.tanda, e.art, e.picked, e.leg,
           least(e.picked, greatest(0, coalesce(x.exc,0)
             - coalesce(sum(e.picked) over (partition by e.art order by e.tanda
                        rows between unbounded preceding and 1 preceding),0))) as from_exc
    from elig e left join exc_avail x on x.art=e.art
  )
  insert into "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, legajo)
  select art,'separar_pedidos', picked,'picking', tanda, coalesce(leg,'pipeline') from alloc
  union all select art,'excedente', -from_exc,'picking', tanda, coalesce(leg,'pipeline') from alloc where from_exc>0
  union all select art,'terminado', -(picked-from_exc),'picking', tanda, coalesce(leg,'pipeline') from alloc where (picked-from_exc)>0
  on conflict do nothing;
  get diagnostics n1 = row_count;

  CREATE TEMP TABLE IF NOT EXISTS _fwd_alloc (tanda text, art text, picked numeric, from_exc numeric, leg text);
  TRUNCATE _fwd_alloc;

  WITH picks AS (
    select upper(trim(split_part(r.texto,'|',1))) tanda,
           coalesce(e.cod_real, upper(trim(split_part(r.texto,'|',2)))) art,
           sum(coalesce(nullif(regexp_replace(split_part(r.texto,'|',4),'[^0-9.\-]','','g'),'')::numeric,0)) picked,
           (array_agg(r.legajo::text ORDER BY r.ts_cliente DESC NULLS LAST))[1] AS leg
    from "Registros_Produccion_Virgilio" r
    left join "Equivalencias_Codigos" e
      on regexp_replace(upper(btrim(e.cod_pedido)),'^0+(?=.)','')
       = regexp_replace(upper(btrim(split_part(r.texto,'|',2))),'^0+(?=.)','')
    where r.opcion='PKC' and coalesce(split_part(r.texto,'|',2),'')<>''
      and r.ts_cliente >= v_desde
    group by 1,2
  ),
  lastpk AS (select upper(trim(split_part(texto,'|',1))) tanda, max(ts_cliente) last_pk
             from "Registros_Produccion_Virgilio" where opcion='PKC'
               and ts_cliente >= v_desde
             group by 1),
  fwd AS (select p.tanda, p.art, p.picked, p.leg from picks p join lastpk l on l.tanda=p.tanda
          where p.picked>=0 and l.last_pk >= v_desde),
  fwd_t AS (select distinct tanda from fwd),
  exc_avail AS (
    select upper(trim(cod_art)) art, greatest(0, sum(delta))::numeric exc
    from "Movimientos_Stock"
    where deposito='excedente' and not (tipo='picking' and upper(trim(ref)) in (select tanda from fwd_t))
    group by upper(trim(cod_art))
  ),
  alloc AS (
    select f.tanda, f.art, f.picked, f.leg,
           least(f.picked, greatest(0, coalesce(x.exc,0)
             - coalesce(sum(f.picked) over (partition by f.art order by f.tanda
                        rows between unbounded preceding and 1 preceding),0))) as from_exc
    from fwd f left join exc_avail x on x.art=f.art
  )
  INSERT INTO _fwd_alloc SELECT tanda, art, picked, from_exc, leg FROM alloc;

  INSERT INTO "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, legajo)
  SELECT art,'separar_pedidos', picked,'picking', tanda, coalesce(leg,'pipeline') FROM _fwd_alloc
  ON CONFLICT (upper(trim(ref)), upper(trim(cod_art)), coalesce(empresa,''), deposito, tipo) WHERE tipo IN ('picking','separado','facturado')
  DO UPDATE SET delta = excluded.delta, legajo = excluded.legajo;

  INSERT INTO "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, legajo)
  SELECT art,'excedente', -from_exc,'picking', tanda, coalesce(leg,'pipeline') FROM _fwd_alloc
  ON CONFLICT (upper(trim(ref)), upper(trim(cod_art)), coalesce(empresa,''), deposito, tipo) WHERE tipo IN ('picking','separado','facturado')
  DO UPDATE SET delta = excluded.delta, legajo = excluded.legajo;

  INSERT INTO "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, legajo)
  SELECT art,'terminado', -(picked-from_exc),'picking', tanda, coalesce(leg,'pipeline') FROM _fwd_alloc
  ON CONFLICT (upper(trim(ref)), upper(trim(cod_art)), coalesce(empresa,''), deposito, tipo) WHERE tipo IN ('picking','separado','facturado')
  DO UPDATE SET delta = -(
    COALESCE((SELECT m.delta FROM "Movimientos_Stock" m
      WHERE m.deposito='separar_pedidos' AND m.tipo='picking'
        AND upper(trim(m.ref)) = upper(trim("Movimientos_Stock".ref))
        AND upper(trim(m.cod_art)) = upper(trim("Movimientos_Stock".cod_art)) AND coalesce(m.empresa,'') = coalesce("Movimientos_Stock".empresa,'')
      LIMIT 1), 0)
    + COALESCE((SELECT m.delta FROM "Movimientos_Stock" m
      WHERE m.deposito='excedente' AND m.tipo='picking'
        AND upper(trim(m.ref)) = upper(trim("Movimientos_Stock".ref))
        AND upper(trim(m.cod_art)) = upper(trim("Movimientos_Stock".cod_art)) AND coalesce(m.empresa,'') = coalesce("Movimientos_Stock".empresa,'')
      LIMIT 1), 0)
  ),
  legajo = excluded.legajo;

  SELECT count(*) INTO n1b FROM _fwd_alloc;
  DROP TABLE IF EXISTS _fwd_alloc;

  return n1 + n1b;
end;
$function$;

CREATE OR REPLACE FUNCTION public.reconciliar_stock_articulo_rt(p_tanda text, p_cod_raw text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
declare
  v_desde timestamptz;
  v_norm_art text;
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

  with picks as (
    select upper(trim(split_part(r.texto,'|',1))) tanda,
           sum(coalesce(nullif(regexp_replace(split_part(r.texto,'|',4),'[^0-9-]','','g'),'')::int,0)) picked
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
    select p.tanda, p.picked from picks p
    where p.picked >= 0
  ),
  fwd_t as (select distinct tanda from fwd),
  exc_avail as (
    select greatest(0, sum(delta))::numeric exc
    from "Movimientos_Stock"
    where regexp_replace(upper(btrim(cod_art)),'^0+(?=.)','') = v_norm_art
      and deposito = 'excedente'
      and not (tipo = 'picking' and upper(trim(ref)) in (select tanda from fwd_t))
  ),
  alloc as (
    select f.tanda, f.picked,
           least(f.picked, greatest(0, coalesce((select exc from exc_avail), 0)
             - coalesce(sum(f.picked) over (order by f.tanda
                        rows between unbounded preceding and 1 preceding), 0))) as from_exc
    from fwd f
  )
  insert into "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, legajo)
  select v_norm_art, 'separar_pedidos', picked, 'picking', tanda, 'pipeline' from alloc
  union all select v_norm_art, 'excedente', -from_exc, 'picking', tanda, 'pipeline' from alloc
  union all select v_norm_art, 'terminado', -(picked - from_exc), 'picking', tanda, 'pipeline' from alloc
  on conflict (upper(trim(ref)), upper(trim(cod_art)), coalesce(empresa,''), deposito, tipo) where tipo in ('picking','separado','facturado')
  do update set delta = excluded.delta;

end;
$function$;
