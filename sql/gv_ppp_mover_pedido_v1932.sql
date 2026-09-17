-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- v19.32 — «CAMBIAR DE DÍA» POR PEDIDO, Y ELEGIR LA TANDA DESTINO
-- Pedido de Luis (2026-09-17):
--   *"Quiero que cada nota de pedido tenga el botón cambiar de día. Cuando se cambia de día una
--   nota de pedido, si hay más notas de pedido que se corresponden a un mismo pedido de ese
--   cliente, que se muevan todas en conjunto… y que cuando se mueven a un día, se dé la opción de
--   crear una tanda nueva para esos pedidos o agregarlos a una tanda que ya existe ese día. Esa
--   misma funcionalidad la quiero para cuando se mueve una tanda entera… si muevo la tanda D71B
--   al martes 29, que me diga si la quiero agregar a la E18A, a la E30A, o si quiero crear un
--   nuevo código de tanda. Si le doy que la quiero agregar a la E18A… deja de existir la tanda
--   original y los pedidos pasan a integrarse dentro de la tanda que elegí."*
--
-- Las dos reglas que puso Luis cuando se le preguntó (2026-09-17):
--   1. **El estado tiene que coincidir**: *"un pedido armado sólo a una tanda que esté armada, un
--      pedido facturado sólo a una tanda que esté facturada, uno en espera a una tanda en espera.
--      El problema es si está en ese momento siendo pickeado/armado, en cuyo caso no se puede
--      mover a una tanda existente y debería decir que sólo se puede mover creándole una tanda
--      nueva."*
--   2. **Súper con clientes, o zonas de camiones distintos**: *"debería poner una advertencia bien
--      clara y bien grande que diga que está mal… de momento advertir sin bloquear."*
--
-- QUÉ ES UN PEDIDO. Web: todas las NP del mismo `order_id` (un pedido de la página se parte en
-- bloques de 18/15 renglones, y cada bloque es una NP). ISIS: la NP es el pedido. Es la misma
-- definición que ya usa «↩ Enviar a programar» (`gv_ppp_web_desprogramar_previo`), que es a lo
-- que Luis lo comparó.
--
-- ⚠ POR QUÉ EL ESTADO NECESITA UNA TABLA. El árbol resuelve «armado» por TANDA (el evento TAP es
-- de la tanda, no de la NP). Si una NP armada se separa a una tanda NUEVA, esa tanda no tiene TAP
-- y la NP figuraría «pendiente» — justo lo contrario de lo que pidió Luis (*"la tanda nueva pasa a
-- figurar como armada"*). Por eso `GV_PPP_NP_Estado`: un PISO de estado por NP, que se graba al
-- separarla y que el árbol respeta. NO se copian eventos de operario a la tanda nueva: eso
-- contaría la misma producción dos veces en Rendimiento.
--
-- ⚠ LO QUE NO SE TOCA: `Movimientos_Stock`. El picking entra al depósito `a_facturar` con
-- `ref` = tanda y SALE con `ref` = `<np>|CP` (medido: 2.221 filas de tipo `facturado` en 15 días,
-- todas con ese formato), así que `ref` no es una cuenta por tanda que haya que cuadrar: es
-- trazabilidad del evento. Mover una NP no mueve una caja de lugar. Al RENOMBRAR una tanda entera
-- sí se renombra `ref`, porque ese código deja de existir.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

-- ⚠ ESTE ARCHIVO ES LO QUE ESTÁ APLICADO. Verificación (md5 del cuerpo sin comentarios ni
-- espacios, el chequeo que usa el repo):
--   select p.proname, md5(regexp_replace(regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','gs'),
--            '--[^\n]*','','g'),'\s','','g'))
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname='public' and p.proname like 'gv_ppp_%mover%';

-- ── 1) El piso de estado por NP ────────────────────────────────────────────────────────────
create table if not exists public."GV_PPP_NP_Estado" (
  np            text primary key,
  estado        text not null check (estado in ('facturado', 'armado', 'proceso')),
  tanda_origen  text,
  motivo        text,
  por           text,
  creado_en     timestamptz not null default now()
);
alter table public."GV_PPP_NP_Estado" enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public'
                  and tablename='GV_PPP_NP_Estado' and policyname='gv_ppp_np_estado_sel') then
    create policy gv_ppp_np_estado_sel on public."GV_PPP_NP_Estado" for select using (true);
  end if;
end $$;
-- La lee el árbol, que corre como el usuario (no es SECURITY DEFINER). Escriben sólo las RPC.
grant select on public."GV_PPP_NP_Estado" to anon, authenticated, lk_ppp_reader, ch_ppp_reader;
revoke insert, update, delete on public."GV_PPP_NP_Estado" from anon, authenticated;

-- ── 2) El estado de una NP, con la MISMA regla que el árbol ────────────────────────────────
-- ⚠ Esta función y el CTE `est` de `gv_ppp_prog_arbol` dicen lo mismo a propósito: si cambia una,
-- cambia la otra. El árbol no sirve acá porque pide un rango de fechas y esto pregunta por NP.
-- Verificado el 17/09: 153 de 153 NP del árbol con el mismo estado que esta función.
create or replace function public.gv_ppp_np_estado(p_nps text[])
 returns table(np text, tanda text, estado text, orden integer)
 language sql stable set search_path to 'public', 'pg_temp'
