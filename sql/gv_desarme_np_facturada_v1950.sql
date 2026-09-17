-- ============================================================================
-- v19.50 — LAS 11 FILAS QUE MARCÓ EL CENTINELA: 8 estaban BIEN, 3 eran un agujero
-- Gestión Virgilio · proyecto hrxfctzncixxqmpfhskv · 2026-09-17
-- Pedido de Luis: "fijate las 11 de CP también"
-- ============================================================================
--
-- ⚠ PRIMERO, LA CORRECCIÓN DEL DIAGNÓSTICO: **no eran drenajes de CP**. Son
-- `tipo = 'desarme'`, o sea el desarmar/cancelar pedido. Lo de "CP" fue una
-- suposición mía al ver el ref con forma de NP; mirando las filas de verdad, no.
--
-- ============================================================================
-- 1. LAS 8 DE `LK 0034` ESTABAN BIEN — era un FALSO POSITIVO del centinela
-- ============================================================================
-- NP LK 0034 (Mitre Hugo Alberto, order 1364), tanda E01G, desarmada el 15/09:
--
--   15:31:47  separado  ref = E01G       a_facturar  +2 +1 +3 +4 +1 +1 +4 +1  (16 cajas)
--   15:53:20  desarme   ref = LK 0034    a_facturar  -2 -1 -3 -4 -1 -1 -4 -1  (16 cajas)
--
-- Balanceado al centavo. El problema era del centinela: la ENTRADA va con
-- `ref = tanda` y la SALIDA del desarme con `ref = NP`, así que agrupando por el
-- prefijo del ref quedaban en dos pilas distintas y la de la NP salía en rojo.
--
-- Corregido: el centinela ahora le devuelve cada desarme a su tanda leyendo el
-- **"(tanda XXXX)" de la descripción**, que es lo que escribe `gv_ppp_np_desarmar`.
-- Es el mismo truco que ya usa el CTE `dev` de `gv_ppp_np_devolucion`.

create or replace view public.gv_stock_afacturar_tanda_negativa as
with m as (
  select
    coalesce(
      case when tipo in ('desarme','ajuste')
           then nullif(upper((regexp_match(coalesce(descripcion,''), '\(tanda ([A-Za-z0-9]+)\)'))[1]), '') end,
      upper(btrim(split_part(btrim(coalesce(ref,'')),'|',1)))
    ) clave,
    regexp_replace(upper(btrim(cod_art)),'^0+(?=.)','') cod,
    delta, ts
  from public."Movimientos_Stock"
 where deposito = 'a_facturar'
)
select clave,
       case when clave ~ '^[A-Z][0-9]{2}[A-Z]$' then 'tanda' else 'np' end clase,
       cod,
       round(sum(delta),2) saldo,
       count(*) movimientos,
       max(ts) ultimo_mov,
       case when clave ~ '^[A-Z][0-9]{2}[A-Z]$'
            then 'La pila de esa tanda se drenó dos veces. Lo frena el guard zzz_facturado_no_negativo cuando el drenaje es un facturado; un desarme sobre una NP ya facturada NO lo toca (problema abierto).'
            else 'Salida de a_facturar bajo una clave que no es tanda y sin entrada bajo esa misma clave. Revisar a mano.'
       end que_significa
  from m
 where clave ~ '^([A-Z][0-9]{2}[A-Z]|[0-9]{4,6}|(LK|CH) ?[0-9]{4})$'
 group by 1,3
having round(sum(delta),2) < 0
 order by 2, 4;

-- ⚠ OBLIGATORIO después de un CREATE OR REPLACE VIEW: el REPLACE borra las
--   reloptions, o sea que te comés el security_invoker.
alter view public.gv_stock_afacturar_tanda_negativa set (security_invoker = true);

comment on view public.gv_stock_afacturar_tanda_negativa is
 'v19.50 - CENTINELA. Vacia = todo bien. Mide la pila de a_facturar por TANDA, devolviendo cada desarme a su tanda por el "(tanda XXXX)" de la descripcion: la entrada va con ref = tanda y la salida del desarme con ref = NP, asi que sin eso un desarme balanceado sale rojo. gv_stock_negativos NO ve esto: agrega por codigo sin mirar la tanda, asi que el saldo positivo de otra tanda lo tapa.';

