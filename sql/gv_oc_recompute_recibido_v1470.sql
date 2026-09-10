-- v14.70 (2026-09-10) — Auto-descuento de OC "desde la primera OC" + "la última anula la anterior".
--
-- PEDIDO DEL DUEÑO: "Arreglá el auto-descuento para que aplique desde la primera OC" +
-- "Siempre la última OC anula la anterior".
--
-- ESTADO PREVIO (v14.59/v14.60):
--   - gv_oc_aplicar_recepcion sumaba en cascada SOLO a la OC de fecha más nueva del
--     proveedor+código, y recién desde el 2026-09-09. Las OCs viejas nunca recibían su
--     cantidad_recibida (medido: 5 de 620 OCs con cantidad_recibida > 0) → el "% de lleno"
--     por OC salía 0 para casi todas.
--   - "La nueva pisa la vieja" vivía SOLO en la vista oc_vigentes_por_proveedor (por max_fecha);
--     el estado guardado de las viejas seguía 'pendiente'.
--
-- SOLUCIÓN: recálculo idempotente que atribuye lo entregado a CADA OC por su ventana temporal
-- y materializa el estado.
--   1) La recepción alimenta la OC — de las DOS fuentes: "Entregas Tallerista Virgilio" y
--      "Entregas Prov AT" (talleristas Y prov. artículo terminado).
--   2) Ventana de atribución por OC: [fecha_OC, tope) con
--      tope = min(fecha de la OC SIGUIENTE del mismo proveedor+código, fecha_OC + 120 días).
--      Igual criterio que el visualizador de OCs del front (ocBuildRecep, v7.52/v7.58).
--      Las entregas ANTERIORES a la OC no cuentan. cantidad_recibida se topea al `cantidad`
--      pedido (el excedente NO entra a la OC; se avisa aparte a Tomás, igual que v14.59).
--   3) "La última anula la anterior": por proveedor+código, la OC de fecha más nueva (no
--      cerrada/anulada) queda viva; las anteriores en 'pendiente' pasan a 'anulada' con su
--      parcial recibido CONGELADO (para el histórico del % de lleno). Las 'cerrada' no se tocan.
--
-- Match del proveedor idéntico a recepcion.js / oc_vigentes_por_proveedor: norm_nombre + alias
-- (Pettofrezza→Rafael) + split por "/","," ,"+","&"," y "; norm_cod para el código. Se hace con
-- helpers gv_norm_prov_key / gv_norm_prov_keys / gv_prov_match (abajo).
--
-- IDEMPOTENTE: recalcula cantidad_recibida ABSOLUTO desde las tablas de entregas (fuente de
-- verdad). Correrla dos veces no cambia nada la 2da vez. Reemplaza el descuento incremental:
--   - gv_oc_aplicar_recepcion(nombre_ent, items) ahora RECALCULA el/los proveedor+código
--     recibido (ignora `items.cajas`; las entregas ya están insertadas cuando el front la llama).
--   - gv_oc_generar_pendientes dispara un recálculo global al generar OCs nuevas, para que
--     "la última anula la anterior" quede materializado también al generar, no sólo al recibir.
--
-- SECURITY DEFINER (la recepción corre como anon/authenticated, sin UPDATE directo sobre
-- Ordenes_Compra). Grants: recompute/aplicar a anon+authenticated; generar a authenticated.
--
-- BACKUP previo: public."GV_Backup_Ordenes_Compra_20260910" (620 filas, RLS ON, sólo service_role).
-- ROLLBACK: docs/ROLLBACK-PRODUCCION.md (§ v14.70).

-- ── Helpers de normalización/match de proveedor ─────────────────────────────
-- clave whole-name normalizada + alias (para partición/ventana/newest)
create or replace function public.gv_norm_prov_key(txt text)
returns text language sql immutable
set search_path = public as $$
  select case when norm_nombre(coalesce(txt,'')) like '%pettofrezza%'
              then 'rafael' else norm_nombre(coalesce(txt,'')) end;
$$;

-- array de claves por partes (para atribuir entregas a OCs compartidas "X / Y")
create or replace function public.gv_norm_prov_keys(txt text)
returns text[] language sql immutable
set search_path = public as $$
  select coalesce(array_agg(distinct k) filter (where k <> ''), '{}'::text[])
  from (
    select case when norm_nombre(p) like '%pettofrezza%' then 'rafael'
                else norm_nombre(p) end as k
    from unnest(string_to_array(
      regexp_replace(
        regexp_replace(trim(coalesce(txt,'')), '\s+y\s+', '/', 'gi'),
        '[,+&]', '/', 'g'),
      '/')) p
  ) s;
$$;

-- match con tolerancia ±2 starts_with (igual que _ocProvKeysMatch de recepcion.js)
create or replace function public.gv_prov_match(a text[], b text[])
returns boolean language sql immutable
set search_path = public as $$
  select exists (
    select 1 from unnest(a) x cross join unnest(b) y
    where x <> '' and y <> '' and (
      x = y
      or (length(x) >= length(y) and length(x)-length(y) <= 2 and starts_with(x,y))
      or (length(y) >= length(x) and length(y)-length(x) <= 2 and starts_with(y,x))
    )
  );
$$;

grant execute on function public.gv_norm_prov_key(text)        to anon, authenticated;
grant execute on function public.gv_norm_prov_keys(text)       to anon, authenticated;
grant execute on function public.gv_prov_match(text[],text[])  to anon, authenticated;

