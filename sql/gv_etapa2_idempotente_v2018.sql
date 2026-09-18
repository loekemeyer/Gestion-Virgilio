-- ============================================================================
-- reconciliar_pipeline_stock_etapa2  (v20.18) — LA ETAPA2 SE CORRIGE SOLA
--
-- EL AGUJERO. La etapa2 era insert-only: escribia el `separado` de una
-- (tanda, articulo) UNA vez, con guard `not exists`, y no lo revisaba nunca
-- mas. Si el picking de esa tanda cambiaba DESPUES del armado —que es
-- exactamente lo que pasa cuando un renombre deja los PKC con el codigo viejo
-- y el cron 68 reasigna el picking a otra tanda— el drenaje quedaba con el
-- numero viejo y NINGUN centinela lo avisaba. La etapa1 SIEMPRE fue idempotente
-- (`on conflict do update set delta = excluded.delta`); esa asimetria entre las
-- dos etapas es la que hay que recordar.
--
-- CASO TESTIGO: E12K (18/09). La tanda se llamo E12L cuando se pickeo, E12J
-- cuando se armo y E12K ahora. Los eventos de tanda pelada (EP/TP/TAP) viajaron
-- con cada renombre; los PKC, que llevan la tanda en el campo 1, no. Resultado:
-- E12K con picking 0 y separado -46 — 34 codigos, 46 cajas de Pickeados en
-- negativo. En pantalla se veian 7, porque `gv_stock_negativos` agrega por
-- codigo y el saldo de otra tanda tapa el agujero. §3.kd y §3.km.
--
-- EL BLOQUE A NO SE TOCO. Lo nuevo es el bloque B.
--
-- POR QUE UPDATE Y NO UNA FILA COMPLEMENTARIA: `mov_stock_pipeline_dedup` es
-- unica por (ref, cod_art, empresa, deposito, tipo). No se puede insertar un
-- segundo `separado` para la misma combinacion, asi que se lleva la fila que
-- existe al valor OBJETIVO — que ademas la hace idempotente de verdad.
--
-- ⚠ Y LA PATA QUE NO EXISTE HAY QUE INSERTARLA. El bloque A no escribe la fila
-- cuyo delta daba 0 (`where x.delta <> 0`). Con solo el UPDATE, la pila quedaba
-- balanceada y las cajas no aterrizaban en ningun deposito — una fuga
-- silenciosa, justo lo que este bloque viene a evitar. Medido rompiendo E33A/502
-- a proposito: pila en 0 y 5 cajas en el aire. Por eso va el INSERT al final.
--
-- LOS TRES GUARDS, todos a proposito:
--  1. La tanda NO puede tener `facturado`. Mover el `separado` mueve
--     a_facturar, o sea camino de facturacion: contra una factura ya emitida no
--     se escribe. Esas quedan a la vista en gv_stock_tanda_pickeado_negativo.
--  2. Una sola grafia del articulo y a lo sumo una fila por deposito. Con varias
--     el reparto necesita la ventana `cum` del bloque A; repetirla aca a mano es
--     pedir un bug silencioso.
--  3. Solo (tanda, articulo) que YA tienen `separado`; el resto es del bloque A.
--
-- ⚠ PERFORMANCE — no es un detalle, esto corre en el cron 68 CADA 10 MINUTOS.
-- La primera version escaneaba los tres depositos enteros con regexp por fila y
-- tardaba MAS DE 60 SEGUNDOS (timeout, con locks sobre Movimientos_Stock
-- mientras los operarios pickean). La version buena arranca del conjunto CHICO
-- —los pares (tanda, articulo) desbalanceados, que hoy son 2— y de ahi sale a
-- buscar. Medido: bloque A solo 286 ms · con el bloque B 542 ms.
--
-- PROBADO ROMPIENDOLO A PROPOSITO (transaccion abortada): se le suman 5 cajas al
-- picking de dos tandas ya armadas, una sin factura y otra con factura.
--   E33A/502 SIN factura -> pila neta 0 y a_facturar 3 + terminado 5 = 8 = lo
--                           pickeado. Se autocorrigio y las cajas aterrizaron.
--   E10A/220 CON factura -> pila neta 5. NO se toco. El guard 1 funciona.
--   dedup por empresa 0 · centinela solo D53A (-2, de agosto, ajena).
-- Sobre los datos vivos: 0 filas tocadas (el unico par desbalanceado es D14B
-- 952E/957E, +4 cajas de agosto, y esta facturado -> guard 1 lo deja afuera).
-- ============================================================================
-- La definicion aplicada, tal cual esta en la base:

