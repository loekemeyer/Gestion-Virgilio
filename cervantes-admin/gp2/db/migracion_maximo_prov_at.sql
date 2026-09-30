-- =====================================================================
-- MIGRACION 2026-09-23 — EL PROV. DE ART. TERMINADO TIENE CONSUMO, MAXIMO Y SUGERIDO
--
-- PEDIDO [usuario 2026-09-23, textual]: "En el modulo prov de art terminado, cuando voy a enviar:
-- me aparece 0 sugerido para enviar. El inventario maximo de los prov de art terminado tiene que
-- ser al igual que los talleristas de un mes de consumo. Si hay mas de un prov de art terminado o
-- tallerista que haga un articulo tenes que dividir segun la proporcion. Si no esta la proporcion
-- --> por default 50% cada uno".
--
-- POR QUE APARECIA 0 (y por que cargar maximos a mano no lo arreglaba): el sugerido de la Tablet
-- NO sale de inventario.maximo, sale de la CTE `rep` de tablet_bundle, y esa CTE filtraba
-- `where tipo in ('proveedor_servicio','tallerista')`. El Prov AT nunca entraba, asi que el
-- left join de env_x no encontraba fila y sugerido/maximo viajaban NULL. No era un dato que
-- faltaba: era una cuenta que no se hacia para ese destino.
--
-- LO QUE SE CONSTRUYE (calcado del precedente de talleristas, CONOCIMIENTO 4du):
--   reparto_prov_at        la tabla del % dictado por el dueno (articulo + prov AT)
--   v_hace_articulo        quien PRODUCE/ENTREGA el terminado de cada articulo (prov AT y tallerista)
--   v_reparto_at_efectivo  el % efectivo de cada prov AT; sin dictar, partes iguales (2 -> 50/50)
--   v_consumo_prov_at      demanda del articulo x ese % = carton/caja que consume cada prov AT
--   v_nivel_stock_prov_at  max_calc = consumo x meses_stock de SU ubicacion (default 1 = un mes)
--   recalcular_maximos_prov_at()  escribe inventario.maximo con origen est_madre_x_reparto
--   tablet_bundle()        la CTE rep ahora tambien cubre 'proveedor_at'
--
-- DOS COSAS QUE QUEDAN DICHAS, A PROPOSITO:
--  1. EL DENOMINADOR YA CUENTA A LOS TALLERISTAS, pero HOY NO CAMBIA NADA: medido el 2026-09-23,
--     NINGUN articulo lo hacen un prov AT y un tallerista a la vez (0 filas). Si manana aparece uno,
--     el prov AT queda en 50 % solo, que es lo que pidio el usuario. Lo que NO toca esta migracion
--     es v_consumo_tallerista: el tallerista seguiria con el 100 % de su parte hasta que el dueno lo
--     confirme, porque hay filas de articulo_prov_at que el propio CONOCIMIENTO marca como resaca
--     (4cy/9030: Tierra Nativa "entregando" terminados que se arman adentro) y partirle el maximo a
--     un tallerista por un dato sucio es peor que dejarlo alto. Cuando pase, es una linea:
--     multiplicar v_consumo_tallerista por (100 - suma del % de los prov AT de ese articulo) / 100.
--  2. LAS PIEZAS SALEN DE LA RECETA DEL ARTICULO (sector 10 y 11), que es el mismo criterio que ya
--     usan tablet_bundle (env), cartones_para_reemplazo y stock_general_extra_bundle. Limite
--     conocido: cuando dos prov AT declaran CAJAS DISTINTAS para el mismo articulo (4bk: Cabral A2
--     y Pintos A8), la receta tiene una sola y la otra vive en su ruta. Ese caso se arregla aparte,
--     en las tres funciones a la vez, no aca.
--
-- NO TOCA NINGUN DATO: todo es DDL (una tabla vacia, cuatro vistas, dos funciones). Los maximos
-- solo se mueven cuando alguien corre recalcular_maximos_prov_at(), y las filas de inventario que
-- faltan solo se crean si se la llama con p_crear_faltantes => true.
--
-- LO MEDIDO EN LA BASE ANTES DE APLICARLA (2026-09-23):
--   · 5 prov AT aparecen hoy en la Tablet para enviarles carton/caja (Pintos 15 piezas, Lopez Jose 6,
--     Maspoli 5, The Plast 4, Carriero 3) y las 33 filas quedan CON consumo: ninguna sigue en "—".
--   · Articulos con DOS prov AT: dos, el 222 y el 910 (Maspoli / Pintos), los dos "Bate Bife Madera".
--     Ahi el carton 222 (M2B) pasa a 545 + 545 y el 910 (Q5) a 142 + 142 — el default 50/50 que
--     pidio el usuario. Si el dueno dicta otra proporcion, va en reparto_prov_at.
--   · Las 12 ubicaciones de prov AT tienen meses_stock NULL y CERO filas de inventario: por eso el
--     max_calc cae a 1 mes solo (coalesce) y por eso recalcular_maximos_prov_at informa lo que le
--     falta fila en vez de fallar. El sugerido de la Tablet NO depende de eso (se calcula al vuelo).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) reparto_prov_at — el % que dicta el dueno
-- ---------------------------------------------------------------------
create table if not exists "GP2".reparto_prov_at (
  id bigint generated always as identity,
  articulo_id bigint not null,
  proveedor_at_id bigint not null,
  pct numeric not null,
  actualizado_en timestamp with time zone not null default now(),
  constraint reparto_prov_at_pkey primary key (id),
  constraint reparto_prov_at_articulo_id_proveedor_at_id_key unique (articulo_id, proveedor_at_id),
  constraint reparto_prov_at_articulo_id_fkey foreign key (articulo_id) references "GP2".articulo(id),
  constraint reparto_prov_at_proveedor_at_id_fkey foreign key (proveedor_at_id) references "GP2".proveedor_at(id),
  constraint reparto_prov_at_pct_check check ((pct > (0)::numeric) and (pct <= (100)::numeric))
);
alter table "GP2".reparto_prov_at enable row level security;
drop policy if exists p_gp2_select on "GP2".reparto_prov_at;
create policy p_gp2_select on "GP2".reparto_prov_at for select to anon, authenticated using (true);

