/* v18.79 (aplicado como v18.78; otra sesión tomó ese número) — «ENVIAR A PROGRAMAR» ABSORBE AL DESARME, y el badge deja de mentir.

   Pedido de Luis (16/09), textual:
     *"Que cuando se apriete «Enviar a programar» a una NP, mande todas las NPs correspondientes
     a ese pedido … si tenían algo armado, se «deshace» = la mercadería vuelve a las bodegas de
     donde salió … y las NPs vuelven «a programar» marcadas para que el cron no las programe
     automáticamente"* · *"el botón de desarmar pedido sacalo"* · *"sigue saliendo el badge de
     «se arma solo» a los pedidos que deberían tener la excepción"*.

   ── 1. Lo de «todas las NP del pedido» YA ESTABA ───────────────────────────────────────────
   El backend resuelve el `order_id` y saca todas desde la v18.40, y el pop-up lo dice antes de
   tocar nada (`gv_ppp_web_desprogramar_previo`). Si en pantalla dice "Va 1 NP" es porque ese
   pedido tiene una sola: dos NP del MISMO cliente pueden ser dos pedidos distintos (LK 0033 y
   LK 0048 son Cresta M.Cecilia, ped. 08/09 y 09/09 — order_id distintos). Lo que se hizo acá es
   no perderlo al cambiar de camino.

   ── 2. Lo que faltaba: devolver la mercadería ──────────────────────────────────────────────
   «Enviar a programar» sacaba la tanda y retenía, pero NO tocaba el stock. El cartel lo decía
   con todas las letras: *"Las cajas ya pickeadas no se mueven de dónde están"*. O sea que un
   pedido a medio armar dejaba su mercadería parada en `a_facturar` / `separar_pedidos`, sin
   dueño y sin que nadie la fuera a guardar.

   Al lado vivía el 🗑 «Desarmar pedido», que sí devolvía el stock pero además mataba el pedido.
   **Dos botones para dos mitades de la misma acción.** Ahora hay uno.

   `gv_ppp_pedido_a_programar(p_np, p_por, p_motivo)` hace las tres cosas de una:
     · resuelve el pedido entero (todas las NP del `order_id`; para ISIS, la NP sola);
     · por CADA NP con tanda llama a `gv_ppp_np_desarmar(..., p_vuelve => true)`, que ya está
       probado: devuelve el stock, retiene contra el cron, deja `tanda = null` y anota el desarme
       en `GV_Desarmes`. **Se reusa en vez de repetir el cálculo de stock**, que es plata;
     · retiene también las NP que ya estaban sin tanda, para que el pedido no se parta.

   ⚠ La guarda de "ya salió" (CCN/CRN) se evalúa sobre **todo el pedido antes de mover nada**: si
   una sola NP ya salió, no se desarma ninguna. Si se evaluara por NP dentro del loop, el pedido
   quedaría a medio deshacer.

   ⚠ Llamar a `gv_ppp_np_desarmar` en loop es seguro aunque dos NP compartan tanda: su cálculo
   de stock lee los movimientos VIVOS de la tanda, así que la segunda llamada ya ve descontado lo
   que devolvió la primera y nunca devuelve de más.

   ⚠ **Adónde va la mercadería: a «A guardar», no a la góndola.** Luis escribió "vuelve a las
   bodegas de donde salió (góndola, pickeado, etc)", pero el 14/09 la regla que él mismo fijó
   para este mismo movimiento fue la contraria y es la que está implementada: *"debería ir A
   guardar el pedido para hacerlo lo más limpio posible, y que un operador después lo tenga que
   procesar como toda la mercadería a guardar"*. Se mantiene ésa —es la vigente y la reversible—
   y de dónde había salido cada caja igual queda anotado (`salio_de_terminado` /
   `salio_de_excedente` en `GV_Desarmes.stock_devuelto`). **Si Luis quiere lo otro, se cambia en
   un solo lugar: el bloque de `gv_ppp_np_desarmar` que arma `_gv_dev`.**

   ── 3. El badge que mentía ─────────────────────────────────────────────────────────────────
   En A Programar, un pedido retenido seguía mostrando **"🤖 se arma solo → mar 22/9 · en
   minutos"**, con fecha y todo, cuando `gv_ppp_web_armar_pendientes` no lo va a tocar nunca. El
   supervisor se quedaba esperando una tanda que no iba a salir.

   Quién decide eso es regla de negocio, así que va al backend: `gv_ppp_web_dia_salida` devuelve
   ahora `r_motivo = 'retenido'` y sin fecha. Para poder mirarlo necesita saber DE QUÉ PEDIDO se
   trata —el front le mandaba sólo `zona` y `m3`—, así que ahora van también `empresa` y
   `order_id`. **Si no llegan (una página vieja cacheada) la función se comporta exactamente como
   antes**: el `exists` no matchea y listo.

   El chip pasó a ser **"🔒 no lo toca el automático · ponele día"**.

   ROLLBACK
   --------
   `gv_ppp_pedido_a_programar` es nueva: alcanza con volver a apuntar el front a
   `gv_ppp_web_desprogramar` / `gv_ppp_isis_desprogramar`. `gv_ppp_web_dia_salida`: sacar el CTE
   `ret` y las tres ramas `'retenido'`. El botón 🗑 y su modal salieron del front; el backend
   `gv_ppp_np_desarmar` sigue vivo y es el que hace el trabajo.
*/

