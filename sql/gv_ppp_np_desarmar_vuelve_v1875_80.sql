/* v18.75 (aplicado como v18.74; otra sesión tomó ese número en paralelo) — DESARMAR ya no significa siempre ANULAR. Problema 325.

   EL BUG
   ------
   `gv_ppp_np_desarmar`, para un pedido WEB, hacía dos cosas que se contradicen:

     insert into "GV_Web_Cancelados" ...        → gv_pedidos_web_excluidos lo lee como
                                                  motivo 'anulado' = NO VUELVE NUNCA
     update "PPP_Web_Programacion" set tanda = null, fecha_entrega = null
                                                → o sea: VUELVE a A Programar

   Las dos a la vez dejan el pedido en el limbo: sin tanda, y excluido para siempre de
   «Pedidos a programar», de Cuarentena y del armado automático. No aparece en ninguna
   pantalla — no es que se ve mal, es que no se ve.

   Caso real: **LK 1364** (Mitre Hugo Alberto, cod 4181, 19 renglones / 46 cajas, NP LK 0034 y
   LK 0035). La tanda E01G se desarmó el 15/09 porque el picking mostraba la lista recortada
   por el corte de 1000 filas — un error NUESTRO, con el pedido del cliente vivo. La propia
   fila de `GV_Web_Cancelados` dice en su motivo *"Se deshace y vuelve a A Programar"*, y el
   mecanismo hizo exactamente lo contrario. Lo encontró Luis el 16/09 buscándolo en pantalla.

   POR QUÉ PASÓ (no es un descuido suelto)
   ---------------------------------------
   Desarmar servía para dos intenciones que nadie había separado:

     · «se canceló»       → el pedido murió. No vuelve. (LK 1375, cancelado por el cliente:
                            ahí el comportamiento de hoy es el correcto y no se toca.)
     · «me equivoqué yo»  → el pedido está vivo y hay que volver a hacerlo.

   El modal dice *"sale de la PPP y no vuelve a entrar"*, así que el backend hacía lo que
   prometía. **Lo que no existía era la segunda acción.** Ahora existe.

   QUÉ CAMBIA
   ----------
   Un parámetro nuevo, `p_vuelve boolean default false`. El default es el comportamiento de
   hoy, así que ningún llamador viejo cambia de conducta.

     p_vuelve = false (default) → idéntico a la v17.90: se cancela y no vuelve.
     p_vuelve = true            → el pedido VUELVE a «Pedidos a programar»:
                                    · web  — no se escribe `GV_Web_Cancelados`, y si había una
                                             fila de un desarme anterior **se borra** (es la que
                                             lo tenía escondido);
                                    · ISIS — se reusa `gv_ppp_isis_desprogramar`, que ya es el
                                             camino probado para "sacar de la programación sin
                                             anular" (deja `desprogramada = true`, guarda la
                                             tanda en `tanda_previa` y NO pone `oculto`).

   El stock vuelve a **A guardar** en los dos casos: eso no depende de la intención, las cajas
   ya se movieron igual.

   La intención queda registrada en `GV_Desarmes.vuelve`, para que dentro de un mes se pueda
   saber si aquel desarme fue un error nuestro o una cancelación.


   ─────────────────────────────────────────────────────────────────────────────────────────
   v18.76 — Y EL QUE VUELVE NO PUEDE VOLVER A CAER EN UNA TANDA SOLO
   ─────────────────────────────────────────────────────────────────────────────────────────
   La v18.75 devolvía el pedido a «A Programar»… y el cron de zonas automáticas lo agarraba de
   nuevo en la corrida siguiente. **Medido: 18 minutos.** LK 1364 se destrabó a las 09:17 y a
   las 09:35:15 ya estaba en la tanda E26C con entrega 22/09, sin que nadie lo tocara.

   Luis, 16/09: *"los pedidos que se desarman o se mandan de vuelta «a programar» no deberían
   volver a tandas automáticamente (tenés que marcarlos con excepción del cron)"*.

   El mecanismo YA EXISTÍA y el automático ya lo respeta: `GV_PPP_Web_Retenido`, que escribe el
   botón ↩ «Enviar a programar» (`gv_ppp_web_desprogramar`) y que `gv_ppp_web_armar_pendientes`
   filtra al principio. Su propio comentario dice por qué existe: *"sin esto el cron lo
   reprograma solo en la corrida siguiente y el botón no sirve de nada: es lo que avisó Luis al
   pedirlo"*. O sea que el pedido ya se había hecho una vez, para el otro camino.

   Lo que hacía el desarme era **exactamente lo contrario**: `delete from GV_PPP_Web_Retenido`.
   Liberaba la retención, y el cron entraba. Ahora, con `p_vuelve = true`, **retiene** —misma
   fila, mismos campos que el botón ↩, con `tanda_previa` para no re-pickear— y el pedido queda
   en A Programar hasta que alguien lo programe a mano. Con `p_vuelve = false` (cancelado) el
   `delete` se mantiene: ahí el pedido sale por `GV_Web_Cancelados` y la retención no hace falta.

   ⚠ El `insert` va ANTES del `update` que pone `tanda = null`: `tanda_previa` se lee de esa fila.


   ─────────────────────────────────────────────────────────────────────────────────────────
   v18.83 (aplicada como v18.80) — LA MERCADERIA VUELVE DE DONDE SALIO (Luis zanja la ambigüedad)
   ─────────────────────────────────────────────────────────────────────────────────────────
   La v18.79 dejó todo en «A guardar» y se avisó que eso chocaba con lo que Luis había escrito.
   Lo zanjó él, 16/09, por partes:

     · *"Pedido que no se pickeó ni nada «pendiente»: se devuelve «a programar», no se movió
       ningún producto, no hay problema"* → ya era así: sin movimientos de picking el cálculo
       no produce ninguna fila y no se toca el stock.
     · *"Pedido que está «en proceso»: si está pickeado/armado/facturado, se revierte la
       mercadería **al lugar de donde se sacó (góndola o excedente)** y vuelve «A programar»
       como un pedido nuevo"*.
     · *"siempre que algo vuelva usando este botón queda registrado para que no se le asigne
       tanda automáticamente"* → la retención de la v18.76.

   Esto **reemplaza** la regla del 14/09 (*"debería ir A guardar… y que un operador después lo
   procese"*), y el motivo por el que aquélla existía ya no aplica: se tomó cuando la función
   **no sabía de dónde había salido cada caja y tenía que adivinar**. Ahora no adivina —
   `org_term` y `org_exc` son los movimientos REALES del picking (lo que salió de `terminado`
   y de `excedente`), así que la devolución es el reverso exacto. El reparto es: primero a
   góndola hasta lo que salió de ahí, después a excedente, y **lo que no se puede explicar con
   un movimiento de picking cae a `a_guardar`**, que queda como red de seguridad.

   ⚠ **El CTE `dev` no es un adorno.** El movimiento de devolución lleva `ref` = NP, no la
   tanda, así que NO entra en `sal` (que filtra por tanda). Sin `dev`, dos NP de la misma tanda
   que comparten un artículo devolverían las dos a góndola aunque la segunda hubiera salido de
   excedente: `org_term` se leería igual de completo en la segunda llamada. `dev` descuenta lo
   ya devuelto, y se identifica por el texto `"(tanda XXXX)"` que escribe esta misma función.

   Medido en transacción con `rollback`, contra tandas reales:

   | caso | resultado |
   |---|---|
   | `LK 0093` (E11C, todo de góndola) | −6 de `a_facturar`, **+6 a góndola** |
   | `CH 0012` (E03G, mezcla) | `054`, `307`, `731` **a excedente**; los otros 12 códigos **a góndola**; 0 a A guardar |
   | `CH 0009` (ya salió) | rechazada por la guarda de Carga Camión / Recepción Remitos |

   Nada quedó escrito: el barrido posterior de `Movimientos_Stock` y `GV_Desarmes` dio vacío.

   ROLLBACK
   --------
   Volver a la v17.90: re-aplicar la definición anterior (está en el historial de
   `pg_get_functiondef`, y el efecto es el de este archivo con el bloque `if v_vuelve` sacado).
   La columna `GV_Desarmes.vuelve` es nullable y no molesta si queda.
*/

