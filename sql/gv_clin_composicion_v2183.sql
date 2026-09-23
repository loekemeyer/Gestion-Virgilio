-- v21.83 (2026-09-23) — "un boton donde se pueda ver la composicion del pedido ... y que aclare
-- que incluye IVA porque es lo que tengo que reclamar al cliente que pague".
--
-- QUE FALTABA. La celda Monto del pipeline muestra DOS numeros (neto y c/IVA) y nada mas. Para
-- reclamarle el pago a un cliente nuevo hay que poder abrir el detalle: que codigos entran, a que
-- precio, cuanto descuenta el volumen, cuanto el 2 % web, y cual es el TOTAL CON IVA — que es el
-- unico numero que se le pide al cliente.
--
-- QUE NO SE TOCA. `gv_ppp_web_valor_items` NO se modifica: es el camino caliente que alimenta la
-- Cuarentena, el limite de credito y el monto del Speech 1. Esta funcion es SOLO LECTURA y se
-- llama al abrir el pop-up, no en cada render.
--
-- COMO SE EVITA QUE LAS DOS COPIAS SE DESFASEN. El front compara la SUMA de las lineas contra el
-- `valor` que ya tiene en pantalla (el que devuelve gv_clientes_nuevos_valor_lote). Si difieren en
-- mas de $1 lo dice en rojo adentro del pop-up. Es una comprobacion VIVA, no un patron de texto:
-- si alguien le cambia una regla a gv_ppp_web_valor_items y no la replica aca, se ve al abrirlo.
-- Mas la fila de centinela de abajo, que cubre el caso contrario (que le saquen la regla a esta).
--
-- POR QUE RECIBE EL LOTE ENTERO Y NO UN PEDIDO. El reparto de lo importado escaso es GREEDY por
-- (fecha, hora, order_id): cuantas cajas de un importado le tocan a este pedido depende de lo que
-- se llevaron los anteriores (`tomado_antes`). Calculado sobre un pedido solo, el cubierto sale de
-- mas. Por eso la firma toma el mismo `p_pedidos` que gv_clientes_nuevos_valor_lote y devuelve las
-- lineas de UNO — el front le pasa el mismo array que ya arma para el monto.
--
-- ⚠ El guard de identidad es el MISMO que el de la funcion canonica, asi que sin permiso devuelve
--   CERO FILAS. El front trata la lista vacia como ERROR, nunca como "el pedido no tiene nada"
--   (regla: una lectura ROTA no es un CERO).
--
-- Rollback: drop function public.gv_clin_composicion(jsonb, text, text);

