-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- v19.29 — «ARMADOS EN ESPERA»: un día más en Programación, para lo que se arma SIN fecha
-- Pedido de Luis (2026-09-17): *"agrega un 'día' en programación que sea «Armados en espera»,
-- va a servir para intencionalmente mandar pedidos que se arman sin fecha de entrega definida.
-- Asegurate que se pueda enviar desde pedidos atrasados y desde programación de entregas"*.
--
-- QUÉ ES: una tanda «en espera» es una tanda NORMAL (su contenido, su picking y su armado no se
-- tocan) a la que se le SACA la fecha de entrega. Sin fecha:
--   · no consume cupo del día         (gv_ppp_web_calendario filtra por rango de fechas)
--   · no entra en ningún camión       (gv_ppp_camion_pasado / _super_mezclado piden fecha)
--   · no aparece como ATRASADA        (gv_ppp_atrasados lee el árbol hasta ayer)
--   · no se le avisa al cliente       (vista_avisar_programacion pide fecha)
--   · el automático no le suma nada   (gv_ppp_web_tanda_abierta_cliente compara fecha = p_fecha)
-- O sea: la regla de "sin fecha" que este sistema YA tenía es la que hace todo el trabajo. Lo
-- único que hacía falta era que esas tandas no desaparecieran de la pantalla.
--
-- CÓMO SE VE: `GV_PPP_Armados_Espera` marca qué NP están en espera, y `gv_ppp_prog_arbol` las
-- devuelve con la fecha centinela `9999-12-31` para que la Programación las agrupe como un día
-- más, el último de la lista. El front lo dibuja como «⏸ Armados en espera».
--   ⚠ Sólo salen si el rango pedido llega hasta el centinela. La Programación pide
--   `p_hasta = 9999-12-31`; Pedidos atrasados pide hasta AYER, así que nunca las ve. Eso es lo
--   que hace que parar una tanda la saque de atrasados sin tocar `gv_ppp_atrasados`.
--
-- POR QUÉ NO UNA FECHA FUTURA (9999-12-31 guardada en la tabla): se probó y es peor. Una fecha
-- futura de verdad la ven TODOS los consumidores de fechas: el trigger `gv_web_cliente_un_solo_dia`
-- se llevaría al año 9999 el resto de los pedidos de ese cliente, `notificar_tandas_adelantar_telegram`
-- pediría adelantarlas todos los días, y el cliente recibiría un WhatsApp con esa fecha. Sin fecha,
-- cada uno de esos guards ya la ignora solo.
--
-- VOLVER: el mismo botón «📅 Cambiar de día» de siempre (`gv_ppp_tanda_mover`), que ahora borra la
-- marca. No hay que volver a pickear ni a armar: el contenido nunca se tocó.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

-- ── 1) La marca ────────────────────────────────────────────────────────────────────────────
create table if not exists public."GV_PPP_Armados_Espera" (
  np         text primary key,
  tanda      text,
  empresa    text,
  m3         numeric,
  por        text,
  motivo     text,
  creado_en  timestamptz not null default now()
);
alter table public."GV_PPP_Armados_Espera" enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public'
                  and tablename='GV_PPP_Armados_Espera' and policyname='gv_ppp_espera_sel') then
    create policy gv_ppp_espera_sel on public."GV_PPP_Armados_Espera" for select using (true);
  end if;
end $$;
-- Se lee desde la pantalla (el árbol corre como el usuario, no es SECURITY DEFINER); se escribe
-- SÓLO por las RPC de abajo, que chequean supervisor.
-- ⚠ `lk_ppp_reader` / `ch_ppp_reader` también: son los roles con los que LK y Chef leen el espejo
-- `gv_ppp_programacion_diaria` por el FDW, y esa vista es `security_invoker` — si no les doy
-- SELECT acá, su `sincronizar_ppp()` se cae con "permission denied" apenas se aplique el punto 2.
grant select on public."GV_PPP_Armados_Espera" to anon, authenticated, lk_ppp_reader, ch_ppp_reader;
revoke insert, update, delete on public."GV_PPP_Armados_Espera" from anon, authenticated;

