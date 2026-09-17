-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- v19.37 (2026-09-17) — CANCELAR / DESARMAR UNA NP QUE YA SALIÓ DEL ESPEJO DE ISIS
--
-- Lo reportó Luis con una captura: en *Pedidos atrasados*, tocar **✕ Cancelar pedido** en la
-- NP **98507** (tanda D53C, Perez Zarate, facturada el 01/09) contestaba
-- *"No encuentro la NP 98507 en la programación"*. Su pregunta fue la correcta:
-- **"¿cómo está en pedido atrasado si no tiene la NP?"**
--
-- ⚠ LA CAUSA: EL ESPEJO DE ISIS ES AMNÉSICO. `gv_ppp_programacion_diaria` sólo trae lo que ISIS
-- tiene cargado HOY, así que una NP de hace 16 días ya no está ahí. El ÁRBOL de la PPP
-- (`gv_ppp_prog_arbol`) lo sabe y usa CUATRO fuentes, con prioridad:
--
--   1. `PPP_Web_Programacion`          → origen 'web'
--   2. `gv_ppp_programacion_diaria`    → origen 'isis'
--   3. `Facturacion_NP`                → origen 'fact'   ← la que faltaba
--   4. `GV_PPP_Entregados_Historico`   → origen 'hist'   ← y ésta
--
-- `gv_ppp_pedido_nps`, `gv_ppp_np_devolucion` y `gv_ppp_np_desarmar` sólo miraban las DOS
-- primeras. Medido el 17/09 sobre Pedidos atrasados: **21 de 31 NP tienen origen 'fact'** y 1
-- tiene 'hist', o sea que **dos tercios del módulo no se podían ni cancelar ni desarmar**.
-- El de desarmar venía latente desde la v17.90; lo destapó el botón nuevo de la v19.34.
--
-- LA REGLA QUE QUEDA: **si la NP se ve en la PPP, se puede cancelar.** `gv_ppp_pedido_nps`
-- resuelve por las mismas cuatro fuentes y en el mismo orden que el árbol. Barrido de
-- verificación sobre toda la PPP (−30/+20 días, 578 NP): **578 de 578, cero agujeros**
-- (fact 314, isis 117, web 146, hist 1).
--
-- Problema 374 de `github_repo_problemas`.
--
-- ⚠ ESTE ARCHIVO ES LO QUE ESTÁ APLICADO. Verificación (md5 del cuerpo sin comentarios ni
-- espacios, el chequeo que usa el repo):
--   select p.proname, md5(regexp_replace(regexp_replace(regexp_replace(
--            p.prosrc,'/\*.*?\*/','','gs'),'--[^\n]*','','g'),'\s','','g'))
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname='public' and p.proname in ('gv_ppp_pedido_nps','gv_ppp_np_devolucion',
--          'gv_ppp_np_desarmar');
--
-- Rollback: las versiones anteriores están en `sql/gv_ppp_mover_pedido_v1932.sql`
-- (`gv_ppp_pedido_nps`) y `sql/gv_ppp_cancelar_pedido_v1934.sql` (las otras dos).
-- ═══════════════════════════════════════════════════════════════════════════════════════════

-- ── 1) Las NP de un pedido, por las CUATRO fuentes del árbol ───────────────────────────────
create or replace function public.gv_ppp_pedido_nps(p_np text)
 returns table(np text, empresa text, order_id bigint, np_idx integer, tanda text, fecha date,
               m3 numeric, cod text, razon_social text, zona text, es_isis boolean)
 language sql stable set search_path to 'public', 'pg_temp'
as $function$
with q as (select regexp_replace(upper(btrim(coalesce(p_np, ''))), '\.0+$', '') as np),
web as (
  select w.empresa, w.order_id
    from public."PPP_Web_Programacion" w, q
   where upper(btrim(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx))) = q.np
   limit 1
),
isis as (
  select regexp_replace(upper(btrim(d.np)), '\.0+$', '') np, public.gv_empresa_de_np_texto(d.np) empresa,
         null::bigint order_id, null::int np_idx, upper(btrim(coalesce(d.tanda, ''))) tanda,
         case when left(btrim(coalesce(d.fecha_entrega, '')), 10) ~ '^\d{4}-\d{2}-\d{2}$'
              then left(btrim(d.fecha_entrega), 10)::date end fecha,
         coalesce(d.m3, 0) m3, btrim(coalesce(d.cod, '')) cod, coalesce(d.razon_social, '') razon_social,
         coalesce(d.zona, '') zona, true es_isis
    from public.gv_ppp_programacion_diaria d, q
   where regexp_replace(upper(btrim(d.np)), '\.0+$', '') = q.np
     and not exists (select 1 from web)
     and coalesce(nullif(btrim(d.tanda), ''), '') <> ''
),
fact as (
  select regexp_replace(upper(btrim(f.np::text)), '\.0+$', ''), public.gv_empresa_de_np_texto(f.np::text),
         null::bigint, null::int, upper(btrim(coalesce(f.tanda, ''))), f.fecha_salida::date,
         coalesce(f.m3, 0), btrim(coalesce(f.cod_cliente, '')), coalesce(f.razon_social, ''), '', true
    from public."Facturacion_NP" f, q
   where regexp_replace(upper(btrim(f.np::text)), '\.0+$', '') = q.np
     and not exists (select 1 from web) and not exists (select 1 from isis)
     and coalesce(nullif(btrim(f.tanda), ''), '') <> ''
)
select upper(btrim(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx))), w.empresa, w.order_id,
       w.np_idx, upper(btrim(coalesce(w.tanda, ''))), w.fecha_entrega, coalesce(w.m3, 0),
       btrim(coalesce(w.cod_cliente, '')), coalesce(w.razon_social, ''), coalesce(w.zona, ''), false
  from public."PPP_Web_Programacion" w
  join web on web.empresa = w.empresa and web.order_id = w.order_id
 where coalesce(nullif(btrim(w.tanda), ''), '') <> ''
