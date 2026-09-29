-- v24.3 — gv_cobranza_ficha(emp, cod): la ficha del cliente, con las TRES fuentes juntas
--
-- Luis (29/09): "tenemos la data de la deuda que se sube para la cuarentena, tenes acceso
-- a la facturacion y a la conciliacion. trata de conectar esas fuentes a la ficha".
--
-- Devuelve UN jsonb con cuatro bloques, en una sola vuelta de red:
--   cabecera → cliente, CUIT, localidad/provincia de entrega, retencion, ultimo pago
--   totales  → deuda, vencida, comprobantes abiertos, dias de la mas vieja, ancla del Excel
--   deuda    → GV_Cobranza_Deuda_Viva  = el Excel de deuda que se sube para la CUARENTENA
--              (el ancla) + las facturas y NC nuevas de ISIS + lo que la CONCILIACION
--              bancaria ya vio cobrado. Por eso cada fila trae `pendiente_ancla` (lo que
--              decia el Excel), `cancelado_banco` (lo que el banco cancelo, con sus recibos)
--              y `origen` (excel | isis nuevo).
--   recibos  → GV_Cobranza_Imputacion = cada pago del banco cruzado contra las facturas que
--              cancela, con dto_tomado vs dto_ganado y lo que queda a_reclamar.
--   entregas → Facturacion_NP = lo que Gestion facturo (NP, tanda, m3, dia de salida).
--
-- La consolidacion LK+CH la hace el front: llama una vez por codigo del grupo y suma.
--
-- ⚠ La empresa de una entrega sale de la NP (gv_emp_de_np), NUNCA del codigo de cliente
--    solo: el mismo numero es otro cliente en la otra empresa (regla del 16/09).
-- ⚠ Guard de supervisor adentro, como el resto de gv_cobranza_*.
--
-- Medido el 29/09 con INC (LK 1651): 27 ms como `authenticated` (timeout del rol: 8 s),
-- deuda 127.002.447, vencida 18.920.032, 7 comprobantes, 126 dias, ultimo pago 14.250.082
-- del 21/09 — los mismos numeros que muestra la pantalla.
--
-- ROLLBACK: drop function if exists public.gv_cobranza_ficha(text,text);
--           (es nueva; la ficha vuelve sola a los totales de la lista de clientes)

