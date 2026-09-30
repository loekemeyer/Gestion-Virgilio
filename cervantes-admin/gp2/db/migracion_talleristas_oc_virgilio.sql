-- ============================================================================
-- TALLERISTAS O.C. — Blist-Pack SA y Carlos Aguirre salen de "Talleristas"
-- 2026-09-23
--
-- [usuario, con la foto de la Tablet: "a Blist-Pack SA y Carlos Aguirre quiero que me los saques
-- afuera de talleristas y me los pongas en un modulo nuevo de talleristas o.c."]
-- [usuario, al preguntarle que cambia ademas del lugar: "No es o.c. de insumos. Es orden de compra
-- que se hace desde Gestion Virgilio que hoy no esta modelado aca. Por ahora sugeri 0"]
-- [usuario, sobre donde: "Solo en la version tablet dentro del modulo enviar"]
--
-- QUE NO SE HACE, Y POR QUE: no se los saca de la tabla `tallerista`. Carlos Aguirre (9) tiene 32
-- pasos de ruta con tipo_paso='tallerista' y Blist-Pack SA (14) tiene 38; cambiarles el tipo
-- voltea rutas, inventario, reparto y costeo. Lo que se separa es la VITRINA: un flag y una
-- baldosa aparte en la Tablet.
--
-- QUE HACE ESTE ARCHIVO
--   1) columna GP2.tallerista.pedido_por_oc_virgilio (DDL, reversible)
--   2) la prende en los dos que pidio el usuario (DATOS)
--   3) tablet_bundle: manda `oc` en cada contraparte y pone el techo (y con el, el sugerido) en 0
--      para el tallerista con O.C. de Virgilio — mismo criterio que el fasonero sin O.C.
--
-- El paso 3 PARCHEA la definicion viva con pg_get_functiondef en vez de reescribir la funcion
-- entera: son dos inserciones y asi no hay forma de pisar sin querer otra cosa. Si un replace no
-- encuentra su texto, la migracion ABORTA (los raise exception de abajo) y no queda a medias.
-- ============================================================================

-- ---------- 1) el flag ----------
alter table "GP2".tallerista
  add column if not exists pedido_por_oc_virgilio boolean not null default false;

comment on column "GP2".tallerista.pedido_por_oc_virgilio is 'true = a este tallerista lo que tiene que hacer se lo pide una ORDEN DE COMPRA que emite Gestion Virgilio, no el maximo de la casa. GP2 todavia NO lee esa O.C. [usuario 2026-09-23, textual: "No es o.c. de insumos. Es orden de compra que se hace desde Gestion Virgilio que hoy no esta modelado aca. Por ahora sugeri 0"], asi que en tablet_bundle su techo es 0 y con el el sugerido -mismo criterio que el fasonero sin O.C. (proveedor_servicio.pedido_por_oc)-. Efecto en pantalla: Tablet_GP2.html los saca de la baldosa "Talleristas" y los pone en "Talleristas O.C.", SOLO en Enviar (en Recibir siguen adentro de Talleristas). Hoy: Carlos Aguirre (9) y Blist-Pack SA (14). NO cambia el modelo: los dos siguen siendo talleristas en rutas, inventario, reparto y costeo -sacarlos de la tabla habria volteado 32 y 38 pasos de ruta-.';

-- ---------- 2) los dos que pidio el usuario ----------
update "GP2".tallerista set pedido_por_oc_virgilio = true where id in (9, 14);

-- ---------- 3) tablet_bundle ----------
do $mig$
declare
  d text;
  v1 text; n1 text;
  v2 text; n2 text;
begin
  select pg_get_functiondef(p.oid) into d
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'GP2' and p.proname = 'tablet_bundle';

  -- (a) cada contraparte viaja con su flag `oc`
  v1 := $a$             'tipo', cp.tipo, 'ref', cp.ref, 'nombre', cp.nombre,
$a$;
  n1 := $a$             'tipo', cp.tipo, 'ref', cp.ref, 'nombre', cp.nombre,
             -- O.C. DE GESTION VIRGILIO (2026-09-23): a este tallerista no se le manda contra el
             -- maximo de la casa; lo que tiene que hacer sale de una O.C. que emite Gestion
             -- Virgilio y que GP2 todavia no lee. La Tablet lo muestra en su propia baldosa
             -- ("Talleristas O.C.", solo en Enviar) y su sugerido es 0 (ver la CTE t) [usuario].
             'oc', (cp.tipo = 'tallerista' and exists (select 1 from tallerista t9
                      where t9.id = cp.ref::bigint and t9.pedido_por_oc_virgilio)),
$a$;

  -- (b) su techo es 0: el pedido no sale del consumo x meses
  v2 := $b$                   then coalesce((select oc.pend from oc_ps oc
                                   where oc.proveedor_id = e.ref::bigint and oc.comp_id = e.comp_id), 0)
                   else cons.consumo * cons.meses end as techo
$b$;
  n2 := $b$                   then coalesce((select oc.pend from oc_ps oc
                                   where oc.proveedor_id = e.ref::bigint and oc.comp_id = e.comp_id), 0)
                   -- TALLERISTA CON O.C. DE VIRGILIO: mismo criterio que el fasonero sin O.C. — el
                   -- pedido no sale del consumo x meses sino de una orden que GP2 no lee, asi que
                   -- el techo es 0 y con el el sugerido [usuario 2026-09-23: "No es o.c. de
                   -- insumos. Es orden de compra que se hace desde Gestion Virgilio que hoy no
                   -- esta modelado aca. Por ahora sugeri 0"]. Cuando esa O.C. se modele, este 0
                   -- es lo unico que se cambia.
                   when e.tipo = 'tallerista'
                    and exists (select 1 from tallerista t8
                                 where t8.id = e.ref::bigint and t8.pedido_por_oc_virgilio)
                   then 0
                   else cons.consumo * cons.meses end as techo
$b$;

  if position(v1 in d) = 0 then raise exception 'tablet_bundle: no se encontro el bloque de contrapartes'; end if;
  if position(v2 in d) = 0 then raise exception 'tablet_bundle: no se encontro el case del techo'; end if;

  d := replace(d, v1, n1);
  d := replace(d, v2, n2);
  execute d;
end
$mig$;

grant execute on function "GP2".tablet_bundle() to anon, authenticated;

-- ---------- verificacion ----------
-- select id, nombre, pedido_por_oc_virgilio from "GP2".tallerista where id in (9,14);
-- select jsonb_agg(c) from jsonb_array_elements(("GP2".tablet_bundle())->'contrapartes') c
--  where (c->>'tipo') = 'tallerista' and (c->>'oc')::boolean;
-- select count(*) filter (where (e->>'sugerido')::numeric <> 0) as deberia_ser_0
--   from jsonb_array_elements(("GP2".tablet_bundle())->'enviar') e
--  where e->>'tipo' = 'tallerista' and e->>'ref' in ('9','14');
