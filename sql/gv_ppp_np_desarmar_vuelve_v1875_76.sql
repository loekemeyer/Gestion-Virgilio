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

  -- EL STOCK VUELVE A "A GUARDAR", no a la gondola (Luis, 14/09: "cuando se aprieta ese boton,
  -- deberia ir A guardar el pedido para hacerlo lo mas limpio posible, y que un operador despues
  -- lo tenga que procesar como toda la mercaderia a guardar"). La pantalla MG "Guardar a gondola"
  -- lista por SALDO de a_guardar (por codigo y empresa), asi que esto aparece ahi solo, y es el
  -- operario el que decide si va a gondola o a excedente y con que ubicacion -- que es la decision
  -- que antes esta funcion adivinaba sola.
  -- De donde HABIA salido cada caja igual se guarda (salio_de_terminado / salio_de_excedente en
  -- GV_Desarmes.stock_devuelto): es dato util para el que la guarda, pero no mueve stock.
  -- ⚠ v18.74: esto NO depende de p_vuelve. Las cajas se movieron igual, asi que vuelven igual.
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
  ), c as (
    select s.cod_art, s.empresa, s.fact, s.sep, s.org_term, s.org_exc,
           least(p.cajas, greatest(s.fact, 0) + greatest(s.sep, 0)) as total
      from ped p join sal s on s.ck = p.ck
  )
  select c.cod_art, c.empresa, c.org_term, c.org_exc, c.total,
         least(c.total, greatest(c.fact, 0))           as de_fact,
         c.total - least(c.total, greatest(c.fact, 0)) as de_sep
    from c where c.total > 0;

  insert into public."Movimientos_Stock" (ts, cod_art, descripcion, deposito, delta, tipo, ref, legajo, empresa)
  select now(), d.cod_art,
         'Desarme del pedido ' || v_np || ' (tanda ' || v_tanda || '): ' || v_just,
         x.dep, x.signo * x.cant, 'desarme', v_np, nullif(btrim(p_por), ''), d.empresa
    from _gv_dev d
    cross join lateral (values
      ('a_facturar',      -1, d.de_fact),
      ('separar_pedidos', -1, d.de_sep),
      ('a_guardar',        1, d.total)
    ) as x(dep, signo, cant)
   where x.cant > 0;

  select coalesce(jsonb_agg(jsonb_build_object('art', d.cod_art, 'empresa', d.empresa,
                              'de_a_facturar', d.de_fact, 'de_separar', d.de_sep,
                              'a_guardar', d.total,
                              'salio_de_terminado', d.org_term, 'salio_de_excedente', d.org_exc)
                            order by d.cod_art), '[]'::jsonb),
         count(*), coalesce(sum(d.total), 0)
    into v_dev, v_arts, v_cajas
    from _gv_dev d;

  if v_isis then
    if v_vuelve then
      /* v18.74 — «me equivoqué»: la NP de ISIS vuelve a A Programar. Se reusa el camino que ya
         existe para eso (guarda la tanda en tanda_previa y NO pone oculto), en vez de escribir
         otra variante de lo mismo. La guarda de "ya salió" ya se evaluó arriba. */
      perform public.gv_ppp_isis_desprogramar(array[v_np], 'desarmado: ' || v_just, p_por);
    else
      insert into public."NP_Canceladas" (np, motivo, legajo)
      values (v_np, 'desarmado: ' || v_just, coalesce(nullif(btrim(p_por),''), 'supervisor'))
      on conflict (np) do update set motivo = excluded.motivo, legajo = excluded.legajo;
      insert into public."GV_PPP_Prog_Override" (np, oculto, nota)
      values (v_np, true, 'v17.90 ' || to_char(now() at time zone 'America/Argentina/Buenos_Aires','YYYY-MM-DD HH24:MI')
                          || ' · DESARMADO (' || v_arts || ' art / ' || v_cajas || ' cajas a guardar): ' || v_just
                          || coalesce(' · por ' || nullif(btrim(p_por),''), ''))
      on conflict (np) do update set oculto = true, nota = excluded.nota;
    end if;
  else
    if v_vuelve then
      /* NO se escribe GV_Web_Cancelados — es justamente la fila que lo dejaba invisible. Y si
         había una de un desarme anterior, se BORRA: sin esto, "vuelve" no podría deshacer un
         "no vuelve" previo y el pedido seguiría escondido. */
      delete from public."GV_Web_Cancelados" c where c.empresa = v_emp and c.order_id = v_oid;
      /* v18.76 — y se RETIENE, para que el cron de zonas automáticas no lo vuelva a armar solo.
         Antes acá había un `delete` de esta misma tabla: liberaba la retención y el automático
         lo agarraba en la corrida siguiente (18 minutos, medido, con LK 1364). Es la misma fila
         y los mismos campos que escribe el botón ↩ «Enviar a programar», `tanda_previa`
         incluido, así que al reprogramarlo a mano vuelve a SU tanda y no se re-pickea.
         ⚠ Va ANTES del `update` de abajo: `tanda_previa` se lee de esa fila. */
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
      /* cancelado: el pedido sale por GV_Web_Cancelados, la retención no hace falta. */
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
    (v_arts || ' articulo' || case when v_arts = 1 then '' else 's' end || ' · ' || v_cajas
     || ' caja' || case when v_cajas = 1 then '' else 's' end || ' pasaron a A GUARDAR'
     || case when v_vuelve then ' · vuelve a A Programar y el automatico NO lo va a tomar'
             else ' · el pedido NO vuelve' end)::text;
end;
$function$;
