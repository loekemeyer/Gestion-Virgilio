-- =====================================================================
--  v18.30 (2026-09-15, Luis) — el ajuste "de menos / no hay en góndola"
--  dejaba Pickeados en negativo y devolvía una caja FANTASMA a góndola
--
--  ── EL SÍNTOMA (lo vio Luis en Stocks) ──────────────────────────────
--  Artículo 116, tanda E11A:
--
--    14/09 16:10  picking  (JC 277)   góndola −50 · Pickeados **+50**   empresa LK
--    15/09 11:23  ajuste   (JF 8)     Pickeados **−1**                  empresa **Mixto**
--    15/09 12:05  separado (pipeline) Pickeados **−50** · A facturar +49 · góndola **+1**
--
--  Saldo: Pickeados **−1** y góndola con **1 caja que no existe**. En total las
--  cuentas cierran (49), pero repartidas mal entre depósitos.
--
--  ── LA CAUSA ────────────────────────────────────────────────────────
--  El ajuste no lo tipeó nadie: lo emite el wizard de armado cuando el armador
--  marca "de menos / no hay en góndola" (evento NPD, `_compDifResolve` en
--  index.html, v12.12). Sirve para que la ETAPA 2 no devuelva a góndola una caja
--  que nunca existió.
--
--  Pero **el saldo de un depósito es por empresa** (misma lección que la v17.07):
--   • el picking lo escribe el backend con `empresa_de_np` → `LK` / `CH`;
--   • el ajuste del front va sin empresa, y para un código NO dual el trigger
--     `trg_normalizar_empresa_stock` lo forzaba a `Mixto`.
--  `Mixto` ≠ `LK`, así que **el ajuste no se resta del picking**: la ETAPA 2 ve
--  net = 50 (no 49), descuenta 50 de Pickeados (quedan −1) y devuelve a góndola
--  la caja fantasma que el ajuste quería evitar.
--
--  Por qué aparece recién ahora: hasta el 11/09 17:55 (`pkc_empresa_desde`) el
--  picking también salía `Mixto`, así que ajuste y picking coincidían y se
--  neteaban. Desde el 14/09 **todos** los pickings salen `LK`/`CH`
--  (semana del 14/09: 439 LK + 76 CH, 0 Mixto), o sea que de acá en adelante
--  esto pasaba en CADA "de menos / no hay en góndola".
--
--  ── EL FIX (dos capas, las dos en el backend) ───────────────────────
--  (1) `trg_normalizar_empresa_stock` — al ESCRIBIR: si la fila no trae empresa
--      y su `ref` es una TANDA (LETRA+NN+LETRA) que ya tiene picking en una sola
--      empresa, hereda ESA empresa en vez de caer en `Mixto`. Arregla el dato en
--      el origen, venga del front, de la app vieja o de un pegado a mano.
--  (2) `reconciliar_pipeline_stock_etapa2` — al CALCULAR: las filas `Mixto` de
--      `separar_pedidos` se netean contra la empresa del picking de esa
--      (tanda, código) cuando el picking tiene una sola. Defensa por si algo
--      vuelve a escribir sin empresa, y cubre lo ya escrito.
--
--  Las dos son conservadoras: si el picking de esa (tanda, código) tiene más de
--  una empresa, o no hay picking, no se toca nada y el comportamiento es el de hoy.
--
--  NO corrige datos ya escritos (protocolo: los datos no se tocan sin permiso).
--  El −1 de E11A/116 y su caja fantasma en góndola siguen ahí.
--
--  Rollback: sql/backups/empresa_mixto_ajuste_pre_v1830_20260915.sql
-- =====================================================================

-- ── (1) al ESCRIBIR ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.trg_normalizar_empresa_stock()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE v_base text; v_dual boolean; v_np text; v_emp2 text; v_explicita boolean; v_tanda text;
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

  -- v18.30: una fila SIN empresa cuyo `ref` es una tanda ya pickeada hereda la
  -- empresa de ESE picking. Si no, cae en `Mixto` y no se netea contra el picking
  -- (que desde el 11/09 sale LK/CH) → Pickeados negativo + caja fantasma en góndola.
  v_tanda := upper(btrim(split_part(coalesce(NEW.ref,''),'|',1)));
  IF NOT v_explicita
     AND NEW.deposito IN ('separar_pedidos','a_facturar','terminado')
     AND v_tanda ~ '^[A-Z][0-9]{2}[A-Z]$' THEN
    SELECT CASE WHEN count(DISTINCT m.empresa)=1 THEN max(m.empresa) END
      INTO v_emp2
      FROM public."Movimientos_Stock" m
     WHERE m.tipo='picking' AND m.deposito='separar_pedidos'
       AND m.empresa IN ('LK','CH')
       AND regexp_replace(upper(btrim(m.cod_art)),'^0+(?=.)','') = v_base
       AND upper(btrim(split_part(m.ref,'|',1))) = v_tanda;
    IF v_emp2 IS NOT NULL THEN
      NEW.empresa := v_emp2;
      RETURN NEW;
    END IF;
  END IF;

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

-- ── (2) al CALCULAR ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.reconciliar_pipeline_stock_etapa2()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
declare n2 int := 0;
begin
  with mov as (
    select upper(trim(ref)) tanda, cod_art art_raw,
           upper(regexp_replace(regexp_replace(trim(cod_art),' +(LK|CH)$',''),'^0+(?=.)','')) artn,
           coalesce(empresa,'Mixto') emp_raw, tipo, delta
    from "Movimientos_Stock" where deposito='separar_pedidos'
  ),
  -- v18.30: empresa REAL del picking de cada (tanda, artículo). Sólo si es una sola.
  emp_pick as (
    select tanda, artn, max(emp_raw) emp
    from mov where tipo='picking' and emp_raw in ('LK','CH')
    group by 1,2 having count(distinct emp_raw) = 1
  ),
  base as (
    -- v18.30: las filas SIN empresa (el ajuste del "de menos / no hay en góndola",
    -- que nace 'Mixto') se netean contra el picking en vez de quedar en su propia
    -- partición. Sin esto, net = pickeado y la caja que no existía vuelve a góndola.
    select m.tanda, m.art_raw, m.artn,
           case when m.emp_raw = 'Mixto' and ep.emp is not null then ep.emp else m.emp_raw end empresa,
           sum(m.delta) net
    from mov m
    left join emp_pick ep on ep.tanda = m.tanda and ep.artn = m.artn
    group by 1,2,3,4
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
