-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- v19.34 (Luis, 2026-09-17) — «✕ CANCELAR PEDIDO» DESDE LA FILA DE LA NP
--
-- Pedido textual: *"Quiero agregar un boton junto al de cambiar fecha para NPs que sea «Cancelar
-- pedido». Se puede hacer con cualquier pedido en cualquier estado. Se borra el pedido de la
-- programacion y la mercadería que tenía (si es que tenía) vuelve a A guardar (que pida
-- confirmacion y que ahi avise si tiene mercadería que va a volver a «A guardar» y que diga el
-- detalle). Si se «Cancela pedido» a una NP que es parte de un pedido distribuido en muchas NPs,
-- tiene que preguntar si se quieren cancelar todas las NPs de ese pedido o solo esa."*
--
-- El caso que lo trajo: la tanda **D66D**, NP **98668** (Nexxo S.R.L.). Se armó, se facturó, se
-- cargó al camión el 11/09 — y ahí el cliente la canceló. El 14/09 la marcaron «↩ sin salida»
-- (evento FSS) y las cajas volvieron al depósito, pero la NP seguía en la PPP y su mercadería
-- seguía contada en `a_facturar`.
--
-- ⚠ NO ES UN MOTOR NUEVO. `gv_ppp_np_desarmar` ya devolvía el stock a «A guardar» desde la
-- v18.90, y el pop-up de cancelar ya existía en Facturación. Lo que faltaba es (a) el botón en la
-- PPP, (b) que ande con algo que ya salió, (c) mostrar el detalle ANTES de confirmar y (d) poder
-- cancelar UN bloque sin matar el pedido entero.
--
-- ⚠ ESTE ARCHIVO ES LO QUE ESTÁ APLICADO. Verificación (md5 del cuerpo sin comentarios ni
-- espacios, el chequeo que usa el repo):
--   select p.proname, md5(regexp_replace(regexp_replace(regexp_replace(
--            p.prosrc,'/\*.*?\*/','','gs'),'--[^\n]*','','g'),'\s','','g'))
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname='public' and p.proname in ('gv_ppp_np_devolucion','gv_ppp_np_cancelar_previo',
--          'gv_ppp_np_desarmar','gv_ppp_pedido_cancelar');
--
-- Rollback: `sql/backups/pre_v1934_cancelar_pedido_20260917.sql`.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

-- ── 1) La marca de "esta NP web se cancela, pero el resto del pedido NO" ───────────────────
-- `GV_Web_Cancelados` tiene clave (empresa, order_id), o sea que es por PEDIDO ENTERO: escribir
-- ahí para cancelar un bloque mataría los otros. Para un bloque hace falta la misma granularidad
-- que ya usan `GV_PPP_Web_Diferido` y `GV_PPP_Web_Retenido`: (empresa, order_id, np_idx). Sin
-- esto la NP queda con tanda=null y el cron la re-arma sola — el problema 213, a nivel bloque.
create table if not exists public."GV_PPP_Web_NP_Cancelada" (
  empresa    text   not null,
  order_id   bigint not null,
  np_idx     int    not null,
  np_label   text,
  motivo     text,
  por        text,
  creado_at  timestamptz not null default now(),
  primary key (empresa, order_id, np_idx)
);
alter table public."GV_PPP_Web_NP_Cancelada" enable row level security;

do $do$
begin
  if not exists (select 1 from pg_policies where schemaname='public'
                   and tablename='GV_PPP_Web_NP_Cancelada' and policyname='gv_web_np_cancelada_lectura') then
    create policy gv_web_np_cancelada_lectura on public."GV_PPP_Web_NP_Cancelada"
      for select to anon, authenticated using (true);
  end if;
end $do$;

grant select on public."GV_PPP_Web_NP_Cancelada" to anon, authenticated;

