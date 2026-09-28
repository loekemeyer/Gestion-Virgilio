-- v23.04 (Luis, 2026-09-28): "implementá la deuda por sucursal" + "en vez de 30 días hacelo 14".
-- Regla de Luis del 21/09 (CLAUDE.md, "la CUARENTENA se mide por SUCURSAL, y Retira nunca exime"):
--   si un cliente tiene direcciones A y B y debe lo de A, un pedido para B pasa sin retener.
--   1. deuda que NO se puede atribuir a una sucursal -> RETIENE
--   2. se mira TODA la deuda viva (el Excel), no una ventana
--   3. Retira nunca exime (ni el pedido que retira, ni la deuda de un retiro)
-- Cadena: comprobante del Excel -> factura ISIS -> GV_Cruce_FC_Asig -> NP -> GV_NP_Sucursal.
--
-- "OTRA sucursal" se exige PROBADA, no supuesta: el comprobante tiene NP con barrio conocido y no
-- es retiro, el pedido tiene barrio conocido y no es retiro, los BARRIOS difieren y la dirección
-- (ni la calle ni la etiqueta de la sucursal) tampoco coincide. Por qué no alcanza el dir_key a
-- secas: la NP de ISIS guarda la calle ("Libertad 6310") y la web la etiqueta ("Oriental Party SRL
-- Casa Albert") para la MISMA sucursal — comparar el dir_key las daba por distintas y liberaba.
-- Ante la duda, cuenta (retiene).
--
-- ⚠ "Misma dirección" se decide por PALABRAS COMPARTIDAS (gv_cuar_tokens: >= 5 letras o >= 3
-- dígitos, sin genéricas), no por el texto entero: la súper Matiz pide a "CD Constitucion" y su
-- NP de ISIS dice "Constitucion 1665" — comparando el texto normalizado salían como sucursales
-- distintas. Comparten "constitucion" -> misma -> retiene.
-- ⚠ La FECHA es la col B del Excel (emisión). La col A es el VENCIMIENTO y la C los días vencidos
-- (negativo = todavía no vence): Matiz salía "desde 23/10".
--
-- La deuda de un pedido = min(deuda total del cliente, deuda positiva de SU sucursal + la no
-- atribuible): un recibo/NC a cuenta baja el total pero no se reparte entre sucursales.
-- Sigue valiendo v23.03: factura sin Recepción Remitos -> no es deuda (ahora hasta 14 días).

create or replace function public.gv_cuar_norm(t text) returns text
language sql immutable parallel safe as $$
  select nullif(regexp_replace(translate(lower(coalesce(t, '')), 'áéíóúüñ', 'aeiouun'), '[^a-z0-9]', '', 'g'), '')
$$;

create or replace function public.gv_cuar_tokens(t text) returns text[]
language sql immutable parallel safe as $$
  select coalesce(array_agg(distinct w), '{}') from unnest(regexp_split_to_array(
           translate(lower(coalesce(t, '')), 'áéíóúüñ', 'aeiouun'), '[^a-z0-9]+')) w
   where (w ~ '^[a-z]{5,}' or w ~ '^[0-9]{3,}$')
     and w not in ('entrega','deposito','sucursal','local','buenos','aires','capital','federal',
                   'retira','expreso','calle','avenida','provincia','partido')
$$;

create or replace function public.gv_cuarentena_deuda_comprobantes()
returns table(empresa text, cod text, comprobante text, pendiente numeric, fecha date, np text,
              barrio_n text, tokens text[], es_retira boolean, sin_entregar boolean)
language sql stable security definer set search_path = public
as $f$
  with crn as materialized (
    select distinct split_part(r.texto, '|', 1) as np
      from public."Registros_Produccion_Virgilio" r where r.opcion = 'CRN'
  ),
  s as (
    select x.empresa, x.cod, x.comprobante, x.pendiente, x.np, x.es_retira,
           public.gv_cuar_norm(split_part(x.dir_key, '|', 2)) as barrio_n,
           public.gv_cuar_tokens(coalesce(x.direccion, '') || ' ' || coalesce(x.sucursal_entrega, '')) as tokens,
           coalesce(case when (dd.fila ->> 1) ~ '^\d{5}(\.\d+)?$'
                         then date '1899-12-30' + floor((dd.fila ->> 1)::numeric)::int end,
                    x.fecha_comprobante) as fecha
      from public.gv_cuarentena_deuda_sucursal x
      left join lateral (select d.fila from public."GV_Cuarentena_Deuda_Detalle" d
                          where d.empresa = x.empresa and d.cod = x.cod
                            and d.comprobante = x.comprobante limit 1) dd on true
  )
  select s.empresa, s.cod, s.comprobante, s.pendiente, s.fecha, s.np, s.barrio_n, s.tokens,
         s.es_retira,
         -- v23.03/v23.04: factura de mercadería que todavía no se entregó (sin CRN), hasta 14 días
         (s.np is not null and s.pendiente > 0
          and not exists (select 1 from crn c where c.np = s.np)
          and coalesce(s.fecha, current_date) >= current_date - 14)
    from s
$f$;
revoke all on function public.gv_cuarentena_deuda_comprobantes() from public, anon;
grant execute on function public.gv_cuarentena_deuda_comprobantes() to authenticated, service_role;

-- Una fila por pedido del lote. Recibe lo mismo que gv_cuarentena_marcar (+ direccion, barrio,
-- zona si vienen). Sin dirección en el lote, la toma de PPP_Web_Programacion.
create or replace function public.gv_cuarentena_deuda_pedido(p_pedidos jsonb)
returns table(order_id text, empresa text, deuda numeric, desde date, comprobantes int,
              otra_sucursal numeric, sin_entregar numeric)
language sql stable security definer set search_path = public
as $f$
  with _cdc as materialized (select * from public.gv_cuarentena_deuda_comprobantes()),
  _cdp_in as (
    select nullif(trim(e->>'order_id'), '') as order_id,
           lower(coalesce(e->>'empresa', 'lk')) as empresa,
           id.empresa as emp_ev, id.cod as cod_ev,
           coalesce(nullif(trim(e->>'direccion'), ''), w.direccion) as dir,
           coalesce(nullif(trim(e->>'barrio'), ''), w.barrio) as bar,
           coalesce(nullif(trim(e->>'zona'), ''), w.zona) as zona
      from jsonb_array_elements(coalesce(p_pedidos, '[]'::jsonb)) e
      cross join lateral public.gv_cuarentena_ident(
        lower(coalesce(e->>'empresa','lk')), nullif(trim(e->>'cod'), ''),
        coalesce(nullif(trim(e->>'order_id'), ''), '') !~* '^np') id
      left join lateral (
        select ww.direccion, ww.barrio, ww.zona from public."PPP_Web_Programacion" ww
         where ww.empresa = lower(coalesce(e->>'empresa','lk'))
           and ww.order_id::text = nullif(trim(e->>'order_id'), '')
         order by ww.np_idx limit 1) w on true
  ),
  _cdp_p as (
    select i.*, public.gv_cuar_norm(i.bar) as bar_n, public.gv_cuar_tokens(i.dir) as tokens,
           (btrim(coalesce(i.zona, '')) ~* '^retira'
            or btrim(coalesce(i.bar, '')) ~* '^retira$'
            or btrim(coalesce(i.dir, '')) ~* 'virgilio\s*2788'
            or btrim(coalesce(i.dir, '')) ~* '(^|[^a-z])retira([^a-z]|$)') as retira
      from _cdp_in i
     where i.order_id is not null
  ),
  _cdp_x as (
    select p.order_id, p.empresa, c.pendiente, c.fecha,
           (p.bar_n is not null and not p.retira
            and c.np is not null and c.barrio_n is not null and c.es_retira is false
            and c.barrio_n <> p.bar_n
            and not (c.tokens && p.tokens)) as otra,
           c.sin_entregar
      from _cdp_p p
      join _cdc c on c.empresa = p.emp_ev and c.cod = p.cod_ev
  )
  select x.order_id, x.empresa,
         round(least(coalesce(sum(x.pendiente) filter (where not x.sin_entregar), 0),
                     coalesce(sum(x.pendiente) filter (where not x.sin_entregar and x.pendiente > 0 and not x.otra), 0)), 2),
         min(x.fecha) filter (where not x.sin_entregar and x.pendiente > 0 and not x.otra),
         (count(*) filter (where not x.sin_entregar and x.pendiente > 0 and not x.otra))::int,
         round(coalesce(sum(x.pendiente) filter (where not x.sin_entregar and x.pendiente > 0 and x.otra), 0), 2),
         round(coalesce(sum(x.pendiente) filter (where x.sin_entregar), 0), 2)
    from _cdp_x x
   group by x.order_id, x.empresa
$f$;
revoke all on function public.gv_cuarentena_deuda_pedido(jsonb) from public, anon;
grant execute on function public.gv_cuarentena_deuda_pedido(jsonb) to authenticated, service_role;

-- La fecha del chip sale de la MISMA cuenta que decide la retención.
drop function if exists public.gv_cuarentena_deuda_desde(jsonb);
create function public.gv_cuarentena_deuda_desde(p_pedidos jsonb)
returns table(order_id text, empresa text, desde date, comprobantes int, sin_entregar numeric,
              otra_sucursal numeric)
language sql stable security definer set search_path = public
as $f$
  select d.order_id, d.empresa, d.desde, d.comprobantes, d.sin_entregar, d.otra_sucursal
    from public.gv_cuarentena_deuda_pedido(p_pedidos) d
   where (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
$f$;
revoke all on function public.gv_cuarentena_deuda_desde(jsonb) from public, anon;
grant execute on function public.gv_cuarentena_deuda_desde(jsonb) to authenticated, service_role;

-- marcar_calc: cambia la deuda por CLIENTE (_cde, v23.03) por la deuda por PEDIDO (_cdp).
-- Sobre la definición viva, idempotente, con raise si no matchea.
do $p$
declare
  d text := pg_get_functiondef('public.gv_cuarentena_marcar_calc(jsonb)'::regprocedure);
  a0 text := E'  -- v23.02 (Luis, 28/09): deuda EFECTIVA = sin facturas de mercaderia que todavia no se entrego (sin CRN)\n  _cde as materialized (select * from public.gv_cuarentena_deuda_efectiva()),';
  e_old text := '(select _cde.deuda from _cde where _cde.empresa = f.empresa and _cde.cod = f.cod)';
  e_new text := '(select _cdp.deuda from _cdp where _cdp.empresa = p.empresa and _cdp.order_id = p.order_id limit 1)';
begin
  if position('_cdp as materialized' in d) > 0 then raise notice 'ya aplicado'; return; end if;
  if position(a0 in d) = 0 or (length(d) - length(replace(d, e_old, ''))) / length(e_old) <> 3 then
    raise exception 'marcar_calc no matchea el texto esperado (v23.03): revisar a mano';
  end if;
  d := replace(d, a0, E'  -- v23.04 (Luis, 28/09): deuda POR PEDIDO = la de SU sucursal + la no atribuible, sin facturas sin entregar\n  _cdp as materialized (select * from public.gv_cuarentena_deuda_pedido(p_pedidos)),');
  d := replace(d, e_old, e_new);
  execute d;
end $p$;

drop function if exists public.gv_cuarentena_deuda_efectiva();

update public."GV_Reglas_Centinela"
   set patron = 'gv_cuarentena_deuda_pedido', version = 'v23.04',
       regla = 'la deuda que retiene es la del PEDIDO: su sucursal + la no atribuible, sin facturas sin Recepcion Remitos (14 dias)'
 where objeto = 'gv_cuarentena_marcar_calc' and patron = 'gv_cuarentena_deuda_efectiva';

-- El armador (gv_cuarentena_retiene_lote) también manda dirección/barrio/zona a marcar_calc.
-- Aplicado sobre la definición viva con marcador 'v23.04-suc' (idempotente).