CREATE OR REPLACE FUNCTION public.gv_clin_composicion(
  p_pedidos jsonb, p_empresa text, p_order_id text)
 RETURNS TABLE(
   art text, cajas numeric, cajas_ok numeric, cajas_falta numeric,
   importado boolean, uxb integer, unidades numeric, precio_unit numeric,
   bruto numeric, dto_vol numeric, dto_web numeric, importe numeric, sin_precio boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- ── de aca hasta _cp_falta: IGUAL que gv_clientes_nuevos_valor_lote (v20.46) ──────────────
  with _cp_src as (
    select nullif(trim(e->>'order_id'), '')     as order_id,
           lower(coalesce(e->>'empresa','lk'))  as empresa,
           nullif(trim(e->>'cod'), '')          as cod,
           e->'items'                           as items,
           nullif(e->>'cond','')                as cond
      from jsonb_array_elements(coalesce(p_pedidos, '[]'::jsonb)) e
     where nullif(trim(e->>'order_id'), '') is not null
  ),
  _cp_ord as materialized (
    select s.order_id, s.empresa,
           coalesce(m.fecha_pedido, '9999-12-31'::date) as f_ped,
           coalesce(m.hora_pedido, '99:99')             as h_ped
      from _cp_src s
      left join public.lk_pedidos_match m
             on m.empresa = s.empresa and m.order_id::text = s.order_id
  ),
  _cp_it as (
    select s.order_id, s.empresa, s.cod as cod_cli, s.cond,
           nullif(trim(i.e->>'art'), '')                  as art,
           coalesce((i.e->>'cajas')::numeric, 0)          as cajas,
           public.gv_cod_stock(i.e->>'art')               as codn,
           case when upper(btrim(coalesce(i.e->>'art',''))) ~ '[0-9E]L$' then 'LK'
                when s.empresa = 'chef' then 'CH' else 'LK' end as emp,
           public.gv_art_es_importado(i.e->>'art')        as imp,
           o.f_ped, o.h_ped
      from _cp_src s
      join _cp_ord o on o.order_id = s.order_id and o.empresa = s.empresa
      left join lateral jsonb_array_elements(coalesce(s.items, '[]'::jsonb)) i(e) on true
  ),
  _cp_prog as materialized (
    select d.codn, d.emp, sum(d.cajas) as cajas
      from public.gv_demanda_programada_pendiente d
     group by d.codn, d.emp
  ),
  _cp_yaprog as materialized (
    select distinct s.order_id, s.empresa
      from _cp_src s
      join public."PPP_Web_Programacion" w
        on w.empresa = s.empresa and w.order_id::text = s.order_id
      join public.gv_demanda_programada_pendiente d
        on d.np = public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx)
  ),
  _cp_libre as (
    select distinct it.codn, it.emp, it.art, it.empresa,
           greatest(0, public.gv_art_disponible(it.art, it.empresa)
                     - coalesce((select p.cajas from _cp_prog p
                                  where p.codn = it.codn and p.emp = it.emp), 0)) as libre
      from _cp_it it
     where it.imp and it.art is not null
  ),
  _cp_rep as (
    select it.*,
           coalesce((select max(l.libre) from _cp_libre l
                      where l.codn = it.codn and l.emp = it.emp), 0) as libre,
           exists (select 1 from _cp_yaprog y
                    where y.order_id = it.order_id and y.empresa = it.empresa) as ya_prog
      from _cp_it it
  ),
  _cp_greedy as (
    select r.*,
           sum(case when r.imp and not r.ya_prog then r.cajas else 0 end)
             over (partition by r.codn, r.emp
                   order by r.f_ped, r.h_ped, r.order_id
                   rows between unbounded preceding and 1 preceding) as tomado_antes
      from _cp_rep r
  ),
  _cp_falta as (
    select g.order_id, g.empresa, g.cod_cli, g.cond, g.art, g.cajas, g.imp,
           case when not g.imp or g.ya_prog or g.art is null then 0
                else greatest(0, g.cajas - greatest(0, g.libre - coalesce(g.tomado_antes, 0)))
           end as falta
      from _cp_greedy g
     where g.art is not null
  ),
  -- ── de aca en adelante: el detalle de UN pedido, con la misma cuenta de gv_ppp_web_valor_items
  _cp_ped as (
    select f.* from _cp_falta f
     where f.empresa  = lower(coalesce(nullif(trim(p_empresa),''), 'lk'))
       and f.order_id = nullif(trim(p_order_id), '')
  ),
  _cp_cli as (
    select ( select cc2.super_key
               from public.cobranzas_cliente_cadena cc2
               join public.cobranzas_super_cadena sc
                 on sc.super_key = cc2.super_key and not sc.usa_lista_general
              where cc2.empresa = case when (select min(empresa) from _cp_ped) = 'lk' then 'lk' else 'ch' end
                and cc2.cod_cliente = btrim(coalesce((select min(cod_cli) from _cp_ped), '')) limit 1) as super_key,
           ( select cd.dto_vol from public.clientes_dto cd
              where cd.cod_cliente = btrim(coalesce((select min(cod_cli) from _cp_ped), ''))
                and cd.empresa = (select min(empresa) from _cp_ped) limit 1) as dto_vol
  ),
  _cp_val as (
    select f.art, f.cajas, f.imp, f.empresa, f.cond,
           greatest(0, f.cajas - f.falta) as cajas_ok, f.falta,
           (f.empresa = 'chef' and public.canon_cod(f.art) ~ '^[0-9]+E?L$') as es_l,
           case when f.empresa = 'chef' and public.canon_cod(f.art) ~ '^[0-9]+E?L$'
                then regexp_replace(public.canon_cod(f.art),'L$','')
                else public.canon_cod(f.art) end as cod_precio,
           c.super_key,
           case when c.super_key is not null then 0 else coalesce(c.dto_vol, 0) end as dto_vol,
           case when c.super_key is not null then 1.0
                when nullif(trim(coalesce(f.cond,'')),'') in ('8','9','10','11','12','13','18') then 0.98
                else 1.0 end as factor_web
      from _cp_ped f cross join _cp_cli c
  ),
  _cp_px as (
    select v.art, v.cajas, v.cajas_ok, v.falta, v.imp, v.dto_vol, v.factor_web,
           coalesce(ps.precio_unit, pv.precio_unit, pc.precio_unit) as precio,
           coalesce(ps.uxb, (select max(g.uxb) from public."GV_UxB" g
                              where public.gv_cod_stock(g.cod) = public.gv_cod_stock(v.cod_precio)
                                and g.uxb > 0), 1) as uxb
      from _cp_val v
      left join public.precios_venta pv
             on (v.empresa <> 'chef' or v.es_l) and public.canon_cod(pv.cod) = v.cod_precio
      left join public.precios_venta_chef pc
             on v.empresa = 'chef' and public.canon_cod(pc.cod) = v.cod_precio
      left join public.cobranzas_precios_super ps
             on v.super_key is not null and ps.super_key = v.super_key
                and ps.nc = public.cob_norm_cod(v.art)
  )
  select x.art,
         x.cajas,
         x.cajas_ok,
         x.falta,
         x.imp,
         x.uxb::int,
         round(x.cajas_ok * x.uxb::numeric, 2),
         round(coalesce(x.precio, 0), 2),
         round(case when x.precio is not null and x.precio > 0
                    then x.cajas_ok * x.uxb::numeric * x.precio else 0 end, 2),
         round(x.dto_vol, 4),
         round(1 - x.factor_web, 4),
         -- ⚠ EXACTAMENTE la linea de gv_ppp_web_valor_items: el redondeo va al final, igual que alla
         round(case when x.precio is not null and x.precio > 0
                    then x.cajas_ok * x.uxb::numeric * x.precio * (1 - x.dto_vol) * x.factor_web
                    else 0 end, 2),
         (x.precio is null or x.precio <= 0)
    from _cp_px x
   where es_supervisor_virgilio() or gv_es_supervisor_o_servicio()
   order by x.art;
$function$;

revoke all on function public.gv_clin_composicion(jsonb, text, text) from public;
grant execute on function public.gv_clin_composicion(jsonb, text, text) to anon, authenticated, service_role;

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_clin_composicion','funcion',
        'x\.cajas_ok \* x\.uxb::numeric \* x\.precio \* \(1 - x\.dto_vol\) \* x\.factor_web',
        'La composicion del pedido se valoriza con la MISMA cuenta que gv_ppp_web_valor_items (cajas x uxb x precio x (1-dto_vol) x factor_web). Si una de las dos cambia y la otra no, el pop-up muestra un total distinto del que se le reclama al cliente.',
        'pedido del chat','v21.83')
on conflict do nothing;

notify pgrst, 'reload schema';