-- ── 2) La cuenta de "qué mercadería vuelve", en UNA sola función ───────────────────────────
-- Estaba escrita adentro de `gv_ppp_np_desarmar` y ahora la necesita también la pantalla, para
-- poder mostrar el detalle ANTES de confirmar (pedido de Luis). Duplicar la fórmula es lo que
-- garantiza que un día digan cosas distintas, así que sale acá y el desarme la llama.
-- Validada contra la fórmula vieja sobre 80 NP (40 de ISIS + 40 web): 0 diferencias.
create or replace function public.gv_ppp_np_devolucion(p_np text, p_tanda text default null)
 returns table(cod_art text, empresa text, org_term numeric, org_exc numeric, total numeric,
               de_fact numeric, de_sep numeric, a_guardar numeric)
 language sql stable set search_path to 'public', 'pg_temp'
as $function$
with np as (
  select regexp_replace(btrim(p_np), '\.0+$', '') as np
), t as (
  select coalesce(
    nullif(btrim(coalesce(p_tanda, '')), ''),
    (select regexp_replace(btrim(p.tanda),'\s+$','') from public.gv_ppp_programacion_diaria p, np
      where regexp_replace(btrim(p.np), '\.0+$','') = np.np limit 1),
    (select btrim(w.tanda) from public."PPP_Web_Programacion" w, np
      where upper(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx)) = upper(np.np) limit 1)
  ) as tanda
), ped as (
  select public.canon_cod(i.art) ck, sum(i.cajas)::numeric cajas
    from public.gv_ppp_np_items i, np where i.np = np.np group by 1
), sal as (
  select public.canon_cod(m.cod_art) ck,
         (array_agg(m.cod_art order by length(m.cod_art)))[1] cod_art,
         (array_agg(m.empresa) filter (where m.empresa is not null))[1] empresa,
         coalesce(sum(m.delta) filter (where m.deposito = 'a_facturar'), 0)      fact,
         coalesce(sum(m.delta) filter (where m.deposito = 'separar_pedidos'), 0) sep,
         coalesce(-sum(m.delta) filter (where m.tipo = 'picking' and m.deposito = 'terminado' and m.delta < 0), 0) org_term,
         coalesce(-sum(m.delta) filter (where m.tipo = 'picking' and m.deposito = 'excedente' and m.delta < 0), 0) org_exc
    from public."Movimientos_Stock" m, t
   where upper(btrim(m.ref)) = upper(btrim(t.tanda))
   group by 1
), dev as (
  select public.canon_cod(m.cod_art) ck,
         coalesce(sum(m.delta) filter (where m.deposito = 'terminado'), 0) tt,
         coalesce(sum(m.delta) filter (where m.deposito = 'excedente'), 0) ee
    from public."Movimientos_Stock" m, t
   where m.tipo = 'desarme' and m.delta > 0
     and m.descripcion like '%(tanda ' || t.tanda || ')%'
   group by 1
), c as (
  select s.cod_art, s.empresa, s.fact, s.sep,
         greatest(s.org_term - coalesce(dv.tt, 0), 0) as org_term,
         greatest(s.org_exc  - coalesce(dv.ee, 0), 0) as org_exc,
         least(p.cajas, greatest(s.fact, 0) + greatest(s.sep, 0)) as total
    from ped p
    join sal s on s.ck = p.ck
    left join dev dv on dv.ck = p.ck
)
select c.cod_art, c.empresa, c.org_term, c.org_exc, c.total,
       least(c.total, greatest(c.fact, 0))           as de_fact,
       c.total - least(c.total, greatest(c.fact, 0)) as de_sep,
       c.total                                       as a_guardar
  from c where c.total > 0;
$function$;

-- ── 3) El PREVIO: qué se lleva puesto cancelar, sin escribir nada ─────────────────────────
-- Luis: "que pida confirmacion y que ahi avise si tiene mercadería que va a volver a A guardar
-- y que diga el detalle" + "si es parte de un pedido distribuido en muchas NPs, tiene que
-- preguntar si se quieren cancelar todas o solo esa".
create or replace function public.gv_ppp_np_cancelar_previo(p_np text)
 returns jsonb
 language plpgsql stable security definer set search_path to 'public', 'pg_temp'