create or replace function public.gv_ppp_pedido_a_programar(
  p_np text, p_por text default null::text, p_motivo text default null::text)
 returns table(np_sacadas integer, order_id bigint, arts integer, cajas numeric, detalle text)
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_np   text := regexp_replace(btrim(p_np), '\.0+$', '');
  v_just text := coalesce(nullif(btrim(p_motivo), ''), 'enviado a A Programar desde la tabla de Programacion');
  v_isis boolean; v_emp text; v_num int; v_oid bigint; v_sal text;
  v_n int := 0; v_arts int := 0; v_cajas numeric := 0; v_ret int := 0;
  r record; d record;
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Solo un supervisor puede devolver un pedido a A Programar.' using errcode='42501';
  end if;
  -- gv_ppp_np_desarmar exige justificativo de 10+ caracteres
  if length(v_just) < 10 then v_just := v_just || ' (enviar a programar)'; end if;

  v_isis := v_np !~* '^(LK|CH)\s*\d+';

  if v_isis then
    select * into d from public.gv_ppp_np_desarmar(v_np, v_just, p_por, true);
    return query select 1, null::bigint, coalesce(d.arts,0), coalesce(d.cajas,0),
      (v_np || ' volvio a A Programar' ||
       case when coalesce(d.arts,0) > 0
            then ' · ' || d.arts || ' articulo' || case when d.arts = 1 then '' else 's' end
                 || ' / ' || d.cajas || ' caja' || case when d.cajas = 1 then '' else 's' end || ' a A GUARDAR'
            else '' end)::text;
    return;
  end if;

  v_emp := case when upper(left(v_np,2)) = 'CH' then 'chef' else 'lk' end;
  v_num := (regexp_match(v_np, '(\d+)'))[1]::int;
  select n.order_id into v_oid from public."PPP_Web_NP" n where n.empresa = v_emp and n.np = v_num limit 1;
  if v_oid is null then raise exception 'No encuentro el pedido web de %.', v_np; end if;

  /* Guarda unica, la misma de gv_ppp_web_desprogramar: si ya salio, no se toca.
     Se evalua sobre TODO el pedido antes de mover nada: si una NP salio, no desarmamos ninguna. */
  select string_agg(distinct upper(btrim(split_part(r2.texto,'|',1))), ', ')
    into v_sal
    from public."Registros_Produccion_Virgilio" r2
    join public."PPP_Web_Programacion" w
      on w.empresa = v_emp and w.order_id = v_oid
     and upper(btrim(split_part(r2.texto,'|',1)))
         = upper(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx))
   where r2.opcion in ('CCN','CRN') and not public.es_legajo_test(r2.legajo);
  if v_sal is not null then
    raise exception 'Estas NP ya tienen Carga Camion o Recepcion Remitos: %. Salieron, no se sacan de la programacion.', v_sal;
  end if;

  /* TODAS las NP del pedido que tengan tanda. Cada una pasa por gv_ppp_np_desarmar con
     p_vuelve = true: devuelve el stock a A guardar, retiene contra el cron, deja tanda=null
     y anota el desarme. Se reusa esa funcion en vez de repetir el calculo de stock. */
  for r in
    select public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) as label
      from public."PPP_Web_Programacion" w
     where w.empresa = v_emp and w.order_id = v_oid
       and coalesce(nullif(btrim(w.tanda), ''), '') <> ''
     order by w.np_idx
  loop
    select * into d from public.gv_ppp_np_desarmar(r.label, v_just, p_por, true);
    v_n := v_n + 1;
    v_arts  := v_arts  + coalesce(d.arts, 0);
    v_cajas := v_cajas + coalesce(d.cajas, 0);
  end loop;

  /* Las NP del pedido que ya estaban SIN tanda tambien se retienen: si no, el cron agarra
     media parte del pedido y el pedido se parte, que es justo lo que no se quiere. */
  insert into public."GV_PPP_Web_Retenido" as t
    (empresa, order_id, np_idx, np, tanda_previa, fecha_previa, ya_pickeada, ya_armada, motivo, por)
  select w.empresa, w.order_id, w.np_idx, w.np, null, null, false, false,
         v_just, nullif(btrim(p_por), '')
    from public."PPP_Web_Programacion" w
   where w.empresa = v_emp and w.order_id = v_oid
     and coalesce(nullif(btrim(w.tanda), ''), '') = ''
  on conflict (empresa, order_id, np_idx) do update
     set motivo = excluded.motivo, por = excluded.por, creado_at = now();
  get diagnostics v_ret = row_count;

  return query select v_n, v_oid, v_arts, v_cajas,
    (case when v_n = 0 then 'El pedido ya estaba sin tanda'
          else v_n || ' NP del pedido volvieron a A Programar' end
     || case when v_arts > 0
             then ' · ' || v_arts || ' articulo' || case when v_arts = 1 then '' else 's' end
                  || ' / ' || v_cajas || ' caja' || case when v_cajas = 1 then '' else 's' end
                  || ' volvieron a A GUARDAR'
             else '' end
     || case when v_ret > 0 then ' · ' || v_ret || ' ya estaba(n) sin tanda' else '' end
     || ' · el automatico no las vuelve a tomar')::text;
