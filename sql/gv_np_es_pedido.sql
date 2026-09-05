-- =============================================================================
-- gv_np_es_pedido.sql — LA NP WEB ES EL NÚMERO DE PEDIDO DE LA PÁGINA (2026-09-05, v12.92)
-- Proyecto Virgilio (hrxfctzncixxqmpfhskv) · todo objetos nuestros (PPP_Web_* / gv_*)
-- =============================================================================
-- LO QUE PIDIÓ EL DUEÑO: "tiene que ser automático: ya cuando llegan a página LK y a
-- Gestión Virgilio, ya vienen con numeración. En página LK ya tienen numeración. En
-- Gestión Virgilio, con la lógica de los 18 ítems para LK y 15 para CH".
--
-- ANTES: Gestión tenía un CONTADOR propio (PPP_Web_NP_Seed, lk 1 / chef 1) y numeraba
-- al PROGRAMAR (job de las 00:01 o "A Programar"). Un pedido esperaba sin número.
--
-- AHORA: la NP web ES el número de pedido de la página (`orders.id` en LK,
-- `chef_orders.id` en Chef). No hay contador ni momento de asignación: el número
-- existe desde que el pedido existe, y es el mismo que ve el cliente en la página.
-- Los bloques de 18 líneas (LK) / 15 (Chef) siguen igual: el bloque 1 lleva el
-- número pelado y los demás un sufijo.
--
--   pedido 1350 de LK, 12 líneas   → LK 1350
--   pedido 1350 de LK, 30 líneas   → LK 1350 (bloque 1) · LK 1350-2 (bloque 2)
--   pedido 217 de Chef              → CH 0217
--
-- Cuatro dígitos (dueño, más temprano hoy); pasado 9999 crece (LK 10000).
--
-- QUÉ CAMBIA EN LA BASE (nada compartido con Producción):
--   · PPP_Web_NP: `np` deja de ser único por empresa (dos bloques del mismo pedido
--     comparten número). PK pasa a (empresa, order_id, np_idx). `np` = order_id.
--   · gv_ppp_web_np_asignar: ya no cuenta; registra np = order_id. Se conserva
--     porque el job, la programación a mano y el front la llaman igual. El candado
--     `numeracion_activa` se conserva.
--   · gv_ppp_web_np_label(empresa, np, np_idx default 1): sufijo "-N" si np_idx > 1.
--     Se DROPEA la de dos parámetros (con la de tres con default, la llamada de dos
--     sería ambigua) y se recrean las dos vistas que dependían de ella.
--   · ppp_web_resync y gv_ppp_web_tanda_programar: pasan np_idx a la etiqueta.
--   · PPP_Web_NP_Seed: queda sin uso. No se borra.
--
-- Medido antes: PPP_Web_NP 0 filas, PPP_Web_Programacion 0, PPP_Web_Base 0, 0 eventos
-- con etiqueta. Nada que migrar.
--
-- ROLLBACK: sql/backups/gv_np_es_pedido_20260905_pre.sql (label, asignar, resync,
-- tanda_programar y las dos vistas tal como estaban) + volver la PK de PPP_Web_NP a
-- (empresa, np). Sólo tiene sentido mientras no haya nada numerado.
-- =============================================================================

-- ── 1. PPP_Web_NP: np = order_id, dos bloques comparten número ────────────────
alter table public."PPP_Web_NP" drop constraint if exists "PPP_Web_NP_pkey";
alter table public."PPP_Web_NP" drop constraint if exists "PPP_Web_NP_empresa_order_id_np_idx_key";
alter table public."PPP_Web_NP" add primary key (empresa, order_id, np_idx);
create index if not exists ppp_web_np_empresa_np_idx on public."PPP_Web_NP" (empresa, np);

-- ── 2. La etiqueta, con bloque ────────────────────────────────────────────────
drop view if exists public.gv_ppp_web_entregados;
drop view if exists public.gv_ppp_web_estado;
drop function if exists public.gv_ppp_web_np_label(text, integer);