as $function$
with nps as (
  select distinct regexp_replace(upper(btrim(x)), '\.0+$', '') as np
    from unnest(coalesce(p_nps, array[]::text[])) x
   where btrim(coalesce(x, '')) <> ''
),
tan as (
  select n.np,
         coalesce(
           (select upper(btrim(w.tanda)) from public."PPP_Web_Programacion" w
             where upper(btrim(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx))) = n.np
               and coalesce(nullif(btrim(w.tanda), ''), '') <> '' limit 1),
           (select upper(btrim(d.tanda)) from public.gv_ppp_programacion_diaria d
             where regexp_replace(upper(btrim(d.np)), '\.0+$', '') = n.np
               and coalesce(nullif(btrim(d.tanda), ''), '') <> '' limit 1),
           (select upper(btrim(f.tanda)) from public."Facturacion_NP" f
             where regexp_replace(upper(btrim(f.np)), '\.0+$', '') = n.np
               and coalesce(nullif(btrim(f.tanda), ''), '') <> '' limit 1)
         ) as tanda
    from nps n
),
ev as (
  select upper(btrim(r.texto)) as tanda, r.opcion, r.ts_cliente
    from public."Registros_Produccion_Virgilio" r
   where r.opcion in ('EP','TP','AP','TAP')
     and coalesce(btrim(r.legajo), '') not in ('0','1')
     and btrim(coalesce(r.texto, '')) <> ''
),
pick as (select distinct on (tanda) tanda, opcion from ev where opcion in ('EP','TP') order by tanda, ts_cliente desc),
arm  as (select distinct on (tanda) tanda, opcion from ev where opcion in ('AP','TAP') order by tanda, ts_cliente desc),
salio as (
  select distinct regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', '') as np
    from public."Registros_Produccion_Virgilio" r
   where r.opcion in ('CCN','CRN') and coalesce(btrim(r.legajo), '') not in ('0','1')
     and btrim(coalesce(r.texto, '')) <> ''
),
fact as (select distinct regexp_replace(upper(btrim(f.np)), '\.0+$', '') as np from public."Facturacion_NP" f),
calc as (
  select t.np, t.tanda,
         case when fc.np is not null then 4
              when s.np is not null or a.opcion = 'TAP' then 3
              when a.opcion = 'AP' or p.opcion in ('TP','EP') then 2
              else 1 end as orden
    from tan t
    left join fact  fc on fc.np = t.np
    left join salio s  on s.np  = t.np
    left join pick  p  on p.tanda = t.tanda and coalesce(t.tanda, '') <> ''
    left join arm   a  on a.tanda = t.tanda and coalesce(t.tanda, '') <> ''
)
select c.np, c.tanda,
       case o.orden when 4 then 'facturado' when 3 then 'armado' when 2 then 'proceso' else 'pendiente' end,
       o.orden
  from calc c
  left join public."GV_PPP_NP_Estado" he on he.np = c.np,
  lateral (select greatest(c.orden, case he.estado when 'facturado' then 4 when 'armado' then 3
                                                   when 'proceso' then 2 else 1 end) as orden) o;
$function$;

-- El estado de un GRUPO de NP (un pedido, una tanda): la misma regla que `_pgaEstadoGrupo` del
-- front — todas facturadas → facturado; todas armadas o mejor → armado; ninguna empezada →
-- pendiente; mezcla → proceso.
create or replace function public.gv_ppp_estado_grupo(p_nps text[])
 returns text language sql stable set search_path to 'public', 'pg_temp'
as $function$
  select case
           when count(*) = 0 then 'pendiente'
           when count(*) filter (where e.orden = 4) = count(*) then 'facturado'
           when count(*) filter (where e.orden >= 3) = count(*) then 'armado'
           when count(*) filter (where e.orden = 1) = count(*) then 'pendiente'
           else 'proceso' end
    from public.gv_ppp_np_estado(p_nps) e;
$function$;

-- ── 3) Las NP de un pedido ─────────────────────────────────────────────────────────────────
-- Web: todas las NP CON TANDA del mismo order_id. ISIS: la NP sola.
create or replace function public.gv_ppp_pedido_nps(p_np text)
 returns table(np text, empresa text, order_id bigint, np_idx integer, tanda text,
               fecha date, m3 numeric, cod text, razon_social text, zona text, es_isis boolean)
 language sql stable set search_path to 'public', 'pg_temp'
as $function$
with q as (select regexp_replace(upper(btrim(coalesce(p_np, ''))), '\.0+$', '') as np),
web as (
  select w.empresa, w.order_id
    from public."PPP_Web_Programacion" w, q
   where upper(btrim(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx))) = q.np
   limit 1
)
select upper(btrim(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx))), w.empresa, w.order_id,
       w.np_idx, upper(btrim(coalesce(w.tanda, ''))), w.fecha_entrega, coalesce(w.m3, 0),
       btrim(coalesce(w.cod_cliente, '')), coalesce(w.razon_social, ''), coalesce(w.zona, ''), false
  from public."PPP_Web_Programacion" w
  join web on web.empresa = w.empresa and web.order_id = w.order_id
 where coalesce(nullif(btrim(w.tanda), ''), '') <> ''
union all
select regexp_replace(upper(btrim(d.np)), '\.0+$', ''), public.gv_empresa_de_np_texto(d.np), null::bigint, null::int,
       upper(btrim(coalesce(d.tanda, ''))),
       case when left(btrim(coalesce(d.fecha_entrega, '')), 10) ~ '^\d{4}-\d{2}-\d{2}$'
            then left(btrim(d.fecha_entrega), 10)::date end,
       coalesce(d.m3, 0), btrim(coalesce(d.cod, '')), coalesce(d.razon_social, ''), coalesce(d.zona, ''), true
  from public.gv_ppp_programacion_diaria d, q
 where regexp_replace(upper(btrim(d.np)), '\.0+$', '') = q.np
   and not exists (select 1 from web)
   and coalesce(nullif(btrim(d.tanda), ''), '') <> '';
