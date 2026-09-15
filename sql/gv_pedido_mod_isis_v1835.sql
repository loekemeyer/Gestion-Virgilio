-- ============================================================================
-- v18.35 — Modificar Pedidos: ahora también las NP de ISIS.  PROYECTO: VIRGILIO.
--
-- Luis, 15/09: *"para los pedidos de isis no hay problema con que se cambien en
-- la PPP, pero en el módulo de facturación debería tener un badge … que indique
-- que fue modificado"*. El badge ya está (v18.29); esto es el otro lado: poder
-- cambiarlas.
--
-- DÓNDE SE ESCRIBE. Una NP de ISIS no tiene pedido en la página: su contenido lo
-- carga la importación del Excel PPP en `GV_PPP_Base_Pedidos` y su dirección vive
-- en `GV_PPP_Programacion_Diaria`, que es tabla COMPARTIDA. Así que no se toca
-- ninguna de las dos: el cambio va a tablas de OVERRIDE que las vistas superponen
-- (la misma receta que ya usaba `GV_PPP_Prog_Override` para tanda y fecha). Eso
-- además hace que una re-importación del Excel NO pise lo modificado.
--
-- ⚠ LO QUE HAY QUE SABER ANTES DE TOCAR `gv_ppp_base_pedidos`: la lee MEDIO
-- SISTEMA — 17 vistas y 8 funciones (picking, cobranzas, cuarentena, facturable,
-- isis_pedido_json). Por eso el cambio se hizo con `CREATE OR REPLACE` (mismas 6
-- columnas, mismos tipos: sin DROP CASCADE) y se verificó con la huella:
--
--   select count(*), sum(hashtext(pedido||'|'||articulo||'|'||cajas||'|'||cliente||'|'||fecha)::bigint),
--          sum(cajas) from public.gv_ppp_base_pedidos;
--   -- antes y después: 9663 filas · 81644939734 · 50443.99  (idéntico, override vacío)
--
-- ⚠ Y LA TRAMPA DE LOS PARES REPETIDOS: `GV_PPP_Base_Pedidos` tiene 9 pares
-- (pedido, artículo) con MÁS DE UNA FILA. Si el override pisara "las cajas" con un
-- LEFT JOIN, cada una de esas filas se quedaría con el valor nuevo y el pedido
-- saldría duplicado. Por eso el bloque (2) agrupa: una sola fila por override.
-- ============================================================================

-- ── 1) El override del CONTENIDO ───────────────────────────────────────────
create table if not exists public."GV_PPP_Base_Override" (
  id        bigserial primary key,
  np        text        not null,
  articulo  text        not null,
  cajas     numeric,
  quitado   boolean     not null default false,
  cliente   text,
  fecha     text,
  motivo    text,
  por       text,
  creado_at timestamptz not null default now()
);
create unique index if not exists gv_ppp_base_override_ux on public."GV_PPP_Base_Override" (np, articulo);
alter table public."GV_PPP_Base_Override" enable row level security;
revoke insert, update, delete, truncate on public."GV_PPP_Base_Override" from anon, authenticated;
grant select on public."GV_PPP_Base_Override" to anon, authenticated, lk_ppp_reader, ch_ppp_reader;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public'
                   and tablename='GV_PPP_Base_Override' and policyname='gv_ppp_base_override_lee') then
    create policy gv_ppp_base_override_lee on public."GV_PPP_Base_Override"
      for select to anon, authenticated, lk_ppp_reader, ch_ppp_reader using (true);
  end if;
end $$;

-- ── 2) La base de picking, con el override superpuesto ─────────────────────
create or replace view public.gv_ppp_base_pedidos as
with base as (
  select b.id, b.pedido, b.articulo, b.cajas, b.cliente, b.fecha,
         regexp_replace(btrim(b.pedido), '\.0+$', '') as np_n,
         upper(btrim(b.articulo)) as art_n
    from public."GV_PPP_Base_Pedidos" b
    cross join public.gv_espejo_corte() c(lk, chef)
   where public.gv_espejo_np_pasa(b.pedido, c.lk, c.chef)
     and not exists (select 1 from public."GV_PPP_Prog_Override" o
                      where o.oculto and o.np = regexp_replace(btrim(b.pedido), '\.0+$', ''))
), ov as (
  select o.id, regexp_replace(btrim(o.np), '\.0+$', '') as np, upper(btrim(o.articulo)) as articulo,
         o.cajas, o.quitado, o.cliente, o.fecha
    from public."GV_PPP_Base_Override" o
)
-- (1) lo que nadie tocó, tal cual
select b.id, b.pedido, b.articulo, b.cajas, b.cliente, b.fecha
  from base b
 where not exists (select 1 from ov o where o.np = b.np_n and o.articulo = b.art_n)
