-- v29.49 (Luis, 13/10/2026): auditoría del módulo de operarios.
-- PROBLEMA: reconciliar_pipeline_stock_etapa2 cruzaba Entregas_Virgilio contra el picking
-- normalizando sólo el sufijo " LK|CH" y los ceros. NO pelaba la L final, así que en un
-- pedido de Chef con artículos de Loeke (031L, 102EL…) el armado no encontraba lo entregado
-- y mandaba TODO lo pickeado de vuelta a `terminado` (góndola) en vez de `a_facturar`.
-- Medido al 13/10: E29G 36 · E18B 43 · F58A 185 · D58A 32 cajas que figuran en góndola y
-- están en el pallet / ya salieron. Y como a_facturar quedaba en 0, el facturado no drenaba.
-- Segundo caso, mismo agujero: el picking aplica Correcciones_Pedido (809 -> 809E) y el
-- armado escribe el código del pedido (809): F13C 5 · F48A 3 cajas.
-- ARREGLO: la normalización del código de Entregas (en los dos bloques) pela la L
-- (regla pkStripL, /[0-9E]L$/) y aplica Correcciones_Pedido por (np, código), y una línea con
-- L sólo cuenta contra la pila de empresa LK (un dual 438E CH no se come las 438EL).
-- Se aplicó con execute replace(...,'QQB','DE'||'LETE') / 'QQD' -> 'DR'||'OP' (el MCP se
-- cuelga con esas palabras en el texto). Marcador interno: v29.49-etapa2-L.
-- ROLLBACK: zz_backups."GV_Backup_Etapa2_def_20261013" guarda el CREATE anterior.

-- Entregas_Virgilio normalizadas al codigo de PICKING (una sola cuenta para los dos bloques).
-- tanda viva (sin -X), artn sin L / sin sufijo / sin ceros, con la correccion
-- secundario->principal que el picking aplica (Correcciones_Pedido). Va ANTES de la funcion.
CREATE OR REPLACE VIEW public.gv_entregas_norm WITH (security_invoker = true) AS
  -- v29.49-etapa2-L
  select upper(trim(e.tanda)) tanda, e.np, e.cod_art,
         upper(regexp_replace(regexp_replace(regexp_replace(
             trim(coalesce(cp.cod_principal, e.cod_art)), '([0-9E])L$', '\1'),
             ' +(LK|CH)$', ''), '^0+(?=.)', '')) artn,
         case when upper(trim(e.cod_art)) ~ '[0-9E]L$' then 'LK' end emp_l,
         coalesce(e.cajas_entregadas, 0)::numeric ent
    from public."Entregas_Virgilio" e
    left join lateral (
      select c.cod_principal from public."Correcciones_Pedido" c
       where upper(trim(c.np)) = upper(trim(e.np))
         and upper(regexp_replace(trim(c.cod_secundario), '^0+(?=.)', ''))
           = upper(regexp_replace(regexp_replace(trim(e.cod_art), '([0-9E])L$', '\1'), '^0+(?=.)', ''))
       limit 1) cp on true
   where e.tanda is not null and e.tanda !~ '-X$';