$function$;

-- ── 4) Las tandas de un día, y si sirven de destino ────────────────────────────────────────
-- `p_np` (un pedido) o `p_tanda_origen` (una tanda entera): con cualquiera de los dos, cada
-- candidata viene ya juzgada — `compatible`, `motivo` (por qué no) y `aviso` (súper / camión).
create or replace function public.gv_ppp_tandas_del_dia(p_fecha date, p_np text default null,
                                                        p_tanda_origen text default null)
 returns table(tanda text, m3 numeric, nps integer, clientes integer, estado text, orden integer,
               zonas text, camiones text, es_super boolean, compatible boolean, motivo text, aviso text)
 language plpgsql stable set search_path to 'public', 'pg_temp'
as $function$
declare
  v_esp date := public.gv_ppp_espera_fecha();
  v_o_nps text[]; v_o_est text := null; v_o_super boolean := false; v_o_cam text[] := null;
begin
  if nullif(btrim(coalesce(p_np, '')), '') is not null then
    select array_agg(x.np), bool_or(public.gv_es_super_np(x.np, x.cod)),
           array_agg(distinct public.gv_ppp_web_camion(x.zona, null))
      into v_o_nps, v_o_super, v_o_cam
      from public.gv_ppp_pedido_nps(p_np) x;
  elsif nullif(btrim(coalesce(p_tanda_origen, '')), '') is not null then
    with n as (
      select upper(btrim(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx))) np,
             btrim(coalesce(w.cod_cliente, '')) cod, coalesce(w.zona, '') zona
        from public."PPP_Web_Programacion" w
       where upper(btrim(coalesce(w.tanda, ''))) = upper(btrim(p_tanda_origen))
      union
      select regexp_replace(upper(btrim(d.np)), '\.0+$', ''), btrim(coalesce(d.cod, '')), coalesce(d.zona, '')
        from public.gv_ppp_programacion_diaria d
       where upper(btrim(coalesce(d.tanda, ''))) = upper(btrim(p_tanda_origen))
    )
    select array_agg(n.np), bool_or(public.gv_es_super_np(n.np, n.cod)),
           array_agg(distinct public.gv_ppp_web_camion(n.zona, null))
      into v_o_nps, v_o_super, v_o_cam from n;
  end if;
  if v_o_nps is not null then v_o_est := public.gv_ppp_estado_grupo(v_o_nps); end if;

  return query
  with filas as (
    select upper(btrim(w.tanda)) as tanda,
           upper(btrim(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx))) as np,
           coalesce(w.m3, 0)::numeric as m3, btrim(coalesce(w.cod_cliente, '')) as cod,
           coalesce(w.zona, '') as zona
      from public."PPP_Web_Programacion" w
     where coalesce(nullif(btrim(w.tanda), ''), '') <> ''
       and (case when p_fecha = v_esp then w.fecha_entrega is null else w.fecha_entrega = p_fecha end)
       and (p_fecha <> v_esp or exists (select 1 from public."GV_PPP_Armados_Espera" e
                                         where e.np = upper(btrim(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx)))))
    union all
    select upper(btrim(d.tanda)), regexp_replace(upper(btrim(d.np)), '\.0+$', ''),
           coalesce(d.m3, 0)::numeric, btrim(coalesce(d.cod, '')), coalesce(d.zona, '')
      from public.gv_ppp_programacion_diaria d
     where coalesce(nullif(btrim(d.tanda), ''), '') <> ''
       and (case when p_fecha = v_esp
                 then exists (select 1 from public."GV_PPP_Armados_Espera" e
                               where e.np = regexp_replace(upper(btrim(d.np)), '\.0+$', ''))
                 else left(btrim(coalesce(d.fecha_entrega, '')), 10) = to_char(p_fecha, 'YYYY-MM-DD') end)
  ),
  agr as (
    select f.tanda, round(sum(f.m3), 3) as m3, count(*)::int as nps,
           count(distinct f.cod)::int as clientes,
           string_agg(distinct coalesce(substring(f.zona, '^(Zona\s*[0-9]+)'), nullif(btrim(f.zona), ''), 'Sin zona'), ' + ') as zonas,
           string_agg(distinct public.gv_ppp_web_camion(f.zona, null), ' + ') as camiones,
           bool_or(public.gv_es_super_np(f.np, f.cod)) as es_super,
           array_agg(f.np) as nps_arr
      from filas f
     where f.tanda <> coalesce(upper(btrim(p_tanda_origen)), '@@')
     group by f.tanda
  )
  select a.tanda, a.m3, a.nps, a.clientes, e.est, e.orden, a.zonas, a.camiones, a.es_super,
         (v_o_est is null or (v_o_est <> 'proceso' and e.est = v_o_est)) as compatible,
         case when v_o_est is null then null
              when v_o_est = 'proceso' then 'Lo que se está pickeando o armando ahora no se puede meter en una tanda que ya existe: va en una tanda NUEVA.'
              when e.est <> v_o_est then 'Esa tanda está ' || e.est || ' y lo que movés está ' || v_o_est || '. Sólo se juntan tandas en el mismo estado.'
         end as motivo,
         nullif(concat_ws(' ',
           case when v_o_super is distinct from a.es_super
                then (case when a.es_super then 'Esa tanda es de un SÚPER y lo que movés no: los súper van solos, sin clientes comunes.'
                           else 'Lo que movés es de un SÚPER y esa tanda es de clientes comunes: los súper van solos.' end) end,
           case when v_o_cam is not null and a.camiones is not null and array_length(v_o_cam, 1) = 1
                     and a.camiones <> v_o_cam[1]
                then 'Esa tanda va en el camión ' || a.camiones || ' y lo que movés es de ' || v_o_cam[1] || ': no viajan juntos.' end), '') as aviso
    from agr a,
    lateral (select public.gv_ppp_estado_grupo(a.nps_arr) as est0) g,
    lateral (select g.est0 as est, case g.est0 when 'facturado' then 4 when 'armado' then 3
                                               when 'proceso' then 2 else 1 end as orden) e
   order by a.tanda;