as $function$
#variable_conflict use_column
declare
  v_np text := regexp_replace(upper(btrim(coalesce(p_np,''))), '\.0+$', '');
  v_out jsonb;
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Solo un supervisor puede cancelar un pedido.' using errcode='42501';
  end if;

  with nps as (
    select * from public.gv_ppp_pedido_nps(v_np)
  ),
  -- ¿Ya salió? CCN = Carga Camión, CRN = Recepción Remitos, FSS = «↩ sin salida» (volvió al
  -- depósito). Una NP con FSS POSTERIOR a su última carga NO salió: está de nuevo acá. Es el
  -- caso que trajo Luis (98668 de la D66D: cargada el 11/09, marcada sin salida el 14/09).
  ev as (
    select regexp_replace(upper(btrim(split_part(r.texto,'|',1))), '\.0+$','') np,
           max(r.ts_cliente) filter (where r.opcion = 'CCN') ccn,
           max(r.ts_cliente) filter (where r.opcion = 'CRN') crn,
           max(r.ts_cliente) filter (where r.opcion = 'FSS') fss
      from public."Registros_Produccion_Virgilio" r
     where r.opcion in ('CCN','CRN','FSS') and not public.es_legajo_test(r.legajo)
       and regexp_replace(upper(btrim(split_part(r.texto,'|',1))), '\.0+$','') in (select np from nps)
     group by 1
  ),
  det as (
    select n.*,
           coalesce(e.crn, e.ccn) is not null
             and (e.fss is null or coalesce(e.crn, e.ccn) > e.fss)     as salio,
           e.crn is not null and (e.fss is null or e.crn > e.fss)      as entregado,
           e.fss is not null and e.fss >= coalesce(e.crn, e.ccn, e.fss) as volvio,
           coalesce(st.estado, 'pendiente')                            as estado,
           d.arts, d.cajas, d.items
      from nps n
      left join ev e on e.np = n.np
      left join lateral (select estado from public.gv_ppp_np_estado(array[n.np]) limit 1) st on true
      left join lateral (
        select count(*)::int arts, coalesce(sum(v.total),0) cajas,
               coalesce(jsonb_agg(jsonb_build_object('art', v.cod_art, 'cajas', v.total)
                                  order by v.cod_art), '[]'::jsonb) items
          from public.gv_ppp_np_devolucion(n.np, n.tanda) v
      ) d on true
  )
  select jsonb_build_object(
    'np',         v_np,
    'existe',     exists (select 1 from det),
    'es_isis',    (select bool_or(es_isis) from det),
    'empresa',    (select empresa  from det where np = v_np),
    'order_id',   (select order_id from det where np = v_np),
    'tanda',      (select tanda    from det where np = v_np),
    'cod',        (select cod      from det where np = v_np),
    'razon_social', (select razon_social from det where np = v_np),
    'fecha',      (select fecha    from det where np = v_np),
    'estado',     (select estado   from det where np = v_np),
    'salio',      (select coalesce(salio, false)     from det where np = v_np),
    'entregado',  (select coalesce(entregado, false) from det where np = v_np),
    'volvio',     (select coalesce(volvio, false)    from det where np = v_np),
    'nps',        (select coalesce(jsonb_agg(jsonb_build_object(
                            'np', np, 'tanda', tanda, 'fecha', fecha, 'm3', m3, 'estado', estado,
                            'salio', coalesce(salio,false), 'entregado', coalesce(entregado,false),
                            'volvio', coalesce(volvio,false),
                            'arts', arts, 'cajas', cajas, 'items', items) order by np), '[]'::jsonb)
                     from det),
    'n_nps',      (select count(*)::int from det),
    'dev_np',     (select jsonb_build_object('arts', arts, 'cajas', cajas, 'items', items)
                     from det where np = v_np),
    'dev_todas',  (select jsonb_build_object('arts', coalesce(sum(arts),0), 'cajas', coalesce(sum(cajas),0))
                     from det)
  ) into v_out;

  return v_out;
