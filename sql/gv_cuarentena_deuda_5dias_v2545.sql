-- REGLA_CONFIRMADA_POR_USUARIO (Luis, 01/10/2026: "5 corridos · de momento vamos con eso")
-- v25.49 (Luis): en Cuarentena, la FACTURA con menos de 5 días corridos (fecha del comprobante,
-- la del reporte de deuda o la que tomó el parser de ISIS) NO cuenta como deuda. La deuda más
-- vieja del mismo cliente sigue reteniendo. Vale para todos los clientes, para la retención
-- (gv_cuarentena_marcar_calc -> gv_cuarentena_deuda_pedido; el armador la hereda) y para la
-- alerta de lo ya programado (gv_cuarentena_ya_programado). Sin fecha: cuenta (retiene).
-- Se aplica sobre pg_get_functiondef, idempotente, y frena con raise si el texto no matchea.
-- Marcador de idempotencia: v25.45-5dias (no cambiarlo).
do $$
declare d text; n text;
begin
  -- 1) deuda por pedido
  d := pg_get_functiondef('public.gv_cuarentena_deuda_pedido(jsonb)'::regprocedure);
  if d !~ 'v25\.45-5dias' then
    n := replace(d, E'c.sin_entregar\n      from _cdp_p p',
      E'c.sin_entregar,\n           -- v25.45-5dias (Luis): la factura de menos de 5 dias corridos no es deuda\n           coalesce(c.pendiente > 0 and c.fecha > current_date - 5, false) as reciente\n      from _cdp_p p');
    if n = d then raise exception 'deuda_pedido: no matchea el FROM'; end if;
    d := n; n := replace(d, 'not x.sin_entregar', 'not x.sin_entregar and not x.reciente');
    if n = d then raise exception 'deuda_pedido: no matchea not x.sin_entregar'; end if;
    execute n;
  end if;

  -- 2) alerta de lo ya programado
  d := pg_get_functiondef('public.gv_cuarentena_ya_programado()'::regprocedure);
  if d !~ 'v25\.45-5dias' then
    n := replace(d, E'  with prog as (',
      E'  -- v25.45-5dias (Luis): la factura de menos de 5 dias corridos no es deuda\n  with _rec5 as materialized (\n    select c.empresa, c.cod, sum(c.pendiente) as rec\n      from public.gv_cuarentena_deuda_comprobantes() c\n     where c.pendiente > 0 and c.fecha > current_date - 5\n     group by 1, 2\n  ),\n  prog as (');
    if n = d then raise exception 'ya_programado: no matchea with prog'; end if;
    d := n; n := replace(d, 'coalesce(f.deuda,0) > 1000',
      'coalesce(f.deuda,0) - coalesce((select r5.rec from _rec5 r5 where r5.empresa = f.empresa and r5.cod = f.cod), 0) > 1000');
    if n = d then raise exception 'ya_programado: no matchea el umbral'; end if;
    d := n; n := replace(d, 'select round(f.deuda, 2)',
      'select round(f.deuda - coalesce((select r5.rec from _rec5 r5 where r5.empresa = f.empresa and r5.cod = f.cod), 0), 2)');
    if n = d then raise exception 'ya_programado: no matchea el monto'; end if;
    execute n;
  end if;
end $$;

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
select * from (values
  ('gv_cuarentena_deuda_pedido','funcion','not x\.reciente','La factura de menos de 5 dias corridos no cuenta como deuda para retener','Luis','v25.45'),
  ('gv_cuarentena_ya_programado','funcion','_rec5 r5','La factura de menos de 5 dias corridos no cuenta en la alerta de programados','Luis','v25.45')
) v(objeto, clase, patron, regla, quien_pidio, version)
where not exists (select 1 from public."GV_Reglas_Centinela" c where c.objeto = v.objeto and c.patron = v.patron);

-- ROLLBACK: volver a crear las dos funciones sin el bloque v25.45-5dias (definiciones previas
-- en zz_backups."GV_Backup_CuarDeuda5_defs_20261001") y borrar las 2 filas del centinela.