-- La fecha centinela, en un solo lugar. El front tiene la misma constante (PGA_ESPERA_ISO).
create or replace function public.gv_ppp_espera_fecha()
returns date language sql immutable as $$ select date '9999-12-31' $$;

-- ── 2) El espejo de ISIS: una NP en espera queda SIN fecha de entrega ───────────────────────
-- Se mantiene la tanda (el armado sigue existiendo); lo único que se borra es la fecha, que es
-- lo que la saca de los días. `desprogramada` sigue haciendo lo suyo (saca tanda Y fecha).
-- ⚠ CREATE OR REPLACE conserva las columnas pero NO las reloptions: el `security_invoker` se
-- vuelve a poner abajo, sí o sí (sin él la vista saltea la RLS).
create or replace view public.gv_ppp_programacion_diaria as
 with multi as (
         select regexp_replace(btrim(g.cod), '\.0+$'::text, ''::text) as cod
           from public."GV_PPP_Programacion_Diaria" g
          where (coalesce(btrim(g.razon_social), ''::text) <> ''::text)
          group by (regexp_replace(btrim(g.cod), '\.0+$'::text, ''::text))
         having (count(distinct lower(btrim(g.razon_social))) > 1)
        )
 select p.id,
    p.np,
        case
            when coalesce(o.desprogramada, false) then ''::text
            else coalesce(nullif(btrim(o.tanda), ''::text), p.tanda)
        end as tanda,
    p.tipo,
    p.fecha_recep,
    coalesce(nullif(btrim(o.cod), ''::text), p.cod) as cod,
    coalesce(nullif(btrim(o.razon_social), ''::text),
        case
            when (m.cod is not null) then nullif(btrim(p.razon_social), ''::text)
            else null::text
        end, rs.razon_social, p.razon_social) as razon_social,
    coalesce(o.m3, p.m3) as m3,
    p.v,
    coalesce(nullif(btrim(o.direccion), ''::text), p.direccion) as direccion,
    coalesce(nullif(btrim(o.barrio), ''::text), p.barrio) as barrio,
    p.op,
        case
            when coalesce(o.desprogramada, false) then ''::text
            -- v19.29: en espera = sin fecha de entrega. La tanda queda.
            when (esp.np is not null) then ''::text
            else coalesce(((o.fecha_entrega)::text || ' 00:00:00'::text), p.fecha_entrega)
        end as fecha_entrega,
    p.fecha_fc,
    coalesce(nullif(btrim(o.zona), ''::text), p.zona) as zona,
    p.observaciones
   from public."GV_PPP_Programacion_Diaria" p
     cross join public.gv_espejo_corte() c(lk, chef)
     left join public."GV_PPP_Prog_Override" o on ((o.np = regexp_replace(p.np, '\.0+$'::text, ''::text)))
     left join public."GV_PPP_Armados_Espera" esp on ((esp.np = regexp_replace(btrim(p.np), '\.0+$'::text, ''::text)))
     left join public."GV_Cliente_Razon_Social" rs on (((rs.cod = regexp_replace(btrim(coalesce(nullif(btrim(o.cod), ''::text), p.cod)), '\.0+$'::text, ''::text)) and (rs.empresa = public.gv_empresa_de_np_texto(p.np))))
     left join multi m on ((m.cod = regexp_replace(btrim(coalesce(nullif(btrim(o.cod), ''::text), p.cod)), '\.0+$'::text, ''::text)))
  where (public.gv_espejo_np_pasa(p.np, c.lk, c.chef) and (not coalesce(o.oculto, false)));

alter view public.gv_ppp_programacion_diaria set (security_invoker = true);

-- ── 3) El árbol: las NP en espera salen agrupadas en el día centinela ───────────────────────
create or replace function public.gv_ppp_prog_arbol(p_desde date, p_hasta date)
 returns table(fecha date, tanda text, np text, np_num numeric, cod text, razon_social text, localidad text, zona text, zona_corta text, empresa text, origen text, m3 numeric, estado text, estado_orden integer, clave text, pide_horario boolean, horario_fecha date, horario_franja text, horario_origen text, barrio text, fecha_pedido date)
 language sql
 stable
 set search_path to 'public', 'pg_temp'