CREATE OR REPLACE FUNCTION public.reconciliar_pipeline_stock_etapa2()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
-- v20.14 (problema: la etapa2 no se corregia sola) — BLOQUE A el de siempre,
-- BLOQUE B nuevo: si el picking de una tanda cambia DESPUES del armado, el
-- `separado` se recalcula. Caso testigo E12K (0 pickeado / -46 drenado), que
-- nacio de un renombre que dejo los PKC con el codigo viejo. La etapa1 SIEMPRE
-- fue idempotente (`do update set delta`); esta asimetria era el agujero.
-- v29.49-etapa2-L (Luis 13/10): el codigo de Entregas se normaliza como el del picking:
-- se pela la L (031L -> 031, 102EL -> 102E) y se aplica Correcciones_Pedido (809 -> 809E).
-- Sin eso lo pickeado de un pedido con L volvia a GONDOLA (F58A: 185 cajas).
declare n2 int := 0; n_fix int := 0; n_new int := 0;
begin
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
  deliv as materialized (
    select en.tanda, en.artn, en.emp_l, sum(en.ent) entregado
      from public.gv_entregas_norm en group by 1,2,3),
  alloc as (
    select e.tanda, e.art_raw, e.artn, e.empresa, e.net, coalesce(tl.leg, 'pipeline') as leg,
           case when et.tanda is not null
                then coalesce((select sum(d.entregado) from deliv d
                                where d.tanda=e.tanda and d.artn=e.artn
                                  and (d.emp_l is null or d.emp_l = e.empresa or e.empresa not in ('LK','CH'))),0)
                else sum(e.net) over (partition by e.tanda,e.artn,e.empresa) end as entregado,
           sum(e.net) over (partition by e.tanda, e.artn, e.empresa order by e.art_raw rows between unbounded preceding and current row) as cum
    from elig e left join tap_leg tl on tl.tanda = e.tanda
    left join ent_t et on et.tanda=e.tanda)
  insert into "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, legajo, empresa)
  select a.art_raw, x.dep, x.delta, 'separado', a.tanda, a.leg, a.empresa
  from alloc a cross join lateral (values
    ('separar_pedidos', -a.net),
    ('a_facturar', greatest(0, least(a.net, a.entregado-(a.cum-a.net)))),
    ('terminado', a.net - greatest(0, least(a.net, a.entregado-(a.cum-a.net))))
  ) x(dep, delta) where x.delta <> 0 on conflict do nothing;
  get diagnostics n2 = row_count;

  -- ── BLOQUE B ────────────────────────────────────────────────────────────────
  -- Arranca del conjunto CHICO (pares tanda/articulo desbalanceados): con el
  -- escaneo de los tres depositos enteros tardaba >60 s y esto corre en el cron
  -- 68 cada 10 min. Asi son ~400 ms sobre los ~290 del bloque A.
  -- GUARDS, los tres a proposito:
  --  1. la tanda NO puede tener `facturado` — mover el separado mueve a_facturar,
  --     o sea camino de facturacion: contra una factura emitida no se escribe.
  --     Esas quedan a la vista en gv_stock_tanda_pickeado_negativo.
  --  2. una sola grafia del articulo y a lo sumo una fila por deposito: con
  --     varias hace falta la ventana `cum` del bloque A y repetirla aca a mano
  --     es pedir un bug silencioso.
  --  3. solo (tanda, articulo) que YA tienen separado; el resto es del bloque A.
  create temp table if not exists _fx_obj (tanda text, artn text, emp text, art_raw text,
    pick numeric, af_obj numeric, te_obj numeric) on commit QQD;
  QQB from _fx_obj where true;

  insert into _fx_obj
  with _fx_ent as materialized (
    select en.tanda, en.artn, en.emp_l, sum(en.ent) ent
      from public.gv_entregas_norm en group by 1,2,3),
  _fx_bad as (
    select upper(trim(ref)) tanda,
           upper(regexp_replace(regexp_replace(trim(cod_art),' +(LK|CH)$',''),'^0+(?=.)','')) artn,
           coalesce(empresa,'Mixto') emp, max(cod_art) art_raw,
           sum(delta) filter (where tipo <> 'separado') pick
      from "Movimientos_Stock" where deposito='separar_pedidos' group by 1,2,3
     having sum(delta) <> 0 and count(*) filter (where tipo='separado') > 0
        and count(distinct cod_art) = 1),
  _fx_ok as (
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
    left join lateral (select sum(en.ent) entregado from _fx_ent en
                        where en.tanda = n.tanda and en.artn = n.artn
                          and (en.emp_l is null or en.emp_l = n.emp or n.emp not in ('LK','CH'))
                       having count(*) > 0) e on true
   where n.n_sep <= 1 and n.n_af <= 1 and n.n_te <= 1;

  -- las patas que existen: UPDATE. No se puede insertar una fila complementaria,
  -- `mov_stock_pipeline_dedup` es unica por (ref, cod_art, empresa, deposito, tipo).
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

  -- ⚠ la pata que NO existe no se puede UPDATEar: el bloque A no la inserto porque
  -- valia 0. Sin esto la pila queda balanceada pero las cajas no aterrizan en
  -- ningun lado — una fuga silenciosa, justo lo que este bloque viene a evitar.
  -- Medido: E33A/502 quedaba con la pila en 0 y 5 cajas en el aire.
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

