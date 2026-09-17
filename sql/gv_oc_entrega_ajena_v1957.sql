-- ============================================================================
-- v19.57 — Aviso propio: "un proveedor está entregando algo que NO está en SU OC"
--
-- Pedido de Thomas (2026-09-17): *"si pasa que un proveedor entrega mercadería que
-- no le corresponde, tiene que avisarme de otra manera... el aviso tiene que llegarme
-- de 'está entregando un proveedor algo que no está en su orden de compra', por fuera
-- de que él tiene la orden de compra"*.
--
-- O SEA: es un aviso SEPARADO del de exceso (v17.99/v17.27). El de exceso dice
-- "entró más de lo que la OC habilita"; éste dice "esto no es de él". Pueden pasar
-- juntos o por separado: un proveedor puede tener OC de 10 códigos y entregar un
-- 11º que es de otro.
--
-- ⚠ POR QUÉ NO SE SUMAN TODAS LAS OC ABIERTAS DEL CÓDIGO (y sí se mira la última)
-- Medido el 17/09: hay 85 OC en estado 'pendiente' que NO son la última de su
-- (código, proveedor), por 4.214 cajas. NO son cajas "invisibles" que haya que
-- sumar: son OC que `gv_oc_recompute_recibido` debía dejar en 'anulada' y no pudo,
-- porque esa función sólo corre cuando se recibe DE ESE proveedor y esos proveedores
-- nunca entregaron. El generador recalcula `Máximo + Pedidos − Stock` cada miércoles,
-- así que la OC nueva YA contempla lo que no llegó de la anterior: sumarlas sería
-- pedir dos veces lo mismo. Caso testigo 550 / Poly: OC 720 del 09/09 por 220 cj y
-- OC 914 del 16/09 por 155, las dos con stock 0 en el cálculo.
-- El arreglo de esas 85 es correr `gv_oc_recompute_recibido()` sin filtros, que
-- ESCRIBE en Ordenes_Compra → va aparte, con permiso explícito del dueño.
--
-- Matcher: se usa el canónico (`gv_norm_prov_keys` + `gv_prov_match`), el mismo que
-- `gv_oc_recompute_recibido`, en vez de repetir el alias inline que tiene
-- `oc_vigentes_por_proveedor` — si divergen, el aviso miente.
-- ============================================================================

-- ── 1. La RPC que contesta "¿esto es de él?" ────────────────────────────────
-- Devuelve UNA fila por cada código entregado que NO está en ninguna OC abierta
-- de ese proveedor. `otros` dice de quién SÍ es (null = de nadie: nunca se pidió).
create or replace function public.gv_oc_entrega_ajena(p_nombre text, p_cods text[])
returns table(cod text, otros text, pend_otros bigint, fecha_otra date, prov_config text)
language sql
stable
security definer
set search_path to 'public'
as $function$
  with k as (select gv_norm_prov_keys(p_nombre) as keys),
  cods as (
    select distinct norm_cod(c) as cod
      from unnest(coalesce(p_cods, '{}'::text[])) c
     where norm_cod(c) <> ''
  ),
  oc as (
    select norm_cod(o.codigo) as cod_n, o.proveedor, o.fecha,
           (o.cantidad - coalesce(o.cantidad_recibida, 0)) as pend,
           gv_norm_prov_keys(o.proveedor) as pkeys
      from "Ordenes_Compra" o
     where o.fecha >= (current_date - 120)
       and lower(coalesce(o.estado, '')) not in ('cerrada', 'anulada')
       and nullif(trim(o.codigo), '') is not null
  ),
  -- la OC vigente por (código, proveedor) es la de fecha máxima; las anteriores
  -- están tácitamente anuladas (ver el comentario de arriba).
  oc_vig as (
    select distinct on (cod_n, gv_norm_prov_key(proveedor)) cod_n, proveedor, fecha, pend, pkeys
      from oc
     order by cod_n, gv_norm_prov_key(proveedor), fecha desc
  ),
  cfg as (
    select norm_cod(m.cod) as cod_n,
           nullif(concat_ws(' / ', nullif(btrim(coalesce(m.proveedor, '')), ''),
                                  nullif(btrim(coalesce(m.proveedor2, '')), '')), '') as prov_config
      from "OC_Maximos" m
     where nullif(btrim(m.cod), '') is not null
  )
  select c.cod,
         (select string_agg(distinct v.proveedor, ' / ' order by v.proveedor)
            from oc_vig v where v.cod_n = c.cod and v.pend > 0)              as otros,
         (select coalesce(sum(v.pend), 0)::bigint
            from oc_vig v where v.cod_n = c.cod and v.pend > 0)              as pend_otros,
         (select max(v.fecha) from oc_vig v where v.cod_n = c.cod and v.pend > 0) as fecha_otra,
         (select max(g.prov_config) from cfg g where g.cod_n = c.cod)        as prov_config
    from cods c, k
   where not exists (
     select 1 from oc_vig v
      where v.cod_n = c.cod and v.pend > 0 and gv_prov_match(v.pkeys, k.keys)
   );
$function$;