comment on table "GP2".reparto_prov_at is 'Que porcentaje del volumen de un ARTICULO entrega cada proveedor de articulo terminado, cuando lo hacen dos o mas (o cuando lo comparte con un tallerista). Lo dicta el dueno y se carga por SQL, igual que reparto_tallerista: NO hay pantalla que lo escriba (el 2026-09-15 un Guardar con el default 50/50 a la vista quedo grabado como dato dictado, ver CONOCIMIENTO 4dw). Sin fila = parte igual entre los que hacen el articulo.';

-- ---------------------------------------------------------------------
-- 2) v_hace_articulo — quien produce o entrega el TERMINADO de cada articulo
--    Tres fuentes, unidas: el paso proveedor_at de la ruta, el padron articulo_prov_at (hay
--    articulos de Prov AT sin ruta armada) y el tallerista cuyo paso SALE en sector 12 (el
--    terminado), que es la misma definicion que ya usa __sim_articulo para saber "quien entrega".
-- ---------------------------------------------------------------------
create or replace view "GP2".v_hace_articulo as
 select distinct r.articulo_id,
        'proveedor_at'::text as tipo,
        rp.proveedor_at_id as ref_id
   from "GP2".ruta_paso rp
   join "GP2".ruta r on r.id = rp.ruta_id
  where rp.tipo_paso = 'proveedor_at' and rp.proveedor_at_id is not null and r.articulo_id is not null
    and exists (select 1 from "GP2".proveedor_at p where p.id = rp.proveedor_at_id and coalesce(p.activo, true))
union
 select distinct a.id,
        'proveedor_at'::text,
        apa.proveedor_at_id
   from "GP2".articulo_prov_at apa
   join "GP2".articulo a on a.codigo = apa.cod_art
  where coalesce(apa.activo, true)
    and not coalesce(a.discontinuado, false)
    and exists (select 1 from "GP2".proveedor_at p where p.id = apa.proveedor_at_id and coalesce(p.activo, true))
union
 select distinct r.articulo_id,
        'tallerista'::text,
        rp.tallerista_id
   from "GP2".ruta_paso rp
   join "GP2".ruta r on r.id = rp.ruta_id
   join "GP2".componente c on c.id = rp.comp_salida_id and c.sector_id = 12
  where rp.tipo_paso = 'tallerista' and rp.tallerista_id is not null and r.articulo_id is not null;

comment on view "GP2".v_hace_articulo is 'Quien produce o entrega el ARTICULO TERMINADO: prov AT (por su paso de ruta o por el padron articulo_prov_at) y tallerista (paso cuya salida es sector 12). Es el denominador del reparto: "mas de un prov AT o tallerista que haga un articulo" [usuario 2026-09-23].';

-- ---------------------------------------------------------------------
-- 3) v_reparto_at_efectivo — el % de cada prov AT
--    Regla: el dictado manda; el que no tiene fila se reparte en partes iguales lo que sobra del
--    100. Dos que hacen el mismo articulo y nadie dicto nada -> 50 y 50, marcado es_supuesto
--    ("falta que lo diga el dueno", no es un dato). Si los dictados ya llenan el 100 (o se pasan),
--    se normalizan sobre su propia suma, igual que v_reparto_efectivo.
-- ---------------------------------------------------------------------
create or replace view "GP2".v_reparto_at_efectivo as
 with hacen as (
   select h.articulo_id, h.tipo, h.ref_id, rp.pct
     from "GP2".v_hace_articulo h
     left join "GP2".reparto_prov_at rp
       on h.tipo = 'proveedor_at' and rp.articulo_id = h.articulo_id and rp.proveedor_at_id = h.ref_id
 ), n as (
   select articulo_id,
          count(*) as n_hacen,
          count(pct) as n_con_pct,
          coalesce(sum(pct), 0::numeric) as suma_pct
     from hacen
    group by articulo_id
 )
 select h.articulo_id,
        h.ref_id as proveedor_at_id,
        round(
          case
            when n.n_con_pct = n.n_hacen or n.suma_pct >= 100::numeric
              then h.pct * 100::numeric / nullif(n.suma_pct, 0)
            when h.pct is not null then h.pct
            else (100::numeric - n.suma_pct) / (n.n_hacen - n.n_con_pct)::numeric
          end, 4) as pct,
        h.pct is null and n.n_hacen > 1 as es_supuesto,
        n.n_hacen
   from hacen h
   join n on n.articulo_id = h.articulo_id
  where h.tipo = 'proveedor_at';

comment on view "GP2".v_reparto_at_efectivo is 'Porcentaje del volumen de un articulo que entrega cada prov AT. El % dictado en reparto_prov_at manda; el resto se reparte en partes iguales entre los que hacen el articulo (prov AT y talleristas del terminado), o sea 50/50 cuando son dos y nadie dicto nada [usuario 2026-09-23]. es_supuesto = ese default, no un dato.';