as $function$
with esp as (
  select regexp_replace(upper(btrim(e.np)), '\.0+$', '') as np
    from public."GV_PPP_Armados_Espera" e
),
fuentes as (
  select 1 as pri,
         regexp_replace(btrim(p.np), '\.0+$', '')                          as np,
         upper(btrim(coalesce(p.tanda, '')))                               as tanda,
         coalesce(p.m3, 0)::numeric                                        as m3,
         nullif(left(btrim(p.fecha_entrega), 10), '')::date                as fe,
         coalesce(btrim(p.cod), '')                                        as cod,
         coalesce(btrim(p.razon_social), '')                               as razon_social,
         coalesce(nullif(btrim(coalesce(p.barrio, '')), ''),
                  btrim(coalesce(p.direccion, '')))                        as localidad,
         coalesce(btrim(p.zona), '')                                       as zona,
         regexp_replace(btrim(p.np), '\.0+$', '')                          as clave,
         nullif(btrim(coalesce(p.barrio, '')), '')                         as barrio,
         case when left(btrim(coalesce(p.fecha_recep, '')), 10) ~ '^\d{4}-\d{2}-\d{2}$'
              then left(btrim(p.fecha_recep), 10)::date end                as fecha_pedido,
         'isis'::text                                                      as origen
    from public.gv_ppp_programacion_diaria p
   where left(btrim(coalesce(p.fecha_entrega, '')), 10) ~ '^\d{4}-\d{2}-\d{2}$'
      -- v19.29: una NP de ISIS en espera quedó sin fecha en el espejo; igual tiene que entrar,
      -- porque su día lo pone la marca.
      or exists (select 1 from esp where esp.np = regexp_replace(upper(btrim(p.np)), '\.0+$', ''))
  union all
  select 2,
         public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx),
         upper(btrim(coalesce(w.tanda, ''))),
         coalesce(w.m3, 0)::numeric,
         w.fecha_entrega,
         coalesce(btrim(w.cod_cliente), ''),
         coalesce(btrim(w.razon_social), ''),
         coalesce(nullif(btrim(coalesce(w.barrio, '')), ''), btrim(coalesce(w.direccion, ''))),
         coalesce(btrim(w.zona), ''),
         w.order_id::text,
         nullif(btrim(coalesce(w.barrio, '')), ''),
         w.fecha_recep::date,
         'web'
    from public."PPP_Web_Programacion" w
   where w.tanda is not null and btrim(w.tanda) <> ''
  union all
  -- v19.11: `ovf` — una NP que ya solo figura facturada se puede reprogramar por el override.
  select 3,
         regexp_replace(upper(btrim(f.np)), '\.0+$', ''),
         upper(btrim(coalesce(f.tanda, ''))),
         coalesce(f.m3, 0)::numeric,
         coalesce(ovf.fecha_entrega, f.fecha_salida),
         coalesce(btrim(f.cod_cliente), ''),
         coalesce(btrim(f.razon_social), ''),
         '', '', regexp_replace(upper(btrim(f.np)), '\.0+$', ''), null::text, null::date, 'fact'
    from public."Facturacion_NP" f
    left join public."GV_PPP_Prog_Override" ovf
      on ovf.np = regexp_replace(upper(btrim(f.np)), '\.0+$', '')
   where f.fecha_salida is not null
  union all
  select 4,
         regexp_replace(btrim(h.np), '\.0+$', ''),
         upper(btrim(coalesce(h.tanda, ''))),
         coalesce(h.m3, 0)::numeric,
         coalesce(ovh.fecha_entrega,
                  case when left(btrim(coalesce(h.fecha_entrega, '')), 10) ~ '^\d{4}-\d{2}-\d{2}$'
                       then left(btrim(h.fecha_entrega), 10)::date end),
         coalesce(btrim(h.cod), ''),
         coalesce(btrim(h.rs), ''),
         '', '', regexp_replace(btrim(h.np), '\.0+$', ''), null::text, null::date, 'hist'
    from public."GV_PPP_Entregados_Historico" h
    left join public."GV_PPP_Prog_Override" ovh
      on ovh.np = regexp_replace(btrim(h.np), '\.0+$', '')
),
fuera as (
  select o.np
    from public."GV_PPP_Prog_Override" o
   where coalesce(o.oculto, false) or coalesce(o.desprogramada, false)
  union
  select regexp_replace(btrim(coalesce(c.np, '')), '\.0+$', '')
    from public."NP_Canceladas" c
),
uni as (
  select distinct on (f.np) f.*,
         exists (select 1 from esp where esp.np = upper(f.np)) as en_espera
    from fuentes f
   where f.np <> ''
     and (f.fe is not null or exists (select 1 from esp where esp.np = upper(f.np)))
     and not exists (select 1 from fuera x where x.np = f.np)
   order by f.np, f.pri, f.m3 desc
),
dia as (
  -- v19.29: el día de una NP en espera es el centinela. Con eso entra en el rango sólo cuando
  -- quien pregunta llega hasta ahí (la Programación), y nunca en un rango de días reales
  -- (Pedidos atrasados, Avance del día).
  select u.*, (case when u.en_espera then public.gv_ppp_espera_fecha() else u.fe end) as fe_dia
    from uni u
   where (case when u.en_espera then public.gv_ppp_espera_fecha() else u.fe end) between p_desde and p_hasta
),
ev as (
  select upper(btrim(r.texto)) as tanda, r.opcion, r.ts_cliente
    from public."Registros_Produccion_Virgilio" r
   where r.opcion in ('EP','TP','AP','TAP')
     and coalesce(btrim(r.legajo), '') not in ('0','1')
     and btrim(coalesce(r.texto, '')) <> ''
     and r.ts_cliente >= (p_desde - interval '60 days')
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
est as (
  select d.fe_dia as fe, d.np, d.tanda, d.m3, d.cod, d.razon_social, d.localidad, d.zona, d.origen, d.clave, d.barrio, d.fecha_pedido,
         (fc.np is not null)                          as b_fact,
         (s.np is not null or a.opcion = 'TAP')       as b_arm,
         (a.opcion = 'AP' or p.opcion in ('TP','EP')) as b_curso
    from dia d
    left join salio s on s.np = upper(d.np)
    left join fact fc on fc.np = upper(d.np)
    left join pick  p on p.tanda = d.tanda and d.tanda <> ''
    left join arm   a on a.tanda = d.tanda and d.tanda <> ''
)
select e.fe,
       coalesce(nullif(e.tanda, ''), '—'),
       e.np,
       nullif(regexp_replace(e.np, '\D', '', 'g'), '')::numeric,
       e.cod, e.razon_social, e.localidad, e.zona,
       case when e.zona ~* 'retira'                                    then 'Retira'
            when public.gv_es_super_np(e.np, e.cod)
              or e.zona ~* 'super|coto|carrefour|chango|krikos'        then 'Súper'
            else coalesce(substring(e.zona, '^(Zona\s*[0-9]+)'), nullif(btrim(e.zona), ''), 'Sin zona') end,
       case when upper(e.np) like 'LK%' then 'LK'
            when upper(e.np) like 'CH%' then 'CH'
            when coalesce(nullif(regexp_replace(e.np, '\D', '', 'g'), '')::numeric, 0) > 90000 then 'LK'
            else 'CH' end,
       e.origen, e.m3,
       case when e.b_fact then 'facturado' when e.b_arm then 'armado'
            when e.b_curso then 'proceso' else 'pendiente' end,
       case when e.b_fact then 4 when e.b_arm then 3 when e.b_curso then 2 else 1 end,
       e.clave,
       public.gv_pide_horario_np(e.np, e.cod, e.zona),
       h.fecha, h.franja, h.origen,
       e.barrio, e.fecha_pedido
  from est e
  left join public."GV_Pedido_Horario" h
    on h.empresa = public.gv_emp_de_np(e.np)
   and h.clave in (e.clave, regexp_replace(upper(btrim(e.np)), '\.0+$', ''))
 order by e.fe, coalesce(nullif(e.tanda, ''), '—'),
          nullif(regexp_replace(e.np, '\D', '', 'g'), '')::numeric nulls last, e.np;
$function$;

-- ── 4) Mandar una tanda a «Armados en espera» ──────────────────────────────────────────────
create or replace function public.gv_ppp_tanda_espera(p_tanda text, p_por text default null, p_motivo text default null)
 returns table(movidas integer, np_web integer, np_isis integer, m3 numeric, aviso text)
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_t     text := upper(btrim(coalesce(p_tanda, '')));
  v_total int;
  v_salio int;
  v_web   int := 0;
  v_isis  int := 0;
  v_m3    numeric := 0;
  v_nota  text;