create or replace function public.gv_ppp_web_np_label(p_empresa text, p_np integer, p_np_idx integer default 1)
returns text language sql immutable as $$
  -- "LK 1350" · "LK 1350-2" · "CH 0217". p_np ES el numero de pedido de la pagina.
  -- lpad TRUNCA si el texto ya es mas largo que el ancho; con la guarda, pasado
  -- 9999 la etiqueta crece (LK 10000) en vez de repetir un numero.
  select case when lower(coalesce(p_empresa,'')) in ('chef','ch') then 'CH' else 'LK' end
      || ' '
      || case when length(p_np::text) >= 4 then p_np::text else lpad(p_np::text, 4, '0') end
      || case when coalesce(p_np_idx, 1) > 1 then '-' || p_np_idx::text else '' end;
$$;
grant execute on function public.gv_ppp_web_np_label(text, integer, integer) to anon, authenticated, service_role;

-- ── 3. "Asignar" = registrar np = order_id ────────────────────────────────────
create or replace function public.gv_ppp_web_np_asignar(p_empresa text, p_pares jsonb)
returns table(r_order_id bigint, r_np_idx integer, r_np integer)
language plpgsql security definer set search_path to 'public'
as $function$
begin
  -- El candado se conserva: con esto en 0 Gestion no registra ni etiqueta nada.
  if coalesce((select valor from public."PPP_Web_Config" where clave = 'numeracion_activa'), 0) <> 1 then
    raise exception 'Numeración de NP APAGADA (PPP_Web_Config.numeracion_activa = 0). Se prende el día que Gestión tome control de Producción.';
  end if;

  -- 2026-09-05: la NP ES el numero de pedido de la pagina. No hay contador: cada
  -- bloque se registra con np = order_id y el bloque va en np_idx. Idempotente.
  insert into public."PPP_Web_NP" (empresa, np, order_id, np_idx)
  select p_empresa, (x->>'order_id')::bigint::int, (x->>'order_id')::bigint, (x->>'np_idx')::int
    from jsonb_array_elements(coalesce(p_pares, '[]'::jsonb)) x
  on conflict (empresa, order_id, np_idx) do nothing;

  return query
    with pedir as (
      select (x->>'order_id')::bigint as oid, (x->>'np_idx')::int as idx
      from jsonb_array_elements(coalesce(p_pares, '[]'::jsonb)) x
    )
    select n.order_id, n.np_idx, n.np
      from public."PPP_Web_NP" n
      join pedir p on p.oid = n.order_id and p.idx = n.np_idx
     where n.empresa = p_empresa;
end
$function$;
revoke all on function public.gv_ppp_web_np_asignar(text, jsonb) from public, anon, authenticated;
grant execute on function public.gv_ppp_web_np_asignar(text, jsonb) to service_role;

-- ── 4. Las dos vistas, con la etiqueta por bloque ─────────────────────────────
create view public.gv_ppp_web_estado
with (security_invoker = true) as
 WITH ev AS (
         SELECT r.texto AS tanda,
            max(CASE WHEN r.opcion = 'EP'  THEN r.created_at END) AS ep,
            max(CASE WHEN r.opcion = 'TP'  THEN r.created_at END) AS tp,
            max(CASE WHEN r.opcion = 'AP'  THEN r.created_at END) AS ap,
            max(CASE WHEN r.opcion = 'TAP' THEN r.created_at END) AS tap
           FROM public."Registros_Produccion_Virgilio" r
          WHERE r.opcion = ANY (ARRAY['EP','TP','AP','TAP'])
            AND r.texto IN (SELECT DISTINCT g_1.tanda FROM public."PPP_Web_Programacion" g_1 WHERE g_1.tanda IS NOT NULL)
          GROUP BY r.texto
        )
 SELECT g.empresa, g.order_id, g.np_idx, g.np,
    public.gv_ppp_web_np_label(g.empresa, g.np, g.np_idx) AS np_label,
    g.cod_cliente, g.razon_social, g.tanda, g.zona, g.fecha_entrega, g.m3, g.cajas, g.lineas,
    g.es_agregado, g.agregado_a_np, g.agregado_en, g.prioridad,
        CASE
            WHEN f.np IS NOT NULL THEN 'facturado'
            WHEN e.tap IS NOT NULL THEN 'armado'
            WHEN e.ap IS NOT NULL THEN 'en_armado'
            WHEN e.tp IS NOT NULL THEN 'pickeado'
            WHEN e.ep IS NOT NULL THEN 'en_picking'
            WHEN g.tanda IS NOT NULL THEN 'programado'
            ELSE 'sin_programar'
        END AS estado,
    COALESCE(e.tap, e.ap, e.tp, e.ep) AS estado_desde,
    (f.np IS NULL) AS puede_agregar,
    false AS puede_quitar,
    (f.np IS NULL AND COALESCE(e.ep, e.tp, e.ap, e.tap) IS NOT NULL) AS agregado_seria_urgente
   FROM public."PPP_Web_Programacion" g
     LEFT JOIN ev e ON e.tanda = g.tanda
     LEFT JOIN public."Facturacion_NP" f ON f.np = public.gv_ppp_web_np_label(g.empresa, g.np, g.np_idx);

