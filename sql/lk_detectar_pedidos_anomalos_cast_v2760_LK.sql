-- v27.60 (Luis, 07/10) · proyecto LK (kwkclwhmoygunqmlegrg) · problema 719
-- detectar_pedidos_anomalos(): en la señal 3, `motivo (text[]) || 'literal'` sin tipo
-- Postgres lo resuelve como array || array y explota con "malformed array literal".
-- Pasaba con todo cliente nuevo con pedido > $3M y abortaba la corrida entera del cron 20:
-- ningún pedido de esa ventana de 15 min se evaluaba. 8 pedidos sin evaluar en 30 días
-- (1452, 1462, 1463, 1475, 1476, 1486, 1629, 1630).
-- Aplicado sobre la definición viva, idempotente:
do $$ declare d text; n text; begin
 d := pg_get_functiondef('public.detectar_pedidos_anomalos()'::regprocedure);
 if d like '%''Cliente nuevo con pedido > $3M''::text%' then return; end if;
 n := replace(d, 'motivo := motivo || ''Cliente nuevo con pedido > $3M'';',
   'motivo := motivo || ''Cliente nuevo con pedido > $3M''::text;  -- v27.60: sin el cast lo toma como array');
 if n = d then raise exception 'no matcheó el texto'; end if;
 execute n;
end $$;
-- Rollback: sacar el ::text (vuelve el bug).