begin
  if not public.gv_es_supervisor_o_servicio() then
    raise exception 'Sólo supervisores pueden mandar una tanda a Armados en espera.';
  end if;
  if v_t = '' then raise exception 'Falta el código de la tanda.'; end if;

  -- ¿Ya salió alguna? Misma definición que gv_ppp_atrasados y gv_ppp_tanda_mover: CCN vigente
  -- (sin un FSS posterior, que es la vuelta al depósito) o CRN (remito controlado = entregado).
  -- Las NP de la tanda van con la MISMA etiqueta con la que las nombra el árbol.
  with nps as (
    select regexp_replace(upper(btrim(x.np_label)), '\.0+$', '') as np from (
      select public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) as np_label
        from public."PPP_Web_Programacion" w
       where upper(btrim(coalesce(w.tanda, ''))) = v_t
      union
      select regexp_replace(upper(btrim(d.np)), '\.0+$', '')
        from public.gv_ppp_programacion_diaria d
       where upper(btrim(coalesce(d.tanda, ''))) = v_t and d.np is not null
      union
      select regexp_replace(upper(btrim(f.np)), '\.0+$', '')
        from public."Facturacion_NP" f
       where upper(btrim(coalesce(f.tanda, ''))) = v_t and f.np is not null
    ) x
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

  if v_total = 0 then raise exception 'No encontré la tanda %.', v_t; end if;
  if v_salio > 0 then
    raise exception 'La tanda % ya salió (% de % pedidos tienen carga de camión o remito controlado): no se puede dejar en espera lo que ya se entregó.', v_t, v_salio, v_total;
  end if;

  v_nota := 'v19.29 ' || to_char(now() at time zone 'America/Argentina/Buenos_Aires', 'YYYY-MM-DD HH24:MI')
            || ' · Armados en espera (sin fecha de entrega)'
            || coalesce(' por ' || nullif(btrim(p_por), ''), '')
            || coalesce(' · ' || nullif(btrim(p_motivo), ''), '');

  -- ── web: se le saca la fecha, la tanda queda ─────────────────────────────
  update public."PPP_Web_Programacion" w
     set fecha_entrega = null
   where upper(btrim(coalesce(w.tanda, ''))) = v_t;
  get diagnostics v_web = row_count;
  if v_web > 0 then
    update public."PPP_Web_Tandas" t set fecha_entrega = null
     where upper(btrim(t.codigo)) = v_t;
  end if;

  -- ── ISIS: la fecha la borra el espejo al ver la marca; acá queda la nota ──
  select count(*) into v_isis
    from public.gv_ppp_programacion_diaria d
   where upper(btrim(coalesce(d.tanda, ''))) = v_t and d.np is not null
     and not exists (
       select 1 from public."PPP_Web_Programacion" w
        where upper(btrim(coalesce(w.tanda, ''))) = v_t
          and (w.np::text = d.np
            or upper(btrim(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx))) = upper(btrim(d.np))));
  if v_isis > 0 then
    insert into public."GV_PPP_Prog_Override" (np, nota)
    select regexp_replace(upper(btrim(d.np)), '\.0+$', ''), v_nota
      from public.gv_ppp_programacion_diaria d
     where upper(btrim(coalesce(d.tanda, ''))) = v_t and d.np is not null
    on conflict (np) do update set nota = excluded.nota;
  end if;

  -- m³ de lo que quedó en espera
  select coalesce(round(sum(x.m3), 3), 0) into v_m3 from (
    select w.m3 from public."PPP_Web_Programacion" w where upper(btrim(coalesce(w.tanda,''))) = v_t
    union all
    select d.m3 from public.gv_ppp_programacion_diaria d where upper(btrim(coalesce(d.tanda,''))) = v_t
  ) x;
  if v_m3 = 0 then
    select coalesce(round(sum(f.m3), 3), 0) into v_m3
      from public."Facturacion_NP" f where upper(btrim(coalesce(f.tanda,''))) = v_t;
  end if;

  -- ── la marca, que es la que la hace visible en Programación ──────────────
  insert into public."GV_PPP_Armados_Espera" (np, tanda, empresa, m3, por, motivo, creado_en)
  with nps as (
    select regexp_replace(upper(btrim(x.np_label)), '\.0+$', '') as np from (
      select public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) as np_label
        from public."PPP_Web_Programacion" w
       where upper(btrim(coalesce(w.tanda, ''))) = v_t
      union
      select regexp_replace(upper(btrim(d.np)), '\.0+$', '')
        from public.gv_ppp_programacion_diaria d
       where upper(btrim(coalesce(d.tanda, ''))) = v_t and d.np is not null
      union
      select regexp_replace(upper(btrim(f.np)), '\.0+$', '')
        from public."Facturacion_NP" f
       where upper(btrim(coalesce(f.tanda, ''))) = v_t and f.np is not null
    ) x
  )
  select n.np, v_t, public.gv_emp_de_np(n.np), null, nullif(btrim(p_por), ''), nullif(btrim(p_motivo), ''), now()
    from nps n
  on conflict (np) do update
     set tanda = excluded.tanda, por = excluded.por, motivo = excluded.motivo, creado_en = now();

  return query select v_total, v_web, v_isis, v_m3,
    ('La tanda ' || v_t || ' quedó SIN fecha de entrega: no sale en ningún camión ni figura como '
     || 'atrasada hasta que le pongas día con «📅 Cambiar de día».')::text;
