-- v26.37 (Luis, 02/10/2026): "quiero que guarde el FOB del pedido en curso, justamente".
-- Se aplicó a la base con el rótulo v26.35 (los comentarios de la columna y de las funciones lo dicen):
-- es la etiqueta con que entró, no cambiarla.
-- Cada bache (línea de un pedido en curso) guarda el FOB unitario con que se pidió, y lo que viene
-- en camino se valoriza con ESE precio, no con el FOB de hoy del maestro.
--
--  1. GV_Importados_Baches.fob_uni (nullable, sin default que reescriba, sin backfill).
--  2. Trigger BEFORE INSERT: si el bache entra sin FOB, toma el de Importados.fob_uni en ese
--     momento (es el que usó Pedidos Importación para calcular el pedido). Cubre los tres caminos
--     que insertan baches (gv_importado_bache_add, gv_imp_recibir_sin_pedido y su contexto).
--  3. El u$s de 🚢 En curso (vista gv_importados_pedidos_curso), del detalle del PI
--     (gv_importado_pedido_lineas) y del 📜 Historial (gv_imp_pedidos_historial) pasa a
--     coalesce(FOB del bache, FOB del maestro): el bache sin FOB guardado (los 89 en curso al
--     02/10) sigue con el del maestro, así que HOY no cambia ningún número.
--  4. gv_importados_curso_fob(): por artículo del maestro, las unidades en camino y su u$s con el
--     FOB del pedido (lo lee el PDF de Pedidos Importación, columna «Llegan»). Sólo supervisor.
--
-- Medido antes: En curso u$s 200.228,23 · Historial u$s 291.018,03 (tienen que dar igual después).
-- Las definiciones vivas se trajeron con pg_get_viewdef / pg_get_functiondef el 02/10 y el cambio
-- es SÓLO la expresión del FOB.
--
-- ROLLBACK:
--   drop trigger if exists gv_importados_bache_fob on public."GV_Importados_Baches";
--   drop function if exists public.gv_importados_bache_fob_ini();
--   drop function if exists public.gv_importados_curso_fob();
--   (y volver a crear las tres de abajo con coalesce(im.fob_uni,0) / im.fob_uni / coalesce(i.fob_uni,0))
--   alter table public."GV_Importados_Baches" drop column if exists fob_uni;
--
-- Backfill (NO aplicado: congela el FOB de hoy en los 89 baches en curso; pide el «sí» de Luis):
--   update public."GV_Importados_Baches" b set fob_uni = i.fob_uni
--     from public."Importados" i
--    where i.id = b.importado_id and b.estado = 'en_curso' and b.fob_uni is null and coalesce(i.fob_uni,0) > 0;

begin;

alter table public."GV_Importados_Baches" add column if not exists fob_uni numeric;
comment on column public."GV_Importados_Baches".fob_uni is
  'v26.35 — FOB unitario (u$s) con que se pidió este bache. Lo pone el trigger gv_importados_bache_fob al insertar (FOB del maestro en ese momento). NULL = bache anterior: se valoriza con el FOB del maestro.';

create or replace function public.gv_importados_bache_fob_ini()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
begin
  -- v26.35 — el bache nace con el FOB del maestro de ESE momento (el del pedido)
  if new.fob_uni is null and new.importado_id is not null then
    select nullif(i.fob_uni, 0) into new.fob_uni from public."Importados" i where i.id = new.importado_id;
  end if;
  return new;
end $function$;

-- (se aplicó como "create or replace trigger": un DROP de primer nivel se cuelga en el MCP)
create or replace trigger gv_importados_bache_fob before insert on public."GV_Importados_Baches"
  for each row execute function public.gv_importados_bache_fob_ini();

create or replace view public.gv_importados_pedidos_curso with (security_invoker = true) as
 WITH b AS (
         SELECT b_1.id,
            b_1.importado_id,
            b_1.cod_art,
            b_1.proveedor,
            b_1.marca,
            b_1.unidades,
            b_1.unidades_llegadas,
            b_1.fecha_reingreso,
            b_1.estado,
            b_1.creado,
            b_1.creado_por,
            b_1.actualizado,
            b_1.pedido_ref,
            b_1.fecha_embarque,
            GREATEST(0, b_1.unidades - b_1.unidades_llegadas) AS pend,
            b_1.fob_uni
           FROM "GV_Importados_Baches" b_1
          WHERE b_1.estado = 'en_curso'::text
        )
 SELECT COALESCE(NULLIF(btrim(b.pedido_ref), ''::text), '(sin pedido)'::text) AS pedido_ref,
    COALESCE(NULLIF(btrim(b.proveedor), ''::text), '(sin proveedor)'::text) AS proveedor,
    count(*)::integer AS n_lineas,
    sum(b.unidades)::integer AS unidades,
    sum(b.pend)::integer AS pendiente,
    sum(b.unidades_llegadas)::integer AS llegadas,
    min(b.fecha_embarque) AS fecha_embarque,
    min(b.fecha_reingreso) AS fecha_llegada,
    max(b.fecha_reingreso) AS fecha_llegada_max,
    count(*) FILTER (WHERE b.fecha_reingreso IS NULL)::integer AS lineas_sin_fecha,
    round(sum(b.pend::numeric * COALESCE(b.fob_uni, im.fob_uni, 0::numeric)), 2) AS usd,
    round(sum(
        CASE
            WHEN COALESCE(v.uni_master, 0::numeric) > 0::numeric AND COALESCE(v.m3_master, 0::numeric) > 0::numeric THEN b.pend::numeric / v.uni_master * v.m3_master
            ELSE 0::numeric
        END), 3) AS m3,
    min(b.fecha_reingreso) - CURRENT_DATE AS dias_para_llegar,
    min(b.fecha_embarque) - CURRENT_DATE AS dias_para_embarcar,
    min(b.creado) AS creado
   FROM b
     LEFT JOIN "Importados" im ON im.id = b.importado_id
     LEFT JOIN "Importados_Volumen" v ON v.cod = b.cod_art
  GROUP BY (COALESCE(NULLIF(btrim(b.pedido_ref), ''::text), '(sin pedido)'::text)), (COALESCE(NULLIF(btrim(b.proveedor), ''::text), '(sin proveedor)'::text));