comment on function public.gv_oc_entrega_ajena(text, text[]) is
  'v19.57 — códigos que ese proveedor entrega SIN tenerlos en su OC vigente. `otros` = de quién es la OC (null = de nadie). Pedido de Thomas 17/09.';

grant execute on function public.gv_oc_entrega_ajena(text, text[]) to anon, authenticated;

-- ── 2. Excepciones: pares que NO hay que avisar ─────────────────────────────
-- Nace VACÍA a propósito. El caso conocido es Oscar: sus 14 códigos salen en la OC a su
-- nombre y los entrega Log/ Fabr porque él sólo hacía el skin (regla del dueño, 15/09:
-- *"dejalo ahí"*). Ese par dispararía el aviso todas las semanas. Para silenciarlo:
--   insert into public."GV_OC_Entrega_Permitida"
--     (proveedor_entrega, proveedor_oc, cod, motivo, quien_pidio)
--   values ('Log/ Fabr','Oscar',null,'Oscar hacía sólo el skin; entrega Log/ Fabr','Thomas');
-- Se deja como decisión del dueño, no como default: silenciar de entrada tapa justo lo que
-- el 15/09 quedó anotado como "el arreglo es que al recibir esos artículos elijan Oscar".
create table if not exists public."GV_OC_Entrega_Permitida" (
  id bigserial primary key,
  proveedor_entrega text not null,
  proveedor_oc text not null,
  cod text,                      -- null = cualquier código de ese par
  motivo text,
  quien_pidio text,
  activo boolean not null default true,
  creado_en timestamptz not null default now()
);
alter table public."GV_OC_Entrega_Permitida" enable row level security;
drop policy if exists gv_oc_ent_perm_sel on public."GV_OC_Entrega_Permitida";
create policy gv_oc_ent_perm_sel on public."GV_OC_Entrega_Permitida"
  for select to anon, authenticated using (true);
revoke insert, update, delete, truncate on public."GV_OC_Entrega_Permitida" from anon, authenticated;
comment on table public."GV_OC_Entrega_Permitida" is
  'v19.57 - pares (entrega, OC) que NO disparan el aviso de entrega ajena. cod null = todo el par.';

-- ── 3. El aviso por Telegram, que NO depende del operario ───────────────────
-- Se engancha en `gv_oc_aplicar_recepcion`, que ya corre al confirmar la recepción:
-- así el aviso sale solo, aunque nadie toque el botón de WhatsApp.
create or replace function public.gv_oc_aplicar_recepcion(nombre_ent text, items jsonb)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  it jsonb;
  v_cod text;
  n int := 0;
  v_cods text[] := '{}'::text[];
  v_caj jsonb := '{}'::jsonb;
  v_lineas text := '';
  v_hay int := 0;
  r record;
begin
  if nombre_ent is null or btrim(nombre_ent) = '' then return 0; end if;

  for it in select value from jsonb_array_elements(coalesce(items, '[]'::jsonb)) loop
    v_cod := norm_cod(it->>'cod');
    if v_cod = '' then continue; end if;
    n := n + public.gv_oc_recompute_recibido(nombre_ent, v_cod);
    v_cods := v_cods || v_cod;
    -- se guardan las cajas para poder decirlas en el aviso
    v_caj := v_caj || jsonb_build_object(v_cod, coalesce((it->>'cajas')::numeric, 0));
  end loop;

  -- v19.57 — aviso propio de ENTREGA AJENA. Va en su propio bloque con su propio
  -- catch: si algo falla acá, la recepción ya quedó aplicada y no se cae.
  begin
    for r in select a.cod, a.otros, a.pend_otros, a.prov_config
               from public.gv_oc_entrega_ajena(nombre_ent, v_cods) a
              where a.otros is not null      -- sólo lo que SÍ es de otro; "de nadie" ya lo cubre el aviso de exceso
                and not exists (
                  select 1 from public."GV_OC_Entrega_Permitida" p
                   where p.activo
                     and gv_prov_match(gv_norm_prov_keys(p.proveedor_entrega), gv_norm_prov_keys(nombre_ent))
                     and gv_prov_match(gv_norm_prov_keys(p.proveedor_oc), gv_norm_prov_keys(a.otros))
                     and (p.cod is null or norm_cod(p.cod) = a.cod))
              order by a.pend_otros desc
    loop
      v_hay := v_hay + 1;
      v_lineas := v_lineas || E'\n- ' || r.cod ||
        ' (' || coalesce((v_caj->>r.cod), '?') || ' cj) -> la OC es de ' || r.otros ||
        ', ' || r.pend_otros || ' pendientes' ||
        case when r.prov_config is not null
              and not gv_prov_match(gv_norm_prov_keys(r.prov_config), gv_norm_prov_keys(nombre_ent))
             then ' - configurado a ' || r.prov_config else '' end;
    end loop;

    if v_hay > 0 then
      perform public.tg_enqueue(
        '⚠ ENTREGA FUERA DE SU ORDEN DE COMPRA' || E'\n' ||
        'Entrego: ' || btrim(nombre_ent) || '   ' ||
        to_char(now() at time zone 'America/Argentina/Buenos_Aires', 'DD/MM HH24:MI') || E'\n' ||
        'Estos codigos NO estan en la OC de ' || btrim(nombre_ent) || ':' || v_lineas || E'\n\n' ||
        'O la OC salio al proveedor equivocado, o entrego mercaderia que no le corresponde.',
        'ocajena_' || gv_norm_prov_key(nombre_ent) || '_' ||
        to_char(now() at time zone 'America/Argentina/Buenos_Aires', 'YYYYMMDDHH24MI') || '_' ||
        md5(array_to_string(v_cods, ','))
      );
      perform public.tg_outbox_flush();
    end if;
  exception when others then null;
  end;

  return n;
