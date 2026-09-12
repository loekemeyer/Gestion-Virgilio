-- =====================================================================
-- VOCABULARIO de GP2 — catalogos chicos cuyo CONTENIDO es parte del contrato con las pantallas.
-- No son datos de negocio: son las palabras que el JS y el SQL tienen que compartir. Por eso
-- viven en git y no solo en la base (db/tablas_GP2.sql guarda el DDL, no las filas).
-- Regenerar junto con db/ cuando se agregue o se renombre una clave.
--
-- tipo_movimiento: hasta el 2026-09-11 esto era un CHECK con 19 literales, y ademas estaba
-- copiado en tres mapas de JS. Los tres se desfasaron: gp2-stock-sector.js sumaba columnas por
-- cinco palabras que el CHECK prohibia ("produccion", "envio_prov", "envio_tall",
-- "recepcion_prov", "recepcion_tall") -- esas columnas daban 0 siempre -- y a los tres les
-- faltaba "traslado". Ahora es una tabla, movimiento.tipo_mov tiene FK contra ella,
-- movimientos_bundle la sirve en `tipos_mov` y tests/ui/test_vocabulario_mov.js falla si una
-- pantalla nombra una palabra que no esta aca.
-- =====================================================================

insert into "GP2".tipo_movimiento (clave, label, lado, clase, orden) values
  ('compra',                'Compra',                        'ent','t-compra',   10),
  ('fabricacion',           'Fabricación',                   'neto','t-fabrica', 20),
  ('armado_fabrica',        'Armado en fábrica',             'ent','t-fabrica',  25),
  ('consumo_prod',          'Consumo de producción',         'sal','t-consumo',  30),
  ('consumo',               'Consumo de materia prima',      'sal','t-consumo',  35),
  ('envio_ps',              'Envío a prov. de servicio',     'sal','t-envio',    40),
  ('entrega_ps',            'Entrega del prov. de servicio', 'ent','t-entrega',  45),
  ('envio_tallerista',      'Envío a tallerista',            'sal','t-envio',    50),
  ('entrega_tallerista',    'Entrega del tallerista',        'ent','t-entrega',  55),
  ('consumo_tall',          'Consumo del tallerista',        'sal','t-consumo',  60),
  ('devolucion_tallerista', 'Devolución del tallerista',     'ent','t-entrega',  65),
  ('envio_prov_at',         'Envío a prov. art. terminado',  'sal','t-envio',    70),
  ('recepcion_virgilio',    'Recepción en Virgilio',         'sal','t-entrega',  75),
  ('consumo_virgilio',      'Consumo por entrega a Virgilio','sal','t-consumo',  80),
  ('envio_inyector',        'Envío al inyector',             'sal','t-envio',    85),
  ('consumo_inyector',      'Consumo del inyector',          'sal','t-consumo',  90),
  ('traslado',              'Traslado a/desde Virgilio',     'neto','t-envio',   95),
  ('stock_inicial',         'Stock inicial',                 'ent','t-ajuste',  100),
  ('ajuste',                'Ajuste',                        'neto','t-ajuste', 105)
on conflict (clave) do update set label = excluded.label, lado = excluded.lado,
                                  clase = excluded.clase, orden = excluded.orden;
