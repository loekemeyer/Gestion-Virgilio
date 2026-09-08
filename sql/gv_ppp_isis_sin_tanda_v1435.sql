-- ═══════════════════════════════════════════════════════════════════════════════════════
-- gv_ppp_isis_sin_tanda + gv_ppp_isis_programar — las NP de ISIS SIN tanda entran a "A Programar"
-- v14.35 (2026-09-08) · migración gv_ppp_isis_sin_tanda_v1435 · Virgilio (hrxfctzncixxqmpfhskv)
--
-- EL PROBLEMA (reportado por el dueño el 08/09). Las NP 98686-98694 (LK) y 44618 (Chef) —pedidos web del
-- 02/09 que ISIS ya numeró— y 44609-44617 (Cencosud, KRIKOS) están en `PPP_Programacion_Diaria` con
-- `tanda = ''` y fecha de entrega puesta. Quedaron en tierra de nadie:
--   · Gestión no las ve en "A Programar" porque esa solapa lista PEDIDOS DE LA PÁGINA (order_id) y las
--     saca `gv_pedidos_web_excluidos` con los motivos `anterior_al_cambio` (fecha_recep < gestion_desde)
--     y `en_produccion` (ISIS ya les dio NP). Las de Cencosud ni siquiera son pedidos web: entraron por
--     el Excel de Krikos, no hay `order_id` que mostrar.
--   · En la solapa Programación SÍ están, pero bajo el día sin tanda: nadie las puede pickear y el cupo
--     del día no las cuenta.
--
-- POR QUÉ NO SE ARREGLA DESEXCLUYÉNDOLAS. Si entraran por la vía web, `gv_ppp_web_tanda_agregar` les
-- asignaría una NP web nueva (LK 00xx) y al facturar el Excel de ISIS las cargaría de nuevo: dobles.
-- Estas NP ya existen en ISIS; hay que programarlas CON SU NÚMERO.
--
-- QUÉ HACE.
--   · `gv_ppp_isis_sin_tanda` — vista: NP de ISIS viva (no facturada, no entregada, no cancelada) que
--     está en el espejo sin tanda. Con cliente, zona, m³ y las líneas/cajas de `PPP_Base_Pedidos`.
--   · `gv_ppp_isis_programar(nps, fecha, por)` — arma UNA tanda con esas NP y la escribe en
--     `GV_PPP_Prog_Override` (np, tanda, fecha_entrega). NO toca `PPP_Programacion_Diaria`, que es
--     compartida con Producción (regla del dueño 2026-09-04: se agrega, nunca se modifica). Es el mismo
--     mecanismo que ya usa `gv_ppp_tanda_mover` (v13.87) y el override manual de 44619 → E07A (v13.50).
--
-- GUARDS.
--   · Supervisor (`gv_es_supervisor_o_servicio`), igual que `gv_ppp_tanda_mover`.
--   · Cada NP tiene que seguir viva y sin tanda: si otro ya la programó, corta y dice cuál.
--   · Regla del dueño v14.23: **el súper no se junta con clientes**. Mezclarlos en la misma tanda es
--     error, no aviso. El código sale de `gv_ppp_web_tanda_codigo_nuevo()`, que da camión NUEVO
--     (LETRA+NN), así que un súper nunca cae en el camión de un cliente.
--   · Avisos que NO bloquean (los muestra el front): cupo del día pasado y día no hábil.
--
-- Súper = `zona ~* 'super|coto|carrefour|chango|krikos'`, la MISMA expresión de `gv_ppp_super_mezclado`.
--
-- ROLLBACK:
--   drop function public.gv_ppp_isis_programar(text[], date, text);
--   drop view public.gv_ppp_isis_sin_tanda;
--   -- y para deshacer lo programado: delete from public."GV_PPP_Prog_Override" where nota like 'v14.35%';
-- ═══════════════════════════════════════════════════════════════════════════════════════