create or replace function public.gv_cobranza_ficha(p_emp text, p_cod text)
returns jsonb
language plpgsql stable security definer set search_path to 'public' as $fn$
declare
  v_emp text := lower(btrim(coalesce(p_emp,'')));
  v_cod text := regexp_replace(coalesce(p_cod,''),'^0+','');
  v_cab jsonb; v_deuda jsonb; v_recibos jsonb; v_entregas jsonb; v_tot jsonb;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'sin permiso';
  end if;

  /* (1) DEUDA — GV_Cobranza_Deuda_Viva: ancla del Excel que se sube para la Cuarentena
         + las facturas/NC nuevas de ISIS + lo cancelado por la conciliacion bancaria. */
  select jsonb_agg(x order by x->>'fecha' desc),
         jsonb_build_object(
           'deuda',        coalesce(sum(greatest(0,(x->>'pendiente')::numeric)),0),
           'vencida',      coalesce(sum(case when (x->>'vencido')::boolean then greatest(0,(x->>'pendiente')::numeric) else 0 end),0),
           'comprobantes', count(*) filter (where (x->>'pendiente')::numeric > 0),
           'dias_mas_vieja', coalesce(max(case when (x->>'pendiente')::numeric > 0 then (x->>'dias')::int end),0),
           'ancla',        max(x->>'ancla'))
    into v_deuda, v_tot
  from (
    select jsonb_build_object(
             'comprobante', d.comprobante, 'fecha', d.fecha, 'vence', d.vence,
             'condicion', d.condicion, 'dto_cond', d.dto_cond, 'lista', d.lista,
             'pendiente_ancla', d.pendiente_ancla, 'cancelado_banco', d.cancelado_banco,
             'pendiente', d.pendiente, 'origen', d.origen, 'recibos_banco', d.recibos_banco,
             'dias', (current_date - d.fecha),
             'vencido', (d.vence is not null and d.vence < current_date and coalesce(d.pendiente,0) > 0),
             'ancla', d.ancla) as x
      from public."GV_Cobranza_Deuda_Viva" d
     where d.empresa = v_emp and regexp_replace(coalesce(d.cod_cliente,''),'^0+','') = v_cod
       and coalesce(d.pendiente,0) <> 0
  ) z;

  /* (2) RECIBOS — GV_Cobranza_Imputacion: cada pago de la conciliacion bancaria
         cruzado contra las facturas que cancela, con el descuento tomado vs el ganado. */
  select jsonb_agg(x order by x->>'fecha_pago' desc)
    into v_recibos
  from (
    select jsonb_build_object(
             'recibo', i.recibo, 'fecha_pago', i.fecha_pago, 'medio', i.medio,
             'pagado', i.pagado, 'facturas', i.facturas, 'lista', i.lista, 'nc', i.nc,
             'dias', i.dias, 'dto_tomado', i.dto_tomado, 'dto_ganado', i.dto_ganado,
             'retencion', i.retencion, 'a_reclamar', i.a_reclamar, 'calidad', i.calidad,
             'plazo', i.plazo, 'atraso', i.atraso, 'pedido', i.pedido) as x
      from public."GV_Cobranza_Imputacion" i
     where i.empresa = v_emp and regexp_replace(coalesce(i.cod_cliente,''),'^0+','') = v_cod
     order by i.fecha_pago desc nulls last, i.recibo
     limit 40
  ) z;

  /* (3) ENTREGAS FACTURADAS — Facturacion_NP (lo que Gestion facturo: NP, tanda, m3,
         dia de salida). La empresa sale de la NP, nunca del codigo de cliente solo. */
  select jsonb_agg(x order by x->>'facturado_at' desc)
    into v_entregas
  from (
    select jsonb_build_object(
             'np', f.np, 'tanda', f.tanda, 'fecha_salida', f.fecha_salida,
             'm3', f.m3, 'facturado_at', f.facturado_at) as x
      from public."Facturacion_NP" f
     where regexp_replace(coalesce(f.cod_cliente,''),'^0+','') = v_cod
       and public.gv_emp_de_np(f.np) = v_emp
     order by f.facturado_at desc nulls last
     limit 12
  ) z;

  /* (4) CABECERA */
  select jsonb_build_object(
           'empresa', v_emp, 'cod', v_cod,
           'cliente', max(c.cliente), 'cuit', max(d.cuit),
           'localidad', max(d.localidad_entrega), 'provincia', max(d.provincia_entrega),
           'ret_cliente', max(c.ret_cliente), 'agente_retencion', bool_or(c.agente_retencion),
           'ultimo_pago', max(c.ultimo_pago), 'ultimo_pago_monto', max(c.ultimo_pago_monto),
           'a_reclamar', max(c.a_reclamar))
    into v_cab
    from (select * from public.gv_cobranza_clientes()
           where empresa = v_emp and regexp_replace(coalesce(cod_cliente,''),'^0+','') = v_cod) c
    full join (select cuit, localidad_entrega, provincia_entrega
                 from public."GV_Cobranza_Deuda_Viva"
                where empresa = v_emp and regexp_replace(coalesce(cod_cliente,''),'^0+','') = v_cod
                  and (cuit is not null or localidad_entrega is not null)
                order by fecha desc limit 1) d on true;

  return jsonb_build_object(
    'cabecera', coalesce(v_cab,'{}'::jsonb),
    'totales',  coalesce(v_tot,'{}'::jsonb),
    'deuda',    coalesce(v_deuda,'[]'::jsonb),
    'recibos',  coalesce(v_recibos,'[]'::jsonb),
    'entregas', coalesce(v_entregas,'[]'::jsonb));
end $fn$;

revoke all on function public.gv_cobranza_ficha(text,text) from public;
grant execute on function public.gv_cobranza_ficha(text,text) to anon, authenticated, service_role;

-- chequeo
-- select public.gv_cobranza_ficha('lk','1651')->'totales';
-- select jsonb_array_length(public.gv_cobranza_ficha('lk','1651')->'deuda');
