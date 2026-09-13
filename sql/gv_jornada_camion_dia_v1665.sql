-- v16.65 — El tope de jornada se mide por VEHÍCULO y por DÍA, no por tanda.
--
-- Qué estaba mal (problema 112): el aviso de la v15.86 agrupa con `_pppCamiones`, que arma un
-- camión por número de tanda. Medido sobre la programación real del 14 al 18/09/2026, los 17
-- "camiones" que salen de ahí dan como mucho 5,7 h, así que el aviso no aparecía nunca. Pero los
-- fleteros son DOS y casi nunca hacen dos vueltas (Thomas, 11/09), y el 16/09 tenía 6 tandas que
-- suman 20,6 h de camión y 448 km: repartidas en 2 vehículos son 10,3 h cada uno.
--
--   Día     Tandas  NP  Paradas   km   h-camión   ÷2
--   14/09      4    39     17     199    11,4     5,7
--   15/09      4    32     19     273    14,5     7,2
--   16/09      6    24     18     448    20,6    10,3  ← se pasa
--   17/09      2    29     16      76     6,7     3,4
--   18/09      1     7      4      39     2,4     1,2
--
-- El parámetro nuevo. Los otros cuatro (v15.86) siguen igual.
insert into public."PPP_Web_Config" (clave, valor, descripcion)
values ('jornada_camiones', '2',
        'Camiones/fleteros que reparten por dia. El aviso de jornada suma las horas de todas las '
        'tandas del dia (sin Retira) y las divide por este numero: si da mas de jornada_horas_max, '
        'avisa. Thomas 11/09: "son 2, pero no hacen dos vueltas casi nunca".')
on conflict (clave) do nothing;

-- Los cinco juntos:
--   select clave, valor from public."PPP_Web_Config" where clave like 'jornada%' order by clave;
--   jornada_camiones     2      vehículos que reparten en el día
--   jornada_factor_ruta  1.35   calle real ÷ línea recta
--   jornada_horas_max    8      tope del día, por vehículo
--   jornada_km_h         28     velocidad de marcha
--   jornada_min_parada   15     descarga por cliente (una parada = una dirección)
--
-- Rollback (vuelve al aviso sólo por tanda, que en la práctica no salta nunca):
--   delete from public."PPP_Web_Config" where clave = 'jornada_camiones';
-- Subir el número apaga el aviso sin tocar código (con 8 camiones ningún día del 14-18/09 avisa).
--
-- No toca ningún objeto de Producción: sólo agrega una fila a una tabla nuestra (`PPP_Web_Config`).
-- El cálculo vive en el front (`_pppComputeErrors` → `jornadaDia`, `pppErroresHtml`), porque es un
-- AVISO sobre lo ya programado, no una regla que escriba datos: nada se persiste ni se bloquea.