end $function$;

-- ── 5) El código de una tanda NUEVA para un día ────────────────────────────────────────────
-- Reusa el camión que ya va ese día a esa etiqueta (regla v13.60) y, si no hay, abre uno nuevo.
-- Misma composición que `ppp_web_armar_tandas`: LETRA + NN + LETRA.
create or replace function public.gv_ppp_tanda_codigo_nuevo(p_fecha date, p_zona text default null)
 returns text language plpgsql stable set search_path to 'public', 'pg_temp'
as $function$
declare
  v_esp   date := public.gv_ppp_espera_fecha();
  v_cam   text := public.gv_ppp_web_camion(coalesce(p_zona, ''), null);
  v_pref  text := coalesce((select nullif(btrim(c.valor_texto), '') from public."PPP_Web_Config" c
                             where c.clave = 'tanda_prefijo'), '');
  v_base  text; v_nn int; v_ti int := 0; v_code text; r record;
begin
  select (regexp_match(t.tanda, '^([A-Z]+)([0-9]+)[A-Z]+$'))[1] as base,
         ((regexp_match(t.tanda, '^([A-Z]+)([0-9]+)[A-Z]+$'))[2])::int as nn
    into r
    from (
      select upper(btrim(w.tanda)) tanda, coalesce(w.zona, '') zona
        from public."PPP_Web_Programacion" w
       where upper(btrim(coalesce(w.tanda, ''))) ~ '^[A-Z]+[0-9]+[A-Z]+$'
         and (case when p_fecha = v_esp then w.fecha_entrega is null else w.fecha_entrega = p_fecha end)
      union all
      select upper(btrim(d.tanda)), coalesce(d.zona, '')
        from public.gv_ppp_programacion_diaria d
       where upper(btrim(coalesce(d.tanda, ''))) ~ '^[A-Z]+[0-9]+[A-Z]+$'
         and left(btrim(coalesce(d.fecha_entrega, '')), 10) = to_char(p_fecha, 'YYYY-MM-DD')
    ) t
   where p_fecha <> v_esp
     and public.gv_ppp_web_camion(t.zona, null) = v_cam
     and t.zona !~* 'super|retira|expo'
   group by 1, 2
   order by count(*) desc, 1 desc, 2 desc
   limit 1;
  if r.base is not null then
    v_base := r.base; v_nn := r.nn;
  else
    select public.ppp_web_letra(lc.letra), lc.camion + 1 into v_base, v_nn
      from public.gv_ppp_web_letra_y_camion() lc;
  end if;
  loop
    v_code := case when v_pref <> '' then v_pref else v_base end || lpad(v_nn::text, 2, '0') || public.ppp_web_letra(v_ti);
    exit when not public.gv_ppp_web_codigo_tomado(v_code);
    v_ti := v_ti + 1;
    if v_ti > 400 then raise exception 'No pude encontrar un código de tanda libre para el %.', p_fecha; end if;
  end loop;
  return v_code;
end $function$;

-- ── 6) Mover un conjunto de NP (el ladrillo) ───────────────────────────────────────────────
-- Cambia tanda y fecha donde vivan las NP, y arrastra su rastro: la factura (para que Carga
-- Camión las ofrezca con la tanda buena), la entrega y los eventos DE ESAS NP (`np|…|tanda`).
-- Los eventos de TANDA (EP/TP/AP/TAP) no se tocan acá: son de toda la tanda, no de una NP.
create or replace function public.gv_ppp_nps_mover_a(p_nps text[], p_tanda text, p_fecha date, p_nota text default null)
 returns integer language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare
  v_nps text[]; v_t text := upper(btrim(coalesce(p_tanda, '')));
  v_esp date := public.gv_ppp_espera_fecha();
  v_fe date := case when p_fecha = public.gv_ppp_espera_fecha() then null else p_fecha end;
  v_web int := 0; v_isis int := 0;