-- ---------------------------------------------------------------------
-- 4) v_consumo_prov_at — carton y caja que consume cada prov AT, por mes
--    El equivalente de v_consumo_tallerista del otro lado del mostrador: demanda del articulo
--    (Est Madre explotada, v_consumo_demanda) x su %. Solo sector 10 (Carton) y 11 (Caja), que es
--    lo unico que crear_envio_prov_at acepta mandarle.
-- ---------------------------------------------------------------------
create or replace view "GP2".v_consumo_prov_at as
 select re.proveedor_at_id,
        ac.componente_id,
        sum(d.uni_mes * re.pct / 100::numeric) as uni_mes,
        bool_or(re.es_supuesto) as tiene_supuesto
   from "GP2".v_reparto_at_efectivo re
   join "GP2".articulo_componente ac on ac.articulo_id = re.articulo_id
   join "GP2".componente c on c.id = ac.componente_id and c.sector_id in (10, 11)
                          and not coalesce(c.discontinuado, false)
   join "GP2".v_consumo_demanda d on d.articulo_id = re.articulo_id and d.componente_id = ac.componente_id
  group by re.proveedor_at_id, ac.componente_id;

comment on view "GP2".v_consumo_prov_at is 'Consumo uni/mes de carton y caja por (prov AT, componente), con la demanda del articulo repartida por v_reparto_at_efectivo. El espejo de v_consumo_tallerista para el proveedor de articulo terminado.';

-- ---------------------------------------------------------------------
-- 5) v_nivel_stock_prov_at — el maximo que sale de ese consumo
--    meses_stock de la ubicacion del PROV AT (no la del sector de la pieza): el usuario lo pidio
--    "igual que los talleristas, de un mes de consumo", y los 12 talleristas tienen 1 mes. Sin
--    meses_stock cargado cae a 1, asi que no hace falta tocar la tabla ubicacion para que ande.
-- ---------------------------------------------------------------------
create or replace view "GP2".v_nivel_stock_prov_at as
 select i.id as inv_id,
        i.componente_id,
        i.ubicacion_id,
        u.ref_id as proveedor_at_id,
        coalesce(cp.uni_mes, 0::numeric) as consumo_mes,
        coalesce(u.meses_stock, 1) as meses_stock,
        round(coalesce(cp.uni_mes, 0::numeric) * coalesce(u.meses_stock, 1)) as max_calc,
        coalesce(cp.tiene_supuesto, false) as tiene_supuesto,
        i.maximo,
        i.maximo_origen
   from "GP2".inventario i
   join "GP2".ubicacion u on u.id = i.ubicacion_id and u.tipo = 'proveedor_at'
   left join "GP2".v_consumo_prov_at cp on cp.proveedor_at_id = u.ref_id and cp.componente_id = i.componente_id;

comment on view "GP2".v_nivel_stock_prov_at is 'max_calc = consumo repartido x meses_stock de la ubicacion del prov AT (default 1 mes). La usa recalcular_maximos_prov_at. Gemela de v_nivel_stock_tallerista.';

-- ---------------------------------------------------------------------
-- 6) recalcular_maximos_prov_at — escribe el maximo
--    Misma forma que recalcular_maximos_talleristas: no pisa un maximo 'fisico', no limpia la fila
--    que quedo sin consumo (un consumo 0 puede ser un articulo sin proyeccion en Est Madre, no una
--    verdad) e informa lo que no toco. Lo que agrega: las filas de inventario que NO EXISTEN. A un
--    prov AT al que nunca se le mando un carton no se le puede escribir el maximo porque no hay
--    fila; se informan siempre y solo se crean (en 0, con su maximo) si se pide explicitamente.
-- ---------------------------------------------------------------------
create or replace function "GP2".recalcular_maximos_prov_at(
    p_crear_faltantes boolean default false,
    p_componentes bigint[] default null::bigint[])
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'GP2'
as $function$
declare
  v_set int := 0; v_creados int := 0; v_cambios jsonb; v_faltan jsonb; v_sin_consumo jsonb;
begin
  with objetivo as (
    select v.inv_id, v.componente_id, v.proveedor_at_id, v.max_calc, v.maximo as maximo_viejo
      from v_nivel_stock_prov_at v
     where coalesce(v.maximo_origen, '') <> 'fisico'
       and v.max_calc > 0
       and (p_componentes is null or v.componente_id = any (p_componentes))
  ), upd as (
    update inventario i
       set maximo = o.max_calc, maximo_origen = 'est_madre_x_reparto'
      from objetivo o
     where i.id = o.inv_id
       and (i.maximo is distinct from o.max_calc or i.maximo_origen is distinct from 'est_madre_x_reparto')
    returning o.proveedor_at_id, o.componente_id, o.maximo_viejo, o.max_calc
  )
  select count(*), coalesce(jsonb_agg(jsonb_build_object(
           'prov_at', (select nombre from proveedor_at p where p.id = u.proveedor_at_id),
           'componente', (select codigo from componente c where c.id = u.componente_id),
           'antes', u.maximo_viejo, 'ahora', u.max_calc) order by u.proveedor_at_id), '[]'::jsonb)
    into v_set, v_cambios from upd u;

  -- (prov AT, pieza) con consumo pero SIN fila de inventario en su ubicacion. Al 2026-09-23 son
  -- TODAS: las 12 ubicaciones de prov AT tienen 0 filas de inventario, asi que sin este paso no
  -- hay donde escribir un maximo. Se informan siempre; se crean solo si lo piden.
  select coalesce(jsonb_agg(jsonb_build_object(
           'prov_at', (select nombre from proveedor_at p where p.id = f.proveedor_at_id),
           'componente', (select codigo from componente c where c.id = f.componente_id),
           'maximo', f.max_calc) order by f.proveedor_at_id), '[]'::jsonb)
    into v_faltan
    from (select cp.proveedor_at_id, cp.componente_id, u.id as ubic_id,
                 round(cp.uni_mes * coalesce(u.meses_stock, 1)) as max_calc
            from v_consumo_prov_at cp
            join ubicacion u on u.tipo = 'proveedor_at' and u.ref_id = cp.proveedor_at_id
           where cp.uni_mes > 0
             and (p_componentes is null or cp.componente_id = any (p_componentes))
             and not exists (select 1 from inventario i
                              where i.componente_id = cp.componente_id and i.ubicacion_id = u.id)) f;

  if p_crear_faltantes then
    with falta as (
      select cp.proveedor_at_id, cp.componente_id, u.id as ubic_id,
             round(cp.uni_mes * coalesce(u.meses_stock, 1)) as max_calc
        from v_consumo_prov_at cp
        join ubicacion u on u.tipo = 'proveedor_at' and u.ref_id = cp.proveedor_at_id
       where cp.uni_mes > 0
         and (p_componentes is null or cp.componente_id = any (p_componentes))
         and not exists (select 1 from inventario i
                          where i.componente_id = cp.componente_id and i.ubicacion_id = u.id)
    ), ins as (
      insert into inventario (componente_id, ubicacion_id, cantidad, maximo, maximo_origen, actualizado_en)
      select f.componente_id, f.ubic_id, 0, f.max_calc, 'est_madre_x_reparto', now()
        from falta f
      returning 1
    )
    select count(*) into v_creados from ins;
  end if;

  -- filas con maximo cargado que hoy no tienen consumo: se informan, no se limpian
  select coalesce(jsonb_agg(jsonb_build_object(
           'prov_at', (select nombre from proveedor_at p where p.id = v.proveedor_at_id),
           'componente', (select codigo from componente c where c.id = v.componente_id),
           'maximo', v.maximo) order by v.proveedor_at_id), '[]'::jsonb)
    into v_sin_consumo
    from v_nivel_stock_prov_at v
   where v.max_calc = 0 and v.maximo is not null and coalesce(v.maximo_origen, '') <> 'fisico';

  return jsonb_build_object('ok', true, 'actualizados', v_set, 'creados', v_creados,
    'faltan_fila_inventario', v_faltan, 'sin_consumo', v_sin_consumo, 'cambios', v_cambios);
