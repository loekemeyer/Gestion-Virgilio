-- v20.72 — Un pedido de una tanda que SALIO SIN EL vuelve a tener camino
-- Problema 472. Pedido de Thomas, 2026-09-21: "cerrá el callejón".
--
-- EL CALLEJON
-- Las dos funciones tenian razon por separado y juntas dejaban el pedido sin ninguna salida:
--   gv_ppp_tanda_mover   -> "La tanda X ya salio en parte... Reprograma el pedido que falta desde
--                            su fila (boton Cambiar de dia de la NP): sale en una tanda nueva,
--                            sin volver a pickear."
--   gv_np_mover_guard    -> 23514 "Esa tanda YA tiene el trabajo hecho... avisa a sistemas."
-- O sea: la primera manda a la segunda y la segunda frena. La pantalla igual ofrece el boton.
--
-- EL CASO QUE LO DESTAPO
-- LK 0027, Albalandia S.R.L. (M), cod 958, 0,709 m3, Misiones por el expreso Snaider. Su tanda
-- E03C tenia 5 NP, se facturaron las 5 el 16/09 con salida 18/09 y salio con 4:
--   LK 0026 · 0031 · 0033 · 0048 -> CCR + CCN (17/09) + CRN (18/09)
--   LK 0027                      -> ninguno de los tres
-- Quedo 3 dias en Pedidos atrasados y nadie podia moverlo.
--
-- LA REGLA
-- El motivo de la v20.01 es que las cajas viven en la PILA DE LA TANDA: mover el papel sin mover
-- el stock deja mercaderia huerfana (caso Martinelli, 92 cajas). Ese motivo NO aplica cuando la
-- pila ya cerro: lo pickeado drenO al facturarse y lo que queda es un bulto identificado
-- esperando el camion. Entonces la exencion pide TRES condiciones, las tres necesarias:
--   (1) alguna NP de la tanda ya salio (CCN vigente o CRN);
--   (2) esta NP no salio;
--   (3) la pila de la tanda cierra en CERO (separar_pedidos + a_facturar).
-- Con saldo vivo NO exime y el guard sigue frenando, que es lo correcto.
--
-- ⚠ NO es un p_forzar. No hay booleano que lo apague: la exencion la decide el estado medido, y
-- por eso vive en su propia funcion, que se puede probar sola con cualquier (np, tanda).
--
-- ⚠ LA PILA SE MIDE CONTANDO LOS REF COMPUESTOS. El drenaje del facturado se anota con
-- ref = '<tanda>|<NP>' (E03C|LK 0027), asi que filtrar ref = 'E03C' a secas da +182 y hace creer
-- que hay saldo vivo cuando en realidad cierra en cero. Es el error que casi frena este arreglo.

-- ── 1. la decision, aislada y testeable ───────────────────────────────────────
create or replace function public.gv_np_mover_exento_salida(p_np text, p_tanda text)
returns boolean
language sql stable security definer
set search_path to 'public','pg_temp'
as $fn$
  with _es_np as (select regexp_replace(upper(btrim(coalesce(p_np,''))),'\.0+$','') np),
       _es_t as (select upper(btrim(coalesce(p_tanda,''))) t),
       -- las NP de la tanda, con las MISMAS tres fuentes que usa gv_ppp_tanda_mover
       _es_nps as (
         select upper(btrim(public.gv_ppp_web_np_label(w.empresa,w.np,w.np_idx))) np
           from public."PPP_Web_Programacion" w, _es_t
          where upper(btrim(coalesce(w.tanda,''))) = _es_t.t
         union
         select regexp_replace(upper(btrim(d.np)),'\.0+$','')
           from public.gv_ppp_programacion_diaria d, _es_t
          where upper(btrim(coalesce(d.tanda,''))) = _es_t.t and d.np is not null
         union
         select regexp_replace(upper(btrim(f.np)),'\.0+$','')
           from public."Facturacion_NP" f, _es_t
          where upper(btrim(coalesce(f.tanda,''))) = _es_t.t and f.np is not null
       ),
       _es_ev as (
         select regexp_replace(upper(btrim(split_part(r.texto,'|',1))),'\.0+$','') np,
                max(r.ts_cliente) filter (where r.opcion = 'CCN') ccn,
                max(r.ts_cliente) filter (where r.opcion = 'FSS') fss,
                max(r.ts_cliente) filter (where r.opcion = 'CRN') crn
           from public."Registros_Produccion_Virgilio" r
          where r.opcion in ('CCN','FSS','CRN') and coalesce(btrim(r.legajo),'') not in ('0','1')
            and btrim(coalesce(r.texto,'')) <> ''
          group by 1
       ),
       _es_salio as (
         select n.np,
                coalesce(e.crn is not null
                      or (e.ccn is not null and e.ccn >= coalesce(e.fss,'-infinity'::timestamptz)), false) salio
           from _es_nps n left join _es_ev e on e.np = n.np
       ),
       _es_pila as (   -- ⚠ los ref compuestos van SI: ahi se anota el drenaje
         select coalesce(sum(m.delta), 0) saldo
           from public."Movimientos_Stock" m, _es_t
          where m.deposito in ('separar_pedidos','a_facturar')
            and (upper(btrim(m.ref)) = _es_t.t
              or upper(btrim(m.ref)) like _es_t.t || '|%'
              or upper(btrim(m.ref)) like '%|' || _es_t.t)
       )
  select (select t from _es_t) <> ''
     and exists (select 1 from _es_salio where salio)
     and not coalesce((select s.salio from _es_salio s, _es_np n where s.np = n.np), false)
     and coalesce((select saldo from _es_pila), 0) = 0;
