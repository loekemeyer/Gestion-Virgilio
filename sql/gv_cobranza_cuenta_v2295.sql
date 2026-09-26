-- v22.95 · Cuenta corriente por cliente: TODAS las facturas/NC/ND de ISIS y TODOS los pagos del banco, con saldo
-- acumulado, y el control contra el Excel de deuda (Thomas, 26/09: "si hacés ese cálculo te debería dar el mismo saldo
-- de deuda a cobrar… fijate cuántos te dan y cuántos no").
--
-- Saldo calculado = Σ FC + Σ ND − Σ NC (ISIS, a valor nominal: el 25 % de descuento ya está en la NC "Sin Cotizador")
--                   − Σ pagos de la conciliación con el código del cliente, todo desde p_desde.
-- No hay saldo de apertura confiable: lo que se debía a p_desde y se pagó después queda como saldo a favor. Por eso
-- el desde por defecto es 01/01/2024 (el que más coincide, medido contra 01/03/2023, 01/01/2025 y 01/07/2025).
-- Coincide = |calculado − Excel| ≤ máx($5.000; 2 % de lo facturado en 12 meses o de la deuda).
-- Las dos funciones son SECURITY DEFINER con chequeo de supervisor: la pantalla no puede leer isis_* directo.
--
-- Rollback: drop function gv_cobranza_cuenta(text,text,date), gv_cobranza_control_saldos(date), gv_cobranza_desde(text);

-- desde cuándo la conciliación tiene los pagos de ese cliente con código cargado (medido 26/09: LK Credicoop
-- 2.243 cobros con código en 2024; Chef 1 en 2023, 11 en 2024 y 602 en 2025 — Chef recién se codifica desde 02/2025)
create or replace function public.gv_cobranza_desde(p_emp text) returns date language sql immutable as $f$
  select case when p_emp = 'chef' then date '2025-02-01' else date '2024-01-01' end $f$;

create or replace function public.gv_cobranza_cuenta(p_emp text, p_cod text, p_desde date default null)
returns table (fecha date, tipo text, comprobante text, condicion text, debe numeric, haber numeric, saldo numeric, detalle text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then raise exception 'solo supervisor'; end if;
  p_desde := coalesce(p_desde, gv_cobranza_desde(p_emp));
  return query
  with m as (
    select d.fecha, case d.familia when 'factura_venta' then 'Factura' when 'nc_venta' then 'NC' else 'ND' end tipo,
           d.tipo || ' ' || d.punto_venta || '-' || d.numero comp, d.condicion_venta cond,
           case when d.familia <> 'nc_venta' then abs(d.total) else 0 end debe,
           case when d.familia = 'nc_venta' then abs(d.total) else 0 end haber, null::text det, 1 ord
      from (select fecha, familia, tipo, punto_venta, numero, condicion_venta, total, contraparte_codigo from isis_lk.documentos where p_emp = 'lk'
            union all
            select fecha, familia, tipo, punto_venta, numero, condicion_venta, total, contraparte_codigo from isis_ch.documentos where p_emp = 'chef') d
     where d.familia in ('factura_venta','nc_venta','nd_venta') and d.fecha >= p_desde and d.total <> 0
       and regexp_replace(coalesce(d.contraparte_codigo,''),'^0+','') = p_cod
    union all
    select c.fecha, 'Pago', coalesce('Recibo ' || c.nro_recibo, 'sin recibo'), null, 0, c.entrada,
           concat_ws(' · ', initcap(c.banco), case when c.tipo = 'a_depositar' then 'e-cheque' else c.operacion end,
                     nullif(c.estado_echeq, ''), nullif(c.observacion, '')), 2
      from gv_conciliacion_bancaria c
     where c.empresa = p_emp and c.cod_cliente = p_cod and c.fecha >= p_desde
       and c.tipo in ('ingreso','a_depositar') and c.entrada > 0)
  select m.fecha, m.tipo, m.comp, m.cond, round(m.debe, 2), round(m.haber, 2),
         round(sum(m.debe - m.haber) over (order by m.fecha, m.ord, m.comp rows unbounded preceding), 2), m.det
    from m order by m.fecha, m.ord, m.comp;
end $$;

create or replace function public.gv_cobranza_control_saldos(p_desde date default null)
returns table (empresa text, cod_cliente text, cliente text, facturado numeric, notas_credito numeric, pagado_banco numeric,
               saldo_calculado numeric, deuda_excel numeric, diferencia numeric, estado text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then raise exception 'solo supervisor'; end if;
  return query
  with lote as (select x.empresa, max(x.lote) lote from "GV_Cuarentena_Deuda_Detalle" x group by 1),
  excel as (select x.empresa emp, regexp_replace(coalesce(x.cod,''),'^0+','') cod, sum(x.pendiente) deuda
              from "GV_Cuarentena_Deuda_Detalle" x join lote l on l.empresa = x.empresa and l.lote = x.lote
             where x.comp_key ~ '^[A-Z]' group by 1, 2),
  docs as (select 'lk'::text emp, regexp_replace(coalesce(contraparte_codigo,''),'^0+','') cod, contraparte_nombre nom, fecha, familia, abs(total) t
             from isis_lk.documentos where familia in ('factura_venta','nc_venta','nd_venta') and fecha >= coalesce(p_desde, gv_cobranza_desde('lk'))
           union all
           select 'chef', regexp_replace(coalesce(contraparte_codigo,''),'^0+',''), contraparte_nombre, fecha, familia, abs(total)
             from isis_ch.documentos where familia in ('factura_venta','nc_venta','nd_venta') and fecha >= coalesce(p_desde, gv_cobranza_desde('chef'))),
  d as (select emp, cod, max(nom) nom,
               sum(t) filter (where familia <> 'nc_venta') fac, sum(t) filter (where familia = 'nc_venta') nc,
               sum(t) filter (where familia = 'factura_venta' and fecha >= current_date - 365) f12
          from docs group by 1, 2),
  p as (select c.empresa emp, c.cod_cliente cod, sum(c.entrada) pago from gv_conciliacion_bancaria c
         where c.fecha >= coalesce(p_desde, gv_cobranza_desde(c.empresa)) and c.tipo in ('ingreso','a_depositar') and c.entrada > 0 and c.cod_cliente ~ '^\d+$' group by 1, 2),
  j as (select coalesce(d.emp, e.emp) emp, coalesce(d.cod, e.cod) cod, d.nom,
               coalesce(d.fac, 0) fac, coalesce(d.nc, 0) nc, coalesce(p.pago, 0) pago,
               coalesce(d.fac, 0) - coalesce(d.nc, 0) - coalesce(p.pago, 0) calc, coalesce(e.deuda, 0) excel,
               greatest(5000, 0.02 * greatest(coalesce(d.f12, 0), abs(coalesce(e.deuda, 0)))) tol
          from d full join excel e on e.emp = d.emp and e.cod = d.cod
          left join p on p.emp = coalesce(d.emp, e.emp) and p.cod = coalesce(d.cod, e.cod))
  select j.emp, j.cod, j.nom, round(j.fac, 2), round(j.nc, 2), round(j.pago, 2), round(j.calc, 2), round(j.excel, 2),
         round(j.calc - j.excel, 2),
         case when abs(j.calc - j.excel) <= j.tol then 'coincide'
              when j.calc > j.excel then 'calculado mayor' else 'calculado menor' end
    from j
   where j.cod <> '' and not (j.emp = 'lk' and j.cod = '411') and not (j.emp = 'chef' and j.cod = '1434');
end $$;

revoke all on function public.gv_cobranza_cuenta(text,text,date), public.gv_cobranza_control_saldos(date) from public, anon;
grant execute on function public.gv_cobranza_cuenta(text,text,date), public.gv_cobranza_control_saldos(date) to authenticated;
