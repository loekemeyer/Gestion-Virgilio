-- v23.03 (Luis, 2026-09-28): "se actualizó la carga del Excel de deuda y figuran con deuda
-- clientes que no tienen" + "en Motivos, cuando tienen deuda, debería aparecer de qué fecha es".
--
-- Medido el 28/09: Multi Bazar (LK 4042) y Nistico (LK 31) salían con deuda por facturas del
-- 25/09 "Pago Contado" (FCA 0004-00036028 = NP LK 0177, FCA 0004-00036029 = NP LK 0218) cuya
-- mercadería se cargó al camión HOY 08:44 (CCN) y NO tiene Recepción Remitos (CRN): el cliente
-- todavía no recibió nada, no puede deber. Al 28/09: 12 comprobantes así (LK), $22,8 M.
--
-- REGLA: un comprobante del Excel cuya NP (cadena comprobante -> factura ISIS -> GV_Cruce_FC_Asig)
-- NO tiene Recepción Remitos NO cuenta como deuda. Tope de 30 días desde la factura: una factura
-- vieja sin CRN (Producción no siempre lo registraba) sigue contando — no se perdona para siempre.
-- Comprobante sin NP resuelta (recibos, NC, facturas viejas) cuenta siempre, como hasta hoy.
-- Cliente sin detalle cargado -> cae al total de GV_Cuarentena_Fuente (fail-safe: retiene).
--
-- La FECHA sale del Excel (col A, serial de Excel) y, si no viene, de la factura de ISIS.
-- `desde` = el comprobante positivo que cuenta más viejo.

create or replace function public.gv_cuarentena_deuda_efectiva()
returns table(empresa text, cod text, deuda numeric, desde date, comprobantes int,
              sin_entregar numeric)
language sql stable security definer set search_path = public
as $f$
  with crn as materialized (
    select distinct split_part(r.texto, '|', 1) as np
      from public."Registros_Produccion_Virgilio" r where r.opcion = 'CRN'
  ),
  s as (
    select s.empresa, s.cod, s.pendiente, s.np,
           coalesce(case when (d_fila ->> 0) ~ '^\d{5}(\.\d+)?$'
                         then date '1899-12-30' + floor((d_fila ->> 0)::numeric)::int end,
                    s.fecha_comprobante) as fecha
      from (select x.*, (select dd.fila from public."GV_Cuarentena_Deuda_Detalle" dd
                          where dd.empresa = x.empresa and dd.cod = x.cod
                            and dd.comprobante = x.comprobante limit 1) as d_fila
              from public.gv_cuarentena_deuda_sucursal x) s
  ),
  m as (
    select s.*,
           (s.np is not null and s.pendiente > 0
            and not exists (select 1 from crn c where c.np = s.np)
            and coalesce(s.fecha, current_date) >= current_date - 30) as _cde_sin_entregar
      from s
  )
  select m.empresa, m.cod,
         round(coalesce(sum(m.pendiente) filter (where not m._cde_sin_entregar), 0), 2),
         min(m.fecha) filter (where not m._cde_sin_entregar and m.pendiente > 0),
         (count(*) filter (where not m._cde_sin_entregar))::int,
         round(coalesce(sum(m.pendiente) filter (where m._cde_sin_entregar), 0), 2)
    from m group by m.empresa, m.cod
$f$;
revoke all on function public.gv_cuarentena_deuda_efectiva() from public, anon;
grant execute on function public.gv_cuarentena_deuda_efectiva() to authenticated, service_role;

-- Fecha de la deuda para la pantalla (chip de Motivos). Recibe la misma lista que
-- gv_cuarentena_marcar y resuelve el padrón igual (gv_cuarentena_ident: TdF -> Chef).
create or replace function public.gv_cuarentena_deuda_desde(p_pedidos jsonb)
returns table(order_id text, empresa text, desde date, comprobantes int, sin_entregar numeric)
language sql stable security definer set search_path = public
as $f$
  with _dd as materialized (select * from public.gv_cuarentena_deuda_efectiva())
  select nullif(trim(e->>'order_id'), ''), lower(coalesce(e->>'empresa','lk')),
         d.desde, d.comprobantes, d.sin_entregar
    from jsonb_array_elements(coalesce(p_pedidos, '[]'::jsonb)) e
    cross join lateral public.gv_cuarentena_ident(
      lower(coalesce(e->>'empresa','lk')), nullif(trim(e->>'cod'), ''),
      coalesce(nullif(trim(e->>'order_id'), ''), '') !~* '^np') id
    join _dd d on d.empresa = id.empresa and d.cod = id.cod
   where (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
$f$;
revoke all on function public.gv_cuarentena_deuda_desde(jsonb) from public, anon;
grant execute on function public.gv_cuarentena_deuda_desde(jsonb) to authenticated, service_role;

-- marcar_calc: la deuda que retiene es la EFECTIVA. Se parchea sobre pg_get_functiondef (varias
-- sesiones tocan esta función), idempotente, y falla con raise si el texto no matchea.
do $p$
declare
  d text := pg_get_functiondef('public.gv_cuarentena_marcar_calc(jsonb)'::regprocedure);
  a1 text := 'with _lbf as materialized (select * from public.gv_cuarentena_liberados_familia),';
  a2 text := 'coalesce(f.deuda,0) > 1000';
  a3 text := 'select round(f.deuda, 2) from';
  ef text := '(select _cde.deuda from _cde where _cde.empresa = f.empresa and _cde.cod = f.cod)';
begin
  if position('_cde as materialized' in d) > 0 then raise notice 'ya aplicado'; return; end if;
  if position(a1 in d) = 0 or (length(d) - length(replace(d, a2, ''))) / length(a2) <> 2
     or position(a3 in d) = 0 then
    raise exception 'marcar_calc no matchea el texto esperado: revisar a mano';
  end if;
  d := replace(d, a1, a1 || E'\n  -- v23.03 (Luis, 28/09): deuda EFECTIVA = sin facturas de mercaderia que todavia no se entrego (sin CRN)\n  _cde as materialized (select * from public.gv_cuarentena_deuda_efectiva()),');
  d := replace(d, a2, 'coalesce(' || ef || ', f.deuda, 0) > 1000');
  d := replace(d, a3, 'select round(coalesce(' || ef || ', f.deuda), 2) from');
  execute d;
end $p$;

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
select 'gv_cuarentena_marcar_calc', 'funcion', 'gv_cuarentena_deuda_efectiva',
        'la deuda que retiene excluye facturas de mercaderia sin Recepcion Remitos (CRN)',
        'Luis', 'v23.03'
 where not exists (select 1 from public."GV_Reglas_Centinela"
                    where objeto = 'gv_cuarentena_marcar_calc' and patron = 'gv_cuarentena_deuda_efectiva');