end $function$;

revoke execute on function "GP2".recalcular_maximos_prov_at(boolean, bigint[]) from public;
-- interna, como el resto de las recalcular_*: NO se le da EXECUTE a anon.

-- ---------------------------------------------------------------------
-- 7) tablet_bundle — la CTE rep ahora cubre tambien al prov AT
--    Cambios, todos dentro de rep (el resto de la funcion es identico al de db/funciones_GP2.sql
--    del 2026-09-21):
--      · cons_pat: v_consumo_prov_at materializada una vez, como las otras tres (2026-09-22);
--      · el filtro de destinos suma 'proveedor_at';
--      · el consumo del prov AT sale de cons_pat;
--      · los MESES del prov AT salen de SU ubicacion (los del tallerista y el P.S. siguen saliendo
--        del sector de la pieza, sin tocar).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "GP2".tablet_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
with
-- FASONERO (proveedor_servicio.pedido_por_oc, hoy Maspoli): lo que falta entregar de su O.C.
-- ENVIADA, sumado por (proveedor, pieza que se le manda). Es el techo de lo que hay que mandarle:
-- si nos debe 10 mangos, hay que tener 10 virolas en su poder [usuario 2026-09-18]. Mismo criterio
-- que el inyector (rep_iny): el borrador es un pedido que todavia no salio y no dispara envio.
oc_ps as (
  select p.proveedor_id, p.comp_entrada_id as comp_id, sum(coalesce(x.pend,0)) as pend
    from (select distinct rp.proveedor_id, rp.comp_entrada_id, rp.comp_salida_id
            from ruta_paso rp
            join proveedor_servicio ps on ps.id = rp.proveedor_id and ps.pedido_por_oc
           where rp.tipo_paso = 'proveedor_servicio' and rp.comp_entrada_id is not null) p
    left join lateral (
       select sum(oi.cantidad - coalesce(oi.recibido,0)) as pend
         from orden_compra_item oi join orden_compra o on o.id = oi.oc_id
        where oi.componente_id = p.comp_salida_id and o.estado = 'enviada'
          and oi.cantidad > coalesce(oi.recibido,0)
    ) x on true
   group by p.proveedor_id, p.comp_entrada_id
),
env as (
  select v.tipo, v.ref_id::text as ref, v.comp_id
    from v_contraparte_parte v
   where v.lado = 'entrada'
     and ( (v.tipo = 'tallerista'
            and exists (select 1 from tallerista t where t.id = v.ref_id and t.activo and t.id <> 3))
        or (v.tipo = 'proveedor_servicio'
            -- los PS hibridos (Charcas/Eclipse) NO se envian desde la tablet: la entrega de su
            -- materia prima se registra solo en el modulo Casos especiales [usuario 2026-09-17].
            -- el FASONERO aparece SIEMPRE, igual que el inyector: sin O.C. su sugerido es 0 y sube
            -- cuando la orden sale [usuario 2026-09-18: "los inyectores por mas que no este
            -- cargada la orden de compra aparecen igual con cero sugerido, tendria que aparecer
            -- Maspoli con cero sugerido y cuando sale la orden de compra ahi sube el sugerido de
            -- entrega de virolas"]. El techo lo pone oc_ps en la CTE rep, que sin O.C. da 0.
            and exists (select 1 from proveedor_servicio ps where ps.id = v.ref_id and not ps.hibrido)) )
  union all
  select 'proveedor_at', apa.proveedor_at_id::text, ac.componente_id
    from articulo_prov_at apa
    join articulo a on a.codigo = apa.cod_art
    join articulo_componente ac on ac.articulo_id = a.id
    join componente c on c.id = ac.componente_id
   where coalesce(apa.activo,true)
     and c.sector_id in (10,11) and not coalesce(c.discontinuado,false)
  union all
  select 'inyector', c.proveedor, c.material_id
    from componente c
   where c.material_id is not null and c.estado_compra is null and c.proveedor is not null
     and exists (select 1 from proveedor_insumo pi where pi.nombre = c.proveedor)
   group by c.proveedor, c.material_id
),
-- rep (Enviar a PS / tallerista): el Maximo y el Sugerido salen del CONSUMO DE LA PIEZA QUE SE
-- ENVIA (la entrada), no de la salida. [usuario 2026-09-17: "sale del consumo de estadistica
-- madre x max de meses por ubicacion"]. Antes se calculaba sobre la SALIDA (inventario.maximo de
-- la pieza procesada/armada): las salidas de tallerista son nodos "X Terminado" del sector 12 que
-- no tienen demanda ni maximo cargado, asi que el 90% de las filas salia en 0 (Martin 6 de 94).
-- Ahora maximo = consumo(entrada) x meses_stock de la ubicacion del sector de la entrada:
--   · tallerista -> v_consumo_tallerista (la demanda YA repartida entre los que hacen el paso,
--     via v_reparto_efectivo; asi no se le pide un mes entero a cada uno de dos que arman lo mismo),
--   · PS         -> v_consumo_componente (demanda total de la pieza),
--   · PROV AT    -> v_consumo_prov_at (la demanda del articulo repartida entre los prov AT que lo
--     entregan y los talleristas que lo arman; sin reparto dictado, partes iguales) [usuario
--     2026-09-23: "el inventario maximo de los prov de art terminado tiene que ser al igual que
--     los talleristas de un mes de consumo... si hay mas de uno dividir segun la proporcion"],
--   · fleje (sector 5, en kg) -> v_consumo_fleje_kg (kg/mes) para cualquiera de los dos tipos.
-- Sugerido = maximo − lo que el tercero ya tiene (inventario en su ubicacion). meses_stock cae a 1
-- si la ubicacion no lo tiene (mismo default que OC). OJO, la ubicacion de la que salen los MESES
-- no es la misma para todos: el tallerista y el P.S. la toman del SECTOR de la pieza (como estaba),
-- y el prov AT de SU PROPIA ubicacion, que es donde vive el "un mes" que pidio el usuario. El consumo ya viene en la unidad de la
-- entrada (kg para fleje, uni para el resto), asi que no hay factor de conversion.
-- CONSUMOS, UNA sola vez (2026-09-22): antes se consultaban las tres vistas de consumo fila por
-- fila dentro de rep (una subconsulta correlacionada por cada pieza x destino), y cada vista es
-- un agregado de 30-40 ms. Materializadas aca se calculan una vez y rep las cruza por join:
-- tablet_bundle bajo de ~700 ms a ~200 ms con el mismo resultado.
cons_fk   as materialized (select componente_id, consumo_kg_mes from v_consumo_fleje_kg),
cons_tall as materialized (select tallerista_id, componente_id, uni_mes from v_consumo_tallerista),
cons_comp as materialized (select componente_id, consumo_uni_mes from v_consumo_componente),
cons_pat  as materialized (select proveedor_at_id, componente_id, uni_mes from v_consumo_prov_at),
rep as (
  select e.tipo, e.ref, e.comp_id,
         round(t.techo) as maximo_dest,
         null::numeric as stock_dest,   -- el front muestra saldo_dest como "Stock", no este
         greatest(0, round(
            t.techo
            - coalesce((select i.cantidad from inventario i
                         where i.componente_id = e.comp_id
                           and i.ubicacion_id = ubic_de(e.tipo, e.ref::bigint) limit 1),0)
         , 2)) as sugerido
    from (select distinct tipo, ref, comp_id from env
           where tipo in ('proveedor_servicio','tallerista','proveedor_at')) e
    join componente ent on ent.id = e.comp_id
    left join cons_fk   fk on fk.componente_id = e.comp_id
    left join cons_tall ct on ct.componente_id = e.comp_id and e.tipo = 'tallerista'
                          and ct.tallerista_id = e.ref::bigint
    left join cons_pat cpa on cpa.componente_id = e.comp_id and e.tipo = 'proveedor_at'
                          and cpa.proveedor_at_id = e.ref::bigint
    left join cons_comp vc on vc.componente_id = e.comp_id
    cross join lateral (
       select
         coalesce((select u.meses_stock from ubicacion u
                    where u.id = case when e.tipo = 'proveedor_at'
                                        then ubic_de('proveedor_at', e.ref::bigint)
                                      else ubic_de('sector', ent.sector_id) end
                    limit 1), 1) as meses,
         case
           when ent.sector_id = 5         then coalesce(fk.consumo_kg_mes, 0)
           when e.tipo = 'tallerista'     then coalesce(ct.uni_mes, 0)
           when e.tipo = 'proveedor_at'   then coalesce(cpa.uni_mes, 0)
           else                                coalesce(vc.consumo_uni_mes, 0)
         end as consumo
    ) cons
    cross join lateral (
       -- FASONERO: el techo es lo que falta entregar de su O.C., no el consumo x meses. Para el
       -- resto (PS normal y tallerista) no cambia nada.
       select case when e.tipo = 'proveedor_servicio'
                    and exists (select 1 from proveedor_servicio ps3
                                 where ps3.id = e.ref::bigint and ps3.pedido_por_oc)
                   then coalesce((select oc.pend from oc_ps oc
                                   where oc.proveedor_id = e.ref::bigint and oc.comp_id = e.comp_id), 0)
                   else cons.consumo * cons.meses end as techo
    ) t
),
-- INYECTOR: el pedido de bolsas surge de la O.C. de partes plasticas ENVIADA (no del deficit
-- automatico). Sin OC enviada -> maximo(O.C.)=0 y sugerido=0; recien cuando se manda la OC de partes
-- (Compras/OC_GP2, proveedor = el inyector) aparecen los kg de bolsa. [usuario 2026-09-16]
rep_iny as (
  select 'inyector'::text as tipo, c.proveedor as ref, c.material_id as comp_id,
         sum(coalesce(ocp.pend,0) * coalesce(c.kg_x_uni,0)) as maximo_dest,  -- O.C. de partes -> kg de resina
         0::numeric as stock_dest,                                           -- el Stock lo pone online_sector en el front
         greatest(0, round(
            sum(coalesce(ocp.pend,0) * coalesce(c.kg_x_uni,0))
            - coalesce((select ir.cantidad from inventario ir
                         where ir.componente_id = c.material_id
                           and ir.ubicacion_id = ubic_de('inyector',
                                 (select pi2.id from proveedor_insumo pi2 where pi2.nombre = c.proveedor limit 1))
                         limit 1), 0)
         , 2)) as sugerido
    from componente c
    left join lateral (
       -- el vinculo es la PIEZA (c.proveedor ya es el inyector), no o.proveedor: la OC de rubro
       -- Plastico abarca partes de varios inyectores y puede venir con proveedor NULL.
       select sum(oi.cantidad - coalesce(oi.recibido,0)) as pend
         from orden_compra o
         join orden_compra_item oi on oi.oc_id = o.id
        where o.estado = 'enviada' and oi.componente_id = c.id
    ) ocp on true
   where c.material_id is not null and c.estado_compra is null and c.proveedor is not null
     and exists (select 1 from proveedor_insumo pi where pi.nombre = c.proveedor)
   group by c.proveedor, c.material_id
),
rec as (
  select 'tallerista'::text as tipo, v.ref_id::text as ref, v.comp_id,
         case when exists (select 1 from componente_bom b where b.componente_padre_id = v.comp_id)
              then null::bigint
              else (select case when count(distinct rp.comp_entrada_id) = 1
                                then min(rp.comp_entrada_id) end
                      from ruta_paso rp
                     where rp.tipo_paso = 'tallerista' and rp.tallerista_id = v.ref_id
                       and rp.comp_salida_id = v.comp_id and rp.comp_entrada_id is not null
                       and rp.comp_entrada_id <> v.comp_id) end as comp_entrada_id,
         (select count(distinct rp.comp_entrada_id) from ruta_paso rp
           where rp.tipo_paso = 'tallerista' and rp.tallerista_id = v.ref_id
             and rp.comp_salida_id = v.comp_id and rp.comp_entrada_id is not null
             and rp.comp_entrada_id <> v.comp_id)::int as n_entradas,
         exists (select 1 from componente_bom b where b.componente_padre_id = v.comp_id) as tiene_bom,
         null::text as cod_art,
         coalesce((select i.cantidad from inventario i
                    where i.componente_id = v.comp_id
                      and i.ubicacion_id = ubic_de('tallerista', v.ref_id) limit 1), 0) as esperado,
         'online_tall'::text as esperado_origen
    from v_contraparte_parte v
    join componente c on c.id = v.comp_id
   where v.tipo = 'tallerista' and v.lado = 'salida'
     and c.sector_id <> 12 and not coalesce(c.discontinuado,false)
     and exists (select 1 from tallerista t where t.id = v.ref_id and t.activo and t.id <> 3)
  union all
  select 'proveedor_servicio', rp.proveedor_id::text, rp.comp_salida_id, rp.comp_entrada_id,
         1, false, null::text,
         coalesce((select i.cantidad from inventario i
                    where i.componente_id = rp.comp_entrada_id
                      and i.ubicacion_id = ubic_de('proveedor_servicio', rp.proveedor_id) limit 1), 0),
         'online_ps'
    from (select distinct proveedor_id, comp_entrada_id, comp_salida_id
            from ruta_paso
           where tipo_paso = 'proveedor_servicio' and proveedor_id is not null
             and comp_entrada_id is not null and comp_salida_id is not null) rp
    join componente cs on cs.id = rp.comp_salida_id and not coalesce(cs.discontinuado,false)
  union all
  select 'proveedor_at', a.proveedor_at_id::text, null::bigint, null::bigint, 0, false, a.cod_art,
         (select sum(oi.cantidad - coalesce(oi.recibido,0)) from orden_compra o
            join orden_compra_item oi on oi.oc_id = o.id
            join componente ci on ci.id = oi.componente_id
           where o.estado in ('borrador','enviada')
             and o.proveedor = (select nombre from proveedor_at where id = a.proveedor_at_id)
             and ci.codigo = a.cod_art),
         'oc'
    from articulo_prov_at a
   where coalesce(a.activo,true)
     and exists (select 1 from proveedor_at p where p.id = a.proveedor_at_id and coalesce(p.activo,true))
  union all
  select 'proveedor_insumo', o.proveedor, oi.componente_id, null::bigint, 0, false, null::text,
         sum(oi.cantidad - coalesce(oi.recibido,0)),
         'oc'
    from orden_compra o
    join orden_compra_item oi on oi.oc_id = o.id
   where o.estado in ('borrador','enviada')
   group by o.proveedor, oi.componente_id
  having sum(oi.cantidad - coalesce(oi.recibido,0)) > 0
  union all
  select 'virgilio', 'virgilio', i.componente_id, null::bigint, 0, false, null::text,
         sum(i.cantidad), 'online_virgilio'
    from inventario i
    join ubicacion u on u.id = i.ubicacion_id and u.tipo in ('virgilio','virgilio_sector')
    join componente c on c.id = i.componente_id
   where c.sector_id <> 12 and not coalesce(c.discontinuado,false)
   group by i.componente_id
  having sum(i.cantidad) <> 0
),
env_x as (
  select distinct on (e.tipo, e.ref, e.comp_id) e.tipo, e.ref, e.comp_id,
         c.codigo cod, c.descripcion descr, s.nombre sector, c.unidad_medida um,
         c.uni_x_cajon uxc, c.kg_x_uni kgu,
         c.sector_id sec_id, c.carton_formato cfmt,
         coalesce((select i.cantidad from inventario i
                    where i.componente_id = c.id
                      and i.ubicacion_id = ubic_de('sector', c.sector_id) limit 1), 0) online_sector,
         -- saldo en poder del tercero = lo que le enviamos − lo que nos entregó = inventario de lo
         -- que se le manda (la pieza/resina) en la ubicacion del destino. [usuario 2026-09-16]
         coalesce((select i.cantidad from inventario i
                    where i.componente_id = c.id
                      and i.ubicacion_id = (case
                            when e.tipo in ('proveedor_servicio','tallerista','proveedor_at') then ubic_de(e.tipo, e.ref::bigint)
                            when e.tipo = 'inyector' then ubic_de('inyector',
                                  (select pi3.id from proveedor_insumo pi3 where pi3.nombre = e.ref limit 1))
                          end) limit 1), 0) saldo_dest,
         coalesce(rep.maximo_dest, ri.maximo_dest) maximo_dest,
         coalesce(rep.stock_dest,  ri.stock_dest)  stock_dest,
         coalesce(rep.sugerido,    ri.sugerido)    sugerido
    from env e
    join componente c on c.id = e.comp_id and not coalesce(c.discontinuado,false)
    left join sector s on s.id = c.sector_id
    left join rep     on rep.tipo = e.tipo and rep.ref = e.ref and rep.comp_id = e.comp_id
    left join rep_iny ri on ri.tipo = e.tipo and ri.ref = e.ref and ri.comp_id = e.comp_id
   order by e.tipo, e.ref, e.comp_id
),
rec_x as (
  select r.tipo, r.ref, r.comp_id, r.comp_entrada_id, r.n_entradas, r.tiene_bom, r.cod_art,
         max(r.esperado) esperado, min(r.esperado_origen) esperado_origen,
         coalesce(c.codigo, r.cod_art) cod,
         coalesce(c.descripcion, (select max(descripcion) from articulo_prov_at ap
                                   where ap.cod_art = r.cod_art)) descr,
         s.nombre sector, c.unidad_medida um, c.uni_x_cajon uxc, c.kg_x_uni kgu,
         c.entrega_unidad ent_uni, c.entrega_uni_x ent_ux,
         ce.codigo ent_cod, ce.descripcion ent_desc,
         -- el CAJON DE LA PIEZA ENVIADA, SOLO donde la pieza vuelve en el MISMO cajon en el que se
         -- mando: hoy los REMACHES que niquela Guazzaroni (sector 8). El esperado de un P.S. se
         -- cuenta en unidades de la ENTRADA (es lo que el proveedor tiene en su poder), asi que ahi
         -- el envase con el que se mira tiene que ser el de ESA pieza y no el de la que devuelve
         -- [usuario 2026-09-18: "Guazzaroni nos entrega los remaches niquelados en los mismos
         -- cajones que se lo enviamos... si envio 2 cajones lo esperado es recibir 2 cajones aprox
         -- (el peso niquelado es un poquito mas - muy infima la diferencia)", y enseguida el limite:
         -- "no aplica para todos los casos... te lo estoy diciendo en el caso de los remaches"].
         -- El uni_x_cajon del remache niquelado (V11 = 2.729 uni = 2 kg) NO es un cajon: es la bolsa
         -- en la que se fracciona DESPUES de recibirlo, con la matriz de embolsado. Mirar el
         -- esperado con ese numero multiplicaba por 10 lo que se le habia mandado.
         -- NULL en el resto de los P.S.: ahi el front sigue con el cajon de la pieza devuelta.
         case when ce.sector_id = 8 then ce.uni_x_cajon end ent_uxc,
         case when ce.sector_id = 8 then ce.kg_x_uni    end ent_kgu,
         -- ...Y CUANTO MIDE ESE CAJON DE VERDAD (2026-09-21): el que anoto logistica al enviar
         -- (movimiento.cajones), no el uni_x_cajon del maestro. CV1 salio como 1 cajon de 21 kg
         -- contra un cajon teorico de 20 kg y la tarjeta de Recibir decia 1,05 cajones [usuario:
         -- "tiene que aparecer en su stock los cajones que escribe logistica, no los que se
         -- calcula a partir de los kg"]. Va SOLO donde ya va ent_uxc (P.S. y sector Remache), que
         -- es donde el front mira el envase de la pieza ENVIADA; null = nadie anoto cajones y
         -- queda el de siempre.
         max(case when ce.sector_id = 8 and r.tipo = 'proveedor_servicio'
                  then (select v.uni_x_cajon_anotado from v_caj_contraparte v
                         where v.componente_id = r.comp_entrada_id
                           and v.ubicacion_id = ubic_de(r.tipo, r.ref::bigint)) end) ent_uxc_anot,
         (select a.articulos_por_caja from articulo a where a.codigo = r.cod_art) por_caja
    from rec r
    left join componente c on c.id = r.comp_id
    left join componente ce on ce.id = r.comp_entrada_id
    left join sector s on s.id = c.sector_id
   where (r.comp_id is null or not coalesce(c.discontinuado,false))
   group by r.tipo, r.ref, r.comp_id, r.comp_entrada_id, r.n_entradas, r.tiene_bom, r.cod_art,
            c.codigo, c.descripcion, s.nombre, c.unidad_medida, c.uni_x_cajon, c.kg_x_uni,
            c.entrega_unidad, c.entrega_uni_x,
            ce.codigo, ce.descripcion, ce.uni_x_cajon, ce.kg_x_uni, ce.sector_id
),
-- envio_unidad / envio_uni_x / envio_carga_unidad: unidad de ENVIO por proveedor (display), p.ej. AJ
-- Adhesivos manda de a paquetes de 100 pliegos y Ester de a bolsas de 1800 mangos. Es solo
-- presentacion: el front muestra/precarga el sugerido dividido por envio_uni_x (techo) y rotula la
-- columna con envio_unidad. envio_carga_unidad dice en QUE unidad se escribe la CANTIDAD: null = en
-- la unidad de envio (AJ escribe paquetes y el front multiplica de nuevo), 'kg' = se escribe en kg y
-- al lado se muestran las bolsas (Ester). En los dos casos lo que llega a la base esta en unidad
-- canonica (uni/kg): el inventario nunca ve bolsas ni paquetes. Hoy solo lo tiene
-- proveedor_servicio; el resto va null. [usuario 2026-09-17]
cp as (
  select 'tallerista'::text tipo, t.id::text ref, t.nombre, null::text envio_unidad, null::numeric envio_uni_x, null::text envio_carga_unidad, null::text entrega_unidad, null::numeric entrega_uni_x
    from tallerista t
   where t.activo and t.id <> 3
     and exists (select 1 from v_contraparte_parte v where v.tipo='tallerista' and v.ref_id = t.id)
  union all
  select 'proveedor_servicio', ps.id::text, ps.nombre, ps.envio_unidad, ps.envio_uni_x, ps.envio_carga_unidad, ps.entrega_unidad, ps.entrega_uni_x
    from proveedor_servicio ps
   where exists (select 1 from v_contraparte_parte v where v.tipo='proveedor_servicio' and v.ref_id = ps.id)
  union all
  select 'proveedor_at', p.id::text, p.nombre, null::text, null::numeric, null::text, null::text, null::numeric
    from proveedor_at p where coalesce(p.activo,true)
  union all
  select distinct 'proveedor_insumo', o.proveedor, o.proveedor, null::text, null::numeric, null::text, null::text, null::numeric
    from orden_compra o where o.estado in ('borrador','enviada')
  union all
  select 'virgilio', 'virgilio', 'Virgilio', null::text, null::numeric, null::text, null::text, null::numeric
  union all
  select distinct 'inyector', c.proveedor, c.proveedor, null::text, null::numeric, null::text, null::text, null::numeric
    from componente c
   where c.material_id is not null and c.estado_compra is null and c.proveedor is not null
     and exists (select 1 from proveedor_insumo pi where pi.nombre = c.proveedor)
)
select jsonb_build_object(
  'generado_en', now(),
  'contrapartes', (
    select coalesce(jsonb_agg(jsonb_build_object(
             'tipo', cp.tipo, 'ref', cp.ref, 'nombre', cp.nombre,
             'envio_unidad', cp.envio_unidad, 'envio_uni_x', cp.envio_uni_x,
             'entrega_unidad', cp.entrega_unidad, 'entrega_uni_x', cp.entrega_uni_x,
             'envio_carga_unidad', cp.envio_carga_unidad,
             'n_env', (select count(*) from env_x e where e.tipo = cp.tipo and e.ref = cp.ref),
             'n_rec', (select count(*) from rec_x r where r.tipo = cp.tipo and r.ref = cp.ref)
           ) order by cp.nombre), '[]'::jsonb)
      from cp where cp.nombre is not null),
  'enviar', (
    select coalesce(jsonb_agg(jsonb_build_object(
             'tipo', tipo, 'ref', ref, 'comp_id', comp_id, 'cod', cod, 'desc', descr,
             'sector', sector, 'um', um, 'uxc', uxc, 'kg_x_uni', kgu,
             'env_unidad', case when tipo in ('tallerista','proveedor_at')
                                  then case when sec_id in (10,11) then 'paquetes' else 'cajones' end end,
             'env_factor', case when tipo in ('tallerista','proveedor_at') then case
                                  when sec_id = 10 then (select f.uni_x_bolsa from carton_formato f where f.nombre = cfmt)
                                  when sec_id = 11 then (select pa.valor::numeric from parametro pa
                                                          where pa.clave = 'caja_uni_x_paquete')
                                  else uxc end end,
             'env_carga',  case when tipo in ('tallerista','proveedor_at')
                                  then case when sec_id in (10,11) then 'envase' else 'kg' end end,
             'online_sector', online_sector, 'saldo_dest', saldo_dest,
             'maximo', maximo_dest, 'stock_dest', stock_dest, 'sugerido', sugerido
           ) order by cod), '[]'::jsonb) from env_x),
  'recibir', (
    select coalesce(jsonb_agg(jsonb_build_object(
             'tipo', tipo, 'ref', ref, 'comp_id', comp_id, 'comp_entrada_id', comp_entrada_id,
             'n_entradas', n_entradas, 'tiene_bom', tiene_bom,
             'cod_art', cod_art, 'cod', cod, 'desc', descr, 'sector', sector, 'um', um,
             'uxc', uxc, 'kg_x_uni', kgu, 'por_caja', por_caja,
             -- envase de ENTREGA (hoy solo el tallerista): el esperado se mira en cajones (o en las
             -- bolsas de 120 de GRJ5/GRJ6) y la cantidad se escribe en kg.
             'env_unidad', case when tipo = 'tallerista' then coalesce(ent_uni, 'cajones') end,
             'env_factor', case when tipo = 'tallerista' then coalesce(ent_ux, uxc) end,
             'env_carga',  case when tipo = 'tallerista' then 'kg' end,
             'ent_cod', ent_cod, 'ent_desc', ent_desc, 'ent_uxc_anot', ent_uxc_anot,
             'ent_uxc', ent_uxc, 'ent_kgu', ent_kgu,
             'esperado', esperado, 'esperado_origen', esperado_origen
           ) order by cod), '[]'::jsonb) from rec_x),
  'alertas_abiertas', (select count(*) from alerta_recepcion where estado = 'abierta')
);
$function$
;

grant execute on function "GP2".tablet_bundle() to anon, authenticated;