union all
-- (2) lo pisado: UNA sola fila por (np, artículo) aunque la base traiga varias
select min(b.id), min(b.pedido), min(b.articulo), max(o.cajas), min(b.cliente), min(b.fecha)
  from base b
  join ov o on o.np = b.np_n and o.articulo = b.art_n
 where not o.quitado
 group by o.id
union all
-- (3) lo agregado: no existe en la base, entra con el id del override en negativo
select -o.id, o.np, o.articulo, o.cajas, coalesce(o.cliente, d.cliente), coalesce(o.fecha, d.fecha)
  from ov o
  left join lateral (select b2.cliente, b2.fecha from base b2 where b2.np_n = o.np limit 1) d on true
 where not o.quitado
   and not exists (select 1 from base b3 where b3.np_n = o.np and b3.art_n = o.articulo);
alter view public.gv_ppp_base_pedidos set (security_invoker = true);
grant select on public.gv_ppp_base_pedidos to anon, authenticated, lk_ppp_reader, ch_ppp_reader;

-- ── 3) La dirección: dos columnas más en el override que ya existía ────────
alter table public."GV_PPP_Prog_Override" add column if not exists direccion text;
alter table public."GV_PPP_Prog_Override" add column if not exists barrio text;
-- y en `gv_ppp_programacion_diaria` (el resto de la vista queda igual; ver el
-- archivo §3.gz / sql/gv_ppp_prog_override.sql) las dos líneas nuevas son:
--     COALESCE(NULLIF(btrim(o.direccion), ''::text), p.direccion) AS direccion,
--     COALESCE(NULLIF(btrim(o.barrio), ''::text), p.barrio) AS barrio,
-- Verificado con la misma huella: 123 filas · -17233616518, antes y después.

-- ── 4) La RPC ──────────────────────────────────────────────────────────────
-- Valida, escribe los dos overrides y el log, todo en la misma transacción.
-- El contenido se REARMA entero en cada guardado (delete + insert del diff contra
-- la base cruda): es idempotente y auto-reparable — si un renglón vuelve a su
-- valor original, su fila de override simplemente no se escribe.
create or replace function public.gv_pedido_mod_isis(
  p_np        text,
  p_items     jsonb   default null,
  p_direccion text    default null,
  p_barrio    text    default null,
  p_motivo    text    default null,
  p_quien     text    default null,
  p_espera    jsonb   default null
) returns jsonb
language plpgsql security definer set search_path to 'public','pg_temp' as $fn$
declare
  v_np    text := regexp_replace(btrim(coalesce(p_np,'')), '\.0+$', '');
  v_emp   text;
  v_prog  record;
  v_antes jsonb; v_despues jsonb; v_det jsonb;
  v_malos text; v_tipo text; v_sinuxb text;
  v_dir_old text; v_bar_old text;