CREATE OR REPLACE FUNCTION public.reconciliar_pipeline_stock_etapa2()
 RETURNS integer LANGUAGE plpgsql AS $function$
declare n2 int := 0; n_fix int := 0; n_new int := 0;
begin
  -- ── BLOQUE A — el de siempre. NO SE TOCO. ─────────────────────────────────
  with mov as (
    select upper(trim(ref)) tanda, cod_art art_raw,
           upper(regexp_replace(regexp_replace(trim(cod_art),' +(LK|CH)$',''),'^0+(?=.)','')) artn,
           coalesce(empresa,'Mixto') emp_raw, tipo, delta
    from "Movimientos_Stock" where deposito='separar_pedidos'),
  emp_pick as (
    select tanda, artn, max(emp_raw) emp from mov where tipo='picking' and emp_raw in ('LK','CH')
    group by 1,2 having count(distinct emp_raw) = 1),
  base as (
    select m.tanda, m.art_raw, m.artn,
           case when m.emp_raw = 'Mixto' and ep.emp is not null then ep.emp else m.emp_raw end empresa,
           sum(m.delta) net
    from mov m left join emp_pick ep on ep.tanda = m.tanda and ep.artn = m.artn group by 1,2,3,4),
  elig as (
    select b.* from base b where b.net>0
      and not exists (select 1 from "Movimientos_Stock" m where m.tipo='separado'
                        and upper(trim(m.ref))=b.tanda
                        and upper(regexp_replace(regexp_replace(trim(m.cod_art),' +(LK|CH)$',''),'^0+(?=.)',''))=b.artn)
      and (exists (select 1 from "Registros_Produccion_Virgilio" r where r.opcion='TAP' and upper(trim(split_part(r.texto,'|',1)))=b.tanda)
           or exists (select 1 from "Entregas_Virgilio" e where upper(trim(e.tanda))=b.tanda))),
  tap_leg as (
    select upper(trim(split_part(r.texto,'|',1))) as tanda,
           (array_agg(r.legajo::text order by r.ts_cliente desc nulls last))[1] as leg
    from "Registros_Produccion_Virgilio" r where r.opcion = 'TAP' group by 1),
  ent_t as (select distinct upper(trim(tanda)) tanda from "Entregas_Virgilio"),
  deliv as (
    select upper(trim(tanda)) tanda,
           upper(regexp_replace(regexp_replace(trim(cod_art),' +(LK|CH)$',''),'^0+(?=.)','')) artn,
           sum(coalesce(cajas_entregadas,0)) entregado from "Entregas_Virgilio" group by 1,2),
  alloc as (
    select e.tanda, e.art_raw, e.artn, e.empresa, e.net, coalesce(tl.leg, 'pipeline') as leg,
           case when et.tanda is not null then coalesce(d.entregado,0)
                else sum(e.net) over (partition by e.tanda,e.artn,e.empresa) end as entregado,
           sum(e.net) over (partition by e.tanda, e.artn, e.empresa order by e.art_raw rows between unbounded preceding and current row) as cum
    from elig e left join tap_leg tl on tl.tanda = e.tanda
    left join ent_t et on et.tanda=e.tanda left join deliv d on d.tanda=e.tanda and d.artn=e.artn)
  insert into "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, legajo, empresa)
  select a.art_raw, x.dep, x.delta, 'separado', a.tanda, a.leg, a.empresa
  from alloc a cross join lateral (values
    ('separar_pedidos', -a.net),
    ('a_facturar', greatest(0, least(a.net, a.entregado-(a.cum-a.net)))),
    ('terminado', a.net - greatest(0, least(a.net, a.entregado-(a.cum-a.net))))
  ) x(dep, delta) where x.delta <> 0 on conflict do nothing;
  get diagnostics n2 = row_count;

  -- ── BLOQUE B (v20.18) — el separado se recalcula si el picking cambio ──────
  create temp table if not exists _fx_obj (tanda text, artn text, emp text, art_raw text,
    pick numeric, af_obj numeric, te_obj numeric) on commit drop;
  delete from _fx_obj where true;

  insert into _fx_obj
  with _fx_bad as (
    select upper(trim(ref)) tanda,
           upper(regexp_replace(regexp_replace(trim(cod_art),' +(LK|CH)$',''),'^0+(?=.)','')) artn,
           coalesce(empresa,'Mixto') emp, max(cod_art) art_raw,
           sum(delta) filter (where tipo <> 'separado') pick
      from "Movimientos_Stock" where deposito='separar_pedidos' group by 1,2,3
     having sum(delta) <> 0 and count(*) filter (where tipo='separado') > 0
        and count(distinct cod_art) = 1),
  _fx_ok as (                                                    -- guard 1
    select b.* from _fx_bad b
     where not exists (select 1 from "Movimientos_Stock" f where f.tipo='facturado'
                        and upper(trim(split_part(f.ref,'|',1))) = b.tanda)),
  _fx_n as (
    select b.tanda, b.artn, b.emp, b.art_raw, b.pick,
           count(*) filter (where m.deposito='separar_pedidos') n_sep,
           count(*) filter (where m.deposito='a_facturar')      n_af,
           count(*) filter (where m.deposito='terminado')       n_te
      from _fx_ok b join "Movimientos_Stock" m
        on m.tipo='separado' and m.deposito in ('separar_pedidos','a_facturar','terminado')
       and upper(trim(m.ref)) = b.tanda
       and upper(regexp_replace(regexp_replace(trim(m.cod_art),' +(LK|CH)$',''),'^0+(?=.)','')) = b.artn
       and coalesce(m.empresa,'Mixto') = b.emp
     group by 1,2,3,4,5)
  select n.tanda, n.artn, n.emp, n.art_raw, n.pick,
         greatest(0, least(n.pick, coalesce(e.entregado, n.pick))),
         n.pick - greatest(0, least(n.pick, coalesce(e.entregado, n.pick)))
    from _fx_n n
    left join (select upper(trim(tanda)) tanda,
                      upper(regexp_replace(regexp_replace(trim(cod_art),' +(LK|CH)$',''),'^0+(?=.)','')) artn,
                      sum(coalesce(cajas_entregadas,0)) entregado
                 from "Entregas_Virgilio" group by 1,2) e on e.tanda=n.tanda and e.artn=n.artn
   where n.n_sep <= 1 and n.n_af <= 1 and n.n_te <= 1;          -- guard 2

  update "Movimientos_Stock" m
     set delta = case m.deposito when 'separar_pedidos' then -o.pick
                                 when 'a_facturar'      then o.af_obj else o.te_obj end
    from _fx_obj o
   where m.tipo = 'separado' and upper(trim(m.ref)) = o.tanda
     and upper(regexp_replace(regexp_replace(trim(m.cod_art),' +(LK|CH)$',''),'^0+(?=.)','')) = o.artn
     and coalesce(m.empresa,'Mixto') = o.emp
     and m.deposito in ('separar_pedidos','a_facturar','terminado')
     and m.delta is distinct from (case m.deposito when 'separar_pedidos' then -o.pick
                                                   when 'a_facturar' then o.af_obj else o.te_obj end);
  get diagnostics n_fix = row_count;

  -- ⚠ la pata que NO existe no se puede UPDATEar (el bloque A no la inserto
  -- porque valia 0). Sin esto la pila queda balanceada y las cajas quedan en el
  -- aire. Medido con E33A/502: 5 cajas perdidas.
  insert into "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, legajo, empresa)
  select o.art_raw, x.dep, x.delta, 'separado', o.tanda, 'pipeline', nullif(o.emp,'Mixto')
    from _fx_obj o cross join lateral (values
      ('separar_pedidos', -o.pick), ('a_facturar', o.af_obj), ('terminado', o.te_obj)
    ) x(dep, delta)
   where x.delta <> 0
     and not exists (select 1 from "Movimientos_Stock" m where m.tipo='separado'
                       and m.deposito = x.dep and upper(trim(m.ref)) = o.tanda
                       and upper(regexp_replace(regexp_replace(trim(m.cod_art),' +(LK|CH)$',''),'^0+(?=.)','')) = o.artn
                       and coalesce(m.empresa,'Mixto') = o.emp)
  on conflict do nothing;
  get diagnostics n_new = row_count;

  return n2 + n_fix + n_new;
end;
$function$;

-- chequeos
-- select * from public.gv_stock_tanda_pickeado_negativo;   -- solo D53A (-2)
-- select public.reconciliar_pipeline_stock_etapa2();       -- 0 filas, ~540 ms
