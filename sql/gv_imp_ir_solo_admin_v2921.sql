-- v29.21 (Luis, 09/10): "NO SE TENDRIA QUE HABER DESCONTADO NADA DE NINGUN PEDIDO QUE NO HAYA SIDO
-- POR MEDIO DEL FRONT DEL ADMIN".
-- El Ingreso a racks de un importado NUNCA descuenta solo el pedido en viaje: con 1 o más pedidos
-- candidatos queda 'a_elegir' en GV_Imp_Ingreso_Racks_Log y lo confirma un admin en
-- Importación → 📥 Recibido (gv_imp_ir_asignar, que fija gv.ir_bache). Retira el «un solo pedido
-- → se descuenta solo» de la v28.96 / v29.13. No mueve stock.
-- Aplicado el 09/10 (marcador en la base: v29.19-ir-solo-admin — llave de idempotencia, no cambiar).
-- Probado en transacción abortada: ingreso 953E con 1 pedido en viaje → log a_elegir, llegadas sin cambio.
-- REGLA_CONFIRMADA_POR_USUARIO
do $$
declare d text; n text;
begin
  d := pg_get_functiondef('public.gv_imp_imputar_ingreso_racks(bigint,text)'::regprocedure);
  if position('v29.19-ir-solo-admin' in d) > 0 then return; end if;
  n := replace(d, 'if v_ncand > 1 then', 'if v_ncand >= 1 then  -- v29.19-ir-solo-admin: NUNCA descuenta solo; lo confirma un admin en Importación');
  n := replace(n, '''a_elegir'',
              v_ncand || '' pedidos en viaje de ese código: se elige en Importación''', '''a_elegir'',
              v_ncand || '' pedido(s) en viaje de ese código: lo confirma un admin en Importación''');
  if n = d or position('v_ncand >= 1' in n) = 0 then raise exception 'no matchea el texto vivo'; end if;
  execute n;
  update public."GV_Reglas_Centinela" set patron = 'v_ncand >= 1',
         regla = 'El Ingreso a racks NUNCA descuenta solo un pedido de importación: queda a_elegir y lo confirma un admin en Importación → Recibido (Luis 09/10)',
         version = 'v29.19' where id = 382;
end $$;
-- Rollback: el mismo bloque con los replace al revés (>= 1 → > 1) y el centinela 382 a 'v_ncand > 1'.