begin
  if auth.uid() is null then
    raise exception 'Hace falta la sesion de supervisor para modificar un pedido.'
      using errcode = 'insufficient_privilege';
  end if;
  if v_np = '' then raise exception 'Falta la NP.' using errcode='check_violation'; end if;
  if length(btrim(coalesce(p_motivo,''))) < 3 then
    raise exception 'Falta el justificativo: hay que escribir por que se modifica el pedido.'
      using errcode='check_violation';
  end if;
  if length(btrim(coalesce(p_quien,''))) < 2 then
    raise exception 'Falta quien hace la modificacion.' using errcode='check_violation';
  end if;
  if p_items is null and p_direccion is null and p_barrio is null then
    raise exception 'No viene ningun cambio.' using errcode='check_violation';
  end if;

  select * into v_prog from public.gv_ppp_programacion_diaria g where g.np = v_np limit 1;
  if not found and not exists (select 1 from public.gv_ppp_base_pedidos b
                                where regexp_replace(btrim(b.pedido), '\.0+$','') = v_np) then
    raise exception 'No encuentro la NP % ni en la programacion ni en la base de picking.', v_np;
  end if;
  v_emp := public.gv_empresa_de_np_texto(v_np);

  if exists (select 1 from public."Facturacion_NP" f
              where regexp_replace(btrim(f.np), '\.0+$','') = v_np) then
    raise exception 'La NP % ya esta facturada: no se modifica desde aca.', v_np
      using errcode='check_violation';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('cod_art', x.art, 'cajas', x.cajas) order by x.art), '[]'::jsonb)
    into v_antes
    from (select upper(btrim(b.articulo)) art, sum(coalesce(b.cajas,0)) cajas
            from public.gv_ppp_base_pedidos b
           where regexp_replace(btrim(b.pedido), '\.0+$','') = v_np
             and coalesce(btrim(b.articulo),'') <> ''
           group by 1) x;
  v_dir_old := v_prog.direccion; v_bar_old := v_prog.barrio;

  if p_espera is not null and p_espera is distinct from v_antes then
    raise exception 'El pedido cambio mientras lo tenias abierto. Cerra y volve a abrirlo.'
      using errcode='serialization_failure';
  end if;

  if p_items is not null then
    if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
      raise exception 'Un pedido no puede quedar sin ningun renglon.' using errcode='check_violation';
    end if;
    -- un codigo vale si Gestion le conoce el u×B o si ya aparece en alguna base:
    -- 369 de los 373 codigos de la base de ISIS estan en gv_uxb_resuelto (medido 15/09),
    -- asi que exigirlo a secas dejaria afuera 4 que son legitimos.
    select string_agg(distinct x.cod, ', ') into v_malos
      from (select upper(btrim(it.value->>'cod_art')) cod, nullif(it.value->>'cajas','')::numeric cajas
              from jsonb_array_elements(p_items) it) x
     where coalesce(x.cod,'') !~ '^[0-9]' or coalesce(x.cajas,0) <= 0
        or (not exists (select 1 from public.gv_uxb_resuelto u where btrim(u.cod) = x.cod)
        and not exists (select 1 from public."GV_PPP_Base_Pedidos" b where upper(btrim(b.articulo)) = x.cod));
    if v_malos is not null then
      raise exception 'Renglones que no puedo guardar (codigo desconocido o cantidad invalida): %', v_malos
        using errcode='check_violation';
    end if;
    if exists (select 1 from (select upper(btrim(it.value->>'cod_art')) c
                                from jsonb_array_elements(p_items) it) q
                group by q.c having count(*) > 1) then
      raise exception 'Hay un codigo repetido en la lista: junta las cajas en un solo renglon.'
        using errcode='check_violation';
    end if;

    delete from public."GV_PPP_Base_Override" o where regexp_replace(btrim(o.np), '\.0+$','') = v_np;

    with nuevo as (
      select upper(btrim(it.value->>'cod_art')) cod, (nullif(it.value->>'cajas','')::numeric) cajas
        from jsonb_array_elements(p_items) it
    ), viejo as (
      select upper(btrim(b.articulo)) cod, sum(coalesce(b.cajas,0)) cajas
        from public."GV_PPP_Base_Pedidos" b
       where regexp_replace(btrim(b.pedido), '\.0+$','') = v_np
         and coalesce(btrim(b.articulo),'') <> ''
       group by 1
    )
    insert into public."GV_PPP_Base_Override" (np, articulo, cajas, quitado, motivo, por)
    select v_np, coalesce(n.cod, v.cod), n.cajas, (n.cod is null),
           btrim(p_motivo), btrim(p_quien)
      from nuevo n full join viejo v on v.cod = n.cod
     where n.cod is null
        or v.cod is null
        or n.cajas is distinct from v.cajas;
    v_tipo := 'items';
  end if;

  if p_direccion is not null or p_barrio is not null then
    insert into public."GV_PPP_Prog_Override" (np, direccion, barrio, nota, creado_en)
    values (v_np, nullif(btrim(coalesce(p_direccion,'')),''), nullif(btrim(coalesce(p_barrio,'')),''),
            'direccion cambiada desde Modificar Pedidos', now())
    on conflict (np) do update
       set direccion = coalesce(nullif(btrim(coalesce(excluded.direccion,'')),''), public."GV_PPP_Prog_Override".direccion),
           barrio    = coalesce(nullif(btrim(coalesce(excluded.barrio,'')),''),    public."GV_PPP_Prog_Override".barrio);
    v_tipo := case when v_tipo = 'items' then 'items+direccion' else 'direccion' end;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('cod_art', x.art, 'cajas', x.cajas) order by x.art), '[]'::jsonb)
    into v_despues
    from (select upper(btrim(b.articulo)) art, sum(coalesce(b.cajas,0)) cajas
            from public.gv_ppp_base_pedidos b
           where regexp_replace(btrim(b.pedido), '\.0+$','') = v_np
             and coalesce(btrim(b.articulo),'') <> ''
           group by 1) x;
  select string_agg(distinct x.art, ', ') into v_sinuxb
    from (select upper(btrim(b.articulo)) art from public.gv_ppp_base_pedidos b
           where regexp_replace(btrim(b.pedido), '\.0+$','') = v_np) x
   where not exists (select 1 from public.gv_uxb_resuelto u where btrim(u.cod) = x.art);

  with va as (select value->>'cod_art' cod, (value->>'cajas')::numeric cajas from jsonb_array_elements(v_antes)),
       nu as (select value->>'cod_art' cod, (value->>'cajas')::numeric cajas from jsonb_array_elements(v_despues)),
       j  as (select coalesce(n.cod, v.cod) cod, v.cajas de, n.cajas a from nu n full join va v on v.cod = n.cod)
  select jsonb_build_object(
    'agregados', coalesce((select jsonb_agg(jsonb_build_object('cod', cod, 'cajas', a)) from j where de is null), '[]'::jsonb),
    'quitados',  coalesce((select jsonb_agg(jsonb_build_object('cod', cod, 'cajas', de)) from j where a is null), '[]'::jsonb),
    'cambiados', coalesce((select jsonb_agg(jsonb_build_object('cod', cod, 'de', de, 'a', a)) from j
                            where de is not null and a is not null and de is distinct from a), '[]'::jsonb),
    'direccion', case when p_direccion is null and p_barrio is null then null
                      else jsonb_build_object('de', coalesce(v_dir_old,'—'),
                                              'a', coalesce(nullif(btrim(coalesce(p_direccion,'')),''), v_dir_old, '—'),
                                              'barrio', nullif(btrim(coalesce(p_barrio,'')),'')) end,
    'sin_uxb', v_sinuxb
  ) into v_det;

  insert into public."GV_Pedido_Mod_Log"
    (empresa, fuente, clave, order_id, nps, hecho_en, quien, quien_sesion, tipo, motivo,
     antes, despues, detalle, origen)
  values (case when v_emp = 'chef' then 'chef' else 'lk' end, 'isis', v_np, null, array[v_np], now(),
          btrim(p_quien), coalesce(auth.jwt()->>'email',''), v_tipo, btrim(p_motivo),
          jsonb_build_object('items', v_antes, 'direccion', v_dir_old, 'barrio', v_bar_old),
          jsonb_build_object('items', v_despues,
                             'direccion', coalesce(nullif(btrim(coalesce(p_direccion,'')),''), v_dir_old),
                             'barrio', coalesce(nullif(btrim(coalesce(p_barrio,'')),''), v_bar_old)),
          v_det, 'gestion:modificar-pedidos');

  return jsonb_build_object('ok', true, 'np', v_np, 'tipo', v_tipo, 'detalle', v_det,
                            'items', v_despues);
