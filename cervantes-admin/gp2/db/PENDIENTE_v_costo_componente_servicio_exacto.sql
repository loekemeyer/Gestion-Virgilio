-- APLICADO 2026-08-31 por el usuario en el SQL Editor (verificado: B4 $314,55 / C10 $33,11).
-- SEGUNDA CIRUGIA APLICADA el mismo dia (tambien corrida por el usuario): precio_por_kg en
-- precio_proveedor y precio_kg+proceso en precio_servicio_pieza — el peso vive en el
-- componente, la tarifa en el proveedor, el costo se calcula en vivo (regla del usuario).
-- Verificado: PCP3 = 3,30 USD/kg x 6,53 g; V1 = crudo 4,45 + niquelado 2606/kg x 0,35 g = 5,36.
-- Queda como documentacion; es idempotente, correrlo de nuevo no hace nada.
-- PENDIENTE (2026-08-31): servicios EXACTOS por pieza en el motor de costos.
-- Contexto: el usuario pidio que el costo de servicios (cromado, temple, niquelado, pintado...)
-- sea EXACTO por pieza, no un promedio por proveedor. Los precios ya estan cargados en la tabla
-- nueva GP2.precio_servicio_pieza (85 filas: Pedernera/FAAT/Guazzaroni por kg convertidos a
-- $/pieza con los gramos de la lista o el kg_x_uni de GP2; Jade/Ximpa por pieza directo).
-- Falta UN cambio en GP2.v_costo_componente: que el paso de servicio use el precio exacto de la
-- pieza si existe, y caiga al precio plano de precio_servicio (hoy placeholder 1 USD) si no.
--
-- Este script hace la cirugia sobre la definicion VIVA de la vista (no pisa otros cambios,
-- como la regla ampliada de "comprado" del 2026-08-31). Correr en el SQL Editor de Supabase.
-- Es idempotente: si ya se aplico, no hace nada.

do $$
declare v text;
begin
  select pg_get_viewdef('"GP2".v_costo_componente'::regclass, true) into v;
  if v like '%precio_servicio_pieza%' then
    raise notice 'ya aplicado, no hago nada';
    return;
  end if;
  v := replace(v,
    'LEFT JOIN psrv p ON p.proveedor_servicio_id = z.proveedor_id',
    'LEFT JOIN "GP2".precio_servicio_pieza pz ON pz.proveedor_servicio_id = z.proveedor_id AND pz.componente_id = z.pieza LEFT JOIN psrv p ON p.proveedor_servicio_id = z.proveedor_id');
  v := replace(v,
    'sum(p.precio_uni) FILTER (WHERE p.moneda',
    'sum(COALESCE(pz.precio_uni, p.precio_uni)) FILTER (WHERE COALESCE(pz.moneda, p.moneda)');
  v := replace(v,
    'count(*) FILTER (WHERE p.precio_uni IS NULL)',
    'count(*) FILTER (WHERE COALESCE(pz.precio_uni, p.precio_uni) IS NULL)');
  if v not like '%precio_servicio_pieza%' then
    raise exception 'no encontre el join de psrv para reemplazar — vista sin tocar';
  end if;
  execute 'create or replace view "GP2".v_costo_componente as ' || v;
end $$;

-- Verificacion sugerida despues de correrlo:
--   select codigo, servicios_pesos, servicios_usd, total_pesos
--   from "GP2".v_costo_componente where codigo in ('B4','C10','B13') and sector_id = 2;
-- Esperado: B4 servicios $150 ARS (pintado Jade) y 0 USD; C10 ~$15,5 ARS (cementado FAAT
-- $11,18 + zincado Guazzaroni $4,34); B13 $84,45 ARS (cromado Pedernera 39,2 g).