end;
$function$;

revoke execute on function public.gv_ppp_np_cancelar_previo(text) from public, anon;
grant  execute on function public.gv_ppp_np_cancelar_previo(text) to authenticated, service_role;

-- ── 4) El desarme, con dos perillas nuevas ────────────────────────────────────────────────
--  · p_forzar  → Luis: "Se puede hacer con cualquier pedido en cualquier estado". El guard de
--                CCN/CRN sigue existiendo (si ya salió y llegó, eso se cierra con el remito),
--                pero ahora se puede pasar por arriba a sabiendas, y queda escrito en el log.
--  · p_solo_np → cancelar UN bloque de un pedido web sin matar el pedido entero.
-- Además la cuenta del stock ya no está acá: la hace `gv_ppp_np_devolucion`, que es la misma
-- que ve la pantalla antes de confirmar.
-- ⚠ La firma vieja de 5 argumentos se DROPEA a propósito: con las dos, PostgREST no sabe cuál
-- llamar (mismo precedente que `gv_ppp_tanda_mover` en la v19.32).
drop function if exists public.gv_ppp_np_desarmar(text, text, text, boolean, boolean);

create or replace function public.gv_ppp_np_desarmar(p_np text, p_justificativo text, p_por text default null,
                                                     p_vuelve boolean default false, p_a_guardar boolean default false,
                                                     p_forzar boolean default false, p_solo_np boolean default false)
 returns table(np text, es_isis boolean, tanda text, arts integer, cajas numeric, detalle text)
 language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
