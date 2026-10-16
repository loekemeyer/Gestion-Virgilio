/* v31.89 (Luis, 16/10/2026) — PEDIDOS ANÓMALOS
   Caso testigo: LK 0364 (Emotiti, cod 4288) pidió 48 cajas de 525E (uxb 24): 48 = 2 × 24, quiso
   decir 2 cajas. Se corrigió a mano. Esto lo detecta solo y lo anuncia en la PPP, en la fila del día.

   TRES REGLAS, por línea (artículo) de cada NP que espera en la PPP (con fecha de hoy en adelante,
   o todavía sin fecha):
   1. historial  — el cliente tiene 3 o más pedidos en los 12 meses previos: si su promedio de cajas
                   cuando compra ESE artículo es < 5, el pedido nuevo no puede pasar de promedio × 5
                   (500 %). Si pasa → CONTACTAR (lo maneja el bot de GestOpClientes).
   2. em         — el cliente tiene menos de 3 pedidos: se compara contra la Est. Madre (proy_cajas_mes
                   de stocks_carga_rapida). Peso del artículo en el pedido / peso del artículo en la
                   E.M. de los artículos del pedido ≥ 5 (500 %) y al menos 10 cajas → CONTACTAR.
   3. cajas_uxb  — el mismo chequeo que muestra la página al cargar (cajasHintHtml): cajas múltiplo
                   del uxb (uxb > 1). SÓLO CARTEL en la PPP, no se contacta.

   Historia de pedidos (igual que gv_isis_estad_pedidos_disruptivos, v26.20): pedidos web
   (lk_pedidos_match, un pedido = order_id o su pedido_origen) y, antes de que existiera la web de
   esa empresa, las facturas de ISIS (una factura = un pedido). Sin cancelados, anulados ni clientes
   de prueba.

   Parámetros en PPP_Web_Config (cambiarlos es un UPDATE, no un deploy):
     anomalo_hist_min_pedidos (3) · anomalo_hist_prom_max (5) · anomalo_hist_factor (5)
     anomalo_em_factor (5) · anomalo_em_piso_cajas (10) · anomalo_uxb_activo (1 = sí)

   Piezas:
     GV_Pedido_Anomalo                    una fila por (NP, artículo, regla); estado del contacto
     gv_ppp_anomalos_calc(p_desde)        cálculo puro (STABLE), no escribe
     gv_ppp_anomalos_detectar()           upsert + pasa a 'sin_efecto' lo que ya no da; cron 92
     gv_ppp_anomalos_lista(p_desde)       lo que lee la PPP (supervisor)
     gv_pedido_anomalo_bot_pendientes()   cola para el bot (servicio)
     gv_pedido_anomalo_bot_marcar(...)    el bot / el supervisor cambia el estado
   Medido el 16/10 (NP con entrega desde el 06/09, 476 NP / 5.426 líneas): historial 18 líneas,
   em 9, cajas_uxb 176 líneas en 100 NP (21 % de las NP). */

-- 1) parámetros ----------------------------------------------------------------------------
insert into public."PPP_Web_Config" (clave, valor, descripcion, actualizado) values
  ('anomalo_hist_min_pedidos', 3,  'Pedidos anómalos: desde cuántos pedidos previos (12 meses) se usa el historial del cliente', now()),
  ('anomalo_hist_prom_max',    5,  'Pedidos anómalos: el historial se evalúa si el promedio del artículo es menor a esto (cajas)', now()),
  ('anomalo_hist_factor',      5,  'Pedidos anómalos: anómalo si pide más que promedio × esto (5 = 500 %)', now()),
  ('anomalo_em_factor',        5,  'Pedidos anómalos (cliente con pocos pedidos): peso en el pedido / peso en la Est. Madre (5 = 500 %)', now()),
  ('anomalo_em_piso_cajas',   10,  'Pedidos anómalos (Est. Madre): mínimo de cajas de la línea para marcarla', now()),
  ('anomalo_uxb_activo',       1,  'Pedidos anómalos: 1 = marcar en la PPP las cajas múltiplo del uxb (sólo cartel)', now())
on conflict (clave) do nothing;