begin
  select array_agg(distinct regexp_replace(upper(btrim(x)), '\.0+$', ''))
    into v_nps from unnest(coalesce(p_nps, array[]::text[])) x where btrim(coalesce(x, '')) <> '';
  if v_nps is null or array_length(v_nps, 1) = 0 then return 0; end if;

  -- ⚠ UN SOLO UPDATE para todas las NP: el trigger `gv_web_cliente_un_solo_dia` es AFTER ROW y
  -- corre al final del statement, así que con las hermanas ya movidas no salta. Moviéndolas de a
  -- una rebotaba con "los pedidos de un cliente no pueden salir en días distintos" por un estado
  -- intermedio que duraba una fila (medido el 17/09 con LK 0009 + LK 0010 de Emilio Martinez).
  update public."PPP_Web_Programacion" w
     set tanda = v_t, fecha_entrega = v_fe, actualizado_at = now()
   where upper(btrim(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx))) = any (v_nps);
  get diagnostics v_web = row_count;

  insert into public."GV_PPP_Prog_Override" (np, tanda, fecha_entrega, nota)
  select n, v_t, v_fe, p_nota from unnest(v_nps) n
   where not exists (select 1 from public."PPP_Web_Programacion" w
                      where upper(btrim(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx))) = n)
  on conflict (np) do update set tanda = excluded.tanda, fecha_entrega = excluded.fecha_entrega,
                                 nota = coalesce(excluded.nota, public."GV_PPP_Prog_Override".nota);
  get diagnostics v_isis = row_count;

  update public."Facturacion_NP" f set tanda = v_t
   where regexp_replace(upper(btrim(f.np)), '\.0+$', '') = any (v_nps);
  update public."Entregas_Virgilio" e set tanda = v_t
   where regexp_replace(upper(btrim(e.np)), '\.0+$', '') = any (v_nps);
  update public."Registros_Produccion_Virgilio" r
     set texto = split_part(r.texto, '|', 1) || '|' || split_part(r.texto, '|', 2) || '|' || v_t
   where regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', '') = any (v_nps)
     and btrim(coalesce(split_part(r.texto, '|', 3), '')) <> ''
     and upper(btrim(split_part(r.texto, '|', 3))) <> v_t;

  if p_fecha = v_esp then
    insert into public."GV_PPP_Armados_Espera" (np, tanda, empresa, por, motivo, creado_en)
    select n, v_t, public.gv_emp_de_np(n), null, p_nota, now() from unnest(v_nps) n
    on conflict (np) do update set tanda = excluded.tanda, creado_en = now();
  else
    delete from public."GV_PPP_Armados_Espera" e where e.np = any (v_nps);
  end if;
  return v_web + v_isis;
end $function$;

-- ── 7) Renombrar una tanda ENTERA (re-código o fusión) ─────────────────────────────────────
-- Acá SÍ se renombran los eventos de tanda y el `ref` del stock: el código viejo deja de existir.
-- Es el mismo movimiento que se hizo a mano en la v17.47 (D67B → E01E).
create or replace function public.gv_ppp_tanda_renombrar(p_vieja text, p_nueva text, p_por text default null)
 returns integer language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare v_a text := upper(btrim(coalesce(p_vieja, ''))); v_b text := upper(btrim(coalesce(p_nueva, ''))); v_n int := 0;
begin
  if v_a = '' or v_b = '' or v_a = v_b then return 0; end if;
  update public."Registros_Produccion_Virgilio" r set texto = v_b where upper(btrim(r.texto)) = v_a;
  get diagnostics v_n = row_count;
  update public."Registros_Produccion_Virgilio" r
     set texto = split_part(r.texto, '|', 1) || '|' || split_part(r.texto, '|', 2) || '|' || v_b
   where upper(btrim(split_part(r.texto, '|', 3))) = v_a;
  update public."Entregas_Virgilio" e set tanda = v_b where upper(btrim(e.tanda)) = v_a;
  update public."Facturacion_NP" f set tanda = v_b where upper(btrim(f.tanda)) = v_a;
  update public."Movimientos_Stock" m set ref = v_b where upper(btrim(coalesce(m.ref, ''))) = v_a;
  update public."GV_PPP_Armados_Espera" e set tanda = v_b where upper(btrim(coalesce(e.tanda, ''))) = v_a;
  update public."PPP_Web_Tandas" t set codigo = v_b
   where upper(btrim(t.codigo)) = v_a
     and not exists (select 1 from public."PPP_Web_Tandas" x where upper(btrim(x.codigo)) = v_b);
  delete from public."PPP_Web_Tandas" t where upper(btrim(t.codigo)) = v_a;
  return v_n;
end $function$;

revoke execute on function public.gv_ppp_nps_mover_a(text[], text, date, text) from public, anon, authenticated;
revoke execute on function public.gv_ppp_tanda_renombrar(text, text, text) from public, anon, authenticated;

-- ── 8) LA RPC del botón de la NP: mover un PEDIDO ──────────────────────────────────────────
create or replace function public.gv_ppp_pedido_mover(p_np text, p_fecha date, p_tanda text default null,
                                                       p_por text default null, p_forzar boolean default false)
 returns table(movidas integer, nps text[], tanda text, fecha date, estado text, nueva boolean, aviso text)
 language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare
  v_np text := regexp_replace(upper(btrim(coalesce(p_np, ''))), '\.0+$', '');
  v_esp date := public.gv_ppp_espera_fecha();
  v_t text := upper(btrim(coalesce(p_tanda, '')));
  v_nueva boolean := (v_t = '');
  v_est text; v_nps text[]; v_tandas text[]; v_zona text;
  v_n int := 0; v_aviso text := null; v_salio boolean := false;
  v_cand record;