#variable_conflict use_column
declare
  v_np   text := regexp_replace(btrim(p_np), '\.0+$', '');
  v_just text := btrim(coalesce(p_justificativo, ''));
  v_vuelve boolean := coalesce(p_vuelve, false);
  v_ag   boolean := coalesce(p_a_guardar, false);
  v_forz boolean := coalesce(p_forzar, false);
  v_solo boolean := coalesce(p_solo_np, false);
  v_isis boolean; v_emp text; v_num int; v_oid bigint; v_idx int;
  v_tanda text; v_fe date; v_cod text; v_rs text; v_m3 numeric;
  v_items jsonb; v_dev jsonb; v_arts int := 0; v_cajas numeric := 0; v_n int;
  v_term numeric := 0; v_exc numeric := 0; v_guard numeric := 0;
  v_ccn timestamptz; v_crn timestamptz; v_fss timestamptz; v_salio boolean;
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Solo un supervisor puede desarmar un pedido.' using errcode='42501';
  end if;
  if length(v_just) < 10 then
    raise exception 'Falta el justificativo del desarme (al menos 10 caracteres): queda guardado con el registro.';
  end if;
  /* v18.91 (Thomas, 16/09) — `p_vuelve` y `p_a_guardar` JUNTOS son validos: `p_vuelve` decide
     que pasa con el PEDIDO, `p_a_guardar` que pasa con el STOCK. */

  v_isis := v_np !~* '^(LK|CH)\s*\d+';

  /* v19.34 — YA SALIO: CCN (Carga Camion) o CRN (Recepcion Remitos). Pero un FSS posterior
     («↩ sin salida») significa que esa NP VOLVIO al deposito, asi que no salio: es el caso que
     trajo Luis (98668 de la D66D, cargada el 11/09 y devuelta el 14/09). Y con `p_forzar` se
     puede cancelar igual algo que si salio — decision de Luis: "se puede hacer con cualquier
     pedido en cualquier estado" — pero queda escrito en el justificativo. */
  select max(r.ts_cliente) filter (where r.opcion = 'CCN'),
         max(r.ts_cliente) filter (where r.opcion = 'CRN'),
         max(r.ts_cliente) filter (where r.opcion = 'FSS')
    into v_ccn, v_crn, v_fss
    from public."Registros_Produccion_Virgilio" r
   where r.opcion in ('CCN','CRN','FSS')
     and regexp_replace(upper(btrim(split_part(r.texto,'|',1))), '\.0+$','') = upper(v_np)
     and not public.es_legajo_test(r.legajo);
  v_salio := coalesce(v_crn, v_ccn) is not null and (v_fss is null or coalesce(v_crn, v_ccn) > v_fss);

  if v_salio and not v_forz then
    raise exception 'La NP % ya tiene Carga Camion o Recepcion Remitos: salio. Eso se cierra con el remito, no se desarma.', v_np;
  end if;
  if v_salio then
    v_just := v_just || ' · ⚠ FORZADO: la NP ya tenia '
              || case when v_crn is not null and (v_fss is null or v_crn > v_fss)
                      then 'Recepcion Remitos' else 'Carga Camion' end || ' al cancelarla.';
  end if;

  if v_isis then
    select regexp_replace(btrim(p.tanda),'\s+$',''), nullif(left(btrim(p.fecha_entrega),10),'')::date,
           btrim(p.cod), btrim(p.razon_social), p.m3
      into v_tanda, v_fe, v_cod, v_rs, v_m3
      from public.gv_ppp_programacion_diaria p
     where regexp_replace(btrim(p.np), '\.0+$','') = v_np limit 1;
  else
    v_emp := case when upper(left(v_np,2)) = 'CH' then 'chef' else 'lk' end;
    v_num := (regexp_match(v_np, '(\d+)'))[1]::int;
    select n.order_id into v_oid from public."PPP_Web_NP" n where n.empresa = v_emp and n.np = v_num limit 1;
    select btrim(w.tanda), w.fecha_entrega, btrim(w.cod_cliente), btrim(w.razon_social), w.m3, w.np_idx
      into v_tanda, v_fe, v_cod, v_rs, v_m3, v_idx
      from public."PPP_Web_Programacion" w
     where w.empresa = v_emp and w.np = v_num limit 1;
  end if;
  if v_tanda is null then
    raise exception 'No encuentro la NP % en la programacion.', v_np;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('art', i.art, 'cajas', i.cajas, 'uxb', i.uxb, 'uni', i.uni)
                            order by i.art), '[]'::jsonb)
    into v_items from public.gv_ppp_np_items i where i.np = v_np;

  /* v18.88 (Thomas) — TODO va a `a_guardar`: nadie va a re-pickear cajas ya armadas, quedan
     esperando a que un operario las baje del piso de armado. v19.34: la cuenta vive en
     `gv_ppp_np_devolucion`, la misma que la pantalla muestra antes de confirmar. */
  drop table if exists _gv_dev;
  create temp table _gv_dev on commit drop as
  select v.cod_art, v.empresa, v.org_term, v.org_exc, v.total, v.de_fact, v.de_sep,
         0::numeric as a_term, 0::numeric as a_exc, v.a_guardar
    from public.gv_ppp_np_devolucion(v_np, v_tanda) v;

  insert into public."Movimientos_Stock" (ts, cod_art, descripcion, deposito, delta, tipo, ref, legajo, empresa)
  select now(), d.cod_art,
         case when v_ag and not v_vuelve then 'Cancelacion del pedido ' else 'Desarme del pedido ' end
           || v_np || ' (tanda ' || v_tanda || '): ' || v_just,
         x.dep, x.signo * x.cant, 'desarme', v_np, nullif(btrim(p_por), ''), d.empresa
    from _gv_dev d
    cross join lateral (values
      ('a_facturar',      -1, d.de_fact),
      ('separar_pedidos', -1, d.de_sep),
      ('terminado',        1, d.a_term),
      ('excedente',        1, d.a_exc),
      ('a_guardar',        1, d.a_guardar)
    ) as x(dep, signo, cant)
   where x.cant > 0;

  select coalesce(jsonb_agg(jsonb_build_object('art', d.cod_art, 'empresa', d.empresa,
                              'de_a_facturar', d.de_fact, 'de_separar', d.de_sep,
                              'a_gondola', d.a_term, 'a_excedente', d.a_exc, 'a_guardar', d.a_guardar,
                              'total', d.total,
                              'salio_de_terminado', d.org_term, 'salio_de_excedente', d.org_exc)
                            order by d.cod_art), '[]'::jsonb),
         count(*), coalesce(sum(d.total), 0),
         coalesce(sum(d.a_term), 0), coalesce(sum(d.a_exc), 0), coalesce(sum(d.a_guardar), 0)
    into v_dev, v_arts, v_cajas, v_term, v_exc, v_guard
    from _gv_dev d;

  if v_isis then
    if v_vuelve then
      perform public.gv_ppp_isis_desprogramar(array[v_np], 'desarmado: ' || v_just, p_por);
    else
      insert into public."NP_Canceladas" (np, motivo, legajo)
      values (v_np, case when v_ag then 'cancelado: ' else 'desarmado: ' end || v_just,
              coalesce(nullif(btrim(p_por),''), 'supervisor'))
      on conflict (np) do update set motivo = excluded.motivo, legajo = excluded.legajo;
      insert into public."GV_PPP_Prog_Override" (np, oculto, nota)
      values (v_np, true, 'v19.34 ' || to_char(now() at time zone 'America/Argentina/Buenos_Aires','YYYY-MM-DD HH24:MI')
                          || case when v_ag then ' · CANCELADO (' else ' · DESARMADO (' end
                          || v_arts || ' art / ' || v_cajas || ' cajas): ' || v_just
                          || coalesce(' · por ' || nullif(btrim(p_por),''), ''))
      on conflict (np) do update set oculto = true, nota = excluded.nota;
    end if;
  else
    if v_vuelve then
      delete from public."GV_Web_Cancelados" c where c.empresa = v_emp and c.order_id = v_oid;
      insert into public."GV_PPP_Web_Retenido" as t
        (empresa, order_id, np_idx, np, tanda_previa, fecha_previa, ya_pickeada, ya_armada, motivo, por)
      select w.empresa, w.order_id, w.np_idx, w.np,
             nullif(btrim(w.tanda), ''), w.fecha_entrega,
             exists (select 1 from public."Registros_Produccion_Virgilio" r
                      where r.opcion in ('EP','TP')
                        and upper(btrim(split_part(r.texto,'|',1))) = upper(btrim(w.tanda))
                        and not public.es_legajo_test(r.legajo)),
             exists (select 1 from public."Registros_Produccion_Virgilio" r
                      where r.opcion in ('AP','TAP')
                        and upper(btrim(split_part(r.texto,'|',1))) = upper(btrim(w.tanda))
                        and not public.es_legajo_test(r.legajo)),
             'desarmado: ' || v_just, nullif(btrim(p_por), '')
        from public."PPP_Web_Programacion" w
       where w.empresa = v_emp and w.np = v_num
         and coalesce(nullif(btrim(w.tanda), ''), '') <> ''
      on conflict (empresa, order_id, np_idx) do update
         set tanda_previa = coalesce(excluded.tanda_previa, t.tanda_previa),
             fecha_previa = coalesce(excluded.fecha_previa, t.fecha_previa),
             ya_pickeada  = excluded.ya_pickeada or t.ya_pickeada,
             ya_armada    = excluded.ya_armada   or t.ya_armada,
             motivo = excluded.motivo, por = excluded.por, creado_at = now();
    elsif v_solo then
      /* v19.34 (Luis) — CANCELAR SOLO ESTE BLOQUE. `GV_Web_Cancelados` tiene clave (empresa,
         order_id): escribir ahi mata el pedido ENTERO. Para un bloque va la tabla por NP, que
         `gv_ppp_web_armar_pendientes` saltea con el mismo pase que ya usa para lo retenido y lo
         diferido. Sin esto la NP queda con tanda=null y el cron la re-arma sola (problema 213). */
      insert into public."GV_PPP_Web_NP_Cancelada" (empresa, order_id, np_idx, np_label, motivo, por)
      values (v_emp, v_oid, v_idx, v_np, case when v_ag then 'cancelado: ' else 'desarmado: ' end || v_just,
              nullif(btrim(p_por),''))
      on conflict (empresa, order_id, np_idx) do update
         set motivo = excluded.motivo, por = excluded.por, np_label = excluded.np_label, creado_at = now();
      delete from public."GV_PPP_Web_Retenido" t
       where t.empresa = v_emp and t.order_id = v_oid and t.np_idx = v_idx;
    else
      insert into public."GV_Web_Cancelados" (empresa, order_id, np_label, motivo, por)
      values (v_emp, v_oid, v_np, case when v_ag then 'cancelado: ' else 'desarmado: ' end || v_just,
              nullif(btrim(p_por),''))
      on conflict (empresa, order_id) do update
         set motivo = excluded.motivo, por = excluded.por, np_label = excluded.np_label, creado_at = now();
      delete from public."GV_PPP_Web_Retenido" t where t.empresa = v_emp and t.order_id = v_oid;
    end if;
    update public."PPP_Web_Programacion" w
       set tanda = null, fecha_entrega = null, actualizado_at = now()
     where w.empresa = v_emp and w.np = v_num;
    get diagnostics v_n = row_count;
  end if;

  insert into public."GV_Desarmes"
    (np, empresa, es_isis, order_id, cod_cliente, razon_social, tanda, fecha_entrega, m3,
     items, stock_devuelto, justificativo, por, vuelve)
  values (v_np, coalesce(v_emp, case when upper(v_np) like 'CH%' then 'chef' else 'lk' end),
          v_isis, v_oid, v_cod, v_rs, v_tanda, v_fe, v_m3, v_items, v_dev, v_just,
          nullif(btrim(p_por),''), v_vuelve);

  return query select v_np, v_isis, v_tanda, v_arts, v_cajas,
    (case when v_cajas = 0 then 'no habia mercaderia movida: no se devolvio nada'
          else v_arts || ' articulo' || case when v_arts = 1 then '' else 's' end || ' · ' || v_cajas
               || ' caja' || case when v_cajas = 1 then '' else 's' end || ' devueltas ('
               || concat_ws(', ',
                    case when v_term  > 0 then v_term  || ' a gondola'   end,
                    case when v_exc   > 0 then v_exc   || ' a excedente' end,
                    case when v_guard > 0 then v_guard || ' a A guardar' end) || ')'
     end
     || case when v_vuelve then ' · vuelve a A Programar y el automatico NO lo va a tomar'
             when v_ag and v_solo and not v_isis then ' · NP CANCELADA: sale de la PPP; el resto del pedido sigue'
             when v_ag     then ' · pedido CANCELADO: sale de la PPP y no vuelve'
             else ' · el pedido NO vuelve' end)::text;
