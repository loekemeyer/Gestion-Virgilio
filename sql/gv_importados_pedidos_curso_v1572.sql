-- v15.72 — Pedidos Importación: "Pedidos en curso" separado del generador (embarque + llegada)
-- Proyecto Supabase: hrxfctzncixxqmpfhskv — 2026-09-11
--
-- Pedido del dueño (11/09): "quiero ver cuáles son los pedidos en curso por separado de si genera
-- o no genera pedido. Haceme un botón donde pueda ver qué día llegan y qué día es la fecha de embarque".
--
-- Qué cambia:
--   1) GV_Importados_Baches: dos columnas nuevas (nullable, sin default, sin backfill destructivo)
--        · pedido_ref      text  — el PI/CI al que pertenece el bache (antes se escribía en creado_por)
--        · fecha_embarque  date  — el día que embarca (sale de China). La llegada sigue en fecha_reingreso.
--   2) Backfill de pedido_ref desde creado_por (donde era un PI/CI) y de las 6 filas que quedaron
--      con el mail del que cargó (5 Fujian = PI HT26-06-600-R1, 1 Frontier = 505C sin PI) + el suelto 323ES.
--   3) Vista gv_importados_pedidos_curso (security_invoker) — UNA fila por pedido en curso.
--   4) RPCs (SECURITY DEFINER, anon): listar pedidos, listar sus líneas, y setear las dos fechas
--      de TODO el pedido de una. gv_importado_baches ahora devuelve pedido_ref y fecha_embarque.
--   5) gv_importado_bache_add acepta p_ref y p_embarque (opcionales; las llamadas viejas siguen igual).
--
-- Backup previo: GV_Importados_Baches_bkp_encurso_20260911 (tabla entera, 131 filas).

-- ---------- 1) columnas ----------
alter table public."GV_Importados_Baches"
  add column if not exists pedido_ref     text,
  add column if not exists fecha_embarque date;

comment on column public."GV_Importados_Baches".pedido_ref is
  'PI/CI del pedido de importación al que pertenece el bache. Agrupa la pantalla "Pedidos en curso".';
comment on column public."GV_Importados_Baches".fecha_embarque is
  'Día de embarque (sale de China). La llegada estimada es fecha_reingreso.';

create index if not exists gv_imp_baches_pedido_ref_idx
  on public."GV_Importados_Baches" (pedido_ref) where estado = 'en_curso';

-- ---------- 2) backfill ----------
update public."GV_Importados_Baches"
   set pedido_ref = btrim(creado_por)
 where pedido_ref is null
   and (creado_por like 'PI %' or creado_por like 'CI %');

-- las 5 líneas de Fujian que Becky cargó el 10/09 desde "Cargar pedido ya hecho" (§3.bm.2)
update public."GV_Importados_Baches"
   set pedido_ref = 'PI HT26-06-600-R1'
 where pedido_ref is null and proveedor = 'Fujian' and estado = 'en_curso';

-- Frontier: 505C 200.000 u, 04/11 — no hay PI cargado todavía
update public."GV_Importados_Baches"
   set pedido_ref = 'Frontier 505C'
 where pedido_ref is null and proveedor = 'Frontier' and estado = 'en_curso';

-- el suelto que cargó el dueño el 11/09
update public."GV_Importados_Baches"
   set pedido_ref = '323ES suelto'
 where pedido_ref is null and estado = 'en_curso' and creado_por like 'dueño%';

-- ---------- 3) vista ----------
create or replace view public.gv_importados_pedidos_curso as
with b as (
  select b.*, greatest(0, b.unidades - b.unidades_llegadas)::int as pend
    from public."GV_Importados_Baches" b
   where b.estado = 'en_curso'
)
select
  coalesce(nullif(btrim(b.pedido_ref), ''), '(sin pedido)')   as pedido_ref,
  coalesce(nullif(btrim(b.proveedor),  ''), '(sin proveedor)') as proveedor,
  count(*)::int                                     as n_lineas,
  sum(b.unidades)::int                              as unidades,
  sum(b.pend)::int                                  as pendiente,
  sum(b.unidades_llegadas)::int                     as llegadas,
  min(b.fecha_embarque)                             as fecha_embarque,
  min(b.fecha_reingreso)                            as fecha_llegada,
  max(b.fecha_reingreso)                            as fecha_llegada_max,
  count(*) filter (where b.fecha_reingreso is null)::int as lineas_sin_fecha,
  round(sum(b.pend * coalesce(im.fob_uni, 0))::numeric, 2)  as usd,
  round(sum(case when coalesce(v.uni_master, 0) > 0 and coalesce(v.m3_master, 0) > 0
                 then b.pend::numeric / v.uni_master * v.m3_master else 0 end)::numeric, 3) as m3,
  (min(b.fecha_reingreso) - current_date)::int      as dias_para_llegar,
  (min(b.fecha_embarque)  - current_date)::int      as dias_para_embarcar,
  min(b.creado)                                     as creado