begin
  if not public.gv_es_supervisor_o_servicio() then
    raise exception 'Sólo supervisores pueden mover un pedido de día.';
  end if;
  if v_np = '' then raise exception 'Falta la NP.'; end if;
  if p_fecha is null then raise exception 'Falta el día al que va.'; end if;

  select array_agg(x.np), array_agg(distinct x.tanda), min(x.zona)
    into v_nps, v_tandas, v_zona
    from public.gv_ppp_pedido_nps(v_np) x;
  if v_nps is null or array_length(v_nps, 1) = 0 then
    raise exception 'No encontré el pedido de la NP % (¿está en alguna tanda?).', v_np;
  end if;
  v_est := public.gv_ppp_estado_grupo(v_nps);

  select exists (
    select 1 from (
      select regexp_replace(upper(btrim(split_part(r2.texto, '|', 1))), '\.0+$', '') np,
             max(r2.ts_cliente) filter (where r2.opcion = 'CCN') ccn,
             max(r2.ts_cliente) filter (where r2.opcion = 'FSS') fss,
             max(r2.ts_cliente) filter (where r2.opcion = 'CRN') crn
        from public."Registros_Produccion_Virgilio" r2
       where r2.opcion in ('CCN','FSS','CRN') and coalesce(btrim(r2.legajo), '') not in ('0','1')
         and btrim(coalesce(r2.texto, '')) <> ''
       group by 1) e
     where e.np = any (v_nps)
       and (e.crn is not null or (e.ccn is not null and e.ccn >= coalesce(e.fss, '-infinity'::timestamptz)))
  ) into v_salio;
  if v_salio and not coalesce(p_forzar, false) then
    raise exception 'PEDIDO_SALIO: el pedido % ya tiene carga de camión o remito controlado. Si salió, no se le cambia el día: se cierra con el remito.', v_np;
  end if;

  if not v_nueva then
    select * into v_cand from public.gv_ppp_tandas_del_dia(p_fecha, v_np) t where t.tanda = v_t;
    if v_cand.tanda is null then
      raise exception 'La tanda % no existe el % (o es la tanda de la que sale).', v_t,
        (case when p_fecha = v_esp then 'Armados en espera' else to_char(p_fecha, 'DD/MM') end);
    end if;
    -- v19.32: la regla de estados de Luis NO se fuerza. `p_forzar` es para la tanda ya
    -- empezada (que sí se mueve, avisando), no para juntar una armada con una pendiente.
    if not v_cand.compatible then
      raise exception 'ESTADO_DISTINTO: %', v_cand.motivo;
    end if;
    v_aviso := v_cand.aviso;
  else
    v_t := public.gv_ppp_tanda_codigo_nuevo(p_fecha, v_zona);
  end if;

  v_n := public.gv_ppp_nps_mover_a(v_nps, v_t, p_fecha,
             'v19.32 ' || to_char(now() at time zone 'America/Argentina/Buenos_Aires', 'YYYY-MM-DD HH24:MI')
             || ' · pedido movido a ' || (case when p_fecha = v_esp then 'Armados en espera' else to_char(p_fecha, 'DD/MM') end)
             || ' · tanda ' || v_t || coalesce(' por ' || nullif(btrim(p_por), ''), ''));

  -- el PISO de estado: una NP armada que se separa a una tanda nueva no tiene el TAP de esa
  -- tanda, y sin esto figuraría "pendiente". Lo respeta gv_ppp_prog_arbol.
  if v_est in ('facturado', 'armado', 'proceso') then
    insert into public."GV_PPP_NP_Estado" (np, estado, tanda_origen, motivo, por)
    select n, v_est, v_tandas[1], 'separado del pedido ' || v_np, nullif(btrim(p_por), '')
      from unnest(v_nps) n
    on conflict (np) do update set estado = excluded.estado, tanda_origen = excluded.tanda_origen,
                                   motivo = excluded.motivo, por = excluded.por, creado_en = now();
  end if;

  -- si la tanda de origen quedó VACÍA, su código deja de existir: sus eventos se van con el pedido
  if array_length(v_tandas, 1) = 1 and v_tandas[1] is not null and v_tandas[1] <> '' and v_tandas[1] <> v_t then
    if not exists (
      select 1 from public."PPP_Web_Programacion" w where upper(btrim(coalesce(w.tanda, ''))) = v_tandas[1]
      union all
      select 1 from public.gv_ppp_programacion_diaria d where upper(btrim(coalesce(d.tanda, ''))) = v_tandas[1]
    ) then
      perform public.gv_ppp_tanda_renombrar(v_tandas[1], v_t, p_por);
      v_aviso := coalesce(v_aviso || ' ', '') || 'La tanda ' || v_tandas[1] || ' quedó vacía: se fusionó en ' || v_t || '.';
    end if;
  end if;

  return query select v_n, v_nps, v_t, (case when p_fecha = v_esp then null else p_fecha end),
                      v_est, v_nueva, v_aviso;
end $function$;

revoke execute on function public.gv_ppp_pedido_mover(text, date, text, text, boolean) from public;
grant execute on function public.gv_ppp_pedido_mover(text, date, text, text, boolean) to anon, authenticated, service_role;

-- ── 9) `gv_ppp_tanda_mover` ahora elige a qué tanda va ─────────────────────────────────────
-- p_tanda_destino: null = mantiene el código (lo de siempre) · '' o '*NUEVA*' = código nuevo del
-- día destino · '<código>' = se fusiona adentro de esa tanda y la de origen deja de existir.
-- ⚠ La firma vieja de 4 argumentos se DROPEA a propósito: con las dos, PostgREST no sabe cuál
-- llamar. El front manda siempre `p_tanda_destino`.
drop function if exists public.gv_ppp_tanda_mover(text, date, text, boolean);
create or replace function public.gv_ppp_tanda_mover(p_tanda text, p_fecha date, p_por text default null,
                                                     p_forzar boolean default false, p_tanda_destino text default null)
 returns table(movidas integer, np_web integer, np_isis integer, m3 numeric, aviso text,
               empezada boolean, tanda_final text)
 language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare
  v_t text := upper(btrim(coalesce(p_tanda, '')));
  v_esp date := public.gv_ppp_espera_fecha();
  v_dest text; v_modo text;
  v_ev int; v_salio int; v_total int;
  v_web int := 0; v_isis int := 0; v_m3 numeric := 0;
  v_aviso text := null; v_cupo numeric; v_usado numeric; v_zona text;
  v_cand record;
