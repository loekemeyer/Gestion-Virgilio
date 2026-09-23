-- v21.75 (23/09) — La capacidad FÍSICA del camión, para el Resumen de la PPP.
--
-- Textual: *"no hay límite para arriba en la cantidad de metros cúbicos por camión.
-- Puedo tener hasta 40 metros cúbicos en un camión"*.
--
-- ⚠ NO confundir con `camion_m3_tope` (6), que YA EXISTE y NO se toca: ése es el tope de
--   lo que el armador MEZCLA en una tanda (`gv_ppp_web_agrupar_geo`, `gv_ancla_simular`),
--   no lo que entra en el camión. Tomar uno por el otro es lo que hacía que el Resumen
--   contara 3 camiones para el pedido de un solo cliente de 12,33 m³ del 28/10.
--
-- El front ya funciona SIN esta fila: `_pppJorCfg.camionM3` trae 40 de default. La fila
-- sólo sirve para poder cambiar el número por SQL, sin deploy. Entra por el fetch que ya
-- existe (`PPP_Web_Config?clave=like.jornada*`), o sea que no agrega ninguna llamada.
--
-- ⚠ PENDIENTE DE AUTORIZACIÓN: es un INSERT en una tabla de datos. No ejecutado.

insert into public."PPP_Web_Config" (clave, valor)
values ('jornada_camion_m3_cap', 40)
on conflict (clave) do nothing;

-- Chequeo:
-- select clave, valor from public."PPP_Web_Config" where clave like 'jornada%' order by 1;
