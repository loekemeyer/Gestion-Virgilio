-- ============================================================================
-- PROV. DE ART. TERMINADO — SUGERIDO 0, IGUAL QUE "TALLERISTAS O.C."
-- 2026-09-24
--
-- [usuario 2026-09-24, textual: "En el envio a proveedor de articulo terminado, al igual que
-- talleristas orden de compra, no tienen un maximo de inventario alla ellos, de un mes, como los
-- talleristas, porque proveedor de articulo terminado y talleristas OC es gente que no tenemos la
-- misma confianza que con los talleristas. Tenes que modelarlo al igual que talleristas OC, que no
-- tienen un maximo alla, por lo tanto no tiene que haber un sugerido de que mandarle, sino que
-- tiene que aparecer en cero. Cuando salga orden de compra de Virgilio, que todavia no lo
-- modelamos, porque lo hace otro sistema ahora"].
--
-- DA VUELTA la migracion db/migracion_maximo_prov_at.sql del 2026-09-23 (Tablet v1.29.0), que le
-- habia puesto sugerido = consumo de su carton/caja x un mes, repartido — el mismo trato que el
-- tallerista a facon. Hoy el dueno reagrupa al prov AT con la gente de menos confianza: sin maximo
-- nuestro alla, el sugerido es 0 y el numero real saldra de una O.C. de Gestion Virgilio que GP2
-- todavia NO lee.
--
-- QUE HACE: una sola cosa. En tablet_bundle, CTE rep, el case del techo suma
--   when e.tipo = 'proveedor_at' then 0
-- (mismo criterio que el fasonero sin O.C. -proveedor_servicio.pedido_por_oc- y que el tallerista
-- con O.C. de Virgilio -tallerista.pedido_por_oc_virgilio-). No hace falta un flag por proveedor:
-- el dueno dijo que TODO el rubro va asi.
--
-- QUE NO SE TOCA, Y POR QUE: la maquinaria de ayer (reparto_prov_at, v_hace_articulo,
-- v_reparto_at_efectivo, v_consumo_prov_at, v_nivel_stock_prov_at, recalcular_maximos_prov_at)
-- queda DORMIDA. Medido el 2026-09-24: las 12 ubicaciones de prov AT tienen 0 filas de inventario y
-- reparto_prov_at 0 filas, o sea que recalcular_maximos_prov_at nunca escribio un maximo. No hay
-- nada que revertir. Si el dueno vuelve a querer el maximo de la casa, este `then 0` es lo unico
-- que se cambia (por eso no se borran esas vistas/funciones).
--
-- El paso PARCHEA la definicion viva con pg_get_functiondef + replace en vez de reescribir la
-- funcion entera: si el texto ancla no aparece, ABORTA y no queda a medias.
-- ============================================================================

do $mig$
declare d text; v text; n text;
begin
  select pg_get_functiondef(p.oid) into d
    from pg_proc p join pg_namespace nsp on nsp.oid = p.pronamespace
   where nsp.nspname = 'GP2' and p.proname = 'tablet_bundle';

  v := $v$else cons.consumo * cons.meses end as techo$v$;
  n := $n$-- PROV. DE ART. TERMINADO: igual que el tallerista con O.C. de Virgilio. El proveedor de
                   -- articulo terminado no tiene un maximo de inventario nuestro alla (no es gente de
                   -- la misma confianza que el tallerista a facon): lo que hay que mandarle sale de una
                   -- O.C. que emite Gestion Virgilio y que GP2 no lee, asi que el techo es 0 y con el el
                   -- sugerido [usuario 2026-09-24: "no tienen un maximo alla ellos... por lo tanto no
                   -- tiene que haber un sugerido de que mandarle, sino que tiene que aparecer en cero.
                   -- Cuando salga orden de compra de Virgilio... lo hace otro sistema ahora"]. DA VUELTA
                   -- la migracion del 2026-09-23 (consumo x meses con reparto), que queda dormida.
                   when e.tipo = 'proveedor_at'
                   then 0
                   else cons.consumo * cons.meses end as techo$n$;

  if position(v in d) = 0 then raise exception $e$tablet_bundle: no se encontro el case del techo$e$; end if;
  d := replace(d, v, n);
  execute d;
end
$mig$;

grant execute on function "GP2".tablet_bundle() to anon, authenticated;

-- ---------- verificacion ----------
-- todas las filas de prov AT en el enviar deben quedar en 0:
-- select count(*) filter (where (e->>'sugerido')::numeric <> 0) as deberia_ser_0,
--        count(*) as prov_at_filas
--   from jsonb_array_elements(("GP2".tablet_bundle())->'enviar') e
--  where e->>'tipo' = 'proveedor_at';
-- y los talleristas normales NO deben cambiar (siguen con sugerido).