-- 2) tabla -----------------------------------------------------------------------------------
create table if not exists public."GV_Pedido_Anomalo" (
  id             bigserial primary key,
  empresa        text not null,
  order_id       bigint not null,
  np_idx         integer not null,
  np             integer,
  np_label       text,
  cod_cliente    text,
  razon_social   text,
  articulo       text not null,
  cajas          numeric not null,
  regla          text not null check (regla in ('historial','em','cajas_uxb')),
  referencia     numeric,          -- historial: promedio · em: peso relativo · cajas_uxb: uxb
  limite         numeric,          -- historial: cajas máximas · em: factor · cajas_uxb: null
  pedidos_previos integer,
  detalle        text,
  contactar      boolean not null default false,
  estado         text not null default 'pendiente'
                 check (estado in ('pendiente','contactado','confirmado','corregido','descartado','sin_efecto')),
  detectado_at   timestamptz not null default now(),
  actualizado_at timestamptz not null default now(),
  contacto_at    timestamptz,
  contacto_nota  text,
  resuelto_por   text,
  unique (empresa, order_id, np_idx, articulo, regla)
);
alter table public."GV_Pedido_Anomalo" enable row level security;   -- sin policies: sólo por las RPC
revoke all on public."GV_Pedido_Anomalo" from anon, authenticated;
create index if not exists gv_pedido_anomalo_estado_idx on public."GV_Pedido_Anomalo" (estado) where estado in ('pendiente','contactado');

-- 3) cálculo puro ----------------------------------------------------------------------------
create or replace function public.gv_ppp_anomalos_calc(p_desde date default null)
returns table (empresa text, order_id bigint, np_idx integer, np integer, np_label text, cod_cliente text,
               razon_social text, fecha_entrega date, articulo text, cajas numeric, regla text,
               referencia numeric, limite numeric, pedidos_previos integer, detalle text, contactar boolean)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $function$
/* v31.89 — marcador: anomalos-v3189 (ver cabecera de sql/gv_ppp_pedidos_anomalos_v3189.sql) */
with par as (
  select coalesce(p_desde, (now() at time zone 'America/Argentina/Buenos_Aires')::date) desde,
         coalesce((select valor from "PPP_Web_Config" where clave='anomalo_hist_min_pedidos'), 3) hmin,
         coalesce((select valor from "PPP_Web_Config" where clave='anomalo_hist_prom_max'), 5)    hprom,
         coalesce((select valor from "PPP_Web_Config" where clave='anomalo_hist_factor'), 5)      hfac,
         coalesce((select valor from "PPP_Web_Config" where clave='anomalo_em_factor'), 5)        efac,
         coalesce((select valor from "PPP_Web_Config" where clave='anomalo_em_piso_cajas'), 10)   episo,
         coalesce((select valor from "PPP_Web_Config" where clave='anomalo_uxb_activo'), 1) = 1   uxb_on),
/* lo que espera en la PPP: con fecha de hoy en adelante o todavía sin fecha (A Programar) */
c as (
  select p.empresa, p.order_id, p.np_idx, p.np, regexp_replace(btrim(coalesce(p.cod_cliente,'')), '^0+(?=.)', '') cli,
         p.razon_social, p.fecha_entrega, upper(btrim(b.articulo)) art, b.cajas,
         coalesce(m.fecha_pedido, p.creado_at::date) fped
    from "PPP_Web_Programacion" p
    join "PPP_Web_Base" b on b.empresa = p.empresa and b.order_id = p.order_id and b.np_idx = p.np_idx
    left join lk_pedidos_match m on m.empresa = p.empresa and m.order_id = p.order_id, par
   where b.cajas > 0
     and (p.fecha_entrega >= par.desde or (p.fecha_entrega is null and p.creado_at >= now() - interval '30 days'))
     and not exists (select 1 from "GV_Clientes_Prueba" pr
                      where lower(btrim(pr.empresa)) in (p.empresa, case p.empresa when 'chef' then 'ch' end)
                        and regexp_replace(btrim(pr.cod), '^0+', '') = regexp_replace(btrim(coalesce(p.cod_cliente, '')), '^0+', ''))),
