-- v17.88 / v17.90 (Luis, 2026-09-14) — "DESARMAR PEDIDO": sale de la PPP, queda el registro,
-- y el stock pasa a "A guardar".
--
-- Nació en la v17.88 devolviendo el stock a góndola; en la v17.90 pasó a mandarlo a `a_guardar`
-- (pedido de Luis) — el archivo está en ese estado, que es el que corre.
--
-- Pedido: *"un botón que sea un tacho de basura y que sea «Desarmar pedido» que, si se aprieta, se
-- elimina el pedido y acomoda el stock de las cajas que lo componían (tiene que saltar un pop-up de
-- ATENCIÓN, bien grande y bien notorio que avise que la acción que se está por tomar es
-- permanente)"*.
--
-- Y las tres definiciones que dio Luis cuando se le preguntó:
--   · alcance: *"se borra de la PPP, tiene que quedar registro en algún lado de que el cliente hizo
--     ese pedido. Agregá además cuando alguien aprieta el botón para desarmar el pedido que tenga
--     que poner un justificativo y que también quede guardado eso"* → NO se borra de la página de
--     LK / Chef; el pedido del cliente sigue ahí. Acá se guarda el snapshot de lo que pidió.
--   · NP de ISIS: *"ídem, se saca de la PPP, se guarda el registro. Agregá en el aviso que como es
--     de ISIS, la va a tener que borrar manualmente"* → el aviso lo da el front.
--   · stock: *"se ajusta el stock por los ítems armados en esa NP (confirmados pickeados/armados).
--     Movimiento compensatorio que explique que es por desarme de pedido armado"*.
--
-- EL CIRCUITO DEL STOCK, medido sobre E14A y E16A:
--    picking   →  terminado −N  ·  excedente −M  ·  separar_pedidos +(N+M)
--    separado  →  separar_pedidos −N  ·  a_facturar +N          (el armado / TAP)
--
-- ⚠⚠ **EL DESARME NO DEVUELVE A GÓNDOLA: MANDA TODO A `a_guardar`.** Luis, 14/09, después de ver
-- la primera versión: *"cuando se aprieta ese botón, debería ir «A guardar» el pedido para hacerlo
-- lo más limpio posible, y que un operador después lo tenga que procesar como toda la mercadería a
-- guardar, ¿no?"*. Y es lo correcto: la pantalla **📥 Guardar a góndola (MG)** lista por SALDO de
-- `a_guardar` (por código y empresa), así que el desarme aparece ahí solo, sin tocar nada más, y es
-- **el operario** el que decide si va a góndola o a excedente y con qué ubicación.
--
-- Esa decisión es justamente la que la primera versión intentaba adivinar sola, y adivinaba mal:
-- devolvía todo a `terminado`, cuando el picking reparte entre `terminado` y `excedente`. Medido en
-- E16A (LK 0049): de 370 cajas, 328 salieron de `terminado` y 42 de `excedente` — devolverlas todas
-- a `terminado` habría movido 42 cajas de un depósito al otro en silencio. (Y ese mismo dato,
-- mirado sólo por la columna `terminado`, hacía parecer que el picking había sido PARCIAL: no lo
-- era.)
--
-- **De dónde había salido cada caja igual se guarda** (`salio_de_terminado` / `salio_de_excedente`
-- en `GV_Desarmes.stock_devuelto`): es dato útil para el que después la guarda, pero no mueve
-- stock. El movimiento es: `a_facturar` (o `separar_pedidos`) −N  ·  `a_guardar` +N.
--
-- La cantidad de cada artículo es `least(lo que pide la NP, lo que la tanda tiene parado hoy)`:
-- nunca se devuelve más de lo que salió, y desarmar dos veces no duplica. ⚠ Una NP **ya facturada**
-- no tiene nada parado (el `facturado` ya vació `a_facturar`), así que el desarme la saca de la PPP
-- pero devuelve 0 cajas — el pop-up lo avisa antes.

begin;

-- ─────────────────────────────────────────────── el registro de lo que el cliente había pedido
create table if not exists public."GV_Desarmes" (
  id             bigserial primary key,
  np             text    not null,
  empresa        text,
  es_isis        boolean not null default false,
  order_id       bigint,
  cod_cliente    text,
  razon_social   text,
  tanda          text,
  fecha_entrega  date,
  m3             numeric,
  items          jsonb,           -- QUÉ PIDIÓ el cliente (el registro que pidió Luis)
  stock_devuelto jsonb,           -- qué volvió a góndola y de qué depósito
  justificativo  text    not null,
  por            text,
  creado_at      timestamptz not null default now(),
  constraint gv_desarmes_justificativo_ck check (length(btrim(justificativo)) >= 10)
);
alter table public."GV_Desarmes" enable row level security;
revoke insert, update, delete, truncate on public."GV_Desarmes" from anon, authenticated;
grant select on public."GV_Desarmes" to anon, authenticated;
do $$
begin
  if not exists (select 1 from pg_policies where schemaname='public'
                  and tablename='GV_Desarmes' and policyname='gv_desarmes_read') then
    create policy gv_desarmes_read on public."GV_Desarmes"
      for select to anon, authenticated using (true);
  end if;