-- ── 1) La vista ────────────────────────────────────────────────────────────────────────
create or replace view public.gv_ppp_isis_sin_tanda
with (security_invoker = true) as
  with d as (
    select regexp_replace(btrim(p.np), '\.0+$', '') as np,
           btrim(coalesce(p.cod, ''))               as cod,
           p.razon_social, p.tipo, p.fecha_recep, p.direccion, p.barrio,
           coalesce(p.zona, '')                     as zona,
           coalesce(p.m3, 0)                        as m3,
           case when btrim(coalesce(p.fecha_entrega, '')) ~ '^\d{4}-\d{2}-\d{2}'
                then left(btrim(p.fecha_entrega), 10)::date end as fecha_entrega
      from public.gv_ppp_programacion_diaria p
     where coalesce(nullif(btrim(p.tanda), ''), '') = ''
       and regexp_replace(btrim(coalesce(p.np, '')), '\.0+$', '') ~ '^\d{1,18}$'
  )
  select d.np,
         d.cod,
         d.razon_social,
         d.tipo,
         d.fecha_recep,
         d.fecha_entrega,
         d.zona,
         d.barrio,
         d.direccion,
         d.m3,
         coalesce(b.lineas, 0) as lineas,
         coalesce(b.cajas, 0)  as cajas,
         (d.zona ~* 'super|coto|carrefour|chango|krikos') as es_super,
         case when left(d.np, 1) = '4' then 'chef' else 'lk' end as empresa
    from d
    left join lateral (
      select count(*)::int as lineas, coalesce(sum(coalesce(bp.cajas, 0)), 0) as cajas
        from public."PPP_Base_Pedidos" bp
       where regexp_replace(btrim(bp.pedido), '\.0+$', '') = d.np
    ) b on true
   where not exists (select 1 from public."Facturacion_NP" f
                      where regexp_replace(btrim(coalesce(f.np, '')), '\.0+$', '') = d.np)
     and not exists (select 1 from public."PPP_Entregados_Meta" e
                      where regexp_replace(btrim(coalesce(e.np, '')), '\.0+$', '') = d.np)
     and not exists (select 1 from public."NP_Canceladas" c
                      where regexp_replace(btrim(coalesce(c.np, '')), '\.0+$', '') = d.np);

grant select on public.gv_ppp_isis_sin_tanda to anon, authenticated, service_role;

-- ── 2) La RPC ──────────────────────────────────────────────────────────────────────────
create or replace function public.gv_ppp_isis_programar(
  p_nps   text[],
  p_fecha date,
  p_por   text default null
)
returns table (codigo text, np_programadas integer, m3 numeric, aviso text)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_nps    text[];
  v_falta  text;
  v_sup    int;
  v_cli    int;
  v_code   text;
  v_n      int;
  v_m3     numeric := 0;
  v_aviso  text := null;
  v_cupo   numeric;
  v_usado  numeric;
  v_nota   text;
begin
  if not public.gv_es_supervisor_o_servicio() then
    raise exception 'Sólo supervisores pueden programar NP de ISIS.';
  end if;
  if p_fecha is null then
    raise exception 'Falta la fecha de entrega: ninguna tanda queda sin fecha.';
  end if;

  select array_agg(distinct regexp_replace(btrim(x), '\.0+$', ''))
    into v_nps
    from unnest(coalesce(p_nps, '{}'::text[])) x
   where nullif(btrim(x), '') is not null;
  if v_nps is null or array_length(v_nps, 1) is null then
    raise exception 'No me pasaste ninguna NP.';
  end if;

  -- Todas tienen que seguir vivas y sin tanda (si otro la programó mientras tanto, corta acá).
  select string_agg(n, ', ' order by n) into v_falta
    from unnest(v_nps) n
   where not exists (select 1 from public.gv_ppp_isis_sin_tanda v where v.np = n);
  if v_falta is not null then
    raise exception 'Estas NP ya no están sin tanda (o ya salieron): %.', v_falta;
  end if;

  -- Regla del dueño v14.23: el súper va solo, nunca con clientes comunes.
  select count(*) filter (where v.es_super), count(*) filter (where not v.es_super)
    into v_sup, v_cli
    from public.gv_ppp_isis_sin_tanda v
   where v.np = any (v_nps);
  if v_sup > 0 and v_cli > 0 then
    raise exception 'Un súper no se junta con clientes en la misma tanda: separalas en dos.';
  end if;

  v_code := public.gv_ppp_web_tanda_codigo_nuevo();
  v_nota := 'v14.35 ' || to_char(now() at time zone 'America/Argentina/Buenos_Aires', 'YYYY-MM-DD HH24:MI')
            || ' · programada desde A Programar (NP de ISIS) para el ' || to_char(p_fecha, 'DD/MM')
            || coalesce(' por ' || nullif(btrim(p_por), ''), '');

  insert into public."GV_PPP_Prog_Override" (np, tanda, fecha_entrega, nota)
  select n, v_code, p_fecha, v_nota from unnest(v_nps) n
  on conflict (np) do update
     set tanda = excluded.tanda, fecha_entrega = excluded.fecha_entrega, nota = excluded.nota;
  get diagnostics v_n = row_count;

  select coalesce(round(sum(p.m3), 3), 0) into v_m3
    from public.gv_ppp_programacion_diaria p
   where upper(btrim(coalesce(p.tanda, ''))) = v_code;

  -- Avisos del día destino: no bloquean, los muestra el front (mismo criterio que gv_ppp_tanda_mover).
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

  return query select v_code, v_n, v_m3, v_aviso;
end $function$;

revoke execute on function public.gv_ppp_isis_programar(text[], date, text) from public;
grant execute on function public.gv_ppp_isis_programar(text[], date, text) to anon, authenticated, service_role;
