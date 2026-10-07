-- v27.69 (07/10/2026): el MONITOR vuelve a traer dato. Fix del regresión de la v27.54.
--
-- Qué pasó: la v27.54 (jornada arranca al fichar) agregó la lectura de GV_Dispositivo_Login a
--   gv_monitor_horas_operario_dia(date) y a su copia gv_horas_operario_detalle_v2(date), pero las
--   dejó SECURITY INVOKER. anon y authenticated sólo tienen INSERT en GV_Dispositivo_Login
--   ("anon sólo INSERTA", regla v25.25), así que el front —que lee la vista security_invoker
--   gv_monitor_horas_operario como anon— recibía:
--       ERROR 42501: permission denied for table GV_Dispositivo_Login
--   y TODO el bloque RITMO / HORAS / Puntaje del monitor (TV y Mon. Admin) quedaba en «—».
--   La base y el fichaje funcionaban: la vista devolvía dato como postgres (MCP), no como anon.
--
-- Arreglo (patrón v20.45: NO se abre la tabla a anon): las dos funciones pasan a SECURITY DEFINER.
--   Las dos ya tienen `SET search_path = public` fijo, así que el DEFINER es seguro. Leen
--   GV_Dispositivo_Login como owner y la tabla sigue cerrada (anon/authenticated sólo INSERT).
--   El flag prosecdef NO está en prosrc, así que la HUELLA (md5(prosrc), a3847ed8...) y el
--   centinela 337 no se mueven; `gv_huellas_cambiadas` y `gv_reglas_perdidas` siguen vacías.
--   Devuelven horas agregadas por legajo: nada sensible que no muestre ya el monitor.
--
-- Verificado como anon: gv_monitor_horas_operario devuelve las 3 filas del día (antes 42501).
-- Problema 720.

alter function public.gv_monitor_horas_operario_dia(date) security definer;
alter function public.gv_horas_operario_detalle_v2(date)  security definer;

-- Rollback:
-- alter function public.gv_monitor_horas_operario_dia(date) security invoker;
-- alter function public.gv_horas_operario_detalle_v2(date)  security invoker;
