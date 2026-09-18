-- ============================================================================
-- gv_stock_tanda_pickeado_negativo  (v20.13)
--
-- CENTINELA: tandas cuyo Pickeados (deposito `separar_pedidos`) quedo NEGATIVO.
-- Vacia = todo bien.
--
-- POR QUE POR TANDA Y NO POR CODIGO. `gv_stock_negativos` agrega por codigo sin
-- mirar la tanda, asi que el saldo positivo de otra tanda TAPA el agujero: el
-- 18/09 el hueco de E12K eran 34 codigos / 46 cajas y en pantalla se veian 7.
-- Peor: a medida que se armaban otras tandas se iba consumiendo ese colchon y
-- aparecian codigos nuevos en rojo sin que se hubiera roto nada — el cartel
-- prendia y apagaba solo. Mirando por tanda el numero es estable y dice DONDE.
--
-- LOS DOS MOTIVOS QUE DISTINGUE:
--   * "armada sin picking propio": pickeado = 0 y el armado igual drena. Es la
--     firma del bug del renombre (problemas 421 / 437): los eventos PKC llevan
--     la tanda en el campo 1 y se quedaban con el codigo viejo, asi que el
--     reconciliador le acreditaba el picking a la tanda que ya no existe.
--   * "drenaje mayor que el picking": el resto (ajustes, sobre-pickeo).
--
-- Se limita a refs con forma de tanda (`^[A-Z][0-9]{2}[A-Z]$`) a proposito: los
-- refs con pipe (`tanda|NP`) y los de ajuste manual (texto largo) no son pilas
-- de tanda y meterlos da ruido.
--
-- Caso que lo estreno: E12K, 18/09 (§3.kh). Al 18/09 devuelve solo D53A (-2).
-- ============================================================================

create or replace view public.gv_stock_tanda_pickeado_negativo as
with x as (
  select upper(btrim(m.ref)) tanda, upper(btrim(m.cod_art)) cod, m.tipo, m.delta
    from public."Movimientos_Stock" m
   where m.deposito = 'separar_pedidos'
     and upper(btrim(coalesce(m.ref,''))) ~ '^[A-Z][0-9]{2}[A-Z]$'
), t as (
  select tanda,
         coalesce(sum(delta) filter (where tipo = 'picking'), 0)  pickeado,
         coalesce(sum(delta) filter (where tipo = 'separado'), 0) drenado,
         coalesce(sum(delta) filter (where tipo not in ('picking','separado')), 0) otros,
         sum(delta) saldo
    from x group by 1
), c as (
  select tanda, cod, sum(delta) saldo_cod from x group by 1, 2
)
select t.tanda, t.pickeado, t.drenado, t.otros, t.saldo,
       (select count(*) from c where c.tanda = t.tanda and c.saldo_cod < 0) cods_en_rojo,
       (select array_agg(c.cod order by c.saldo_cod, c.cod)
          from c where c.tanda = t.tanda and c.saldo_cod < 0) cods,
       case when t.pickeado = 0 and t.drenado < 0
            then 'armada sin picking propio (el picking quedo en otra tanda)'
            else 'drenaje mayor que el picking' end motivo
  from t
 where t.saldo < 0
 order by t.saldo;

-- ⚠ Sin esto la vista corre como `postgres` y saltea la RLS.
alter view public.gv_stock_tanda_pickeado_negativo set (security_invoker = true);

comment on view public.gv_stock_tanda_pickeado_negativo is
  'Centinela: tandas con Pickeados (separar_pedidos) negativo. Vacia = todo bien. Distingue "armada sin picking propio" (el picking quedo en otra tanda por un renombre) de "drenaje mayor que el picking". Mira POR TANDA, no por codigo: gv_stock_negativos agrega por codigo y el saldo de otra tanda tapa el agujero.';

-- chequeo
-- select * from public.gv_stock_tanda_pickeado_negativo;