$fn$;
revoke all on function public.gv_np_mover_exento_salida(text,text) from anon, authenticated;
comment on function public.gv_np_mover_exento_salida(text,text) is
  'v20.72 (problema 472): true si ese pedido se puede sacar de esa tanda aunque la tanda tenga el trabajo hecho, porque la tanda YA SALIO SIN EL y no queda stock vivo que pueda quedar huerfano. Tres condiciones, las tres necesarias: (1) alguna NP de la tanda tiene carga de camion o remito controlado; (2) esta NP no; (3) la pila de la tanda (separar_pedidos + a_facturar, contando los ref compuestos) cierra en cero. Si queda saldo vivo NO exime: ese es el caso Martinelli y lo tiene que mirar una persona.';

-- ── 2. el guard, con la definicion viva del 21/09 mas la exencion ─────────────
-- (el CREATE completo va en el repo a proposito: parchear con replace() sobre pg_get_functiondef
--  y no volcar el resultado es lo que hizo cara la recuperacion del v16.30)
CREATE OR REPLACE FUNCTION public.gv_np_mover_guard(p_nps text[], p_tanda_destino text, p_tanda_entera text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_t text := upper(btrim(coalesce(p_tanda_destino, '')));
  v_ex text := nullif(upper(btrim(coalesce(p_tanda_entera, ''))), '');
  v_msg text;
begin
  -- v20.01 (Thomas, 18/09) — NO SE MUEVE UN PEDIDO CUYA TANDA YA TIENE EL TRABAJO HECHO.
  -- Mover la NP cambia el papel (programacion, Entregas, facturacion, eventos) pero NO mueve las
  -- cajas: el picking y el armado viven en la PILA DE LA TANDA, no del pedido. La mercaderia
  -- queda en la tanda vieja y nadie se entera. Es el caso Martinelli (98622: armada en D69C,
  -- movida a E33A, 92 cajas huerfanas y el facturado de otra NP se las llevo).
  -- BLOQUEA, no avisa: decision de Thomas — "y que inhabilite; cuando haga falta se ve el codigo
  -- en el momento". La excepcion se levanta a mano, caso por caso, mirando el stock.
  -- v20.30 (Luis, 21/09, problema 458) — `p_tanda_entera` es la tanda que viaja COMPLETA. Sus NP
  -- quedan exentas porque el stock viaja con ellas (gv_ppp_tanda_renombrar se lo lleva y lo
  -- fusiona); las de cualquier OTRA tanda pickeada se siguen frenando igual.
  -- v20.72 (Thomas, 21/09, problema 472) — LA TANDA QUE YA SALIO SIN EL. gv_ppp_tanda_mover frena
  -- la tanda que salio en parte y manda a mover la NP sola; este guard frenaba exactamente eso, y
  -- el pedido quedaba sin ningun camino (caso LK 0027 Albalandia: E03C salio el 17/09 con 4 de sus
  -- 5 NP y el quinto quedo 3 dias en Pedidos atrasados). `gv_np_mover_exento_salida` lo exime SOLO
  -- cuando la tanda ya salio sin el Y su pila cierra en cero, o sea cuando no hay una sola caja
  -- que pueda quedar huerfana: lo que queda es un bulto ya facturado esperando el camion. Con
  -- saldo vivo sigue frenando — ahi el motivo de la v20.01 vale igual. NO es un p_forzar: no hay
  -- booleano que lo apague, la exencion la decide el estado medido.
  if v_t = '' then return; end if;
  select string_agg(format('%s (esta en %s, %s)', x.np, x.tanda,
                    concat_ws(' y ', case when x.tiene_picking then 'pickeada' end,
                                     case when x.tiene_armado  then 'armada'   end)), E'\n  - ')
    into v_msg
    from unnest(coalesce(p_nps, array[]::text[])) n
    cross join lateral public.gv_np_trabajo_hecho(n) x
   where x.tanda is not null and x.tanda <> v_t
     and (v_ex is null or x.tanda <> v_ex)
     and (x.tiene_picking or x.tiene_armado)
     and not public.gv_np_mover_exento_salida(n, x.tanda);
  if v_msg is not null then
    raise exception E'No se puede mover a %:\n  - %\n\nEsa tanda YA tiene el trabajo hecho. Si se mueve el pedido, la mercaderia queda fisicamente en la tanda vieja y el sistema la pierde de vista. Hay que resolver el stock primero: avisa a sistemas.', v_t, v_msg
      using errcode = '23514';
  end if;
end $function$;

-- ── 3. que la exencion no pase en silencio ────────────────────────────────────
-- En gv_ppp_pedido_mover, justo antes del gv_ppp_nps_mover_a, va este bloque (aplicado el 21/09
-- con el loop mecanico pg_get_functiondef -> replace -> execute; el cuerpo entero de esa funcion
-- NO se copia aca porque lo tocan varias sesiones y hay que traer la version viva):
--
--   if v_tandas[1] is not null and v_tandas[1] <> '' and v_tandas[1] <> v_t
--      and public.gv_np_mover_exento_salida(v_nps[1], v_tandas[1]) then
--     v_aviso := coalesce(v_aviso || ' ', '') || 'La tanda ' || v_tandas[1]
--             || ' ya habia salido sin este pedido y su pila de stock cierra en cero: sale en tanda '
--             || 'nueva y NO hay que volver a pickear (esta armado y facturado; falta controlar el '
--             || 'remito y cargarlo).';
--   end if;

-- ── 4. el centinela: que el caso se VEA antes de que alguien lo busque ────────
-- Albalandia estuvo 3 dias sin que ninguna pantalla lo dijera. Esta vista lo dice.
create or replace view public.gv_pedido_quedo_sin_salir as
with _qs_nps as (
  select upper(btrim(public.gv_ppp_web_np_label(w.empresa,w.np,w.np_idx))) np,
         upper(btrim(coalesce(w.tanda,''))) tanda, w.cod_cliente cod, w.razon_social,
         coalesce(w.m3,0) m3, w.fecha_entrega, w.zona
    from public."PPP_Web_Programacion" w where coalesce(w.tanda,'') <> ''
  union all
  select regexp_replace(upper(btrim(d.np)),'\.0+$',''), upper(btrim(coalesce(d.tanda,''))),
         d.cod, d.razon_social, coalesce(d.m3,0),
         (case when left(btrim(coalesce(d.fecha_entrega,'')),10) ~ '^\d{4}-\d{2}-\d{2}$'
               then left(btrim(d.fecha_entrega),10)::date end), d.zona
    from public.gv_ppp_programacion_diaria d where coalesce(d.tanda,'') <> '' and d.np is not null
), _qs_ev as (
  select regexp_replace(upper(btrim(split_part(r.texto,'|',1))),'\.0+$','') np,
         max(r.ts_cliente) filter (where r.opcion = 'CCN') ccn,
         max(r.ts_cliente) filter (where r.opcion = 'FSS') fss,
         max(r.ts_cliente) filter (where r.opcion = 'CRN') crn
    from public."Registros_Produccion_Virgilio" r
   where r.opcion in ('CCN','FSS','CRN') and coalesce(btrim(r.legajo),'') not in ('0','1')
     and btrim(coalesce(r.texto,'')) <> '' group by 1
), _qs as (
  select n.*, coalesce(e.crn is not null
           or (e.ccn is not null and e.ccn >= coalesce(e.fss,'-infinity'::timestamptz)), false) salio,
         greatest(e.crn, e.ccn) salio_ts
    from _qs_nps n left join _qs_ev e on e.np = n.np
), _qs_t as (
  select tanda, count(*) filter (where salio) salidas, count(*) filter (where not salio) vivas,
         max(salio_ts) ultima_salida
    from _qs group by tanda
)
select q.np, q.tanda, q.cod, q.razon_social, q.m3, q.fecha_entrega, q.zona,
       t.salidas, t.vivas,
       (t.ultima_salida at time zone 'America/Argentina/Buenos_Aires')::date salio_el_resto_el,
       (current_date - (t.ultima_salida at time zone 'America/Argentina/Buenos_Aires')::date) dias,
       public.gv_np_mover_exento_salida(q.np, q.tanda) se_puede_reprogramar,
       case when public.gv_np_mover_exento_salida(q.np, q.tanda)
            then 'El resto de la tanda salio y este quedo. Ya esta armado: se reprograma con Cambiar de dia de la NP y NO hay que volver a pickear.'
            else 'El resto de la tanda salio y este quedo, PERO la pila de la tanda todavia tiene stock vivo: mirar el stock antes de moverlo (avisa a sistemas).'
       end que_hacer
  from _qs q join _qs_t t on t.tanda = q.tanda
 where not q.salio and t.salidas > 0;

alter view public.gv_pedido_quedo_sin_salir set (security_invoker = true);
revoke all on public.gv_pedido_quedo_sin_salir from anon, authenticated;
comment on view public.gv_pedido_quedo_sin_salir is
  'Centinela (v20.72, problema 472): pedido cuya TANDA ya salio sin el — el resto se cargo y se entrego y este quedo en el deposito. Vacia = todo bien. Nace del caso LK 0027 (Albalandia): E03C salio el 17/09 con 4 de sus 5 NP y el quinto estuvo 3 dias en Pedidos atrasados sin que nada lo mostrara. Solo service_role.';

-- ── 5. para que la exencion no se pueda borrar en silencio ────────────────────
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_np_mover_guard','funcion','gv_np_mover_exento_salida',
        'El guard exime al pedido cuya tanda YA SALIO SIN EL y cuya pila cierra en cero (problema 472, caso LK 0027 Albalandia). Si se le saca esa llamada, un pedido de una tanda que salio en parte vuelve a no tener NINGUN camino para reprogramarse: gv_ppp_tanda_mover lo manda aca y aca se frena.',
        'Thomas','v20.72')
