-- v21.92 (Vivi, 2026-09-23) — "el 25% corresponde por pago, como es cliente nuevo y tiene que
-- pagar anticipado le corresponde". Y sobre el alcance: "esto es solo a nivel informativo, para
-- pedirle al cliente lo que tiene que pagar para que se le arme el pedido (solo a los que estan
-- en cuarentena por cliente nuevo)".
--
-- QUE FALTABA, MEDIDO. El descuento por plazo de pago vive en `cobranzas_escalones` (contado
-- 0-14 dias = 25 %) y viaja en el pedido web como `lk_pedidos_match.metodo_pago`. En 60 dias,
-- 300 de 468 pedidos dicen contado. `gv_ppp_web_valor_items` NUNCA lo aplico: valoriza a lista
-- con el dto de volumen y el 2 % web, y el descuento de pago lo pone ISIS al facturar, por la
-- condicion de venta. O sea que el monto del Speech 1 le pedia 25 % de mas a cada cliente nuevo
-- de contado.
--
-- QUE NO SE TOCA (decision de Vivi: "solo el pop-up de composicion"):
--   * gv_ppp_web_valor_items y gv_clientes_nuevos_valor_lote NO se modifican.
--   * La celda Monto, el limite de credito y la cuarentena siguen exactamente igual.
--   * Esta funcion SOLO la lee el pop-up, al abrirlo.
--
-- LA CUENTA, ENCADENADA (Vivi eligio esta de las tres opciones):
--   lista - dto volumen - 2 % web = neto        <- lo que devuelve gv_clin_composicion
--   neto - dto de pago            = a cobrar    <- lo que se le reclama, + IVA 21 %
--
-- ⚠ FAIL-OPEN HACIA EL NUMERO MAS ALTO, y a la vista. Si la condicion no se puede leer devuelve
--   dto = 0 y lo dice en `escalon`; el front muestra el neto pelado con un aviso naranja. Nunca
--   se asume un 25 % que nadie declaro: un descuento inventado se factura mal.
--
-- Medido al aplicarla:
--   'Contado' (LK 1448, Silvano)        -> contado, 14 dias, 0.2500
--   'Pago Contado: 25% Dto' (LK 1481)   -> contado, 14 dias, 0.2500
--   'Sin Cotizador' (LK 1533)           -> 0, "no se pudo leer el plazo de «Sin Cotizador»"
--
-- Sobre LK 1448: neto 1.696.048,97 -> a cobrar 1.272.036,73 -> TOTAL CON IVA 1.539.164,44
-- (antes el pop-up decia 2.052.219,25).
--
-- Rollback: drop function public.gv_dto_pago_pedido(text, text);  (y sacar la llamada del front)

CREATE OR REPLACE FUNCTION public.gv_dto_pago_pedido(p_empresa text, p_order_id text)
 RETURNS TABLE(metodo_pago text, dias int, escalon text, escalon_label text, dto numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with m as (
    select lp.metodo_pago as mp
      from public.lk_pedidos_match lp
     where lp.empresa = lower(coalesce(nullif(trim(p_empresa),''),'lk'))
       and lp.order_id::text = nullif(trim(p_order_id),'')
     limit 1
  ),
  d as (
    select m.mp,
           coalesce(
             -- 1) la condicion tal cual, si esta en el padron de condiciones
             (select dc.dias from public.deudores_condiciones dc
               where upper(btrim(dc.condicion_venta)) = upper(btrim(m.mp)) limit 1),
             -- 2) si no, se lee el plazo del propio texto del metodo de pago
             case
               when m.mp ~* 'contado'            then 14
               when m.mp ~* '15\s*[-a]\s*30'     then 30
               when m.mp ~* '31\s*[-a]\s*45'     then 45
               when m.mp ~* '46\s*[-a]\s*60'     then 60
               when m.mp ~* '(^|[^0-9])90([^0-9]|$)'  then 90
               when m.mp ~* '(^|[^0-9])120([^0-9]|$)' then 120
               else null
             end) as dias
      from m
  )
  select d.mp,
         d.dias,
         coalesce(e.escalon, 'sin condicion de pago reconocida'),
         coalesce(e.label,   'no se pudo leer el plazo de «' || coalesce(d.mp,'(vacio)') || '»'),
         coalesce(e.dto, 0)
    from d
    left join lateral (
      select ce.escalon, ce.label, ce.dto
        from public.cobranzas_escalones ce
       where d.dias is not null and ce.dias >= d.dias
       order by ce.dias asc
       limit 1) e on true;
$function$;

revoke all on function public.gv_dto_pago_pedido(text, text) from public;
grant execute on function public.gv_dto_pago_pedido(text, text) to authenticated, service_role;

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_dto_pago_pedido','funcion',
        'ce\.dias >= d\.dias',
        'El descuento por plazo de pago sale del escalon de cobranzas_escalones cuyo tope de dias alcanza al plazo del pedido (contado 0-14 dias = 25 %). Sin esa resolucion el pop-up de composicion le reclama al cliente nuevo un 25 % de mas.',
        'Vivi','v21.92')
on conflict do nothing;

notify pgrst, 'reload schema';

-- ⚠ LO QUE QUEDA ABIERTO, y NO se toco (es decision comercial, no de codigo):
-- `gv_ppp_web_valor_items` sigue sin aplicar el descuento de pago, asi que la celda Monto, el
-- Speech 1 y el control de limite de credito muestran el numero SIN ese 25 %. Vivi eligio
-- a proposito que por ahora lo arregle solo el pop-up. Si algun dia se quiere alinear el resto,
-- hay que mirar que bajar 25 % el valor de los pedidos de contado retiene a menos gente por
-- limite de credito.