end $function$;

revoke execute on function public.gv_ppp_tanda_espera(text, text, text) from public;
grant execute on function public.gv_ppp_tanda_espera(text, text, text) to anon, authenticated, service_role;

-- ── 5) Sacar de espera = el mismo «Cambiar de día» de siempre ──────────────────────────────
-- Lo único que cambia respecto de la v19.11: borra la marca de espera al final (si no, la NP
-- volvería a la fecha nueva Y seguiría apareciendo en el día centinela), y no le hace avisos de
-- cupo/día hábil al centinela porque ahí no se entrega nada.
create or replace function public.gv_ppp_tanda_mover(p_tanda text, p_fecha date, p_por text default null, p_forzar boolean default false)
 returns table(movidas integer, np_web integer, np_isis integer, m3 numeric, aviso text, empezada boolean)
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
  -- v19.29: a «Armados en espera» no se llega por acá (no tiene fecha): va gv_ppp_tanda_espera.
  if p_fecha = public.gv_ppp_espera_fecha() then
    raise exception 'Para dejar la tanda % en Armados en espera usá gv_ppp_tanda_espera: ahí no se le pone fecha, se le saca.', v_t;
  end if;

  -- ¿alguna NP de la tanda YA SALIÓ? Misma definición que gv_ppp_atrasados: CCN vigente (sin un FSS
  -- posterior, que es la vuelta al depósito) o CRN (control de remito = entregado).
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

  v_nota := 'v19.29 ' || to_char(now() at time zone 'America/Argentina/Buenos_Aires', 'YYYY-MM-DD HH24:MI')
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
  -- v19.11: además de la programación viva, las NP que ya sólo figuran en Facturacion_NP (origen `fact`
  -- del árbol). Sin eso, una tanda atrasada de ésas contestaba "No encontré la tanda".
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

  -- v19.29 — si estaba en «Armados en espera», vuelve a tener día: se borra la marca.
  delete from public."GV_PPP_Armados_Espera" e where upper(btrim(coalesce(e.tanda, ''))) = v_t;

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

-- ── 6) Chequeos ────────────────────────────────────────────────────────────────────────────
-- select * from public."GV_PPP_Armados_Espera";                       -- qué está parado y por quién
-- select * from public.gv_ppp_prog_arbol(current_date, '9999-12-31')  -- el día centinela
--  where fecha = public.gv_ppp_espera_fecha();
-- select * from public.gv_ppp_atrasados();                            -- lo parado NO tiene que estar
-- select * from public.gv_ppp_tanda_dos_dias();                       -- vacío = todo bien