end;
$function$;

comment on function public.gv_oc_aplicar_recepcion(text, jsonb) is
  'v19.57 — aplica la recepción a las OC y, si el proveedor entregó códigos que no están en SU OC, avisa por Telegram (aviso separado del de exceso).';

-- ── 4. Centinela: el histórico de entregas ajenas ───────────────────────────
-- Para mirar de una que no volvió a pasar, y para medir el pasado.
create or replace view public.gv_oc_entregas_ajenas as
with ent as (
  select case when e."Fecha" ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then e."Fecha"::date end as f,
         btrim(e."Nombre_Tall") as proveedor,
         gv_norm_prov_keys(e."Nombre_Tall") as pkeys,
         norm_cod(e."Cod") as cod,
         coalesce(e."Cajas", 0) as cajas,
         e."Remito" as remito
    from "Entregas Tallerista Virgilio" e
   where nullif(btrim(e."Cod"), '') is not null and coalesce(e."Cajas", 0) > 0
),
oc as (
  select norm_cod(o.codigo) as cod, btrim(o.proveedor) as proveedor,
         gv_norm_prov_keys(o.proveedor) as pkeys
    from "Ordenes_Compra" o
   where nullif(btrim(o.codigo), '') is not null
   group by 1, 2, 3
)
select e.f as fecha, e.proveedor, e.cod, e.cajas, e.remito,
       (select string_agg(distinct o.proveedor, ' / ' order by o.proveedor)
          from oc o where o.cod = e.cod) as oc_a_nombre_de,
       case when exists (select 1 from oc o where o.cod = e.cod)
            then 'oc_de_otro' else 'sin_oc_de_nadie' end as caso
  from ent e
 where e.f is not null
   and not exists (select 1 from oc o where o.cod = e.cod and gv_prov_match(o.pkeys, e.pkeys));

alter view public.gv_oc_entregas_ajenas set (security_invoker = true);
grant select on public.gv_oc_entregas_ajenas to anon, authenticated;

comment on view public.gv_oc_entregas_ajenas is
  'v19.57 — entregas cuyo código no figura en NINGUNA OC de ese proveedor. caso=oc_de_otro (la pidió otro) / sin_oc_de_nadie (nunca se pidió). Ventana real: desde 2026-07-13, que es donde arranca Ordenes_Compra.';

-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================
-- 1) el caso testigo: Garcia entregando 550, que la OC tiene a nombre de Poly
-- select * from public.gv_oc_entrega_ajena('Garcia', array['550','760']);
--   -> 550 | Poly | 155 | 2026-09-16 | Poly
--
-- 2) y que un proveedor con su OC en orden NO dispara nada
-- select * from public.gv_oc_entrega_ajena('Poly', array['550']);   -- 0 filas
--
-- 3) el histórico
-- select caso, count(*) entregas, sum(cajas) cajas, count(distinct cod) codigos
--   from public.gv_oc_entregas_ajenas group by 1;
--
-- 4) las 85 OC fantasma (NO se tocan acá; requiere permiso del dueño)
-- select count(*), sum(cantidad - coalesce(cantidad_recibida,0)) from (
--   select o.*, row_number() over (partition by norm_cod(o.codigo), gv_norm_prov_key(o.proveedor)
--            order by (lower(coalesce(o.estado,'')) in ('cerrada','anulada')), o.fecha desc, o.id desc) rn
--     from public."Ordenes_Compra" o where o.fecha is not null) z
--  where rn > 1 and lower(coalesce(estado,'')) not in ('cerrada','anulada');
--
-- ============================================================================
-- ROLLBACK
-- ============================================================================
-- drop view if exists public.gv_oc_entregas_ajenas;
-- drop function if exists public.gv_oc_entrega_ajena(text, text[]);
-- y volver gv_oc_aplicar_recepcion a su cuerpo previo (el del loop pelado):
--   create or replace function public.gv_oc_aplicar_recepcion(nombre_ent text, items jsonb)
--   returns integer language plpgsql security definer set search_path to 'public' as $$
--   declare it jsonb; v_cod text; n int := 0;
--   begin
--     if nombre_ent is null or btrim(nombre_ent) = '' then return 0; end if;
--     for it in select value from jsonb_array_elements(coalesce(items,'[]'::jsonb)) loop
--       v_cod := norm_cod(it->>'cod');
--       if v_cod = '' then continue; end if;
--       n := n + public.gv_oc_recompute_recibido(nombre_ent, v_cod);
--     end loop;
--     return n;
--   end; $$;
