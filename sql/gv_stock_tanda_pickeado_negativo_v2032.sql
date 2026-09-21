-- v20.32 (Luis, 2026-09-21) — EL CENTINELA CONTABA EL AJUSTE QUE DESCUENTA Y NO EL QUE LO REVIERTE.
-- Problema 459.
--
-- Sintoma: D53A vivia en rojo ("drenaje mayor que el picking", codigo 839) con el deposito sano.
--
-- Que habia pasado de verdad, en D53A:
--   31/08 09:30-10:00  se pickea la tanda: 28 codigos, 102 cajas. El 839 NO esta (no hay PKC).
--   31/08 11:18        entra un ajuste de -2 en separar_pedidos con ref = 'D53A'.
--   01/09 10:38        alguien lo corrige a mano y deja escrito el motivo:
--                      +2 con ref 'ajuste manual | Revierte ajuste D53A: se cargo -2 en
--                      separar_pedidos pero el picking D53A nunca se registro.'
--                      y -4 en terminado: 'Operario dijo 6, habia 4 y se llevaron todo.'
--   Saldo del 839 hoy: 0 en separar_pedidos, 2 en terminado. No falta ninguna caja.
--
-- La vista agrupaba filtrando `ref ~ '^[A-Z][0-9]{2}[A-Z]$'`, o sea el codigo de tanda PELADO.
-- El -2 lo tiene; el +2 que lo anula no, porque su ref es texto libre. Contaba media pareja.
--
-- Y fallaba en las dos direcciones: hay 47 movimientos en 8 tandas con ref de texto libre que la
-- vista ignoraba. Entre ellos los ajustes negativos que dejaron a D20E en -2 (366E,
-- 'FIX_STOCK_ZERO_366E_D20E') y a E10A en -1 (221, 'correccion 221 NP 98532: la caja se cargo 3
-- veces'), que no aparecian en ningun lado.
--
-- Efecto medido al aplicarlo: D53A sale (queda en 0), entran D20E (-2) y E10A (-1).
-- Los 8 codigos que el regex saca del texto libre son tandas reales: 0 falsos positivos.
-- 128 ms (una primera version cruzaba ademas contra los refs de Movimientos_Stock y tardaba 334).
--
-- Probado de verdad, en una transaccion abortada:
--   · un +2 de reversion con ref de texto libre saca a D20E del centinela;
--   · un ajuste contra la tanda inventada 'Z98Z' NO genera ninguna fila (la validacion contra
--     GV_Tandas_Codigos_Usados hace su trabajo).
--
-- ⚠ Lo que sigue quedando afuera, a proposito: los 143 ajustes de separar_pedidos que no nombran
-- ninguna tanda (suma -54). No hay dato para atribuirlos; van por gv_stock_negativos.

create or replace view public.gv_stock_tanda_pickeado_negativo as
with x as (
  -- (1) el pipeline de la tanda: ref = el codigo pelado
  select upper(btrim(m.ref)) tanda, upper(btrim(m.cod_art)) cod, m.tipo, m.delta, 0 por_texto
    from public."Movimientos_Stock" m
   where m.deposito = 'separar_pedidos'
     and upper(btrim(coalesce(m.ref, ''))) ~ '^[A-Z][0-9]{2}[A-Z]$'
  union all
  -- (2) v20.31 (problema 459) — LOS AJUSTES QUE NOMBRAN LA TANDA EN TEXTO LIBRE.
  -- Un ajuste manual se anota con ref = el codigo pelado, pero su REVERSION se anota con texto
  -- ("ajuste manual | Revierte ajuste D53A: se cargo -2 pero el picking nunca se registro").
  -- Contando uno y no el otro, esta vista veia el -2 de D53A y no el +2 que lo anula: la tanda
  -- vivia en rojo con el deposito sano. Y al reves, los ajustes negativos que dejaron a D20E en
  -- -2 y a E10A en -1 no los veia nadie. Son 47 movimientos en 8 tandas, medido el 21/09.
  -- ⚠ Se toma el PRIMER codigo que nombra el ref y se lo valida contra GV_Tandas_Codigos_Usados:
  -- sin esa validacion el regex sobre texto libre puede inventar una tanda. Esa tabla la llena el
  -- cron gv-tandas-codigos-usados cada 10 min y tambien gv_ppp_tanda_renombrar, asi que una tanda
  -- nacida hace menos de 10 minutos podria no estar; no se la cruza ademas contra los refs de
  -- Movimientos_Stock a proposito, porque ese segundo scan cuesta 200 ms y el caso que cubriria
  -- (un ajuste manual de reversion sobre una tanda recien creada) no existe en la practica.
  select z.codigo, upper(btrim(z.cod_art)), z.tipo, z.delta, 1
    from (select (regexp_match(upper(coalesce(m.ref, '')), '[A-Z][0-9]{2}[A-Z]'))[1] codigo,
                 m.cod_art, m.tipo, m.delta
            from public."Movimientos_Stock" m
           where m.deposito = 'separar_pedidos'
             and m.tipo not in ('picking', 'separado')
             and upper(btrim(coalesce(m.ref, ''))) !~ '^[A-Z][0-9]{2}[A-Z]$'
             and upper(coalesce(m.ref, '')) ~ '[A-Z][0-9]{2}[A-Z]') z
   where exists (select 1 from public."GV_Tandas_Codigos_Usados" u
                  where upper(btrim(u.codigo)) = z.codigo)
), t as (
  select x.tanda,
         coalesce(sum(x.delta) filter (where x.tipo = 'picking'), 0) pickeado,
         coalesce(sum(x.delta) filter (where x.tipo = 'separado'), 0) drenado,
         coalesce(sum(x.delta) filter (where x.tipo not in ('picking','separado')), 0) otros,
         sum(x.delta) saldo,
         count(*) filter (where x.por_texto = 1) por_texto
    from x group by x.tanda
), c as (
  select x.tanda, x.cod, sum(x.delta) saldo_cod from x group by x.tanda, x.cod
)
select t.tanda, t.pickeado, t.drenado, t.otros, t.saldo,
       (select count(*) from c where c.tanda = t.tanda and c.saldo_cod < 0) cods_en_rojo,
       (select array_agg(c.cod order by c.saldo_cod, c.cod) from c where c.tanda = t.tanda and c.saldo_cod < 0) cods,
       case when t.pickeado = 0 and t.drenado < 0 then 'armada sin picking propio (el picking quedo en otra tanda)'
            when t.pickeado + t.drenado >= 0 and t.otros < 0 then 'el picking cierra: lo negativo lo dejo un ajuste manual'
            else 'drenaje mayor que el picking' end motivo,
       t.por_texto atribuidos_por_texto
  from t where t.saldo < 0
 order by t.saldo;

-- ⚠ CREATE OR REPLACE VIEW sin WITH (...) BORRA las reloptions: sin esta linea la vista corre como
-- postgres y saltea la RLS.
alter view public.gv_stock_tanda_pickeado_negativo set (security_invoker = true);

-- centinelas (ya insertados; quedan aca para poder rehacerlos)
-- insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version) values
--   ('gv_stock_tanda_pickeado_negativo','vista','regexp_match\(upper\(COALESCE\(m\.ref', '…','Luis','v20.32'),
--   ('gv_stock_tanda_pickeado_negativo','vista','GV_Tandas_Codigos_Usados', '…','Luis','v20.32');

-- ROLLBACK: la version anterior esta en sql/gv_stock_tanda_pickeado_negativo_v2013.sql.
-- Ojo: volver atras hace que D53A vuelva a figurar en rojo y que D20E y E10A desaparezcan.
