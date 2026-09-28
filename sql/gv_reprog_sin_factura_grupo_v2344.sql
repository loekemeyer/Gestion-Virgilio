-- v23.44 (Luis 28/09): el cron 96 de las 18:00 (gv_ppp_reprogramar_sin_factura) re-optimiza con la
-- regla de UN GRUPO DE ZONAS POR DIA (gv_ppp_web_dia_grupo) todo lo que NO se programo a mano.
-- Lo fijado a mano (creado_por <> 'sistema' o marca gv_manual_por) sigue la regla vieja: proximo
-- dia con camion a su zona. Super, Retira y tanda mitad facturada: aviso, como siempre.
--
-- 1) Marca de "a mano": columnas nullables + trigger que las llena SOLO si el cambio entra por
--    PostgREST con mail en el JWT (una persona). pg_cron y el armador (service_role) no marcan.
alter table public."PPP_Web_Programacion" add column if not exists gv_manual_por text, add column if not exists gv_manual_at timestamptz;
alter table public."GV_PPP_Prog_Override" add column if not exists gv_manual_por text, add column if not exists gv_manual_at timestamptz;
-- (cuerpo de trg_gv_marca_manual: ver pg_get_functiondef; triggers gv_marca_manual en las dos tablas,
--  before insert or update of fecha_entrega, tanda)
--
-- 2) La funcion se parcheo sobre pg_get_functiondef (marcador interno 'v23.43-grupo', llave de
--    idempotencia): agrega zona_larga / a_mano / entrada / expreso al loop y, si no es a mano,
--    destino = gv_ppp_web_dia_grupo(zona_larga, entrada, expreso, v_obj + 1, m3).
--
-- Probado: simulacion del 29/09 -> E29G Z3 -> 30/09, E90B y E99A Z1 -> 01/10, F01F Z4 -> 05/10, E30A super aviso.
-- Trigger probado en transaccion abortada: sin JWT no marca; con JWT {"email":...} marca.
--
-- Rollback:
--   drop trigger gv_marca_manual on public."PPP_Web_Programacion";
--   drop trigger gv_marca_manual on public."GV_PPP_Prog_Override";
--   y reponer la funcion sin el bloque v23.43-grupo (el else vuelve a gv_ppp_web_dias_ancla solo).

-- v23.45 (Luis 28/09) sobre la misma funcion (marcadores 'v23.45-proceso' y 'v23.45-fijada'):
--   · EN PROCESO (pickeo/armado empezado sin TAP) -> aviso_en_proceso, no se mueve.
--   · DIFERIDO por reingreso (GV_PPP_Web_Diferido) o CLIENTE NUEVO aprobado (gv_clin_prioritarios)
--     -> aviso_fijada, no se reacomoda.
--   · Piso "un dia se arma, el siguiente se factura, el siguiente sale": armada -> desde v_obj+1;
--     sin empezar -> desde el habil siguiente a v_obj + 1.
-- Marcado historico de "a mano": 38 tandas / 116 NP del 23 al 28/09, reconstruido cruzando la hora de
-- cada llamada del panel (edge_logs, POST rpc gv_ppp_*mover/programar/reprog) con actualizado_at (±6 s).
-- gv_manual_por = 'manual (reconstruido de logs del panel)'.

-- v23.49 (Luis 28/09, v23.50): "NADA DE LO QUE SE PROGRAMA MANUAL SE MUEVE, se programo manual por algun
-- motivo (programado manual o movido manual)". Una tanda a_mano ya no se corre: sale 'aviso_manual'.
-- Centinela: GV_Reglas_Centinela (gv_ppp_reprogramar_sin_factura, patron 'aviso_manual').
-- -- REGLA_CONFIRMADA_POR_USUARIO
do $x$ declare d text;
begin
  d := pg_get_functiondef('public.gv_ppp_reprogramar_sin_factura(boolean,date)'::regprocedure);
  if d ~ 'aviso_manual' then return; end if;
  d := replace(d, $a$    elsif r.fijada is not null then$a$,
                  $a$    elsif r.a_mano then
      v_acc := 'aviso_manual'; v_avi := v_avi + 1;
      v_det := 'PROGRAMADA/MOVIDA A MANO: no se mueve sola, lo decide una persona.';
    elsif r.fijada is not null then$a$);
  if d !~ 'aviso_manual' then raise exception 'parche no matcheo'; end if;
  execute d;
end $x$;
