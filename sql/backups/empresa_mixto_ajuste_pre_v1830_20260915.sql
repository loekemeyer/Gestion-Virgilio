-- =====================================================================
--  BACKUP — definiciones VIVAS antes del fix v18.30 (2026-09-15)
--
--  Qué se cambia y por qué: ver sql/gv_ajuste_hereda_empresa_v1830.sql.
--  Rollback = ejecutar este archivo entero (vuelve el comportamiento previo).
-- =====================================================================

CREATE OR REPLACE FUNCTION public.trg_normalizar_empresa_stock()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE v_base text; v_dual boolean; v_np text; v_emp2 text; v_explicita boolean;
BEGIN
  IF NEW.deposito = 'insumos' THEN
    NEW.cod_art := regexp_replace(NEW.cod_art,'\s+(LK|CH|LOKE)$','');
    RETURN NEW;
  END IF;

  v_explicita := NEW.empresa IS NOT NULL AND NEW.empresa IN ('LK','CH');

  IF NEW.cod_art ~ '\s+(LK|LOKE)$' THEN NEW.empresa:='LK'; NEW.cod_art:=regexp_replace(NEW.cod_art,'\s+(LK|LOKE)$','');
  ELSIF NEW.cod_art ~ '\s+CH$' THEN NEW.empresa:='CH'; NEW.cod_art:=regexp_replace(NEW.cod_art,'\s+CH$',''); END IF;
  IF NEW.cod_art ~ '[0-9E]L$' THEN
    NEW.empresa := 'LK';
    NEW.cod_art := regexp_replace(NEW.cod_art,'([0-9E])L$','\1');
    v_explicita := true;
  END IF;

  v_base := regexp_replace(upper(btrim(NEW.cod_art)),'^0+(?=.)','');
  SELECT true INTO v_dual FROM public.codigos_duales WHERE regexp_replace(upper(btrim(cod)),'^0+(?=.)','')=v_base LIMIT 1;

  IF NOT COALESCE(v_dual,false) THEN
    IF NOT v_explicita THEN NEW.empresa := 'Mixto'; END IF;
  ELSE
    IF NEW.empresa IS NULL OR NEW.empresa = 'Mixto' THEN
      v_np := nullif(regexp_replace(split_part(coalesce(NEW.ref,''),'|',2),'\D','','g'),'');
      IF v_np IS NOT NULL THEN NEW.empresa := public.empresa_de_np(v_np); END IF;
      IF (NEW.empresa IS NULL OR NEW.empresa = '' OR NEW.empresa = 'Mixto')
         AND NEW.deposito = 'a_facturar' AND NEW.tipo = 'facturado' THEN
        SELECT CASE WHEN count(DISTINCT m.empresa)=1 THEN max(m.empresa) END
          INTO v_emp2
          FROM public."Movimientos_Stock" m
         WHERE m.deposito='a_facturar' AND m.tipo='separado'
           AND regexp_replace(upper(btrim(m.cod_art)),'^0+(?=.)','') = v_base
           AND upper(btrim(split_part(m.ref,'|',1))) = upper(btrim(split_part(coalesce(NEW.ref,''),'|',1)))
           AND m.empresa IN ('LK','CH');
        IF v_emp2 IS NOT NULL THEN NEW.empresa := v_emp2; END IF;
      END IF;
      IF NEW.empresa IS NULL OR NEW.empresa = '' THEN NEW.empresa := 'Mixto'; END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.reconciliar_pipeline_stock_etapa2()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
declare n2 int := 0;
begin
  with base as (
    select upper(trim(ref)) tanda, cod_art art_raw,
           upper(regexp_replace(regexp_replace(trim(cod_art),' +(LK|CH)$',''),'^0+(?=.)','')) artn,
           coalesce(empresa,'Mixto') empresa,
           sum(delta) net
    from "Movimientos_Stock" where deposito='separar_pedidos' group by 1,2,3,4
  ),
  elig as (
    select b.* from base b
    where b.net>0
      -- v12.44: guard por (tanda, artn) en CUALQUIER empresa (evita doble emisión contra un
      -- separado Mixto histórico; la empresa correcta igual la lleva el INSERT desde base).
      and not exists (select 1 from "Movimientos_Stock" m where m.tipo='separado'
                        and upper(trim(m.ref))=b.tanda
                        and upper(regexp_replace(regexp_replace(trim(m.cod_art),' +(LK|CH)$',''),'^0+(?=.)',''))=b.artn)
      and (exists (select 1 from "Registros_Produccion_Virgilio" r where r.opcion='TAP' and upper(trim(split_part(r.texto,'|',1)))=b.tanda)
           or exists (select 1 from "Entregas_Virgilio" e where upper(trim(e.tanda))=b.tanda))
  ),
  tap_leg as (
    select upper(trim(split_part(r.texto,'|',1))) as tanda,
           (array_agg(r.legajo::text order by r.ts_cliente desc nulls last))[1] as leg
    from "Registros_Produccion_Virgilio" r where r.opcion = 'TAP' group by 1
  ),
  ent_t as (select distinct upper(trim(tanda)) tanda from "Entregas_Virgilio"),
  deliv as (
    select upper(trim(tanda)) tanda,
           upper(regexp_replace(regexp_replace(trim(cod_art),' +(LK|CH)$',''),'^0+(?=.)','')) artn,
           sum(coalesce(cajas_entregadas,0)) entregado
    from "Entregas_Virgilio" group by 1,2
  ),
  alloc as (
    select e.tanda, e.art_raw, e.artn, e.empresa, e.net,
           coalesce(tl.leg, 'pipeline') as leg,
           case when et.tanda is not null then coalesce(d.entregado,0)
                else sum(e.net) over (partition by e.tanda,e.artn,e.empresa) end as entregado,
           sum(e.net) over (partition by e.tanda, e.artn, e.empresa order by e.art_raw rows between unbounded preceding and current row) as cum
    from elig e
    left join tap_leg tl on tl.tanda = e.tanda
    left join ent_t et on et.tanda=e.tanda
    left join deliv d on d.tanda=e.tanda and d.artn=e.artn
  )
  insert into "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, legajo, empresa)
  select a.art_raw, x.dep, x.delta, 'separado', a.tanda, a.leg, a.empresa
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
$function$;