end;
$function$;

revoke execute on function public.gv_ppp_pedido_a_programar(text, text, text) from public, anon;

/* ── gv_ppp_web_dia_salida ─────────────────────────────────────────────────────────────────
   El CREATE va ENTERO, no "lo que cambió": el CLAUDE.md lo pide después de que una definición
   parcheada a mano dejó al repo sin la versión viva y recuperarla costó caro (v16.30).
   Lo nuevo es el CTE `ret` y las tres ramas `'retenido'`. */
create or replace function public.gv_ppp_web_dia_salida(p_filas jsonb, p_ahora timestamp with time zone default now())
 returns table(r_idx integer, r_dia date, r_motivo text, r_detalle text)
 language plpgsql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_local  timestamp := p_ahora at time zone 'America/Argentina/Buenos_Aires';
  v_corte  time := coalesce((select valor_texto from public."PPP_Web_Config" where clave = 'intradia_corte_hora'), '12:00')::time;
  v_umbral numeric := coalesce((select valor from public."PPP_Web_Config" where clave = 'intradia_umbral_m3'), 0.80);
  v_auto   text[] := string_to_array(coalesce((select valor_texto from public."PPP_Web_Config" where clave = 'zonas_automaticas'), '1,2'), ',');
  v_desde  date := public.gv_ppp_web_dia_minimo(p_ahora);   -- v13.22
  v_manana timestamptz := ((v_local::date + 1)::timestamp + time '00:01') at time zone 'America/Argentina/Buenos_Aires';
  v_dia_intra date := public.gv_ppp_web_proximo_dia_entrega(p_ahora);
  v_dia_job   date := public.gv_ppp_web_proximo_dia_entrega(v_manana);