alter view public.gv_importados_pedidos_curso set (security_invoker = true);

CREATE OR REPLACE FUNCTION public.gv_importado_pedido_lineas(p_pedido_ref text, p_proveedor text DEFAULT NULL::text)
 RETURNS TABLE(bache_id bigint, importado_id bigint, cod_art text, marca text, descripcion text, unidades integer, pendiente integer, fecha_embarque date, fecha_reingreso date, fob_uni numeric, usd numeric, uni_master integer, m3 numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- v26.35 — el FOB es el del PEDIDO (guardado en el bache); sin guardar, el del maestro
  select b.id, b.importado_id, b.cod_art, b.marca, im.descripcion,
         b.unidades, greatest(0, b.unidades - b.unidades_llegadas)::int,
         b.fecha_embarque, b.fecha_reingreso,
         coalesce(b.fob_uni, im.fob_uni),
         round((greatest(0, b.unidades - b.unidades_llegadas) * coalesce(b.fob_uni, im.fob_uni, 0))::numeric, 2),
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
$function$;

CREATE OR REPLACE FUNCTION public.gv_imp_pedidos_historial(p_dias integer DEFAULT 365)
 RETURNS TABLE(pedido_ref text, proveedor text, creado timestamp with time zone, creado_por text, embarque date, reingreso date, estado text, items integer, unidades numeric, llegadas numeric, anulados integer, codigos text, usd numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- v23.91 (Luis) — el HISTORIAL de pedidos: un renglón por (pedido, proveedor), con lo que se
-- pidió, lo que llegó y en qué estado está. La solapa 📜 Historial lo muestra al lado de las
-- recepciones ("mostrar recepción y pedidos").
-- ⚠ El pedido sin PI se agrupa por su DÍA de carga: el `coalesce` no puede llevar un agregado
--   adentro del GROUP BY, así que la clave se arma en un subselect y se etiqueta afuera.
-- v26.35 — el u$s es con el FOB del PEDIDO (guardado en el bache); sin guardar, el del maestro.
  select coalesce(z.ref, '(sin PI · ' || to_char(z.creado at time zone 'America/Argentina/Buenos_Aires','dd/mm/yy') || ')') as pedido_ref,
         z.proveedor, z.creado, z.creado_por, z.embarque, z.reingreso, z.estado,
         z.items, z.unidades, z.llegadas, z.anulados, z.codigos, z.usd
    from (
      select nullif(btrim(b.pedido_ref),'') as ref,
             coalesce(nullif(btrim(b.proveedor),''),'(sin proveedor)') as proveedor,
             (case when nullif(btrim(b.pedido_ref),'') is null
                   then (b.creado at time zone 'America/Argentina/Buenos_Aires')::date::text else '' end) as dia,
             min(b.creado) as creado,
             (array_agg(b.creado_por order by b.creado) filter (where nullif(btrim(b.creado_por),'') is not null))[1] as creado_por,
             min(b.fecha_embarque) as embarque,
             min(b.fecha_reingreso) filter (where b.estado <> 'anulado') as reingreso,
             case when count(*) filter (where b.estado = 'en_curso') > 0 then 'en curso'
                  when count(*) filter (where b.estado = 'llegado')  > 0 then 'llegado'
                  else 'anulado' end as estado,
             count(*) filter (where b.estado <> 'anulado')::int as items,
             coalesce(sum(b.unidades) filter (where b.estado <> 'anulado'), 0) as unidades,
             coalesce(sum(b.unidades_llegadas) filter (where b.estado <> 'anulado'), 0) as llegadas,
             count(*) filter (where b.estado = 'anulado')::int as anulados,
             string_agg(distinct upper(btrim(b.cod_art)), ' · ') as codigos,
             coalesce(sum(b.unidades * coalesce(b.fob_uni, i.fob_uni, 0)) filter (where b.estado <> 'anulado'), 0) as usd
        from public."GV_Importados_Baches" b
        left join public."Importados" i on i.id = b.importado_id
       where b.creado >= now() - make_interval(days => greatest(coalesce(p_dias,365), 1))
       group by 1, 2, 3
    ) z
   order by z.creado desc;
$function$;

create or replace function public.gv_importados_curso_fob()
 returns table(importado_id bigint, pendiente integer, usd numeric, uni_con_fob integer)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  -- v26.35 — por artículo del maestro: lo que viene en camino y su u$s con el FOB del PEDIDO
  -- (el del bache; sin guardar, el del maestro). Sólo supervisor: sin permiso no devuelve filas.
  select b.importado_id,
         sum(greatest(0, b.unidades - b.unidades_llegadas))::int,
         round(sum(greatest(0, b.unidades - b.unidades_llegadas) * coalesce(b.fob_uni, im.fob_uni, 0))::numeric, 2),
         sum(greatest(0, b.unidades - b.unidades_llegadas)) filter (where b.fob_uni is not null)::int
    from public."GV_Importados_Baches" b
    left join public."Importados" im on im.id = b.importado_id
   where b.estado = 'en_curso' and greatest(0, b.unidades - b.unidades_llegadas) > 0
     and (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio())
   group by b.importado_id;
$function$;
revoke execute on function public.gv_importados_curso_fob() from public, anon;
grant execute on function public.gv_importados_curso_fob() to authenticated, service_role;

commit;