-- ============================================================================
-- 2. LAS 3 DE `98507` SÍ ERAN UN AGUJERO
-- ============================================================================
-- NP 98507 (Perez Zarate S.R.L., cod 4036), tanda D53C.
--
--   01/09 15:08  separado                ref = D53C        a_facturar  404E +1 · 522E +2 · 599E +3
--   02/09 08:46  facturado               ref = D53C|98497  a_facturar  522E -1 · 599E -2
--   02/09 08:48  facturado               ref = D53C|98507  a_facturar  404E -1 · 522E -1 · 599E -1
--   ────────────────────────────────────────────────────── pila de D53C en 0 ✔
--   17/09 16:09  desarme  ref = 98507    a_facturar  -1 -1 -1   ← saca de una pila VACÍA
--                                        a_guardar   +1 +1 +1
--   17/09 16:25  guardado (legajo 104)   a_guardar -1 -1 -1 · terminado +1 +1 +1
--
-- Justificativo del desarme: *"Cancelado desde la PPP: Cancelo el pedido el cliente
-- proque no cubre el flete"*, por `loekemeyer.n8n@gmail.com`.
--
-- **Las cajas físicas están bien**: el pedido se canceló, nunca salió, y volvieron a
-- góndola. Lo que quedó mal es el ASIENTO: la NP ya se había facturado el 02/09 —y el
-- facturado significa "estas cajas salieron del depósito"—, así que al volver había que
-- deshacer ESE asiento, no sacar otra vez de `a_facturar`. Resultado: `a_facturar` en
-- −3 y el stock total 3 cajas corto (la góndola, en cambio, quedó bien).
--
-- CAUSA: `gv_ppp_np_desarmar` **no mira si la NP está en `Facturacion_NP`**. El sistema
-- YA tiene el camino correcto y completo —borrar la fila de `Facturacion_NP` dispara
-- `revertir_drenaje_facturado()` (borra el drenaje, la pila vuelve) y
-- `isis_anular_facturado()` (encola la anulación en ISIS)—, pero el desarme ni lo usa
-- ni avisa. El guard de la v19.34 que sí existe mira **CCN / CRN** (carga camión y
-- recepción remitos), no la facturación, y esta NP no tenía ninguno de los dos.
--
-- ⚠ Y el guard `zzz_facturado_no_negativo` (v19.49) tampoco lo frena, a propósito:
--    sólo mira `tipo = 'facturado'`. Un desarme no es un drenaje de facturación.

-- Corrección del asiento (3 filas). Repone lo que el facturado había descontado, bajo
-- el mismo ref del desarme, así la pila de D53C cierra en 0:
insert into public."Movimientos_Stock"
  (cod_art, descripcion, deposito, delta, tipo, ref, legajo, empresa)
select d.cod,
  'Reversa del facturado del 02/09 de la NP 98507 (tanda D53C): el cliente canceló el pedido y las cajas volvieron a góndola, así que nunca salieron. El desarme del 17/09 las sacó de a_facturar cuando esa pila ya estaba en 0 por el facturado, y dejó el depósito en -1. Esta fila repone lo que el facturado había descontado. v19.50',
  'a_facturar', 1, 'ajuste', '98507', 'sistemas', 'LK'
from (values ('404E'),('522E'),('599E')) d(cod);
-- después: select public.refresh_stocks_carga_rapida();
-- Verificación: gv_stock_afacturar_tanda_negativa quedó VACÍA y gv_stock_negativos en 0.

-- ============================================================================
-- 3. LO QUE FALTA DECIDIR (problema 392, ABIERTO)
-- ============================================================================
-- Qué tiene que hacer el desarme cuando la NP YA está facturada. Dos caminos, y la
-- diferencia no es técnica sino de negocio, porque toca la factura:
--
--   (A) FRENARLO, como ya se frena el "ya salió" de la v19.34: *"la NP está facturada:
--       primero hay que desfacturarla"*. El operador de Facturación borra la fila de
--       `Facturacion_NP` —que revierte el drenaje Y encola la anulación en ISIS— y recién
--       ahí desarma. Es el camino completo: deja bien el stock Y la factura.
--
--   (B) COMPENSARLO SOLO: que el desarme escriba la reversa del facturado (lo que se hizo
--       a mano acá arriba) y siga. El stock queda bien al instante, pero la factura queda
--       parada y a alguien le toca acordarse de la nota de crédito.
--
-- No se implementó ninguno: (A) cambia un flujo que Facturación usa todos los días y (B)
-- deja una factura emitida sin avisar. Mientras tanto el centinela lo canta el mismo día.
-- ============================================================================
