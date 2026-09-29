-- v24.41 (Luis, 29/09) — Cobranzas: RESUMEN del cliente como la planilla de cobranza + Conciliación por banco
--
-- (1) gv_cobranza_operaciones(emp, cod): cada OPERACIÓN del cliente para dibujar la planilla de cobranza
--     (la que Luis pasó al principio: facturas · pagos con días y ponderación · total · escala · NC de dto).
--       pagadas  = GV_Cobranza_Imputacion agrupada por el juego de facturas, con el detalle de cada factura
--                  y de cada NC sacado de ISIS (isis_lk / isis_ch, de la empresa del cliente).
--       abiertas = GV_Cobranza_Deuda_Viva con pendiente, agrupada por día de factura.
-- (2) gv_conc_planilla(banco, empresa, dias): la planilla de UNA cuenta como la ve el Excel — lo de los
--     últimos N días arriba de la línea amarilla y todo lo proyectado abajo — para el pop-up del banco.
-- (3) gv_conc_tablero(): por cuenta, a qué fecha está conciliada (la línea amarilla), cuándo se subió la
--     planilla, y cuántos movimientos del extracto esperan a una persona (el badge de «Completar datos»).
-- Todas de lectura, SECURITY DEFINER con el guard de supervisor.

create or replace function public.gv_cobranza_operaciones(p_emp text, p_cod text)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare
  v_emp text := lower(btrim(coalesce(p_emp,'')));
  v_cod text := regexp_replace(coalesce(p_cod,''),'^0+','');
  v_pag jsonb; v_abi jsonb; v_nums text[];
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then raise exception 'sin permiso'; end if;

  -- los numeros que hacen falta, antes: filtrar documentos por el codigo del cliente es un seq scan
  -- (2,5 s medido); por numero entra por documentos_numero_idx
  select array_agg(distinct lpad(n, 8, '0')) into v_nums
    from public."GV_Cobranza_Imputacion" i,
         unnest(string_to_array(coalesce(i.facturas,'') || '+' || coalesce(i.nc,''), '+')) n
   where i.empresa = v_emp and regexp_replace(coalesce(i.cod_cliente,''),'^0+','') = v_cod and n ~ '^\d+$';

  with docs as (
    select 'lk'::text emp, familia, tipo, letra, punto_venta, numero, fecha, total, subt_gravado,
           regexp_replace(coalesce(contraparte_codigo,''),'^0+','') cod
      from isis_lk.documentos where v_emp = 'lk' and numero = any(v_nums) and familia in ('factura_venta','nc_venta')
    union all
    select 'chef', familia, tipo, letra, punto_venta, numero, fecha, total, subt_gravado,
           regexp_replace(coalesce(contraparte_codigo,''),'^0+','')
      from isis_ch.documentos where v_emp = 'chef' and numero = any(v_nums) and familia in ('factura_venta','nc_venta')
  ), mis as (select * from docs where cod = v_cod),
  imp as (
    select i.* from public."GV_Cobranza_Imputacion" i
     where i.empresa = v_emp and regexp_replace(coalesce(i.cod_cliente,''),'^0+','') = v_cod
       and coalesce(i.facturas,'') <> ''
  ),
  ops as (
    select i.facturas, max(i.nc) nc, max(i.lista) lista, max(i.lista_nc) lista_nc, max(i.pedido) fecha_fc,
           max(i.plazo) plazo, max(i.dto_tomado) dto_tomado, max(i.dto_ganado) dto_ganado,
           max(i.retencion) retencion, max(i.ret_cliente) ret_cliente, sum(coalesce(i.a_reclamar,0)) a_reclamar,
           string_agg(distinct i.calidad, ', ') calidad, max(i.fecha_pago) ultimo_pago,
           jsonb_agg(jsonb_build_object(
             'recibo', i.recibo, 'fecha', i.fecha_pago, 'pagado', i.pagado, 'medio', i.medio, 'dias', i.dias,
             -- un recibo que pagó varios juegos de facturas aparece en cada uno con el pago ENTERO
             'grupos', (select count(distinct j.facturas) from imp j where j.recibo = i.recibo))
             order by i.fecha_pago) filter (where i.recibo is not null) pagos
      from imp i group by i.facturas
  )
  select jsonb_agg(jsonb_build_object(
           'facturas_txt', o.facturas, 'nc_txt', o.nc, 'lista', o.lista, 'lista_nc', o.lista_nc, 'fecha_fc', o.fecha_fc,
           'plazo', o.plazo, 'dto_tomado', o.dto_tomado, 'dto_ganado', o.dto_ganado, 'retencion', o.retencion,
           'ret_cliente', o.ret_cliente, 'a_reclamar', o.a_reclamar, 'calidad', o.calidad, 'ultimo_pago', o.ultimo_pago,
           'pagos', coalesce(o.pagos,'[]'::jsonb),
           'facturas', (select jsonb_agg(jsonb_build_object('tipo', d.tipo, 'pv', d.punto_venta, 'numero', ltrim(d.numero,'0'),
                                        'fecha', d.fecha, 'total', d.total, 'gravado', d.subt_gravado) order by d.fecha, d.numero)
                          from mis d where d.familia = 'factura_venta'
                           and ltrim(d.numero,'0') = any(string_to_array(o.facturas,'+'))),
           'ncs', (select jsonb_agg(jsonb_build_object('tipo', d.tipo, 'numero', ltrim(d.numero,'0'), 'fecha', d.fecha,
                                   'total', d.total, 'gravado', d.subt_gravado) order by d.fecha)
                     from mis d where d.familia = 'nc_venta'
                      and ltrim(d.numero,'0') = any(string_to_array(coalesce(o.nc,''),'+'))))
         order by o.ultimo_pago desc nulls last, o.fecha_fc desc)
    into v_pag
    from (select * from ops order by ultimo_pago desc nulls last, fecha_fc desc limit 40) o;

  select jsonb_agg(jsonb_build_object('fecha', z.fecha, 'facturas', z.facturas, 'lista', z.lista,
                                      'pendiente', z.pendiente, 'cancelado', z.cancelado) order by z.fecha desc)
    into v_abi
    from (select d.fecha,
                 jsonb_agg(jsonb_build_object('comprobante', d.comprobante, 'fecha', d.fecha, 'vence', d.vence,
                           'condicion', d.condicion, 'dto_cond', d.dto_cond, 'lista', d.lista, 'pendiente', d.pendiente,
                           'cancelado_banco', d.cancelado_banco, 'recibos_banco', d.recibos_banco, 'origen', d.origen)
                           order by d.comprobante) facturas,
                 sum(coalesce(d.lista, d.pendiente)) lista, sum(d.pendiente) pendiente, sum(coalesce(d.cancelado_banco,0)) cancelado
            from public."GV_Cobranza_Deuda_Viva" d
           where d.empresa = v_emp and regexp_replace(coalesce(d.cod_cliente,''),'^0+','') = v_cod
             and coalesce(d.pendiente,0) > 0
           group by d.fecha) z;

  return jsonb_build_object('pagadas', coalesce(v_pag,'[]'::jsonb), 'abiertas', coalesce(v_abi,'[]'::jsonb));