cli_set as (select distinct empresa, cli from c),
/* historia: pedidos web */
m as (
  select x.empresa, coalesce(x.pedido_origen, x.order_id) pedido, x.fecha_pedido,
         regexp_replace(btrim(coalesce(x.cod_cliente,'')), '^0+(?=.)', '') cli, x.items_string
    from lk_pedidos_match x
   where x.fecha_pedido >= current_date - 400
     and not exists (select 1 from "GV_Web_Cancelados" wc where wc.empresa = x.empresa and wc.order_id = x.order_id)
     and not exists (select 1 from "GV_Pedidos_Anulados" pa where pa.empresa = x.empresa and pa.order_id = x.order_id)),
pw as (
  select m.empresa, m.cli, m.pedido::text pedido, min(m.fecha_pedido) fecha,
         regexp_replace(regexp_replace(upper(btrim(z.r[1])), '·.*$', ''), '\s+(LK|CH|LOKE)$', '') cod, sum((z.r[2])::numeric) cajas
    from m
    join cli_set cs on cs.empresa = m.empresa and cs.cli = m.cli
    cross join lateral unnest(string_to_array(coalesce(m.items_string, ''), ',')) t(item)
    cross join lateral (select regexp_match(btrim(t.item), '^(.+)x([0-9]+(?:\.[0-9]+)?)$') r) z
   where z.r is not null
   group by 1, 2, 3, 5),
/* historia: facturas de ISIS del tramo sin web */
ws as (select x.empresa, min(x.fecha_pedido) web_desde from lk_pedidos_match x group by 1),
fd as (
  select 'lk'::text empresa, x.id, x.fecha, regexp_replace(btrim(coalesce(x.contraparte_codigo,'')), '^0+(?=.)', '') cli
    from isis_lk.documentos x join ws on ws.empresa = 'lk'
   where x.familia = 'factura_venta' and x.fecha >= current_date - 400 and x.fecha < ws.web_desde
  union all
  select 'chef', x.id, x.fecha, regexp_replace(btrim(coalesce(x.contraparte_codigo,'')), '^0+(?=.)', '')
    from isis_ch.documentos x join ws on ws.empresa = 'chef'
   where x.familia = 'factura_venta' and x.fecha >= current_date - 400 and x.fecha < ws.web_desde),
fdc as (select fd.* from fd join cli_set cs on cs.empresa = fd.empresa and cs.cli = fd.cli),
pf as (
  select fdc.empresa, fdc.cli, 'fc' || fdc.id pedido, fdc.fecha, upper(btrim(i.codigo_articulo)) cod, sum(i.cantidad_caja) cajas
    from fdc join isis_lk.documento_items i on i.documento_id = fdc.id
   where fdc.empresa = 'lk' and coalesce(i.cantidad_caja, 0) > 0 group by 1, 2, 3, 4, 5
  union all
  select fdc.empresa, fdc.cli, 'fc' || fdc.id, fdc.fecha, upper(btrim(i.codigo_articulo)), sum(i.cantidad_caja)
    from fdc join isis_ch.documento_items i on i.documento_id = fdc.id
   where fdc.empresa = 'chef' and coalesce(i.cantidad_caja, 0) > 0 group by 1, 2, 3, 4, 5),
h as (select pw.empresa, pw.cli, pw.pedido, pw.fecha, pw.cod, pw.cajas from pw
      union all select pf.empresa, pf.cli, pf.pedido, pf.fecha, pf.cod, pf.cajas from pf where pf.cli <> ''),
hp as (select h.empresa, h.cli, h.pedido, min(h.fecha) fecha from h group by 1, 2, 3),
/* pedidos previos del cliente (cualquier artículo), 12 meses antes del pedido */
np_ as (select o.empresa, o.order_id, count(distinct hp.pedido)::int nped
          from (select distinct c.empresa, c.order_id, c.cli, c.fped from c) o
          left join hp on hp.empresa = o.empresa and hp.cli = o.cli
                      and hp.fecha < o.fped and hp.fecha >= o.fped - interval '12 months'
         group by 1, 2),
/* historia del artículo para ese cliente */
na as (select c.empresa, c.order_id, c.np_idx, c.art, count(h.pedido)::int nart, avg(h.cajas) prom
         from c left join h on h.empresa = c.empresa and h.cli = c.cli and h.cod = c.art
                           and h.fecha < c.fped and h.fecha >= c.fped - interval '12 months'
        group by 1, 2, 3, 4),