end;
$function$;

revoke execute on function public.gv_ppp_np_desarmar(text,text,text,boolean,boolean,boolean,boolean) from public, anon;
grant  execute on function public.gv_ppp_np_desarmar(text,text,text,boolean,boolean,boolean,boolean) to authenticated, service_role;

-- ── 5) El armador no vuelve a agarrar un bloque cancelado ─────────────────────────────────
-- Pase (a0c) de `gv_ppp_web_armar_pendientes`, calcado del (a0b) que ya existía para lo retenido.
-- Se aplica como parche de texto porque la función es larga y lo único que cambia es este pase.
-- Probado corriendo el armador de verdad: con el bloque 1 marcado, arma sólo el 2.
do $do$
declare d text; marca text; nuevo text;
begin
  d := pg_get_functiondef('public.gv_ppp_web_armar_pendientes(text,date,jsonb,jsonb)'::regprocedure);
  if d like '%GV_PPP_Web_NP_Cancelada%' then raise notice 'ya estaba'; return; end if;

  marca := '  -- (a) forzados con fecha';
  if position(marca in d) = 0 then raise exception 'no encuentro el bloque (a): la funcion cambio'; end if;

  nuevo :=
'  -- (a0c) v19.34 (Luis) -- BLOQUE CANCELADO A MANO: la NP que un supervisor cancelo con el boton
  --   "Cancelar pedido" de su fila no vuelve a entrar. Es el mismo pase que (a0b) pero para lo
  --   cancelado, y hace falta por lo mismo: la NP queda con tanda=null y sin esto el cron la
  --   re-arma en la corrida siguiente (el problema 213, ahora a nivel bloque). El pedido ENTERO
  --   cancelado ya lo frena `gv_pedidos_web_excluidos` via GV_Web_Cancelados; esta tabla es para
  --   cuando se cancelo UNA sola NP de un pedido de varias.
  p_filas := coalesce((
    select jsonb_agg(x)
      from jsonb_array_elements(p_filas) x
     where not exists (select 1 from public."GV_PPP_Web_NP_Cancelada" c
                        where c.empresa  = p_empresa
                          and c.order_id = (x->>''order_id'')::bigint
                          and c.np_idx   = (x->>''np_idx'')::int)), ''[]''::jsonb);