end $fn$;
revoke all on function public.gv_cobranza_operaciones(text,text) from public;
grant execute on function public.gv_cobranza_operaciones(text,text) to anon, authenticated, service_role;

create or replace function public.gv_conc_planilla(p_banco text, p_empresa text, p_dias int default 45)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare v_b text := lower(btrim(p_banco)); v_e text := lower(btrim(p_empresa)); l record; v jsonb;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then raise exception 'sin permiso'; end if;
  select * into l from public.gv_conc_linea x where x.banco = v_b and x.empresa = v_e;
  select jsonb_agg(to_jsonb(z) order by z.anio, z.fila) into v from (
    select g.anio, g.fila, g.fecha, g.operacion, g.entrada, g.salida, g.saldo, g.detalle, g.det, g.nro_op,
           g.nro_recibo, g.cod_cliente, g.observacion,
           (l.anio is not null and (g.anio, g.fila) > (l.anio, l.fila)) as proyectado,
           (select m.id from public."GV_Conc_Mov" m
             where m.proy_key = g.banco || '|' || g.empresa || '|' || g.anio || '|' || g.fila limit 1) as mov_id
      from public.gv_conciliacion_bancaria g
     where g.banco = v_b and g.empresa = v_e
       and ( (g.fecha >= current_date - greatest(coalesce(p_dias,45),1)
              and (l.anio is null or g.anio >= l.anio - 1))
          or (l.anio is not null and (g.anio, g.fila) > (l.anio, l.fila)) )
     order by g.anio desc, g.fila desc limit 1500) z;
  return jsonb_build_object('conciliado_al', l.conciliado_al, 'saldo_linea', l.saldo, 'filas', coalesce(v,'[]'::jsonb));
end $fn$;
revoke all on function public.gv_conc_planilla(text,text,int) from public;
grant execute on function public.gv_conc_planilla(text,text,int) to anon, authenticated, service_role;

create or replace function public.gv_conc_tablero()
returns table(banco text, empresa text, conciliado_al date, saldo_linea numeric, subido_en timestamptz,
              preguntas bigint, propuestos bigint, movs_extracto bigint, ultimo_extracto date)
language plpgsql stable security definer set search_path to 'public' as $fn$
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then raise exception 'sin permiso'; end if;
  return query
  with c(banco, empresa) as (values ('credicoop','lk'),('santander','chef'),('credicoop','chef'),('santander','lk'))
  select c.banco, c.empresa, l.conciliado_al, l.saldo,
         (select max(g.cargado_en) from public.gv_conciliacion_bancaria g where g.banco = c.banco and g.empresa = c.empresa),
         (select count(*) from public."GV_Conc_Mov" m where m.banco = c.banco and m.empresa = c.empresa and m.estado = 'pregunta'),
         (select count(*) from public."GV_Conc_Mov" m where m.banco = c.banco and m.empresa = c.empresa and m.estado = 'propuesto'),
         (select count(*) from public."GV_Conc_Mov" m where m.banco = c.banco and m.empresa = c.empresa),
         (select max(m.fecha) from public."GV_Conc_Mov" m where m.banco = c.banco and m.empresa = c.empresa)
    from c left join public.gv_conc_linea l on l.banco = c.banco and l.empresa = c.empresa;
end $fn$;
revoke all on function public.gv_conc_tablero() from public;
grant execute on function public.gv_conc_tablero() to anon, authenticated, service_role;

-- (4) Lo que espera a una persona en las 4 cuentas (la pestaña «Completar datos»): preguntas y propuestos.
create or replace function public.gv_conc_pendientes_lista()
returns jsonb language sql stable security definer set search_path to 'public' as $fn$
  select case when not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then null else
  coalesce((select jsonb_agg(to_jsonb(x) - 'huella' order by greatest(x.credito, x.debito) desc, x.id)
              from public."GV_Conc_Mov" x where x.estado in ('pregunta','propuesto')), '[]'::jsonb) end
$fn$;
revoke all on function public.gv_conc_pendientes_lista() from public;
grant execute on function public.gv_conc_pendientes_lista() to anon, authenticated, service_role;