end $$;

-- ───────────────────────────────────────────────────────────────────────── el desarme
create or replace function public.gv_ppp_np_desarmar(
  p_np text, p_justificativo text, p_por text default null::text)
returns table(np text, es_isis boolean, tanda text, arts integer, cajas numeric, detalle text)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
#variable_conflict use_column
declare
  v_np   text := regexp_replace(btrim(p_np), '\.0+$', '');
  v_just text := btrim(coalesce(p_justificativo, ''));
  v_isis boolean; v_emp text; v_num int; v_oid bigint;
  v_tanda text; v_fe date; v_cod text; v_rs text; v_m3 numeric;
  v_items jsonb; v_dev jsonb; v_arts int := 0; v_cajas numeric := 0; v_n int;
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Solo un supervisor puede desarmar un pedido.' using errcode='42501';
  end if;
  if length(v_just) < 10 then
    raise exception 'Falta el justificativo del desarme (al menos 10 caracteres): queda guardado con el registro.';
  end if;

  v_isis := v_np !~* '^(LK|CH)\s*\d+';

  -- si ya salió (Carga Camion o Recepcion Remitos) no se desarma: eso se cierra con el remito
  if exists (select 1 from public."Registros_Produccion_Virgilio" r
              where r.opcion in ('CCN','CRN')
                and regexp_replace(upper(btrim(split_part(r.texto,'|',1))), '\.0+$','') = upper(v_np)
                and not public.es_legajo_test(r.legajo)) then
    raise exception 'La NP % ya tiene Carga Camion o Recepcion Remitos: salio. Eso se cierra con el remito, no se desarma.', v_np;
  end if;

  -- de dónde sale el encabezado, según sea de la página o de ISIS
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
    select btrim(w.tanda), w.fecha_entrega, btrim(w.cod_cliente), btrim(w.razon_social), w.m3
      into v_tanda, v_fe, v_cod, v_rs, v_m3
      from public."PPP_Web_Programacion" w
     where w.empresa = v_emp and w.np = v_num limit 1;
  end if;
  if v_tanda is null then
    raise exception 'No encuentro la NP % en la programacion.', v_np;
  end if;

  -- (1) el registro de lo que el cliente habia pedido
  select coalesce(jsonb_agg(jsonb_build_object('art', i.art, 'cajas', i.cajas, 'uxb', i.uxb, 'uni', i.uni)
                            order by i.art), '[]'::jsonb)
    into v_items from public.gv_ppp_np_items i where i.np = v_np;

  -- (2) el stock que vuelve. DOS cosas distintas, y por eso hay cuatro columnas:
  --   de donde se DESCUENTA hoy: a_facturar si la tanda ya se armo, si no separar_pedidos;
  --   a donde VA: a `a_guardar`, para que lo procese un operario con la pantalla MG. De donde
  --   HABIA salido cada caja se guarda en el JSON, pero no mueve stock (ver la nota de arriba).
  -- La cantidad es least(lo que pide la NP, lo que la tanda tiene parado hoy).
  drop table if exists _gv_dev;
  create temp table _gv_dev on commit drop as
  with ped as (
    select public.canon_cod(i.art) ck, sum(i.cajas)::numeric cajas
      from public.gv_ppp_np_items i where i.np = v_np group by 1
  ), sal as (
    select public.canon_cod(m.cod_art) ck,
           (array_agg(m.cod_art order by length(m.cod_art)))[1] cod_art,
           (array_agg(m.empresa) filter (where m.empresa is not null))[1] empresa,
           coalesce(sum(m.delta) filter (where m.deposito = 'a_facturar'), 0)      fact,
           coalesce(sum(m.delta) filter (where m.deposito = 'separar_pedidos'), 0) sep,
           coalesce(-sum(m.delta) filter (where m.tipo = 'picking' and m.deposito = 'terminado'  and m.delta < 0), 0) org_term,
           coalesce(-sum(m.delta) filter (where m.tipo = 'picking' and m.deposito = 'excedente' and m.delta < 0), 0) org_exc
      from public."Movimientos_Stock" m
     where upper(btrim(m.ref)) = upper(btrim(v_tanda))
     group by 1
  ), c as (
    select s.cod_art, s.empresa, s.fact, s.sep, s.org_term, s.org_exc,
           least(p.cajas, greatest(s.fact, 0) + greatest(s.sep, 0)) as total
      from ped p join sal s on s.ck = p.ck
  )
  select c.cod_art, c.empresa, c.org_term, c.org_exc, c.total,
         least(c.total, greatest(c.fact, 0))           as de_fact,
         c.total - least(c.total, greatest(c.fact, 0)) as de_sep
    from c where c.total > 0;

  insert into public."Movimientos_Stock" (ts, cod_art, descripcion, deposito, delta, tipo, ref, legajo, empresa)
  select now(), d.cod_art,
         'Desarme del pedido ' || v_np || ' (tanda ' || v_tanda || '): ' || v_just,
         x.dep, x.signo * x.cant, 'desarme', v_np, nullif(btrim(p_por), ''), d.empresa
    from _gv_dev d
    cross join lateral (values
      ('a_facturar',      -1, d.de_fact),
      ('separar_pedidos', -1, d.de_sep),
      ('a_guardar',        1, d.total)
    ) as x(dep, signo, cant)
   where x.cant > 0;

  select coalesce(jsonb_agg(jsonb_build_object('art', d.cod_art, 'empresa', d.empresa,
                              'de_a_facturar', d.de_fact, 'de_separar', d.de_sep,
                              'a_guardar', d.total,
                              'salio_de_terminado', d.org_term, 'salio_de_excedente', d.org_exc)
                            order by d.cod_art), '[]'::jsonb),
         count(*), coalesce(sum(d.total), 0)
    into v_dev, v_arts, v_cajas
    from _gv_dev d;

  -- (3) sale de la PPP y queda el registro de la cancelacion, como ya hacia gv_ppp_np_cancelar
  if v_isis then
    insert into public."NP_Canceladas" (np, motivo, legajo)
    values (v_np, 'desarmado: ' || v_just, coalesce(nullif(btrim(p_por),''), 'supervisor'))
    on conflict (np) do update set motivo = excluded.motivo, legajo = excluded.legajo;
    insert into public."GV_PPP_Prog_Override" (np, oculto, nota)
    values (v_np, true, 'v17.90 ' || to_char(now() at time zone 'America/Argentina/Buenos_Aires','YYYY-MM-DD HH24:MI')
                        || ' · DESARMADO (' || v_arts || ' art / ' || v_cajas || ' cajas a guardar): ' || v_just
                        || coalesce(' · por ' || nullif(btrim(p_por),''), ''))
    on conflict (np) do update set oculto = true, nota = excluded.nota;
  else
    insert into public."GV_Web_Cancelados" (empresa, order_id, np_label, motivo, por)
    values (v_emp, v_oid, v_np, 'desarmado: ' || v_just, nullif(btrim(p_por),''))
    on conflict (empresa, order_id) do update
       set motivo = excluded.motivo, por = excluded.por, np_label = excluded.np_label, creado_at = now();
    update public."PPP_Web_Programacion" w
       set tanda = null, fecha_entrega = null, actualizado_at = now()
     where w.empresa = v_emp and w.np = v_num;
    get diagnostics v_n = row_count;
    -- un pedido desarmado no lo tiene que volver a agarrar el automatico (v17.85)
    delete from public."GV_PPP_Web_Retenido" t where t.empresa = v_emp and t.order_id = v_oid;
  end if;

  insert into public."GV_Desarmes"
    (np, empresa, es_isis, order_id, cod_cliente, razon_social, tanda, fecha_entrega, m3,
     items, stock_devuelto, justificativo, por)
  values (v_np, coalesce(v_emp, case when upper(v_np) like 'CH%' then 'chef' else 'lk' end),
          v_isis, v_oid, v_cod, v_rs, v_tanda, v_fe, v_m3, v_items, v_dev, v_just, nullif(btrim(p_por),''));

  return query select v_np, v_isis, v_tanda, v_arts, v_cajas,
    (v_arts || ' articulo' || case when v_arts = 1 then '' else 's' end || ' · ' || v_cajas
     || ' caja' || case when v_cajas = 1 then '' else 's' end || ' pasaron a A GUARDAR')::text;
end;
$function$;
revoke all on function public.gv_ppp_np_desarmar(text,text,text) from public;
grant execute on function public.gv_ppp_np_desarmar(text,text,text) to anon, authenticated;

commit;

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- ROLLBACK  (⚠ los movimientos de stock ya escritos NO se borran: se compensan con un ajuste)
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- drop function if exists public.gv_ppp_np_desarmar(text,text,text);
-- drop table    if exists public."GV_Desarmes";
-- -- para deshacer UN desarme puntual (devuelve el stock a donde estaba):
-- --   insert into public."Movimientos_Stock" (ts, cod_art, descripcion, deposito, delta, tipo, ref, empresa)
-- --   select now(), cod_art, 'rollback del desarme ' || ref, deposito, -delta, 'ajuste', ref, empresa
-- --     from public."Movimientos_Stock" where tipo = 'desarme' and ref = '<NP>';