' || marca;

  execute replace(d, marca, nuevo);
end $do$;

-- ── 6) La que llama la pantalla: cancelar ESTA NP o TODO el pedido ────────────────────────
create or replace function public.gv_ppp_pedido_cancelar(p_np text, p_motivo text, p_por text default null,
                                                         p_todas boolean default false, p_forzar boolean default false)
 returns table(np text, tanda text, arts integer, cajas numeric, detalle text)
 language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
#variable_conflict use_column
declare
  v_np   text := regexp_replace(upper(btrim(coalesce(p_np,''))), '\.0+$', '');
  v_mot  text := btrim(coalesce(p_motivo, ''));
  v_todas boolean := coalesce(p_todas, false);
  v_just text;
  r record; v_n int := 0;
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Solo un supervisor puede cancelar un pedido.' using errcode='42501';
  end if;
  if length(v_mot) < 5 then
    raise exception 'Falta el motivo de la cancelacion: es lo unico que va a explicar esto manana.';
  end if;
  v_just := 'Cancelado desde la PPP: ' || v_mot;

  /* El alcance lo decide quien cancela (Luis: "tiene que preguntar si se quieren cancelar todas
     las NPs de ese pedido o solo esa"). Con `p_todas` van todas las NP CON TANDA del mismo
     pedido — `gv_ppp_pedido_nps` ya sabe cuales son, es la misma que usa «Cambiar de dia» — y
     ademas la marca web queda a nivel PEDIDO, asi que tampoco vuelve un bloque que todavia no
     estaba programado. Con `p_todas = false` se cancela solo este bloque y el resto del pedido
     sigue su camino. */
  for r in
    select n.np from public.gv_ppp_pedido_nps(v_np) n where v_todas
    union
    select v_np where not v_todas
    order by 1
  loop
    return query
      select d.np, d.tanda, d.arts, d.cajas, d.detalle
        from public.gv_ppp_np_desarmar(r.np, v_just, p_por,
                                       false,          -- el pedido NO vuelve a A Programar: se cancelo
                                       true,           -- y lo armado va a «A guardar»
                                       coalesce(p_forzar, false),
                                       not v_todas) d; -- solo este bloque, o el pedido entero
    v_n := v_n + 1;
  end loop;

  if v_n = 0 then
    raise exception 'No encuentro la NP % en la programacion.', v_np;
  end if;
end;
$function$;

revoke execute on function public.gv_ppp_pedido_cancelar(text,text,text,boolean,boolean) from public, anon;
grant  execute on function public.gv_ppp_pedido_cancelar(text,text,text,boolean,boolean) to authenticated, service_role;