union all
select * from isis
union all
select * from fact
union all
-- (4) la última fuente del árbol: el histórico de entregados. Es 1 de las 31 NP atrasadas, pero
--     si no está acá queda un agujero: se ve en la pantalla y no se puede cancelar.
select regexp_replace(btrim(h.np), '\.0+$', ''), public.gv_empresa_de_np_texto(h.np),
       null::bigint, null::int, upper(btrim(coalesce(h.tanda, ''))),
       case when left(btrim(coalesce(h.fecha_entrega, '')), 10) ~ '^\d{4}-\d{2}-\d{2}$'
            then left(btrim(h.fecha_entrega), 10)::date end,
       coalesce(h.m3, 0), btrim(coalesce(h.cod, '')), coalesce(h.rs, ''), '', true
  from public."GV_PPP_Entregados_Historico" h, q
 where regexp_replace(btrim(h.np), '\.0+$', '') = q.np
   and not exists (select 1 from web) and not exists (select 1 from isis) and not exists (select 1 from fact)
   and coalesce(nullif(btrim(h.tanda), ''), '') <> '';
$function$;

-- ── 2) La cuenta del stock: la TANDA, por las mismas cuatro fuentes ────────────────────────
create or replace function public.gv_ppp_np_devolucion(p_np text, p_tanda text default null)
 returns table(cod_art text, empresa text, org_term numeric, org_exc numeric, total numeric,
               de_fact numeric, de_sep numeric, a_guardar numeric)
 language sql stable set search_path to 'public', 'pg_temp'
as $function$
with np as (
  select regexp_replace(btrim(p_np), '\.0+$', '') as np
), t as (
  /* La tanda, por las MISMAS cuatro fuentes que `gv_ppp_prog_arbol` y en el mismo orden: la
     programación viva primero, y después lo que ya salió del espejo de ISIS (que es amnésico). */
  select coalesce(
    nullif(btrim(coalesce(p_tanda, '')), ''),
    (select regexp_replace(btrim(p.tanda),'\s+$','') from public.gv_ppp_programacion_diaria p, np
      where regexp_replace(btrim(p.np), '\.0+$','') = np.np limit 1),
    (select btrim(w.tanda) from public."PPP_Web_Programacion" w, np
      where upper(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx)) = upper(np.np) limit 1),
    (select btrim(f.tanda) from public."Facturacion_NP" f, np
      where regexp_replace(btrim(f.np::text), '\.0+$','') = np.np
        and coalesce(nullif(btrim(f.tanda), ''), '') <> '' limit 1),
    (select btrim(h.tanda) from public."GV_PPP_Entregados_Historico" h, np
      where regexp_replace(btrim(h.np), '\.0+$','') = np.np
        and coalesce(nullif(btrim(h.tanda), ''), '') <> '' limit 1)
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

-- ── 3) El desarme, con los dos fallbacks ──────────────────────────────────────────────────
-- ⚠ Va el CREATE COMPLETO, no un parche sobre `pg_get_functiondef`. La primera versión de esto
-- era un `do $do$` con `replace()`, y eso deja el repo mintiendo: `sql/gv_ppp_cancelar_pedido_v1934.sql`
-- tiene el CREATE SIN los fallbacks, así que correr ese archivo pisaría el arreglo en silencio.
-- Es el pozo que el CLAUDE.md ya tiene escrito ("el CREATE completo va EN EL REPO").
-- **Ésta es la definición vigente de `gv_ppp_np_desarmar`**; la del v1934 quedó superada.
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
    /* v19.37 -- el espejo de ISIS es AMNESICO: solo trae lo que ISIS tiene cargado HOY, asi que
       una NP de hace dos semanas ya no esta. `gv_ppp_atrasados` ya la levanta de `Facturacion_NP`
       (origen = 'fact'), que al 17/09 son 21 de las 31 NP de Pedidos atrasados. Ultimo recurso,
       no reemplazo: si la NP esta en la programacion viva, manda esa. */
    if v_tanda is null then
      select upper(btrim(f.tanda)), f.fecha_salida::date, btrim(f.cod_cliente), btrim(f.razon_social), f.m3
        into v_tanda, v_fe, v_cod, v_rs, v_m3
        from public."Facturacion_NP" f
       where regexp_replace(btrim(f.np::text), '\.0+$','') = v_np
         and coalesce(nullif(btrim(f.tanda), ''), '') <> '' limit 1;
    end if;
    if v_tanda is null then
      select upper(btrim(h.tanda)),
             case when left(btrim(coalesce(h.fecha_entrega, '')), 10) ~ '^\d{4}-\d{2}-\d{2}$'
                  then left(btrim(h.fecha_entrega), 10)::date end,
             btrim(h.cod), btrim(h.rs), h.m3
        into v_tanda, v_fe, v_cod, v_rs, v_m3
        from public."GV_PPP_Entregados_Historico" h
       where regexp_replace(btrim(h.np), '\.0+$','') = v_np
         and coalesce(nullif(btrim(h.tanda), ''), '') <> '' limit 1;
    end if;
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
