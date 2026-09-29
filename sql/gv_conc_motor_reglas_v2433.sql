-- v24.33 — MOTOR DE CONCILIACION, primera pieza: leer el extracto CRUDO de Credicoop Loeke
--
-- Luis (29/09) paso el Manual N 39, la conciliacion cerrada al 24/09 y los extractos crudos
-- del 27 y 28/09: "determina las reglas de la conciliacion y que la pueda hacer el programa
-- por su cuenta a futuro (quiero que agregue data como cuits de clientes y mas cosas que el
-- excel de conciliacion no tiene)".
--
-- HALLAZGO QUE CAMBIA TODO: el extracto crudo de Credicoop SI trae el CUIT, pegado en el
-- texto del concepto. El Excel de conciliacion NO lo tiene — se pierde al copiar a mano:
--   "Credito Inmediato (DEBIN) dist titular 30718101243-VAR-BAZAR MONICA S CAP I SE CBU Origen:32200..."
--    -> CUIT 30718101243, nombre "BAZAR MONICA S CAP I SE", CBU 3220001805000054570077
--
-- MEDIDO sobre los 189 movimientos de los dos extractos (25 al 28/09):
--   · 189 de 189 clasificados por regla (operacion + codigo del Manual N 39)
--   · 13 entradas, 12 con CUIT en el texto (la 13a es "Acreditacion Valores Camara", que son
--     los cheques de terceros acreditandose: no trae CUIT por diseno)
--   · 12 de 12 CUIT encontrados en el padron -> cliente y codigo
-- La conciliacion esta cerrada al 24/09 con saldo 129.389.443,37 (hoja "CONCILIACION 2026",
-- fila de la linea amarilla).
--
-- FORMATO DESTINO (columnas de la planilla, Manual N 39):
--   A Fecha | B Operacion | C ENTRADA | D SALIDA | E SALDO | F DETALLE | G DET | H Nro OP |
--   I Nro Recibo | J Prov/Cliente (codigo)
-- Codigos de la columna G: 1 deposito no identificado · 3 cheque de terceros · AP aporte de
-- capital · CS cargas sociales · D deposito identificado · G gastos · C.EXT importacion ·
-- IMP iva/iibb/retenciones · P cheque propio · PNI cheque propio no ingresado · RECH cheque
-- rechazado · S sueldos · TP tarjeta precargada · T transferencia.
--
-- ⚠ LO QUE EL MANUAL DICE Y HAY QUE RESPETAR:
--   · Debito = egreso, Credito = ingreso.
--   · Arriba de la linea amarilla va lo CONCILIADO; abajo lo PROYECTADO (pendiente de salida).
--     Transferencias, cargas sociales y sueldos van siempre proyectados.
--   · Los gastos van en UNA sola linea por dia (la suma), salvo SIRCREB, que va aparte.
--   · Los cheques a depositar se cargan uno por uno como "A DEPOSITAR" y pasan a "DEP./CH"
--     cuando se acreditan. Eso explica las filas repetidas del mismo recibo en la base:
--     son el cheque proyectado a su fecha de vencimiento, no un pago distinto.
--   · "Deposito/Credito Inmediato", "Credito Inmediato (DEBIN)" y "Transf. Inmediata" en la
--     columna de Credito son DEPOSITOS.

create table if not exists public."GV_Conc_Regla" (
  id bigserial primary key,
  banco text not null default 'credicoop',
  orden int not null default 100,
  patron text not null,                 -- regex sobre el concepto del extracto
  lado text not null default 'ambos',   -- 'credito' | 'debito' | 'ambos'
  operacion text not null,              -- columna B de la conciliacion
  det text not null,                    -- columna G: el codigo del Manual N 39
  es_cobranza boolean not null default false,
  saca_cuit boolean not null default false,
  nota text,
  activo boolean not null default true,
  creado_en timestamptz not null default now()
);
alter table public."GV_Conc_Regla" enable row level security;
drop policy if exists gv_conc_regla_lee on public."GV_Conc_Regla";
create policy gv_conc_regla_lee on public."GV_Conc_Regla" for select using (true);
revoke insert, update, delete, truncate on public."GV_Conc_Regla" from anon, authenticated;

-- Las 21 reglas cargadas para credicoop estan en la tabla: agregar una es un INSERT, no un
-- deploy. Se listan con:  select orden, lado, patron, operacion, det from public."GV_Conc_Regla"
--                          where banco='credicoop' order by orden;

-- traduce el concepto crudo a las columnas de la conciliacion + saca CUIT, nombre y CBU
-- (el cuerpo vigente sale de: select pg_get_functiondef('public.gv_conc_parse(text,text,numeric,numeric)'::regprocedure))
--   select public.gv_conc_parse('credicoop', <concepto>, <debito>, <credito>);
--     -> {"regla":1,"operacion":"Deposito","det":"D","es_cobranza":true,"lado":"credito",
--         "cuit":"30718101243","nombre":"BAZAR MONICA S CAP I SE","cbu":"32200...","nota":"..."}

-- del CUIT al codigo de cliente. Un CUIT puede tener codigo en LK y en Chef: desempata la
-- DEUDA ABIERTA. Si las dos tienen deuda devuelve las dos con elegido=false y decide una
-- persona — no se adivina.
--   select * from public.gv_conc_cliente_por_cuit('30718101243');   -- lk 4045, elegido
--   select * from public.gv_conc_cliente_por_cuit('33707037739');   -- lk 637 y chef 820, sin elegir

-- ROLLBACK (las tres son nuevas y solo leen; la tabla no la usa nada mas):
-- drop function if exists public.gv_conc_cliente_por_cuit(text);
-- drop function if exists public.gv_conc_parse(text,text,numeric,numeric);
-- drop table if exists public."GV_Conc_Regla";
