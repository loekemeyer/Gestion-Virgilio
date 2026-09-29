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

-- ============================================================================
-- v24.34 — DEFINICIONES DE LUIS (29/09) y lo que cambiaron
--
-- 1) "cada empresa maneja su deuda en sus cuentas. un cliente que tiene deuda por compras
--     con chef va a pagar por medio de chef y lo mismo con loeke"
--    => LA EMPRESA LA DA LA CUENTA BANCARIA, no la deuda. Lo que entra al Credicoop de
--       Loeke es de LK, punto. El CUIT solo elige el CODIGO dentro de esa empresa.
--       gv_cobranza_cliente_por_cuit paso a recibir la empresa: gv_conc_cliente_por_cuit(cuit, empresa).
--       Se retira el desempate por deuda que tenia la version anterior.
--       Si el CUIT no tiene codigo en la empresa de la cuenta, la fila sale con alerta
--       ("pago en la cuenta equivocada o falta darlo de alta"): NO se lo manda a la otra empresa.
--       Medido: los 11 CUIT distintos de los extractos dan codigo UNICO en LK.
--
-- 2) "el programa lo arma uno por uno ... pero todos los datos al maximo que se puedan derivar"
--    => nada de agrupar los gastos en un renglon por dia: eso queda para la vista o la impresion.
--       El motor devuelve una fila por movimiento del extracto.
--
-- 3) "nro de recibo es un numero que se genera de ISIS. dejalo vacio vos"
--    => la columna I sale siempre NULL.
--
-- gv_conc_proponer(banco, empresa, movimientos jsonb) arma las filas de la conciliacion
-- desde el extracto crudo, con todo lo que se puede derivar:
--   fecha | operacion | entrada | salida | detalle | det | nro_op | nro_recibo (vacio) |
--   cod_cliente | cliente | cuit | cbu | es_cobranza | deuda_cliente | cancela | alerta
-- "cancela" propone el comprobante cuando el importe coincide EXACTO con un pendiente del
-- cliente; el cruce fino de pagos parciales ya lo hace gv_cobranza_imputar.
--
-- Prueba (5 movimientos reales del 25 y 28/09):
--   select * from public.gv_conc_proponer('credicoop','lk','[{"fecha":"2026-09-28",
--     "concepto":"Credito Inmediato (DEBIN) dist titular 30718101243-VAR-BAZAR MONICA S CAP I SE CBU Origen:3220001805000054570077",
--     "debito":0,"credito":472524.71,"nro_op":"80009"}]'::jsonb);
--   -> Deposito | D | 4045 | Bazar Monica S. CAP I SECC IV | 30718101243 | sin alerta
--
-- ROLLBACK de esta parte:
-- drop function if exists public.gv_conc_proponer(text,text,jsonb);
-- drop function if exists public.gv_conc_cliente_por_cuit(text,text);