from b
left join public."Importados"        im on im.id  = b.importado_id
left join public."Importados_Volumen" v on v.cod  = b.cod_art
group by 1, 2;

alter view public.gv_importados_pedidos_curso set (security_invoker = true);

-- ---------- 4) RPCs ----------
create or replace function public.gv_importados_pedidos_curso()
returns table (pedido_ref text, proveedor text, n_lineas int, unidades int, pendiente int,
               llegadas int, fecha_embarque date, fecha_llegada date, fecha_llegada_max date,
               lineas_sin_fecha int, usd numeric, m3 numeric,
               dias_para_llegar int, dias_para_embarcar int, creado timestamptz)
language sql stable security definer set search_path to 'public' as $$
  select p.pedido_ref, p.proveedor, p.n_lineas, p.unidades, p.pendiente, p.llegadas,
         p.fecha_embarque, p.fecha_llegada, p.fecha_llegada_max, p.lineas_sin_fecha,
         p.usd, p.m3, p.dias_para_llegar, p.dias_para_embarcar, p.creado
    from public.gv_importados_pedidos_curso p
   order by coalesce(p.fecha_llegada, '9999-12-31'::date), p.proveedor, p.pedido_ref;
$$;

create or replace function public.gv_importado_pedido_lineas(p_pedido_ref text, p_proveedor text default null)
returns table (bache_id bigint, importado_id bigint, cod_art text, marca text, descripcion text,
               unidades int, pendiente int, fecha_embarque date, fecha_reingreso date,
               fob_uni numeric, usd numeric, uni_master int, m3 numeric)
language sql stable security definer set search_path to 'public' as $$
  select b.id, b.importado_id, b.cod_art, b.marca, im.descripcion,
         b.unidades, greatest(0, b.unidades - b.unidades_llegadas)::int,
         b.fecha_embarque, b.fecha_reingreso,
         im.fob_uni,
         round((greatest(0, b.unidades - b.unidades_llegadas) * coalesce(im.fob_uni, 0))::numeric, 2),
         v.uni_master,
         case when coalesce(v.uni_master,0) > 0 and coalesce(v.m3_master,0) > 0
              then round((greatest(0, b.unidades - b.unidades_llegadas)::numeric / v.uni_master * v.m3_master), 3)
              else null end
    from public."GV_Importados_Baches" b
    left join public."Importados"         im on im.id = b.importado_id
    left join public."Importados_Volumen"  v on v.cod = b.cod_art
   where b.estado = 'en_curso'
     and coalesce(nullif(btrim(b.pedido_ref), ''), '(sin pedido)') = p_pedido_ref
     and (p_proveedor is null
          or coalesce(nullif(btrim(b.proveedor), ''), '(sin proveedor)') = p_proveedor)
   order by b.cod_art, b.id;
$$;

-- Setea las fechas de TODO el pedido de una. p_set_* distingue "no tocar" de "poner en null".
create or replace function public.gv_importado_pedido_fechas(
  p_pedido_ref text, p_proveedor text default null,
  p_embarque date default null, p_llegada date default null,
  p_set_embarque boolean default false, p_set_llegada boolean default false)
returns jsonb
language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare v_n int; v_ids bigint[];
begin
  if coalesce(btrim(p_pedido_ref), '') = '' then raise exception 'pedido_ref requerido'; end if;
  if not (p_set_embarque or p_set_llegada) then return jsonb_build_object('filas', 0); end if;

  with upd as (
    update public."GV_Importados_Baches" b
       set fecha_embarque  = case when p_set_embarque then p_embarque else b.fecha_embarque end,
           fecha_reingreso = case when p_set_llegada  then p_llegada  else b.fecha_reingreso end,
           actualizado = now()
     where b.estado = 'en_curso'
       and coalesce(nullif(btrim(b.pedido_ref), ''), '(sin pedido)') = p_pedido_ref
       and (p_proveedor is null
            or coalesce(nullif(btrim(b.proveedor), ''), '(sin proveedor)') = p_proveedor)
    returning b.importado_id
  )
  select count(*)::int, array_agg(distinct importado_id) into v_n, v_ids from upd;

  if p_set_llegada and v_ids is not null then
    perform public.gv_importados_resync(x) from unnest(v_ids) as x;   -- reingreso_est = fecha más cercana
  end if;
  return jsonb_build_object('filas', coalesce(v_n, 0), 'importados', coalesce(array_length(v_ids, 1), 0));
end $$;

-- Renombrar / reasignar el PI de un pedido en curso (o de un bache suelto).
create or replace function public.gv_importado_pedido_ref(
  p_pedido_ref text, p_proveedor text default null, p_nuevo_ref text default null)
returns jsonb
language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare v_n int;
begin
  if coalesce(btrim(p_pedido_ref), '') = '' then raise exception 'pedido_ref requerido'; end if;
  update public."GV_Importados_Baches" b
     set pedido_ref = nullif(btrim(coalesce(p_nuevo_ref, '')), ''), actualizado = now()
   where b.estado = 'en_curso'
     and coalesce(nullif(btrim(b.pedido_ref), ''), '(sin pedido)') = p_pedido_ref
     and (p_proveedor is null
          or coalesce(nullif(btrim(b.proveedor), ''), '(sin proveedor)') = p_proveedor);
  get diagnostics v_n = row_count;
  return jsonb_build_object('filas', v_n);