create view public.gv_ppp_web_entregados
with (security_invoker = true) as
with crn as (
  select upper(btrim(split_part(r.texto, '|', 1))) as np_label,
         min(r.ts_cliente)                          as controlado_at,
         count(*)                                   as n_crn
  from public."Registros_Produccion_Virgilio" r
  where r.opcion = 'CRN'
    and r.texto ~* '^\s*(LK|CH)\s+\d+'
    and not public.es_legajo_test(r.legajo)
  group by 1
)
select p.empresa, p.np, c.np_label, p.tanda, p.cod_cliente, p.razon_social, p.m3, p.fecha_entrega,
       c.controlado_at, c.n_crn
from crn c
join public."PPP_Web_Programacion" p
  on public.gv_ppp_web_np_label(p.empresa, p.np, p.np_idx) = c.np_label;

revoke all on public.gv_ppp_web_estado, public.gv_ppp_web_entregados from anon, authenticated;
grant select on public.gv_ppp_web_estado, public.gv_ppp_web_entregados to anon, authenticated;

-- ── 5. resync y programar a mano: la etiqueta lleva el bloque ────────────────
create or replace function public.ppp_web_resync(p_empresa text, p_filas jsonb)
returns table(r_order_id bigint, r_np_idx integer, r_accion text)
language plpgsql as $function$
begin
  return query
  with vivas as (
    select (x->>'order_id')::bigint as order_id,
           (x->>'np_idx')::int      as np_idx,
           nullif(x->>'m3','')::numeric                 as m3,
           coalesce((x->>'m3_parcial')::boolean, false) as m3_parcial,
           nullif(x->>'lineas','')::int                 as lineas,
           nullif(x->>'cajas','')::numeric              as cajas,
           nullif(x->>'cod','')          as cod_cliente,
           nullif(x->>'razon_social','') as razon_social,
           nullif(x->>'direccion','')    as direccion,
           nullif(x->>'barrio','')       as barrio
      from jsonb_array_elements(p_filas) x
  ),
  -- Pedidos que ya tienen programación y ninguna NP facturada: los únicos que se tocan.
  -- El apareo con Facturacion_NP va por la ETIQUETA (`gv_ppp_web_np_label`, con bloque),
  -- no por el número pelado: `Facturacion_NP.np` es text con la NP tal como viaja.
  pedidos as (
    select distinct g.order_id
      from public."PPP_Web_Programacion" g
     where g.empresa = p_empresa
       and exists (select 1 from vivas v where v.order_id = g.order_id)
       and not exists (
             select 1 from public."PPP_Web_Programacion" g2
               join public."Facturacion_NP" f
                 on f.np = public.gv_ppp_web_np_label(p_empresa, g2.np, g2.np_idx)
              where g2.empresa = p_empresa and g2.order_id = g.order_id)
  ),
  tanda as (
    select distinct on (g.order_id)
           g.order_id, g.tanda, g.zona, g.fecha_entrega, g.op, g.observaciones,
           g.np as np_padre,
           exists (select 1 from public."Registros_Produccion_Virgilio" r
                    where r.opcion in ('EP','TP','AP','TAP') and r.texto = g.tanda)
             as ya_en_marcha
      from public."PPP_Web_Programacion" g
      join pedidos p on p.order_id = g.order_id
     where g.empresa = p_empresa
     order by g.order_id, g.np_idx
  ),
  borradas as (
    delete from public."PPP_Web_Programacion" g
     where g.empresa = p_empresa
       and g.order_id in (select order_id from tanda t where not t.ya_en_marcha)
       and not exists (select 1 from vivas v
                        where v.order_id = g.order_id and v.np_idx = g.np_idx)
    returning g.order_id, g.np_idx
  ),
  actualizadas as (
    update public."PPP_Web_Programacion" g
       set m3 = v.m3, m3_parcial = v.m3_parcial,
           lineas = v.lineas, cajas = v.cajas,
           cod_cliente  = coalesce(v.cod_cliente,  g.cod_cliente),
           razon_social = coalesce(v.razon_social, g.razon_social),
           direccion    = coalesce(v.direccion,    g.direccion),
           barrio       = coalesce(v.barrio,       g.barrio)
      from vivas v
     where g.empresa = p_empresa
       and g.order_id in (select order_id from pedidos)
       and v.order_id = g.order_id and v.np_idx = g.np_idx
       and (g.m3         is distinct from v.m3
         or g.lineas     is distinct from v.lineas
         or g.cajas      is distinct from v.cajas
         or g.m3_parcial is distinct from v.m3_parcial)
    returning g.order_id, g.np_idx
  ),
  agregadas as (
    insert into public."PPP_Web_Programacion"
      (empresa, order_id, np_idx, np, cod_cliente, razon_social, direccion, barrio,
       tanda, zona, fecha_entrega, op, observaciones, m3, m3_parcial, lineas, cajas,
       es_agregado, agregado_a_np, agregado_en, prioridad)
    select p_empresa, v.order_id, v.np_idx,
           -- 2026-09-05: la NP es el numero de pedido; el bloque nuevo lo hereda.
           coalesce((select n.np from public."PPP_Web_NP" n
                      where n.empresa = p_empresa and n.order_id = v.order_id and n.np_idx = v.np_idx),
                    v.order_id::int),
           v.cod_cliente, v.razon_social, v.direccion, v.barrio,
           t.tanda, t.zona, t.fecha_entrega, t.op, t.observaciones,
           v.m3, v.m3_parcial, v.lineas, v.cajas,
           t.ya_en_marcha,
           case when t.ya_en_marcha then t.np_padre end,
           case when t.ya_en_marcha then now() end,
           case when t.ya_en_marcha then 100 else 0 end
      from vivas v
      join tanda t on t.order_id = v.order_id
     where not exists (select 1 from public."PPP_Web_Programacion" g
                        where g.empresa = p_empresa
                          and g.order_id = v.order_id and g.np_idx = v.np_idx)
    returning order_id, np_idx, es_agregado
  )
  select b.order_id, b.np_idx, 'borrada'::text from borradas b
  union all
  select a.order_id, a.np_idx, 'actualizada'   from actualizadas a
  union all
  select g.order_id, g.np_idx,
         case when g.es_agregado then 'agregado_urgente' else 'agregada_a_tanda' end
    from agregadas g;
