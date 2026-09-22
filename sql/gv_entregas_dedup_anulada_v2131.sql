-- v21.31 (Luis, 2026-09-22) — UNA FILA ANULADA NO ES UN ANTECEDENTE PARA EL DEDUP
-- (el marcador de idempotencia adentro de la funcion dice `v21.22`, que es la version con la
--  que se aplico; main se movio mientras tanto. NO cambiarlo: es la llave que evita reaplicar.)
--
-- Para deshacer un armado NO se borra la fila de `Entregas_Virgilio`: se le pega `-X` a la
-- `tanda` (E29D -> E29D-X) y queda su fila en `GV_Tanda_Anulada`. Es el mismo criterio que
-- los eventos (TAP->TAPX): borrarla libera el `client_id` y la cola offline del celular
-- resucita el armado.
--
-- `entregas_virgilio_dedup` mira `np|cod_art` + las tres cantidades y **a proposito NO mira
-- la tanda** (v15.92: un pedido reprogramado y rearmado quedaba duplicado). Con una fila
-- anulada delante, ese mismo criterio descarta la fila del rearmado: el remito sale
-- incompleto y nadie se entera, porque el insert devuelve 201 igual.
--
-- CASO E29D / LK 0034 (22/09): el armado del 15/09 se anulo (17 cajas volvieron a gondola).
-- El 22/09 el operario rearmo y de las 19 lineas entraron **3**: las 16 cuyas cantidades no
-- habian cambiado se descartaron contra E29D-X. 38 cajas fuera del remito y de la factura.
--
-- Es la mitad BACKEND del mismo agujero que la v21.21 tapo en el front (_compNpsYaArmadas
-- contaba un armado anulado como armado). Las dos leen Entregas por NP ignorando la tanda,
-- que es justo donde viaja la marca de anulacion.
--
-- SE APLICA SOBRE LA DEFINICION VIVA (varias sesiones tocan estos objetos), es IDEMPOTENTE
-- y falla con un raise si el texto no matchea, en vez de escribir una version vieja encima.

do $mig$
declare v_def text; v_old text; v_new text;
begin
  v_def := pg_get_functiondef('public.entregas_virgilio_dedup()'::regprocedure);
  if position('v21.22' in v_def) > 0 then raise notice 'ya aplicada'; return; end if;
  v_old := '       and coalesce(e.cajas_pedidas, 0)    = coalesce(new.cajas_pedidas, 0)';
  if position(v_old in v_def) = 0 then raise exception 'ANCLA no matchea: revisar a mano'; end if;
  v_new := v_old || chr(10)
    || '       -- v21.22 (Luis, 2026-09-22): UNA FILA ANULADA NO ES UN ANTECEDENTE.' || chr(10)
    || '       -- Para deshacer un armado no se borra la fila: se le pega `-X` a la tanda' || chr(10)
    || '       -- (E29D -> E29D-X) mas su fila en GV_Tanda_Anulada. Este dedup mira np|cod_art' || chr(10)
    || '       -- + las tres cantidades SIN la tanda (v15.92, a proposito), asi que la fila' || chr(10)
    || '       -- anulada descartaba la del rearmado y el remito salia incompleto.' || chr(10)
    || '       -- Caso E29D / LK 0034 (22/09): el armado del 15/09 se anulo, el 22/09 se rearmo' || chr(10)
    || '       -- y solo entraron 3 lineas de 19: las 16 que no habian cambiado de cantidad se' || chr(10)
    || '       -- descartaron contra E29D-X y quedaron fuera del remito (38 cajas).' || chr(10)
    || '       -- El dedup de verdad (mismo armado dos veces) sigue igual: esas filas estan vivas.' || chr(10)
    || '       and coalesce(e.tanda, '''') !~ ''-X[0-9]*$''';
  execute replace(v_def, v_old, v_new);
  raise notice 'aplicada';
end $mig$;

-- CENTINELA DE DATOS: que codigo quedo SOLO en el armado anulado, o sea fuera del remito vivo.
-- Vacia = ninguna anulacion se comio una linea. Es lo que faltaba para que E29D se viera sola.
create or replace view public.gv_entregas_perdidas_por_anulacion
with (security_invoker = true) as
with _epa_anu as (
  select regexp_replace(upper(btrim(e.np)), '\.0+$', '') np,
         upper(btrim(e.tanda)) tanda_anulada,
         upper(btrim(e.cod_art)) cod,
         e.cajas_pedidas, e.cajas_entregadas, e.cajas_falto, e.creado
    from public."Entregas_Virgilio" e
   where e.tanda ~ '-X[0-9]*$'
),
_epa_viva as (
  select distinct regexp_replace(upper(btrim(e.np)), '\.0+$', '') np,
         upper(btrim(e.cod_art)) cod
    from public."Entregas_Virgilio" e
   where coalesce(e.tanda, '') !~ '-X[0-9]*$'
),
-- la tanda VIVA de esa NP hoy (si volvio a armarse): sin rearmado no hay nada perdido,
-- la anulacion simplemente esta esperando que alguien arme.
_epa_hoy as (
  select regexp_replace(upper(btrim(e.np)), '\.0+$', '') np,
         (array_agg(upper(btrim(coalesce(e.tanda, ''))) order by e.id desc))[1] tanda_viva,
         max(e.creado) rearmado_el
    from public."Entregas_Virgilio" e
   where coalesce(e.tanda, '') !~ '-X[0-9]*$'
   group by 1
)
select a.np,
       a.tanda_anulada,
       h.tanda_viva,
       h.rearmado_el,
       count(*)                                          codigos_perdidos,
       sum(a.cajas_entregadas)                           cajas_entregadas_perdidas,
       sum(a.cajas_pedidas)                              cajas_pedidas_perdidas,
       string_agg(a.cod, ', ' order by a.cod)            codigos,
       'Estos codigos estan SOLO en el armado anulado ' || a.tanda_anulada ||
       ': no salen en el remito de ' || coalesce(h.tanda_viva, '(sin rearmar)') ||
       ' ni en la factura.'                              que_pasa
  from _epa_anu a
  join _epa_hoy h on h.np = a.np          -- solo si la NP SE REARMO: si no, no hay perdida
  left join _epa_viva v on v.np = a.np and v.cod = a.cod
 where v.cod is null
 group by a.np, a.tanda_anulada, h.tanda_viva, h.rearmado_el
 order by sum(a.cajas_entregadas) desc nulls last, a.np;

alter view public.gv_entregas_perdidas_por_anulacion set (security_invoker = true);

comment on view public.gv_entregas_perdidas_por_anulacion is
  'v21.22 - Codigos que quedaron SOLO en un armado anulado (tanda -X) de una NP que despues se rearmo: el dedup de Entregas_Virgilio los descarto y no salen en el remito vivo. Vacia = todo bien.';

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('entregas_virgilio_dedup','funcion','-X\[0-9\]\*\$',
        'El dedup de Entregas_Virgilio no puede tomar una fila ANULADA (tanda con sufijo -X) como antecedente: descarta la del rearmado y el remito sale incompleto (E29D / LK 0034, 22/09: 16 codigos y 38 cajas afuera).',
        'Luis','v21.22')
on conflict do nothing;

-- CHEQUEO
-- select * from public.gv_reglas_perdidas;                        -- vacia = la regla sigue puesta
-- select * from public.gv_entregas_perdidas_por_anulacion;        -- vacia = ningun remito incompleto