ux as (select regexp_replace(btrim(u.cod), '^0+(?=.)', '') base, max(u.uxb) uxb from vista_uxb_articulo u where u.uxb > 0 group by 1),
/* Est. Madre: el secundario usa la de su principal; dual LK/CH por empresa (la L es LK) */
em0 as (select s.cod, coalesce(nullif(pr.proy_cajas_mes, 0), s.proy_cajas_mes, 0) em
          from stocks_carga_rapida s left join stocks_carga_rapida pr on pr.cod = s.familia_principal),
y as (
  select c.*, np_.nped, na.nart, na.prom, ux.uxb, nullif(coalesce(e1.em, e2.em), 0) em
    from c
    join np_ on np_.empresa = c.empresa and np_.order_id = c.order_id
    join na on na.empresa = c.empresa and na.order_id = c.order_id and na.np_idx = c.np_idx and na.art = c.art
    left join ux on ux.base = regexp_replace(regexp_replace(c.art, '^0+(?=.)', ''), '([0-9E])L$', '\1')
    left join em0 e1 on e1.cod = regexp_replace(c.art, '([0-9E])L$', '\1')
                              || case when c.art ~ '[0-9E]L$' or c.empresa = 'lk' then ' LK' else ' CH' end
    left join em0 e2 on e2.cod = regexp_replace(c.art, '([0-9E])L$', '\1')),
/* el peso se mide sobre el PEDIDO entero (todas sus NP), sólo con artículos que tienen E.M. */
z as (
  select y.*, sum(y.cajas) filter (where y.em is not null) over (partition by y.empresa, y.order_id) tot,
              sum(y.em) over (partition by y.empresa, y.order_id) emtot
    from y),
r as (
  select z.*, case when z.em is not null and z.tot > 0 and z.emtot > 0 then (z.cajas / z.tot) / (z.em / z.emtot) end peso
    from z)
select r.empresa, r.order_id, r.np_idx, r.np, gv_ppp_web_np_label(r.empresa, r.np), r.cli, r.razon_social, r.fecha_entrega,
       r.art, r.cajas, 'historial'::text, round(r.prom, 2), r.prom * par.hfac, r.nped,
       format('Pidió %s cj de %s; su promedio es %s cj (%s pedido%s con el artículo, %s pedidos en 12 meses). Tope ×%s = %s cj',
              r.cajas, r.art, replace(round(r.prom, 1)::text, '.', ','), r.nart, case when r.nart = 1 then '' else 's' end, r.nped, par.hfac, replace(round(r.prom * par.hfac, 1)::text, '.', ',')),
       true
  from r, par
 where r.nped >= par.hmin and r.nart > 0 and r.prom < par.hprom and r.cajas > r.prom * par.hfac
union all
select r.empresa, r.order_id, r.np_idx, r.np, gv_ppp_web_np_label(r.empresa, r.np), r.cli, r.razon_social, r.fecha_entrega,
       r.art, r.cajas, 'em', round(r.peso, 2), par.efac, r.nped,
       format('Pidió %s cj de %s = %s %% del pedido; en la Est. Madre ese artículo pesa %s %% de lo que pidió (%s cj/mes). Desbalance ×%s (tope ×%s). Cliente con %s pedido%s previo%s',
              r.cajas, r.art, round(100 * r.cajas / r.tot), replace(round(100 * r.em / r.emtot, 1)::text, '.', ','), r.em, replace(round(r.peso, 1)::text, '.', ','), par.efac,
              r.nped, case when r.nped = 1 then '' else 's' end, case when r.nped = 1 then '' else 's' end),
       true
  from r, par
 where r.nped < par.hmin and r.peso >= par.efac and r.cajas >= par.episo
union all
select r.empresa, r.order_id, r.np_idx, r.np, gv_ppp_web_np_label(r.empresa, r.np), r.cli, r.razon_social, r.fecha_entrega,
       r.art, r.cajas, 'cajas_uxb', r.uxb, null::numeric, r.nped,
       format('Pidió %s cj de %s y la caja trae %s u.: ¿quiso decir %s cj (%s unidades)?',
              r.cajas, r.art, round(r.uxb), round(r.cajas / r.uxb), r.cajas),
       false
  from r, par
 where par.uxb_on and r.uxb > 1 and r.cajas >= r.uxb and mod(r.cajas, r.uxb) = 0;
