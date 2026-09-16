-- gv_ppp_tanda_mover_v1911.sql — «Cambiar de día» por tanda desde la TABLA de Programación · v19.11 (2026-09-16)
-- Thomas: "PPP > Programación, vista tabla: agregá un botón a cada tanda que sea 'Cambiar de día' y que te
-- permita asignarla en un día diferente. Válido para la programación de entregas y para los Pedidos atrasados".
--
-- EL BOTÓN es front (index.html, `pgaTandaMoverAbrir` → el pop-up de días que ya existía). Lo que hubo que
-- tocar del backend son las DOS cosas que hacían que en «Pedidos atrasados» el botón no sirviera para nada:
--
-- 1) LA TANDA EMPEZADA. `gv_ppp_tanda_mover` (v13.87) rechazaba cualquier tanda con UN evento de operario.
--    Medido el 16/09 sobre `gv_ppp_atrasados`: las 8 tandas atrasadas tienen eventos, y las 8 tienen TAP
--    (armadas). O sea que el 100% del submódulo rebotaba. Y es al revés: un pedido atrasado es justamente uno
--    que YA se pickeó y armó y el camión no salió — cambiarle el día no obliga a rehacer nada, es la operación
--    normal. Ahora:
--      · si la tanda YA SALIÓ ENTERA (todos con CCN vigente —sin FSS posterior— o CRN) → se rechaza: mover el
--        día de algo que ya se cargó al camión o ya se entregó no significa nada. Es la misma regla con la que
--        `gv_ppp_atrasados` decide que un pedido salió; una sola definición, no dos.
--      · si salió UNA PARTE (medido el 16/09: D53C 7 de 8, D66D 3 de 4 — 2 de las 8 tandas atrasadas) →
--        también se rechaza, y el mensaje dice qué hacer. Mover la tanda arrastraría la fecha de lo ya
--        entregado; mover sólo lo que queda la partiría en dos días, que es justo lo que prohíbe la v18.92 y
--        lo que vigila `gv_ppp_tanda_dos_dias`. Separar un pedido de su tanda ya tiene su camino: el botón ↩
--        de la fila (`gv_ppp_pedido_a_programar` → `gv_ppp_isis_programar`), que lo manda a una tanda NUEVA.
--      · si tiene eventos pero no salió → se mueve con `p_forzar => true`, que es el sí explícito del
--        supervisor en el pop-up. Sin `p_forzar` el error empieza con `TANDA_EMPEZADA:` para que el front lo
--        reconozca, pregunte y reintente.
--
-- 2) LA TANDA QUE YA NO ESTÁ EN LA PROGRAMACIÓN. El árbol (`gv_ppp_prog_arbol`) tiene cuatro fuentes y las dos
--    últimas —`Facturacion_NP` (origen `fact`) y `GV_PPP_Entregados_Historico` (`hist`)— no viven en ninguna
--    tabla de programación. La tanda D53C (NP 98507, atrasada del 01/09) es una de ésas: `gv_ppp_tanda_mover`
--    contestaba "No encontré la tanda D53C". Ahora la rama de ISIS también levanta las NP de `Facturacion_NP`
--    por tanda, y `gv_ppp_prog_arbol` respeta `GV_PPP_Prog_Override.fecha_entrega` en las ramas `fact`/`hist`
--    (antes sólo la respetaba la de ISIS, vía la vista `gv_ppp_programacion_diaria`). Medido antes de tocar:
--    0 de las 1.164 filas `fact` y 0 de las 1.687 `hist` tenían override hoy, así que el cambio es INERTE
--    sobre lo que se ve ahora y sólo habilita los movimientos nuevos.
--
-- NO se toca `PPP_Programacion_Diaria` (tabla compartida): lo de ISIS sigue yendo al override, igual que antes.
--
-- PROBADO contra la base real (16/09), no leyendo la función:
--   · D66D (3 de 4 salidas) → rechaza con el mensaje de "salió en parte";
--   · E19A sin `p_forzar` → `TANDA_EMPEZADA` (11 eventos); con `p_forzar` → movidas 1, np_web 1, np_isis 0,
--     0,043 m³, y el árbol pasa a mostrarla el 18/09 y `gv_ppp_atrasados` deja de listarla;
--   · vuelta al 15/09 → todo como estaba (12 atrasados, mismas 8 tandas, 0 overrides de prueba,
--     `PPP_Web_Tandas.E19A` de nuevo en 2026-09-15). `gv_ppp_tanda_dos_dias` queda en las 3 filas de D69C
--     que ya estaban (problema 338), ninguna nueva.
--
-- Rollback: `sql/backups/gv_ppp_tanda_mover_gv_ppp_prog_arbol_20260916_pre_v1911.sql` tiene las dos
-- definiciones viejas tal cual estaban; correrlo las deja como antes (y el botón nuevo vuelve a rebotar en
-- «Pedidos atrasados», que es exactamente el estado previo).