end $$;

-- El listado por artículo (popup 📦 Baches) pasa a mostrar de qué PI es cada bache y su embarque.
drop function if exists public.gv_importado_baches(bigint);
create or replace function public.gv_importado_baches(p_importado_id bigint)
returns table (id bigint, unidades integer, unidades_llegadas integer, pendiente integer,
               fecha_reingreso date, fecha_embarque date, pedido_ref text, estado text,
               creado timestamptz)
language sql stable security definer set search_path to 'public' as $$
  select id, unidades, unidades_llegadas, greatest(0, unidades - unidades_llegadas) as pendiente,
         fecha_reingreso, fecha_embarque, pedido_ref, estado, creado
    from public."GV_Importados_Baches"
   where importado_id = p_importado_id and estado <> 'anulado'
   order by coalesce(fecha_reingreso, '9999-12-31'::date), id;
$$;

-- Alta de bache con PI y embarque (los dos opcionales: las llamadas viejas siguen andando).
-- Se dropea la firma de 4 args: con las dos nuevas por default, convivir daría llamada ambigua en PostgREST.
drop function if exists public.gv_importado_bache_add(bigint, numeric, date, text);
create or replace function public.gv_importado_bache_add(
  p_importado_id bigint, p_unidades numeric, p_fecha date default null, p_legajo text default null,
  p_ref text default null, p_embarque date default null)
returns jsonb
language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare r record; v_u int; v_id bigint;
begin
  if p_importado_id is null then raise exception 'importado_id requerido'; end if;
  v_u := round(coalesce(p_unidades, 0));
  if v_u <= 0 then raise exception 'unidades debe ser > 0'; end if;
  select id, cod_art, proveedor, marca into r from public."Importados" where id = p_importado_id;
  if not found then raise exception 'Importado % no existe', p_importado_id; end if;
  insert into public."GV_Importados_Baches"
    (importado_id, cod_art, proveedor, marca, unidades, fecha_reingreso, fecha_embarque,
     pedido_ref, estado, creado_por)
  values (r.id, r.cod_art, r.proveedor, r.marca, v_u, p_fecha, p_embarque,
     nullif(btrim(coalesce(p_ref, '')), ''), 'en_curso', nullif(btrim(coalesce(p_legajo, '')), ''))
  returning id into v_id;
  perform public.gv_importados_resync(p_importado_id);
  return jsonb_build_object('bache_id', v_id, 'cod', r.cod_art, 'unidades', v_u);
end $$;

-- Editar un bache: se le puede tocar también el embarque.
create or replace function public.gv_importado_bache_embarque(p_bache_id bigint, p_embarque date default null)
returns jsonb
language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
begin
  update public."GV_Importados_Baches" set fecha_embarque = p_embarque, actualizado = now()
   where id = p_bache_id;
  if not found then raise exception 'Bache % no existe', p_bache_id; end if;
  return jsonb_build_object('bache_id', p_bache_id, 'fecha_embarque', p_embarque);
end $$;

grant execute on function public.gv_importados_pedidos_curso()                              to anon, authenticated;
grant execute on function public.gv_importado_pedido_lineas(text, text)                      to anon, authenticated;
grant execute on function public.gv_importado_pedido_fechas(text, text, date, date, boolean, boolean) to anon, authenticated;
grant execute on function public.gv_importado_pedido_ref(text, text, text)                   to anon, authenticated;
grant execute on function public.gv_importado_baches(bigint)                                 to anon, authenticated;
grant execute on function public.gv_importado_bache_add(bigint, numeric, date, text, text, date) to anon, authenticated;
grant execute on function public.gv_importado_bache_embarque(bigint, date)                   to anon, authenticated;

-- ---------- CHEQUEO ----------
-- select * from public.gv_importados_pedidos_curso order by fecha_llegada;
--   → 8 pedidos en curso; ninguno con fecha_embarque hasta que el dueño las pase.
--
-- ---------- ROLLBACK ----------
--   drop view  if exists public.gv_importados_pedidos_curso;
--   drop function if exists public.gv_importados_pedidos_curso();
--   drop function if exists public.gv_importado_pedido_lineas(text, text);
--   drop function if exists public.gv_importado_pedido_fechas(text, text, date, date, boolean, boolean);
--   drop function if exists public.gv_importado_pedido_ref(text, text, text);
--   drop function if exists public.gv_importado_bache_embarque(bigint, date);
--   drop function if exists public.gv_importado_bache_add(bigint, numeric, date, text, text, date);
--   -- (recrear gv_importado_bache_add y gv_importado_baches con las firmas de v14.94:
--   --  sql/gv_importados_baches_v1494.sql)
--   alter table public."GV_Importados_Baches" drop column if exists pedido_ref, drop column if exists fecha_embarque;