$function$;
revoke all on function public.gv_ppp_anomalos_calc(date) from public, anon, authenticated;

-- 4) detector (cron) -------------------------------------------------------------------------
create or replace function public.gv_ppp_anomalos_detectar()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $function$
/* v31.89 — anomalos-v3189. Graba lo nuevo, refresca lo que sigue y pasa a 'sin_efecto' lo pendiente
   que ya no da (se corrigió el pedido, se canceló o ya salió). Lo que el bot/supervisor ya movió
   (contactado, confirmado, corregido, descartado) no se toca. */
declare v_nuevos int; v_sin int;
begin
  create temp table _anom on commit drop as select * from public.gv_ppp_anomalos_calc(null);

  with ins as (
    insert into "GV_Pedido_Anomalo" as g (empresa, order_id, np_idx, np, np_label, cod_cliente, razon_social, articulo,
                                     cajas, regla, referencia, limite, pedidos_previos, detalle, contactar)
    select a.empresa, a.order_id, a.np_idx, a.np, a.np_label, a.cod_cliente, a.razon_social, a.articulo,
           a.cajas, a.regla, a.referencia, a.limite, a.pedidos_previos, a.detalle, a.contactar
      from _anom a
    on conflict (empresa, order_id, np_idx, articulo, regla) do update
       set np = excluded.np, np_label = excluded.np_label, cajas = excluded.cajas, referencia = excluded.referencia,
           limite = excluded.limite, pedidos_previos = excluded.pedidos_previos, detalle = excluded.detalle,
           estado = case when g.estado = 'sin_efecto' then 'pendiente' else g.estado end,
           actualizado_at = now()
       where (g.cajas, g.detalle, g.estado) is distinct from (excluded.cajas, excluded.detalle, case when g.estado = 'sin_efecto' then 'pendiente' else g.estado end)
    returning (xmax = 0) nuevo)
  select count(*) filter (where nuevo) into v_nuevos from ins;

  update "GV_Pedido_Anomalo" g set estado = 'sin_efecto', actualizado_at = now()
   where g.estado = 'pendiente'
     and not exists (select 1 from _anom a where a.empresa = g.empresa and a.order_id = g.order_id
                       and a.np_idx = g.np_idx and a.articulo = g.articulo and a.regla = g.regla);
  get diagnostics v_sin = row_count;

  return jsonb_build_object('vigentes', (select count(*) from _anom), 'nuevos', v_nuevos, 'sin_efecto', v_sin);
end;
$function$;
revoke all on function public.gv_ppp_anomalos_detectar() from public, anon, authenticated;

-- 5) lo que lee la PPP -----------------------------------------------------------------------
create or replace function public.gv_ppp_anomalos_lista(p_desde date default null)
returns table (id bigint, empresa text, order_id bigint, np_idx integer, np_label text, cod_cliente text, razon_social text,
               fecha_entrega date, articulo text, cajas numeric, regla text, detalle text, contactar boolean,
               estado text, contacto_nota text)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $function$
/* v31.89 — anomalos-v3189. La fecha es la de HOY de la programación (una NP que se movió de día
   lleva su cartel al día nuevo). Se ven pendientes y contactados: confirmado / corregido /
   descartado ya no son anomalías abiertas. */
select g.id, g.empresa, g.order_id, g.np_idx, gv_ppp_web_np_label(p.empresa, p.np), p.cod_cliente, p.razon_social,
       p.fecha_entrega, g.articulo, g.cajas, g.regla, g.detalle, g.contactar, g.estado, g.contacto_nota
  from "GV_Pedido_Anomalo" g
  join "PPP_Web_Programacion" p on p.empresa = g.empresa and p.order_id = g.order_id and p.np_idx = g.np_idx
 where g.estado in ('pendiente','contactado')
   and (p.fecha_entrega is null or p.fecha_entrega >= coalesce(p_desde, (now() at time zone 'America/Argentina/Buenos_Aires')::date))
   and (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
 order by p.fecha_entrega nulls last, 5, g.articulo;
$function$;
revoke all on function public.gv_ppp_anomalos_lista(date) from public, anon;
grant execute on function public.gv_ppp_anomalos_lista(date) to authenticated;

-- 6) contrato con el bot (GestOpClientes, Pablo) ---------------------------------------------
create or replace function public.gv_pedido_anomalo_bot_pendientes()
returns table (empresa text, order_id bigint, np_label text, cod_cliente text, razon_social text, fecha_entrega date,
               ids bigint[], lineas jsonb, detectado_at timestamptz)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $function$