/* ⚠ EL DROP NO ES OPCIONAL. `create or replace` con un parámetro MÁS no reemplaza nada: crea
   una SEGUNDA función (sobrecarga), y entonces la llamada de 3 argumentos que hace el front
   queda AMBIGUA entre las dos — Postgres la rechaza. Peor todavía: hasta que alguien lo note,
   la vieja (la del bug) sigue viva. Drop + create van juntos, en una sola transacción. */
drop function if exists public.gv_ppp_np_desarmar(text, text, text);

alter table public."GV_Desarmes" add column if not exists vuelve boolean not null default false;
comment on column public."GV_Desarmes".vuelve is
  'v18.74 — true = el desarme fue por un error nuestro y el pedido volvió a A Programar; false = se canceló y no vuelve.';

create or replace function public.gv_ppp_np_desarmar(
  p_np text, p_justificativo text, p_por text default null::text, p_vuelve boolean default false)
 returns table(np text, es_isis boolean, tanda text, arts integer, cajas numeric, detalle text)
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
#variable_conflict use_column
declare
  v_np   text := regexp_replace(btrim(p_np), '\.0+$', '');
  v_just text := btrim(coalesce(p_justificativo, ''));
  v_vuelve boolean := coalesce(p_vuelve, false);
  v_isis boolean; v_emp text; v_num int; v_oid bigint;
  v_tanda text; v_fe date; v_cod text; v_rs text; v_m3 numeric;
  v_items jsonb; v_dev jsonb; v_arts int := 0; v_cajas numeric := 0; v_n int;
  v_term numeric := 0; v_exc numeric := 0; v_guard numeric := 0;
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Solo un supervisor puede desarmar un pedido.' using errcode='42501';
  end if;
  if length(v_just) < 10 then
    raise exception 'Falta el justificativo del desarme (al menos 10 caracteres): queda guardado con el registro.';
  end if;

  v_isis := v_np !~* '^(LK|CH)\s*\d+';

  if exists (select 1 from public."Registros_Produccion_Virgilio" r
              where r.opcion in ('CCN','CRN')
                and regexp_replace(upper(btrim(split_part(r.texto,'|',1))), '\.0+$','') = upper(v_np)
                and not public.es_legajo_test(r.legajo)) then
    raise exception 'La NP % ya tiene Carga Camion o Recepcion Remitos: salio. Eso se cierra con el remito, no se desarma.', v_np;
  end if;

  if v_isis then
    select regexp_replace(btrim(p.tanda),'\s+$',''), nullif(left(btrim(p.fecha_entrega),10),'')::date,
           btrim(p.cod), btrim(p.razon_social), p.m3
      into v_tanda, v_fe, v_cod, v_rs, v_m3
      from public.gv_ppp_programacion_diaria p
     where regexp_replace(btrim(p.np), '\.0+$','') = v_np limit 1;
  else
    v_emp := case when upper(left(v_np,2)) = 'CH' then 'chef' else 'lk' end;
    v_num := (regexp_match(v_np, '(\d+)'))[1]::int;
    select n.order_id into v_oid from public."PPP_Web_NP" n where n.empresa = v_emp and n.np = v_num limit 1;
    select btrim(w.tanda), w.fecha_entrega, btrim(w.cod_cliente), btrim(w.razon_social), w.m3
      into v_tanda, v_fe, v_cod, v_rs, v_m3
      from public."PPP_Web_Programacion" w
     where w.empresa = v_emp and w.np = v_num limit 1;
  end if;
  if v_tanda is null then
    raise exception 'No encuentro la NP % en la programacion.', v_np;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('art', i.art, 'cajas', i.cajas, 'uxb', i.uxb, 'uni', i.uni)
                            order by i.art), '[]'::jsonb)
    into v_items from public.gv_ppp_np_items i where i.np = v_np;

  /* v18.80 (Luis, 16/09) — LA MERCADERIA VUELVE DE DONDE SALIO, no a "A guardar".
     Regla textual: "si esta pickeado/armado/facturado, se revierte la mercaderia al lugar de
     donde se saco (gondola o excedente) y vuelve A programar como un pedido nuevo".
     Reemplaza la regla del 14/09 ("deberia ir A guardar... y que un operador despues lo
     procese"), que se tomo cuando la funcion NO sabia de donde habia salido cada caja y tenia
     que adivinar. Ahora no adivina: `org_term` / `org_exc` son los movimientos REALES del
     picking (lo que salio de terminado y de excedente), asi que la devolucion es el reverso
     exacto. Lo que no se puede explicar con un movimiento de picking cae a `a_guardar`, que
     sigue siendo la red de seguridad. */
  drop table if exists _gv_dev;
  create temp table _gv_dev on commit drop as
  with ped as (
    select public.canon_cod(i.art) ck, sum(i.cajas)::numeric cajas
      from public.gv_ppp_np_items i where i.np = v_np group by 1
  ), sal as (
    select public.canon_cod(m.cod_art) ck,
           (array_agg(m.cod_art order by length(m.cod_art)))[1] cod_art,
           (array_agg(m.empresa) filter (where m.empresa is not null))[1] empresa,
           coalesce(sum(m.delta) filter (where m.deposito = 'a_facturar'), 0)      fact,
           coalesce(sum(m.delta) filter (where m.deposito = 'separar_pedidos'), 0) sep,
           coalesce(-sum(m.delta) filter (where m.tipo = 'picking' and m.deposito = 'terminado' and m.delta < 0), 0) org_term,
           coalesce(-sum(m.delta) filter (where m.tipo = 'picking' and m.deposito = 'excedente' and m.delta < 0), 0) org_exc
      from public."Movimientos_Stock" m
     where upper(btrim(m.ref)) = upper(btrim(v_tanda))
     group by 1
  ), dev as (
    /* Lo que ya devolvio un desarme ANTERIOR de esta misma tanda. Hace falta porque el
       movimiento de devolucion lleva `ref` = NP (no la tanda), asi que NO entra en `sal`: sin
       esto, dos NP de la misma tanda que comparten un articulo devolverian las dos a gondola
       aunque la segunda hubiera salido de excedente. Se identifica por el texto que escribe
       esta misma funcion, "(tanda XXXX)". */
    select public.canon_cod(m.cod_art) ck,
           coalesce(sum(m.delta) filter (where m.deposito = 'terminado'), 0) t,
           coalesce(sum(m.delta) filter (where m.deposito = 'excedente'), 0) e
      from public."Movimientos_Stock" m
     where m.tipo = 'desarme' and m.delta > 0
       and m.descripcion like '%(tanda ' || v_tanda || ')%'
     group by 1
  ), c as (
    select s.cod_art, s.empresa, s.fact, s.sep,
           greatest(s.org_term - coalesce(dv.t, 0), 0) as org_term,
           greatest(s.org_exc  - coalesce(dv.e, 0), 0) as org_exc,
           least(p.cajas, greatest(s.fact, 0) + greatest(s.sep, 0)) as total
      from ped p
      join sal s on s.ck = p.ck
      left join dev dv on dv.ck = p.ck
  )
  select c.cod_art, c.empresa, c.org_term, c.org_exc, c.total,
         least(c.total, greatest(c.fact, 0))           as de_fact,
         c.total - least(c.total, greatest(c.fact, 0)) as de_sep,
         -- a donde vuelve: primero la gondola (lo que salio de ahi), despues excedente,
         -- y lo que no tenga origen conocido queda en A guardar
         least(c.total, c.org_term) as a_term,
         least(c.total - least(c.total, c.org_term), c.org_exc) as a_exc,
         c.total - least(c.total, c.org_term)
                 - least(c.total - least(c.total, c.org_term), c.org_exc) as a_guardar
    from c where c.total > 0;

  insert into public."Movimientos_Stock" (ts, cod_art, descripcion, deposito, delta, tipo, ref, legajo, empresa)
  select now(), d.cod_art,
         'Desarme del pedido ' || v_np || ' (tanda ' || v_tanda || '): ' || v_just,
         x.dep, x.signo * x.cant, 'desarme', v_np, nullif(btrim(p_por), ''), d.empresa
    from _gv_dev d
    cross join lateral (values
      ('a_facturar',      -1, d.de_fact),
      ('separar_pedidos', -1, d.de_sep),
      ('terminado',        1, d.a_term),
      ('excedente',        1, d.a_exc),
      ('a_guardar',        1, d.a_guardar)
    ) as x(dep, signo, cant)
   where x.cant > 0;

  select coalesce(jsonb_agg(jsonb_build_object('art', d.cod_art, 'empresa', d.empresa,
                              'de_a_facturar', d.de_fact, 'de_separar', d.de_sep,
                              'a_gondola', d.a_term, 'a_excedente', d.a_exc, 'a_guardar', d.a_guardar,
                              'total', d.total,
                              'salio_de_terminado', d.org_term, 'salio_de_excedente', d.org_exc)
                            order by d.cod_art), '[]'::jsonb),
         count(*), coalesce(sum(d.total), 0),
         coalesce(sum(d.a_term), 0), coalesce(sum(d.a_exc), 0), coalesce(sum(d.a_guardar), 0)
    into v_dev, v_arts, v_cajas, v_term, v_exc, v_guard
    from _gv_dev d;

  if v_isis then
    if v_vuelve then
      perform public.gv_ppp_isis_desprogramar(array[v_np], 'desarmado: ' || v_just, p_por);
    else
      insert into public."NP_Canceladas" (np, motivo, legajo)
      values (v_np, 'desarmado: ' || v_just, coalesce(nullif(btrim(p_por),''), 'supervisor'))
      on conflict (np) do update set motivo = excluded.motivo, legajo = excluded.legajo;
      insert into public."GV_PPP_Prog_Override" (np, oculto, nota)
      values (v_np, true, 'v17.90 ' || to_char(now() at time zone 'America/Argentina/Buenos_Aires','YYYY-MM-DD HH24:MI')
                          || ' · DESARMADO (' || v_arts || ' art / ' || v_cajas || ' cajas): ' || v_just
                          || coalesce(' · por ' || nullif(btrim(p_por),''), ''))
      on conflict (np) do update set oculto = true, nota = excluded.nota;
    end if;
  else
    if v_vuelve then
      delete from public."GV_Web_Cancelados" c where c.empresa = v_emp and c.order_id = v_oid;
      insert into public."GV_PPP_Web_Retenido" as t
        (empresa, order_id, np_idx, np, tanda_previa, fecha_previa, ya_pickeada, ya_armada, motivo, por)
      select w.empresa, w.order_id, w.np_idx, w.np,
             nullif(btrim(w.tanda), ''), w.fecha_entrega,
             exists (select 1 from public."Registros_Produccion_Virgilio" r
                      where r.opcion in ('EP','TP')
                        and upper(btrim(split_part(r.texto,'|',1))) = upper(btrim(w.tanda))
                        and not public.es_legajo_test(r.legajo)),
             exists (select 1 from public."Registros_Produccion_Virgilio" r
                      where r.opcion in ('AP','TAP')
                        and upper(btrim(split_part(r.texto,'|',1))) = upper(btrim(w.tanda))
                        and not public.es_legajo_test(r.legajo)),
             'desarmado: ' || v_just, nullif(btrim(p_por), '')
        from public."PPP_Web_Programacion" w
       where w.empresa = v_emp and w.np = v_num
         and coalesce(nullif(btrim(w.tanda), ''), '') <> ''
      on conflict (empresa, order_id, np_idx) do update
         set tanda_previa = coalesce(excluded.tanda_previa, t.tanda_previa),
             fecha_previa = coalesce(excluded.fecha_previa, t.fecha_previa),
             ya_pickeada  = excluded.ya_pickeada or t.ya_pickeada,
             ya_armada    = excluded.ya_armada   or t.ya_armada,
             motivo = excluded.motivo, por = excluded.por, creado_at = now();
    else
      insert into public."GV_Web_Cancelados" (empresa, order_id, np_label, motivo, por)
      values (v_emp, v_oid, v_np, 'desarmado: ' || v_just, nullif(btrim(p_por),''))
      on conflict (empresa, order_id) do update
         set motivo = excluded.motivo, por = excluded.por, np_label = excluded.np_label, creado_at = now();
      delete from public."GV_PPP_Web_Retenido" t where t.empresa = v_emp and t.order_id = v_oid;
    end if;
    update public."PPP_Web_Programacion" w
       set tanda = null, fecha_entrega = null, actualizado_at = now()
     where w.empresa = v_emp and w.np = v_num;
    get diagnostics v_n = row_count;
  end if;

  insert into public."GV_Desarmes"
    (np, empresa, es_isis, order_id, cod_cliente, razon_social, tanda, fecha_entrega, m3,
     items, stock_devuelto, justificativo, por, vuelve)
  values (v_np, coalesce(v_emp, case when upper(v_np) like 'CH%' then 'chef' else 'lk' end),
          v_isis, v_oid, v_cod, v_rs, v_tanda, v_fe, v_m3, v_items, v_dev, v_just,
          nullif(btrim(p_por),''), v_vuelve);

  return query select v_np, v_isis, v_tanda, v_arts, v_cajas,
    (case when v_cajas = 0 then 'no habia mercaderia movida: no se devolvio nada'
          else v_arts || ' articulo' || case when v_arts = 1 then '' else 's' end || ' · ' || v_cajas
               || ' caja' || case when v_cajas = 1 then '' else 's' end || ' devueltas ('
               || concat_ws(', ',
                    case when v_term  > 0 then v_term  || ' a gondola'   end,
                    case when v_exc   > 0 then v_exc   || ' a excedente' end,
                    case when v_guard > 0 then v_guard || ' a A guardar' end) || ')'
     end
     || case when v_vuelve then ' · vuelve a A Programar y el automatico NO lo va a tomar'
             else ' · el pedido NO vuelve' end)::text;
end;
$function$;