drop function if exists public.gv_ppp_tanda_mover(text, date, text);

create or replace function public.gv_ppp_tanda_mover(
  p_tanda  text,
  p_fecha  date,
  p_por    text    default null,
  p_forzar boolean default false
) returns table(movidas integer, np_web integer, np_isis integer, m3 numeric, aviso text, empezada boolean)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_t      text := upper(btrim(coalesce(p_tanda, '')));
  v_ev     int;
  v_salio  int;
  v_total  int;
  v_web    int := 0;
  v_isis   int := 0;
  v_m3     numeric := 0;
  v_aviso  text := null;
  v_cupo   numeric;
  v_usado  numeric;
  v_nota   text;
begin
  if not public.gv_es_supervisor_o_servicio() then
    raise exception 'Sólo supervisores pueden mover tandas.';
  end if;
  if v_t = '' then raise exception 'Falta el código de la tanda.'; end if;
  if p_fecha is null then raise exception 'Falta la fecha nueva.'; end if;

  -- ¿alguna NP de la tanda YA SALIÓ? Misma definición que gv_ppp_atrasados: CCN vigente (sin un FSS
  -- posterior, que es la vuelta al depósito) o CRN (control de remito = entregado). Eso NO se mueve.
  with nps as (
    select regexp_replace(upper(btrim(x.np_label)), '\.0+$', '') as np from (
      select public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) as np_label
        from public."PPP_Web_Programacion" w
       where upper(btrim(coalesce(w.tanda, ''))) = v_t
    ) x
    union
    select regexp_replace(upper(btrim(d.np)), '\.0+$', '')
      from public.gv_ppp_programacion_diaria d
     where upper(btrim(coalesce(d.tanda, ''))) = v_t and d.np is not null
    union
    select regexp_replace(upper(btrim(f.np)), '\.0+$', '')
      from public."Facturacion_NP" f
     where upper(btrim(coalesce(f.tanda, ''))) = v_t and f.np is not null
  ),
  ev as (
    select regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', '') as np,
           max(r.ts_cliente) filter (where r.opcion = 'CCN') as ccn,
           max(r.ts_cliente) filter (where r.opcion = 'FSS') as fss,
           max(r.ts_cliente) filter (where r.opcion = 'CRN') as crn
      from public."Registros_Produccion_Virgilio" r
     where r.opcion in ('CCN', 'FSS', 'CRN')
       and coalesce(btrim(r.legajo), '') not in ('0', '1')
       and btrim(coalesce(r.texto, '')) <> ''
     group by 1
  )
  select count(*),
         count(*) filter (where e.crn is not null
                            or (e.ccn is not null and e.ccn >= coalesce(e.fss, '-infinity'::timestamptz)))
    into v_total, v_salio
    from nps n left join ev e on e.np = n.np;

  -- Toda la tanda salió → no hay nada que reprogramar.
  if v_total > 0 and v_salio = v_total then
    raise exception 'La tanda % ya salió entera (% pedido(s) con carga de camión o remito controlado): no hay nada a lo que cambiarle el día.', v_t, v_salio;
  end if;
  -- Salió una parte → mover la tanda arrastraría lo ya entregado, y mover sólo el resto la partiría en
  -- dos días (regla v18.92: una tanda no puede salir en dos días). Eso se resuelve por pedido, no por tanda.
  if v_salio > 0 then
    raise exception 'La tanda % ya salió en parte (% de % pedidos tienen carga de camión o remito). Cambiarle el día arrastraría lo que ya se entregó, y mover sólo el resto partiría la tanda en dos días. Reprogramá el pedido que falta desde su fila (botón ↩ Enviar a programar): sale en una tanda nueva, sin volver a pickear.', v_t, v_salio, v_total;
  end if;

  -- ¿ya la empezaron? (EP, PKC, TP, AP, TAP… cualquier evento con la tanda en el primer campo del texto)
  select count(*) into v_ev
    from public."Registros_Produccion_Virgilio" r
   where upper(btrim(split_part(r.texto, '|', 1))) = v_t;
  if v_ev > 0 and not coalesce(p_forzar, false) then
    raise exception 'TANDA_EMPEZADA: la tanda % ya tiene % evento(s) de operarios (pickeada o armada). Se puede mover igual —el contenido no cambia, no hay que volver a pickear— pero hay que confirmarlo.', v_t, v_ev;
  end if;

  v_nota := 'v19.11 ' || to_char(now() at time zone 'America/Argentina/Buenos_Aires', 'YYYY-MM-DD HH24:MI')
            || ' · movida desde la app a ' || to_char(p_fecha, 'DD/MM')
            || coalesce(' por ' || nullif(btrim(p_por), ''), '')
            || case when v_ev > 0 then ' · estaba empezada (' || v_ev || ' evento(s))' else '' end;

  -- ── tanda WEB ────────────────────────────────────────────────────────────
  update public."PPP_Web_Programacion" w
     set fecha_entrega = p_fecha
   where upper(btrim(coalesce(w.tanda, ''))) = v_t;
  get diagnostics v_web = row_count;
  if v_web > 0 then
    update public."PPP_Web_Tandas" t set fecha_entrega = p_fecha
     where upper(btrim(t.codigo)) = v_t;
  end if;

  -- ── tanda de ISIS: se pisa fila por fila en el override ───────────────────
  -- v19.11: además de la programación viva, las NP que ya sólo figuran en Facturacion_NP (origen `fact` del
  -- árbol). Sin eso, una tanda atrasada de esas contestaba "No encontré la tanda".
  -- ⚠ `Facturacion_NP` guarda las NP web con su ETIQUETA ('LK 0067'), no con el número: el guard tiene
  -- que comparar contra gv_ppp_web_np_label, si no le escribe un override al pedido web que ya movió la
  -- rama de arriba (pasó en la prueba del 16/09: np_isis daba 1 en una tanda 100 % web).
  insert into public."GV_PPP_Prog_Override" (np, fecha_entrega, nota)
  select x.np, p_fecha, v_nota from (
    select d.np as np
      from public.gv_ppp_programacion_diaria d
     where upper(btrim(coalesce(d.tanda, ''))) = v_t and d.np is not null
    union
    select regexp_replace(btrim(f.np), '\.0+$', '')
      from public."Facturacion_NP" f
     where upper(btrim(coalesce(f.tanda, ''))) = v_t and f.np is not null
  ) x
   where not exists (
           select 1 from public."PPP_Web_Programacion" w
            where upper(btrim(coalesce(w.tanda, ''))) = v_t
              and (w.np::text = x.np
                or upper(btrim(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx))) = upper(btrim(x.np))))
  on conflict (np) do update
     set fecha_entrega = excluded.fecha_entrega, nota = excluded.nota;
  get diagnostics v_isis = row_count;

  if v_web = 0 and v_isis = 0 then
    raise exception 'No encontré la tanda %.', v_t;
  end if;

  -- m³ de lo movido (ya con la fecha nueva)
  select coalesce(round(sum(x.m3), 3), 0) into v_m3 from (
    select w.m3 from public."PPP_Web_Programacion" w where upper(btrim(coalesce(w.tanda,''))) = v_t
    union all
    select d.m3 from public.gv_ppp_programacion_diaria d where upper(btrim(coalesce(d.tanda,''))) = v_t
  ) x;
  if v_m3 = 0 then
    select coalesce(round(sum(f.m3), 3), 0) into v_m3
      from public."Facturacion_NP" f where upper(btrim(coalesce(f.tanda,''))) = v_t;
  end if;

  -- avisos del día destino (no bloquean: los muestra el front)
  v_cupo := public.gv_ppp_web_cupo(p_fecha);
  select coalesce(sum(g.m3), 0) into v_usado
    from public."PPP_Web_Programacion" g
   where g.fecha_entrega = p_fecha and coalesce(nullif(trim(g.tanda), ''), '') <> '';
  v_usado := v_usado + public.gv_ppp_web_m3_isis(p_fecha);
  if v_usado > v_cupo then
    v_aviso := 'El ' || to_char(p_fecha, 'DD/MM') || ' queda con ' || round(v_usado, 3)
               || ' m³, por encima del cupo de ' || v_cupo || ' m³.';
  end if;
  if not public.gv_es_dia_habil(p_fecha) then
    v_aviso := coalesce(v_aviso || ' ', '') || 'Ojo: el ' || to_char(p_fecha, 'DD/MM')
               || ' no es día hábil (fin de semana o feriado).';
  end if;

  return query select (v_web + v_isis), v_web, v_isis, v_m3, v_aviso, (v_ev > 0);
end $function$;

revoke all on function public.gv_ppp_tanda_mover(text, date, text, boolean) from public;
grant execute on function public.gv_ppp_tanda_mover(text, date, text, boolean) to anon, authenticated, service_role;
-- (el gate real es gv_es_supervisor_o_servicio adentro de la función, igual que la v13.87)