end $fn$;
revoke all on function public.gv_pedido_mod_isis(text, jsonb, text, text, text, text, jsonb) from public, anon;
grant execute on function public.gv_pedido_mod_isis(text, jsonb, text, text, text, text, jsonb) to authenticated;

-- ── Prueba (15/09, transacción abortada, NP 98664) ─────────────────────────
-- · sin motivo → corta.
-- · con motivo: el 034 pasó de 1 a 6, se quitó el 960E y se agregó el 001 ×3 →
--   la NP quedó con 16 renglones, `gv_ppp_programacion_diaria` mostró la dirección
--   pisada ("Calle Falsa 123 / Lanus") y quedó 1 fila en `GV_Pedido_Mod_Log`
--   (fuente='isis'). Tras el rollback: 0 overrides, 0 log, 9663 filas en la base
--   y `gv_endpoints_rotos` vacía.
--
-- ── Rollback ───────────────────────────────────────────────────────────────
-- drop function public.gv_pedido_mod_isis(text,jsonb,text,text,text,text,jsonb);
-- y volver `gv_ppp_base_pedidos` a su forma simple (sin el CTE del override):
--   create or replace view public.gv_ppp_base_pedidos as
--   select b.id, b.pedido, b.articulo, b.cajas, b.cliente, b.fecha
--     from "GV_PPP_Base_Pedidos" b cross join gv_espejo_corte() c(lk, chef)
--    where gv_espejo_np_pasa(b.pedido, c.lk, c.chef)
--      and not exists (select 1 from "GV_PPP_Prog_Override" o
--                       where o.oculto and o.np = regexp_replace(btrim(b.pedido), '\.0+$', ''));
--   alter view public.gv_ppp_base_pedidos set (security_invoker = true);
-- Las dos columnas de `GV_PPP_Prog_Override` pueden quedarse: son nullable y nadie
-- más las mira.