on conflict do nothing;

-- ── CHEQUEO ──────────────────────────────────────────────────────────────────
-- select * from public.gv_pedido_quedo_sin_salir;   -- vacia = ningun bulto quedo atras
-- select * from public.gv_reglas_perdidas;          -- vacia = la exencion sigue en el guard
--
-- ── COMO SE PROBO (21/09) — haciendo ENTRAR la rama, no leyendola ─────────────
-- Hoy no queda ningun caso vivo (Albalandia era el unico), asi que se devolvio LK 0027 a E03C
-- dentro de un bloque `do $$ … raise exception` que ABORTA todo: nada quedo escrito, y se
-- comprobo que LK 0027 sigue en E29A despues de cada prueba. Las cinco ramas:
--   (1) LK 0027 en E03C (salio sin el, pila 0)        -> PASA   (la exencion)
--   (2) LK 0026, que YA salio, misma tanda            -> FRENA
--   (3) LK 0100, en E29C con 176 cajas vivas          -> FRENA  (caso Martinelli intacto)
--   (4) LK 0100 con p_tanda_entera = 'E29C'           -> PASA   (la v20.30 sigue)
--   (5) gv_ppp_pedido_mover('LK 0027', …) completo    -> ANDA   (el camino que aprieta el usuario)
-- La condicion (3) se midio ademas en su insumo, porque no hay un caso que combine salida parcial
-- con stock vivo: la pila de E03C / E12R / E44A / E12S da 0 y la de E29C 176 y la de E51A 50.
