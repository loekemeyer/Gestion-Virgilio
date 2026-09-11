-- v15.86 (2026-09-11) — LÍMITE DE JORNADA DEL CAMIÓN. Thomas: *"al tiempo de viaje entre paradas
-- (máx 8 hs en un día) hay que considerar que hay tiempo parado para descargar cada pedido.
-- Considerá por ahora sólo 15' por parada x cliente. Más que 8 hs por día no se puede programar"*.
-- Y sobre los otros dos números: *"lo lógico para un camión, definí vos"*.
--
-- Los CUATRO parámetros viven en PPP_Web_Config (se cambian por SQL, sin tocar código ni redeployar):
--
--   jornada_horas_max   = 8      el tope de Thomas
--   jornada_min_parada  = 15     lo que tarda bajar un pedido, también de Thomas
--   jornada_km_h        = 28     velocidad de MARCHA de un camión de reparto en AMBA. No es la
--                                velocidad "comercial" (22-25) porque el tiempo parado ya se cuenta
--                                aparte: son sólo los tramos en movimiento, con semáforos y tráfico.
--   jornada_factor_ruta = 1.35   el recorrido por calle contra la distancia en línea recta. En una
--                                ciudad en grilla la relación es 1,27-1,40; se toma el medio.
--
-- LOS DOS ÚLTIMOS SON UNA ESTIMACIÓN y hay que recalibrarlos: las horas reales van a entrar por la
-- hoja de ruta del fletero (GV_Viaje_Horas, §3.bx) y ahí se compara contra lo estimado. Hasta
-- entonces el número sirve para comparar camiones entre sí, no como promesa al cliente.
--
-- El cálculo vive en el FRONT (index.html: _pppJornadaCam) y no en SQL a propósito: el recorrido
-- óptimo ya lo resuelve _rtOptimize (nearest-neighbour + 2-opt, v4.84) con las coordenadas que la
-- PPP ya tiene cargadas; reescribir un TSP en plpgsql para el mismo resultado sería peor. Lo que sí
-- vive en el backend es la REGLA (los cuatro números), que es lo que se cambia.
--
-- MEDIDO el 11/09 sobre lo programado (28 km/h · 1,35 · 15' · tope 8 h):
--   16/09 Norte  13 paradas · 207 km · 10,6 h  → se pasa (con Luján; sin Luján: 8,5 h, sigue pasado)
--   15/09 Sur    18 paradas · 148 km ·  9,8 h  → se pasa
--   14/09 Sur    16 paradas · 135 km ·  8,8 h  → se pasa
--   17/09 Sur    16 paradas ·  57 km ·  6,0 h  → entra
--   18/09 Sur     4 paradas ·  51 km ·  2,8 h  → entra
--
-- ROLLBACK: delete from public."PPP_Web_Config" where clave like 'jornada%';
--           (sin las filas el front usa sus defaults, que son los mismos números)

insert into public."PPP_Web_Config" (clave, valor) values
  ('jornada_horas_max',   8),
  ('jornada_min_parada',  15),
  ('jornada_km_h',        28),
  ('jornada_factor_ruta', 1.35)
on conflict (clave) do update set valor = excluded.valor;

-- para verlos:
-- select clave, valor from public."PPP_Web_Config" where clave like 'jornada%' order by clave;