begin
  if not public.gv_es_supervisor_o_servicio() then
    raise exception 'Sólo supervisores pueden mover tandas.';
  end if;
  if v_t = '' then raise exception 'Falta el código de la tanda.'; end if;
  if p_fecha is null then raise exception 'Falta la fecha nueva.'; end if;
  if p_fecha = v_esp and coalesce(btrim(p_tanda_destino), '') = '' then
    raise exception 'Para dejar la tanda % en Armados en espera usá gv_ppp_tanda_espera: ahí no se le pone fecha, se le saca.', v_t;
  end if;

  -- las NP de la tanda, con la etiqueta con la que las nombra el árbol
  create temp table if not exists _tm_nps (np text primary key, web boolean, zona text) on commit drop;
  delete from _tm_nps where true;   -- v19.45: WHERE obligatorio — el rol authenticator precarga safeupdate,
                                    -- que rechaza todo DELETE sin WHERE (incluso sobre tabla temporal).
                                    -- Sin esto, mover una tanda de día tiraba "DELETE requires a WHERE clause".
  insert into _tm_nps (np, web, zona)
  select x.np, bool_or(x.web), min(x.zona) from (
    select upper(btrim(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx))) np, true web, coalesce(w.zona,'') zona
      from public."PPP_Web_Programacion" w where upper(btrim(coalesce(w.tanda, ''))) = v_t
    union all
    select regexp_replace(upper(btrim(d.np)), '\.0+$', ''), false, coalesce(d.zona,'')
      from public.gv_ppp_programacion_diaria d where upper(btrim(coalesce(d.tanda, ''))) = v_t and d.np is not null
    union all
    select regexp_replace(upper(btrim(f.np)), '\.0+$', ''), false, ''
      from public."Facturacion_NP" f where upper(btrim(coalesce(f.tanda, ''))) = v_t and f.np is not null
  ) x group by x.np;

  select count(*) into v_total from _tm_nps;
  select count(*) into v_salio from _tm_nps n
    join (select regexp_replace(upper(btrim(split_part(r2.texto, '|', 1))), '\.0+$', '') np,
                 max(r2.ts_cliente) filter (where r2.opcion = 'CCN') ccn,
                 max(r2.ts_cliente) filter (where r2.opcion = 'FSS') fss,
                 max(r2.ts_cliente) filter (where r2.opcion = 'CRN') crn
            from public."Registros_Produccion_Virgilio" r2
           where r2.opcion in ('CCN','FSS','CRN') and coalesce(btrim(r2.legajo), '') not in ('0','1')
             and btrim(coalesce(r2.texto, '')) <> '' group by 1) e on e.np = n.np
   where e.crn is not null or (e.ccn is not null and e.ccn >= coalesce(e.fss, '-infinity'::timestamptz));

  if v_total > 0 and v_salio = v_total then
    raise exception 'La tanda % ya salió entera (% pedido(s) con carga de camión o remito controlado): no hay nada a lo que cambiarle el día.', v_t, v_salio;
  end if;
  if v_salio > 0 then
    raise exception 'La tanda % ya salió en parte (% de % pedidos tienen carga de camión o remito). Cambiarle el día arrastraría lo que ya se entregó, y mover sólo el resto partiría la tanda en dos días. Reprogramá el pedido que falta desde su fila (botón 📅 Cambiar de día de la NP): sale en una tanda nueva, sin volver a pickear.', v_t, v_salio, v_total;
  end if;

  select count(*) into v_ev from public."Registros_Produccion_Virgilio" r
   where upper(btrim(split_part(r.texto, '|', 1))) = v_t;
  if v_ev > 0 and not coalesce(p_forzar, false) then
    raise exception 'TANDA_EMPEZADA: la tanda % ya tiene % evento(s) de operarios (pickeada o armada). Se puede mover igual —el contenido no cambia, no hay que volver a pickear— pero hay que confirmarlo.', v_t, v_ev;
  end if;

  -- ── a dónde va: mismo código / código nuevo del día / adentro de una tanda que ya existe ──
  select min(n.zona) into v_zona from _tm_nps n where coalesce(n.zona, '') <> '';
  if p_tanda_destino is null then
    v_dest := v_t; v_modo := 'mantiene';
  elsif btrim(p_tanda_destino) = '' or upper(btrim(p_tanda_destino)) = '*NUEVA*' then
    v_dest := public.gv_ppp_tanda_codigo_nuevo(p_fecha, v_zona); v_modo := 'nueva';
  else
    v_dest := upper(btrim(p_tanda_destino)); v_modo := 'fusion';
    select * into v_cand from public.gv_ppp_tandas_del_dia(p_fecha, null, v_t) t where t.tanda = v_dest;
    if v_cand.tanda is null then
      raise exception 'La tanda % no existe el %.', v_dest,
        (case when p_fecha = v_esp then 'día de espera' else to_char(p_fecha, 'DD/MM') end);
    end if;
    -- v19.32: la regla de estados de Luis NO se fuerza (ver gv_ppp_pedido_mover).
    if not v_cand.compatible then
      raise exception 'ESTADO_DISTINTO: %', v_cand.motivo;
    end if;
    v_aviso := v_cand.aviso;
  end if;

  select count(*) filter (where n.web), count(*) filter (where not n.web) into v_web, v_isis from _tm_nps n;
  perform public.gv_ppp_nps_mover_a((select array_agg(n.np) from _tm_nps n), v_dest, p_fecha,
      'v19.32 ' || to_char(now() at time zone 'America/Argentina/Buenos_Aires', 'YYYY-MM-DD HH24:MI')
      || ' · tanda ' || v_t || ' → ' || v_dest || ' el '
      || (case when p_fecha = v_esp then 'día de espera' else to_char(p_fecha, 'DD/MM') end)
      || coalesce(' por ' || nullif(btrim(p_por), ''), '')
      || case when v_ev > 0 then ' · estaba empezada (' || v_ev || ' evento(s))' else '' end);
  if v_total = 0 then raise exception 'No encontré la tanda %.', v_t; end if;

  -- el código viejo deja de existir: sus eventos, su stock y sus entregas se van con él
  if v_dest <> v_t then perform public.gv_ppp_tanda_renombrar(v_t, v_dest, p_por); end if;
  update public."PPP_Web_Tandas" t
     set fecha_entrega = (case when p_fecha = v_esp then null else p_fecha end)
   where upper(btrim(t.codigo)) = v_dest;

  select coalesce(round(sum(x.m3), 3), 0) into v_m3 from (
    select w.m3 from public."PPP_Web_Programacion" w where upper(btrim(coalesce(w.tanda,''))) = v_dest
    union all
    select d.m3 from public.gv_ppp_programacion_diaria d where upper(btrim(coalesce(d.tanda,''))) = v_dest
  ) x;

  if p_fecha <> v_esp then
    v_cupo := public.gv_ppp_web_cupo(p_fecha);
    select coalesce(sum(g.m3), 0) into v_usado from public."PPP_Web_Programacion" g
     where g.fecha_entrega = p_fecha and coalesce(nullif(trim(g.tanda), ''), '') <> '';
    v_usado := v_usado + public.gv_ppp_web_m3_isis(p_fecha);
    if v_usado > v_cupo then
      v_aviso := coalesce(v_aviso || ' ', '') || 'El ' || to_char(p_fecha, 'DD/MM') || ' queda con ' || round(v_usado, 3)
                 || ' m³, por encima del cupo de ' || v_cupo || ' m³.';
    end if;
    if not public.gv_es_dia_habil(p_fecha) then
      v_aviso := coalesce(v_aviso || ' ', '') || 'Ojo: el ' || to_char(p_fecha, 'DD/MM')
                 || ' no es día hábil (fin de semana o feriado).';
    end if;
  end if;
  if v_modo = 'fusion' then
    v_aviso := coalesce(v_aviso || ' ', '') || 'La tanda ' || v_t || ' dejó de existir: sus pedidos ahora son de ' || v_dest || '.';
  elsif v_modo = 'nueva' then
    v_aviso := coalesce(v_aviso || ' ', '') || 'Código nuevo: ' || v_t || ' pasó a ser ' || v_dest || '.';
  end if;

  return query select (v_web + v_isis), v_web, v_isis, v_m3, v_aviso, (v_ev > 0), v_dest;