-- ============================================================================
-- v24.35 — SANTANDER: otro formato, y NO trae CUIT
--
-- Extracto "descargaUltimosMovimientos.xls" (Santander Chef, cuenta 058-004885/5):
--   Fecha | Suc. Origen | Desc. Sucursal | Cod. Operativo | Referencia | Concepto | Importe | Saldo
--   · DOS bloques en la misma hoja: "Movimientos del Dia" y "Ultimos Movimientos",
--     cada uno con su propio encabezado. Hay que leer los dos y deduplicar.
--   · El IMPORTE viene en UNA sola columna: entre parentesis = DEBITO, sin parentesis = CREDITO.
--     Formato es-AR (punto de miles, coma decimal): "(2.149,55)" = -2.149,55.
--   · El saldo de la ultima fila del bloque del dia viene vacio.
--
-- ⚠⚠ LA DIFERENCIA QUE MANDA: Santander NO trae CUIT ni nombre. El concepto es generico
--    ("Deposito de efectivo en sucursal - Tarj nro... atm... op..."). Lo que SI trae y sirve:
--      · Cod. Operativo — el codigo del banco, estable: 2030 deposito de efectivo en sucursal ·
--        0867 valor al cobro comp elect propia localidad · 0870 idem otra localidad ·
--        0869 deposito ch 48 hs camara local · 4633/4637 impuesto al cheque · 3253/3254/1923
--        percepciones · 2960/3489/0960 comisiones.
--      · Suc. Origen + Desc. Sucursal — DONDE se deposito (Rosario, Rio Cuarto, Cordoba).
--
-- Medido sobre el extracto: 12 de 12 movimientos clasificados por regla, 0 con CUIT.
-- El importe exacto tampoco alcanza: las 5 entradas dieron 0 candidatos contra la deuda
-- viva de Chef (que hoy tiene 97 filas / 36 clientes).
--
-- => PARA SANTANDER EL CLIENTE NO SALE DEL EXTRACTO. Sale del apareo contra lo PROYECTADO:
--    el manual dice que los cheques se cargan uno por uno como "A DEPOSITAR" con su cliente y
--    su recibo, y pasan a "DEP./CH" cuando se acreditan. O sea que el dato ya esta cargado
--    antes: el motor tiene que aparear importe (y fecha) contra esas filas, no inventarlo.
--    Medido: 4.821 filas de deposito/cheque en la base, 3.776 con cliente (78 %) y 3.747 con recibo.
--
-- ROLLBACK: las reglas de santander se sacan con
--   delete from public."GV_Conc_Regla" where banco = 'santander';

-- ============================================================================
-- v24.36 — SANTANDER, con el extracto largo (203 movimientos, 01 al 29/09, Santander Chef)
--
-- ⚠ SE RETIRA lo que decia la v24.35 ("Santander NO trae CUIT"): el extracto corto no tenia
--    transferencias. Santander SI trae el CUIT en las transferencias, al final:
--      "Transferencia recibida - De aloe/dario rafael      / ... - fac / 20210080415"
--      "Transf recibida cvu dif titular - De guillermina soledad troil/ mercado pago /27318504836"
--      "Pago a proveedores recibido - Castets y tanino srl  30606858058 03 1780871"
--    Lo que NO lo trae: el efectivo en sucursal (2030) y los cheques/e-cheq (3036, 3042, 3034,
--    0867, 0869, 0870).
--
-- Reglas de santander rehechas POR CODIGO OPERATIVO (columna nueva GV_Conc_Regla.codop):
-- 28 reglas; gv_conc_parse recibe p_codop y lo prefiere al texto.
--
-- MEDIDO contra la conciliacion que ya cargaron (gv_conciliacion_bancaria, santander/chef,
-- mismo importe y fecha +-10 dias):
--   entradas con CUIT: 27 -> la persona identifico 27 · el motor 25 · COINCIDEN 24 · difiere 1
--     · difiere: $883.469,27 "De loekemeyer hnos srl" -> la persona lo cargo como ARYLO S.A (2419):
--       LK cobro por cuenta de un cliente. => un CUIT propio YA NO saca el movimiento de la
--       cobranza: sale con alerta para identificarlo a mano (GV_Conc_Cuit_Propio).
--     · sin codigo (2): quien paga no es el cliente. Lisia Nina Manzetti (27120479437) pago por
--       SUCESION DE ZAPATA RICARDO (1796); Mario Dealbera (20278713017) por MARDO MAYORISTA (2677).
--       => tabla nueva GV_Conc_Alias_Pagador (empresa, cuit_pagador, cod_cliente): se consulta
--       ANTES que el padron. Nace VACIA: los dos alias medidos esperan el si de Luis.
--   entradas sin CUIT: 14 -> la persona identifico 6 (5 e-cheq que ya estaban A DEPOSITAR con
--     cliente y recibo + 1 efectivo en Rosario = P & M BAZAR 2701); los otros 8 tambien quedaron
--     "No Identificado" (det 1) en la planilla. El motor todavia no aparea contra A DEPOSITAR:
--     los marca con alerta.
--   Manual: un deposito que no se pudo identificar va con det = 1 (no D). gv_conc_proponer lo hace.
--
-- La planilla cargada NO guarda el concepto crudo del banco (solo en la observacion de los no
-- identificados): el historico no sirve para saber que traia el extracto; los extractos crudos si.