-- ── Recálculo del recibido por OC (idempotente) ─────────────────────────────
-- p_nombre / p_cod NULL = todas las OCs; con valor = sólo ese proveedor+código.
create or replace function public.gv_oc_recompute_recibido(p_nombre text default null, p_cod text default null)
returns integer
language plpgsql
security definer
set search_path = public
as $function$
declare
  n_updated int := 0;
  k_filtro text[];
  cod_filtro text;
begin
  k_filtro   := case when p_nombre is not null then gv_norm_prov_keys(p_nombre) end;
  cod_filtro := case when p_cod is not null then norm_cod(p_cod) end;

  with entregas as (
    select norm_cod("Cod") as cod, gv_norm_prov_keys("Nombre_Tall") as pk,
           coalesce("Fecha_RTO",
             case when "Fecha" ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then "Fecha"::date end) as f,
           coalesce("Cajas",0) as caj
    from "Entregas Tallerista Virgilio"
    union all
    select norm_cod("Cod_Art"), gv_norm_prov_keys("Proveedor"),
           coalesce("Fecha_RTO",
             case
               when "Dia_mes" ~ '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{2}$'  then to_date("Dia_mes",'DD/MM/YY')
               when "Dia_mes" ~ '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$'  then to_date("Dia_mes",'DD/MM/YYYY')
               when "Dia_mes" ~ '^[0-9]{1,2}-[0-9]{1,2}$'          then to_date("Dia_mes"||'-'||extract(year from current_date)::text,'DD-MM-YYYY')
             end),
           coalesce("Cantidad",0)
    from "Entregas Prov AT"
  ),
  oc as (
    select o.id, o.cantidad, o.estado, o.fecha,
           norm_cod(o.codigo) as cod_n,
           gv_norm_prov_key(o.proveedor) as pkey,
           gv_norm_prov_keys(o.proveedor) as pkeys
    from "Ordenes_Compra" o
    where nullif(trim(o.codigo),'') is not null and o.fecha is not null
  ),
  oc_win as (
    select oc.*,
           least(
             coalesce(lead(oc.fecha) over (partition by oc.cod_n, oc.pkey order by oc.fecha, oc.id),
                      date '9999-12-31'),
             oc.fecha + 120
           ) as tope,
           (row_number() over (
              partition by oc.cod_n, oc.pkey
              order by (lower(coalesce(oc.estado,'')) in ('cerrada','anulada')), oc.fecha desc, oc.id desc
            ) = 1
            and lower(coalesce(oc.estado,'')) not in ('cerrada','anulada')) as es_ultima
    from oc
  ),
  recibido as (
    select w.id,
           least(w.cantidad, coalesce((
             select sum(e.caj)::int
             from entregas e
             where e.cod = w.cod_n and e.f is not null
               and e.f >= w.fecha and e.f < w.tope
               and gv_prov_match(w.pkeys, e.pk)
           ),0)) as rec_cap,
           w.cantidad, w.estado, w.es_ultima
    from oc_win w
    where (cod_filtro is null or w.cod_n = cod_filtro)
      and (k_filtro is null or gv_prov_match(w.pkeys, k_filtro))
  ),
  upd as (
    update "Ordenes_Compra" o
      set cantidad_recibida = r.rec_cap,
          estado = case
                     when lower(coalesce(o.estado,'')) = 'cerrada' then o.estado
                     when r.es_ultima and r.rec_cap >= r.cantidad then 'recibida'
                     when not r.es_ultima then 'anulada'
                     else 'pendiente'
                   end,
          fecha_entrega_real = case when r.rec_cap > 0 then coalesce(o.fecha_entrega_real, current_date)
                                    else o.fecha_entrega_real end
      from recibido r
      where o.id = r.id
        and (o.cantidad_recibida is distinct from r.rec_cap
             or o.estado is distinct from (case
                     when lower(coalesce(o.estado,'')) = 'cerrada' then o.estado
                     when r.es_ultima and r.rec_cap >= r.cantidad then 'recibida'
                     when not r.es_ultima then 'anulada'
                     else 'pendiente' end))
      returning 1
  )
  select count(*) into n_updated from upd;
  return n_updated;
end;
$function$;

grant execute on function public.gv_oc_recompute_recibido(text,text) to anon, authenticated;

-- ── Recepción en vivo: ahora RECALCULA (idempotente) en vez de sumar incremental ────
create or replace function public.gv_oc_aplicar_recepcion(nombre_ent text, items jsonb)
returns integer
language plpgsql
security definer
set search_path = public
as $function$
declare
  it jsonb;
  v_cod text;
  n int := 0;
begin
  if nombre_ent is null or btrim(nombre_ent) = '' then return 0; end if;
  for it in select value from jsonb_array_elements(coalesce(items,'[]'::jsonb)) loop
    v_cod := norm_cod(it->>'cod');
    if v_cod = '' then continue; end if;
    n := n + public.gv_oc_recompute_recibido(nombre_ent, v_cod);
  end loop;
  return n;
end;
$function$;

revoke all on function public.gv_oc_aplicar_recepcion(text, jsonb) from public;
grant execute on function public.gv_oc_aplicar_recepcion(text, jsonb) to anon, authenticated;

-- Backfill de una vez (desde la primera OC, todos los proveedores):
--   select public.gv_oc_recompute_recibido();