/* v31.89 — anomalos-v3189. Una fila por PEDIDO con todas sus líneas a confirmar con el cliente
   (sólo reglas que contactan: historial y em). El bot manda por wa_outbox de LK (vasectomía:
   la llave wa_envio_automatico manda) y después llama a gv_pedido_anomalo_bot_marcar. */
select g.empresa, g.order_id, string_agg(distinct gv_ppp_web_np_label(p.empresa, p.np), ' · '), max(p.cod_cliente),
       max(p.razon_social), min(p.fecha_entrega), array_agg(g.id order by g.id),
       jsonb_agg(jsonb_build_object('id', g.id, 'articulo', g.articulo, 'cajas', g.cajas, 'regla', g.regla, 'detalle', g.detalle) order by g.articulo),
       min(g.detectado_at)
  from "GV_Pedido_Anomalo" g
  join "PPP_Web_Programacion" p on p.empresa = g.empresa and p.order_id = g.order_id and p.np_idx = g.np_idx
 where g.contactar and g.estado = 'pendiente' and gv_es_supervisor_o_servicio()
 group by g.empresa, g.order_id
 order by min(g.detectado_at);
$function$;
revoke all on function public.gv_pedido_anomalo_bot_pendientes() from public, anon, authenticated;

create or replace function public.gv_pedido_anomalo_bot_marcar(p_ids bigint[], p_estado text, p_nota text default null, p_por text default null)
returns integer
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $function$
/* v31.89 — anomalos-v3189. contactado (se le escribió) · confirmado (el cliente dijo que está bien)
   · corregido (el pedido se cambió) · descartado (no era anomalía). */
declare n int;
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Sin permiso';
  end if;
  if p_estado not in ('contactado','confirmado','corregido','descartado') then
    raise exception 'Estado inválido: %', p_estado;
  end if;
  update "GV_Pedido_Anomalo"
     set estado = p_estado, contacto_nota = coalesce(p_nota, contacto_nota), actualizado_at = now(),
         contacto_at = case when p_estado = 'contactado' then now() else contacto_at end,
         resuelto_por = coalesce(p_por, auth.jwt() ->> 'email', session_user)
   where id = any (p_ids);
  get diagnostics n = row_count;
  return n;
end;
$function$;
revoke all on function public.gv_pedido_anomalo_bot_marcar(bigint[], text, text, text) from public, anon;
grant execute on function public.gv_pedido_anomalo_bot_marcar(bigint[], text, text, text) to authenticated;

-- 7) cron 167 (minuto por fórmula, 3 jobs en cada minuto 8/18/…/58, anti-solape) -----------
select cron.schedule('gv-ppp-anomalos', '8-59/10 * * * *',
 $c$do $b$ begin if pg_try_advisory_xact_lock(hashtext('cron:gv_ppp_anomalos_detectar')::bigint) then perform public.gv_ppp_anomalos_detectar(); end if; end $b$;$c$);

-- 8) centinela: las tres reglas no se pueden perder ------------------------------------------
insert into "GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version, activo) values
('gv_ppp_anomalos_calc','funcion','r\.prom < par\.hprom and r\.cajas > r\.prom \* par\.hfac','pedido anomalo por historial: cliente con 3+ pedidos y promedio del articulo < 5 cj -> anomalo si pide mas que promedio x5 (contactar)','Luis','v31.89',true),
('gv_ppp_anomalos_calc','funcion','r\.nped < par\.hmin and r\.peso >= par\.efac','pedido anomalo por Est. Madre: cliente con menos de 3 pedidos y desbalance del articulo vs la E.M. >= x5 (contactar)','Luis','v31.89',true),
('gv_ppp_anomalos_calc','funcion','mod\(r\.cajas, r\.uxb\) = 0','pedido anomalo cajas multiplo del uxb (mismo chequeo que la pagina): solo cartel en la PPP, no se contacta','Luis','v31.89',true);