end $function$;

revoke execute on function public.gv_ppp_tanda_mover(text, date, text, boolean, text) from public;
grant execute on function public.gv_ppp_tanda_mover(text, date, text, boolean, text) to anon, authenticated, service_role;

-- ── 10) El árbol respeta el piso de estado ─────────────────────────────────────────────────
-- Se aplica como PARCHE sobre la definición viva (el CREATE completo del árbol vive en
-- `sql/gv_ppp_armados_espera_v1929.sql`): son tres reemplazos exactos, reproducibles.
do $do$
declare d text; n text;
begin
  d := pg_get_functiondef('public.gv_ppp_prog_arbol(date,date)'::regprocedure);
  if position('GV_PPP_NP_Estado' in d) > 0 then return; end if;   -- ya está
  n := replace(d,
    $a$         (a.opcion = 'AP' or p.opcion in ('TP','EP')) as b_curso
    from dia d$a$,
    $b$         (a.opcion = 'AP' or p.opcion in ('TP','EP')) as b_curso,
         -- v19.32: PISO de estado por NP. Una NP armada que se separa a una tanda nueva no tiene
         -- el TAP de esa tanda, y sin esto figuraria "pendiente". Lo graba gv_ppp_pedido_mover.
         coalesce(case he.estado when 'facturado' then 4 when 'armado' then 3 when 'proceso' then 2 end, 1) as piso
    from dia d$b$);
  n := replace(n,
    $c$    left join arm   a on a.tanda = d.tanda and d.tanda <> ''
)$c$,
    $d$    left join arm   a on a.tanda = d.tanda and d.tanda <> ''
    left join public."GV_PPP_NP_Estado" he on he.np = upper(d.np)
)$d$);
  n := replace(n,
    $e$       case when e.b_fact then 'facturado' when e.b_arm then 'armado'
            when e.b_curso then 'proceso' else 'pendiente' end,
       case when e.b_fact then 4 when e.b_arm then 3 when e.b_curso then 2 else 1 end,$e$,
    $f$       case greatest(case when e.b_fact then 4 when e.b_arm then 3 when e.b_curso then 2 else 1 end, e.piso)
            when 4 then 'facturado' when 3 then 'armado' when 2 then 'proceso' else 'pendiente' end,
       greatest(case when e.b_fact then 4 when e.b_arm then 3 when e.b_curso then 2 else 1 end, e.piso),$f$);
  if position('e.piso' in n) = 0 or position('GV_PPP_NP_Estado' in n) = 0 then
    raise exception 'los tres reemplazos del arbol no entraron';
  end if;
  execute n;
end $do$;

-- ── Chequeos ───────────────────────────────────────────────────────────────────────────────
-- select * from public.gv_ppp_tandas_del_dia(current_date + 1, 'LK 0009');  -- candidatas juzgadas
-- select * from public.gv_ppp_np_estado(array['LK 0009']);                  -- estado de una NP
-- select * from public."GV_PPP_NP_Estado";                                  -- qué se separó y de dónde
-- select * from public.gv_ppp_tanda_dos_dias;   -- vacío = todo bien
-- select * from public.gv_ppp_super_mezclado;   -- vacío = todo bien