begin
  return query
  with f as (
    select (x.ord - 1)::int as idx,
           btrim(x.v->>'zona') as zona,
           coalesce(nullif(x.v->>'m3','')::numeric, 0) as m3,
           (regexp_match(btrim(x.v->>'zona'), '^Zona\s*([0-9]+)'))[1] as zn,
           /* v18.78 — el pedido, para poder mirar la retencion. Si el front no los manda
              (pagina vieja cacheada) quedan null y la funcion se comporta como antes. */
           nullif(btrim(coalesce(x.v->>'empresa','')), '') as empresa,
           nullif(x.v->>'order_id','')::bigint as order_id
      from jsonb_array_elements(coalesce(p_filas, '[]'::jsonb)) with ordinality as x(v, ord)
  ),
  /* v18.78 (Luis: "sigue saliendo el badge de «se arma solo» a los pedidos que deberian tener la
     excepcion") — un pedido RETENIDO no lo toca el armado automatico: gv_ppp_web_armar_pendientes
     lo saltea. El chip decia igual "se arma solo -> tal dia", que es justo lo contrario, y encima
     con fecha: el supervisor se quedaba esperando una tanda que nunca iba a salir. */
  ret as (
    select f.idx
      from f
      join public."GV_PPP_Web_Retenido" t
        on t.empresa = f.empresa and t.order_id = f.order_id
     where f.empresa is not null and f.order_id is not null
     group by f.idx
  ),
  pend_auto as (
    select coalesce(sum(m3), 0) as m3 from f
     where zn = any(v_auto) and not exists (select 1 from ret where ret.idx = f.idx)
  ),
  camiones as (
    select (regexp_match(btrim(w.zona), '^Zona\s*([0-9]+)'))[1] as zn, w.fecha_entrega as dia, upper(btrim(w.tanda)) as tanda
      from public."PPP_Web_Programacion" w
     where w.fecha_entrega >= v_desde and coalesce(nullif(btrim(w.tanda),''),'') <> '' and w.zona is not null
    union all
    select (regexp_match(btrim(i.zona), '^Zona\s*([0-9]+)'))[1], left(btrim(i.fecha_entrega::text), 10)::date, upper(btrim(i.tanda))
      from public.gv_ppp_programacion_diaria i
     where btrim(i.fecha_entrega::text) ~ '^\d{4}-\d{2}-\d{2}'
       and left(btrim(i.fecha_entrega::text), 10)::date >= v_desde
       and coalesce(nullif(btrim(i.tanda),''),'') <> '' and i.zona is not null
  ),
  manual as (
    select f.idx, c.dia, string_agg(distinct c.tanda, ' · ' order by c.tanda) as tandas
      from f
      join camiones c on c.zn = f.zn
       and c.dia = (select min(c2.dia) from camiones c2 where c2.zn = f.zn)
     where f.zn is not null and not (f.zn = any(v_auto))
     group by f.idx, c.dia
  )
  select f.idx,
         case
           when exists (select 1 from ret where ret.idx = f.idx) then null
           when f.zona ilike 'retira%' then null
           when f.zona ilike 's_per%' or f.zona ilike 'súper%' or f.zona ilike 'super%' then null
           when f.zn = any(v_auto) then
             case when v_local::time < v_corte and (select m3 from pend_auto) >= v_umbral then v_dia_intra else v_dia_job end
           else m.dia
         end as r_dia,
         case
           when exists (select 1 from ret where ret.idx = f.idx) then 'retenido'
           when f.zona ilike 'retira%' then 'retira'
           when f.zona ilike 's_per%' or f.zona ilike 'súper%' or f.zona ilike 'super%' then 'super'
           when f.zn = any(v_auto) then
             case when v_local::time < v_corte and (select m3 from pend_auto) >= v_umbral then 'intradia' else 'job' end
           when m.dia is not null then 'camion'
           when f.zn is null then 'sin_zona'
           else 'sin_camion'
         end as r_motivo,
         case
           when exists (select 1 from ret where ret.idx = f.idx)
             then 'Lo sacaste de una tanda a proposito: el armado automatico NO lo vuelve a tomar. Ponele el dia vos.'
           when f.zn = any(v_auto) then 'Zona automática: se arma sola para el próximo día hábil con cupo (desde el ' || to_char(v_desde, 'DD/MM') || ')'
           when m.dia is not null then 'Ya hay camión a la zona ' || f.zn || ': ' || m.tandas
           when f.zona ilike 'retira%' then 'Lo pasa a buscar el cliente'
           when f.zona ilike 's_per%' or f.zona ilike 'súper%' or f.zona ilike 'super%' then 'Súper: camión propio, lo programa el supervisor'
           when f.zn is null then 'Sin zona: revisar barrio'
           else 'No hay camión previsto a la zona ' || f.zn || ' desde el ' || to_char(v_desde, 'DD/MM') || ': programar a mano'
         end as r_detalle
    from f
    left join manual m on m.idx = f.idx
   order by f.idx;
end $function$;