end
$function$;

create or replace function public.gv_ppp_web_tanda_programar(p_empresa text, p_codigo text, p_fecha date, p_items jsonb default '[]'::jsonb, p_por text default null)
returns table(np_programadas integer, m3 numeric, lineas_base integer, aviso_dia text)
language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_estado text;
  v_n      int;
  v_m3     numeric;
  v_base   int := 0;
  v_cupo   numeric := coalesce((select valor from public."PPP_Web_Config" where clave='m3_max_dia'), 5.00);
  v_usado  numeric;
  v_aviso  text := null;
  v_pares  jsonb;
begin
  select t.estado into v_estado from public."PPP_Web_Tandas" t
   where t.empresa = p_empresa and t.codigo = p_codigo;
  if v_estado is null then raise exception 'No existe la tanda % de %', p_codigo, p_empresa; end if;
  if v_estado <> 'borrador' then raise exception 'La tanda % ya está %.', p_codigo, v_estado; end if;
  if p_fecha is null then raise exception 'Falta la fecha de entrega.'; end if;

  select count(*), coalesce(sum(i.m3),0) into v_n, v_m3
    from public."PPP_Web_Tanda_Items" i where i.empresa = p_empresa and i.codigo = p_codigo;
  if v_n = 0 then raise exception 'La tanda % está vacía.', p_codigo; end if;

  -- Registrar la NP (= numero de pedido) de cada bloque. `PPP_Web_Base.np_label`
  -- es NOT NULL y se arma con ese numero.
  select jsonb_agg(jsonb_build_object('order_id', i.order_id, 'np_idx', i.np_idx))
    into v_pares
    from public."PPP_Web_Tanda_Items" i
   where i.empresa = p_empresa and i.codigo = p_codigo;
  perform public.gv_ppp_web_np_asignar(p_empresa, v_pares);

  update public."PPP_Web_Tandas" t
     set estado = 'programada', fecha_entrega = p_fecha,
         programada_por = p_por, programada_at = now()
   where t.empresa = p_empresa and t.codigo = p_codigo;

  insert into public."PPP_Web_Programacion"
    (empresa, order_id, np_idx, np, cod_cliente, razon_social, zona,
     tanda, fecha_entrega, fecha_recep, m3, m3_parcial, lineas, cajas)
  select i.empresa, i.order_id, i.np_idx,
         (select n.np from public."PPP_Web_NP" n
           where n.empresa = i.empresa and n.order_id = i.order_id and n.np_idx = i.np_idx),
         i.cod_cliente, i.razon_social, i.zona,
         p_codigo, p_fecha, i.fecha_recep, i.m3, i.m3_parcial, i.lineas, i.cajas
    from public."PPP_Web_Tanda_Items" i
   where i.empresa = p_empresa and i.codigo = p_codigo
  on conflict (empresa, order_id, np_idx) do update
     set tanda = excluded.tanda, fecha_entrega = excluded.fecha_entrega,
         np = coalesce(excluded.np, public."PPP_Web_Programacion".np),
         zona = excluded.zona, m3 = excluded.m3, m3_parcial = excluded.m3_parcial,
         lineas = excluded.lineas, cajas = excluded.cajas;

  if jsonb_array_length(coalesce(p_items,'[]'::jsonb)) > 0 then
    insert into public."PPP_Web_Base" (empresa, order_id, np_idx, np_label, articulo, cajas)
    select p_empresa, (x->>'order_id')::bigint, (x->>'np_idx')::int,
           public.gv_ppp_web_np_label(p_empresa,
             (select n.np from public."PPP_Web_NP" n
               where n.empresa = p_empresa and n.order_id = (x->>'order_id')::bigint
                 and n.np_idx = (x->>'np_idx')::int),
             (x->>'np_idx')::int),
           btrim(it->>'art'), sum(coalesce((it->>'cajas')::numeric, 0))
      from jsonb_array_elements(p_items) x,
           jsonb_array_elements(coalesce(x->'items','[]'::jsonb)) it
     where btrim(coalesce(it->>'art','')) <> ''
     group by 1,2,3,4,5
    on conflict (empresa, order_id, np_idx, articulo) do update set cajas = excluded.cajas;
    get diagnostics v_base = row_count;
  end if;

  delete from public."PPP_Web_Tanda_Items" i
   where i.empresa = p_empresa and i.codigo = p_codigo;

  select coalesce(sum(g.m3),0) into v_usado
    from public."PPP_Web_Programacion" g
   where g.fecha_entrega = p_fecha and coalesce(nullif(trim(g.tanda),''),'') <> '';
  if v_usado > v_cupo then
    v_aviso := 'El ' || to_char(p_fecha,'DD/MM') || ' queda con ' || round(v_usado,3) ||
               ' m³ programados, por encima del cupo de ' || v_cupo || ' m³.';
  end if;
  if not public.gv_es_dia_habil(p_fecha) then
    v_aviso := coalesce(v_aviso || ' ', '') || 'Ojo: el ' || to_char(p_fecha,'DD/MM') ||
               ' no es día hábil (fin de semana o feriado).';
  end if;

  return query select v_n, round(v_m3,3), v_base, v_aviso;
end $function$;
