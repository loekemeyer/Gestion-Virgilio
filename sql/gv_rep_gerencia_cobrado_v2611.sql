-- v26.11 — Reportes de gerencia (Luis, 02/10/2026): "sumale lo cobrado por día (sacado el dato de la conciliación)".
--
-- Lo lee LK por el FDW virgilio_db (rol lk_ppp_reader) para el reporte diario/semanal/mensual de Telegram.
-- lk_ppp_reader NO tiene acceso a las tablas de la conciliación (GV_Conc_*: RLS sólo supervisores), y no se le
-- abre: son todos los movimientos de banco (sueldos, proveedores). Por eso el dato sale por una función
-- SECURITY DEFINER que devuelve SÓLO lo cobrado a clientes, agregado por día / empresa / banco / cliente,
-- y una vista security_invoker encima (regla: toda vista nueva con security_invoker).
--
-- Qué es COBRADO (con IVA, es plata que entró):
--   * filas de gv_conciliacion_bancaria tipo ingreso o a_depositar, con entrada > 0,
--   * ARRIBA de la línea amarilla de cada cuenta (gv_conc_linea): lo conciliado con el extracto. Lo de abajo es
--     cartera de cheques / proyección y no entró todavía. La carga manual (GV_Cobranza_Pago_Manual) no tiene línea
--     y cuenta entera.
--   * det 'D' (depósito/transferencia de un cliente) y '3' (cheque acreditado)  -> clase 'cliente'
--     det '1' (No identificado: casi siempre un cliente que todavía no se imputó) -> clase 'sin_identificar'
--   * FUERA: TB (transferencia entre cuentas propias), Vta Cheq / VTACH (venta de cheques: adelanta cartera, no es
--     cobranza nueva), INV (rescate de fondos / venta de dólares), DEV, CHRECH, TFRECH, G, y un No identificado
--     que nombra a Loekemeyer o a Chef (transferencia entre las dos empresas).
--   Las ventas entre empresas por código de cliente (ventas_clientes_internos) las saca LK, que tiene la lista.
--
-- Medido el 02/10 (cobrado cliente + sin identificar, con IVA): sep LK $ 413,4 M · Chef $ 109,9 M, de los que
-- $ 21,6 M son de Loekemeyer Hnos (cliente interno de Chef, 1434) y LK los saca: el reporte dice Chef $ 88,3 M.

create or replace function public.gv_rep_gerencia_cobrado_fn()
returns table(fecha date, empresa text, banco text, clase text, cod_cliente text, monto numeric, n bigint)
language sql stable security definer set search_path = public, pg_temp as $$
  select g.fecha, g.empresa, g.banco,
         case when g.banco = 'manual' or g.det in ('D', '3') then 'cliente' else 'sin_identificar' end,
         nullif(btrim(g.cod_cliente), ''),
         sum(g.entrada), count(*)
    from public.gv_conciliacion_bancaria g
    left join public.gv_conc_linea l on l.banco = g.banco and l.empresa = g.empresa
   where g.tipo in ('ingreso', 'a_depositar')
     and coalesce(g.entrada, 0) > 0
     and g.fecha is not null
     and (g.banco = 'manual'
          or g.det in ('D', '3')
          or (g.det = '1' and coalesce(g.observacion, '') !~* '(loekemeyer|chef\s*s\.?r\.?l|30515842450|30685756257)'))
     and (l.banco is null or g.anio < l.anio or g.fila <= l.fila)
   group by 1, 2, 3, 4, 5
$$;

-- hasta qué día está conciliada cada cuenta (para avisar en el reporte si falta un banco)
create or replace function public.gv_rep_gerencia_conc_al_fn()
returns table(banco text, empresa text, conciliado_al date)
language sql stable security definer set search_path = public, pg_temp as $$
  select l.banco, l.empresa, l.conciliado_al from public.gv_conc_linea l
$$;

revoke execute on function public.gv_rep_gerencia_cobrado_fn(), public.gv_rep_gerencia_conc_al_fn()
  from public, anon, authenticated;
grant execute on function public.gv_rep_gerencia_cobrado_fn(), public.gv_rep_gerencia_conc_al_fn() to lk_ppp_reader;

create or replace view public.gv_rep_gerencia_cobrado with (security_invoker = true) as
  select * from public.gv_rep_gerencia_cobrado_fn();
create or replace view public.gv_rep_gerencia_conc_al with (security_invoker = true) as
  select * from public.gv_rep_gerencia_conc_al_fn();

revoke all on public.gv_rep_gerencia_cobrado, public.gv_rep_gerencia_conc_al from anon, authenticated;
grant select on public.gv_rep_gerencia_cobrado, public.gv_rep_gerencia_conc_al to lk_ppp_reader;

-- Chequeo:
--   select empresa, date_trunc('month', fecha)::date, clase, round(sum(monto))
--     from public.gv_rep_gerencia_cobrado where fecha >= '2026-09-01' group by 1, 2, 3 order by 1, 2, 3;
--   select * from public.gv_rep_gerencia_conc_al;
--
-- Rollback:
--   drop view if exists public.gv_rep_gerencia_cobrado, public.gv_rep_gerencia_conc_al;
--   drop function if exists public.gv_rep_gerencia_cobrado_fn(), public.gv_rep_gerencia_conc_al_fn();
