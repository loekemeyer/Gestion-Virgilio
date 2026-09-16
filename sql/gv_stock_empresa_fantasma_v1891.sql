-- v18.91 — CENTINELA de stock partido por empresa ("cajas fantasma").
--
-- QUÉ MIDE. Por (código, depósito): el saldo TOTAL contra la suma de los saldos por empresa
-- que son POSITIVOS. Si alguna empresa quedó en NEGATIVO, esos dos números no coinciden, y la
-- diferencia (`fantasma`) son cajas que una pantalla que mire el desglose va a ofrecer aunque
-- en el depósito no existan.
--
-- Pasa cuando la mercadería ENTRA con una empresa y SALE con otra. El caso que lo destapó: el
-- 16/09, "Mover a Góndola" ofrecía 475 cajas en 10 códigos (026 70 · 027 53 · 031 133 · 103 73
-- · 312 7 · 562 54 · 564 17 · 735 41 · 859 21 · 862 6) con neto CERO — habían entrado a A
-- Guardar como LK/CH y salido como 'Mixto'. Se corrigieron reasignando los 24 movimientos de
-- `guardado` a la empresa de entrada (backup en zz_backups."GV_Backup_MovStock_Mixto_guardado_20260916").
--
-- ⚠ ESTA VISTA NO ARRANCA VACÍA, y está bien que no lo haga. Al 16/09, DESPUÉS de la
-- corrección, devuelve **61 códigos / 1.474 cajas**: racks 870 · góndola 368 · excedente 236,
-- y CERO en `a_guardar` (ése quedó limpio). Son restos históricos del mismo origen —
-- movimientos viejos sin empresa, de cuando recepción marcaba todo 'Mixto'— en otros módulos,
-- que NO se tocaron porque cada uno necesita su propia evidencia de con qué empresa entró.
-- Lo que hay que mirar es que el número **no crezca**, y sobre todo que `a_guardar` siga en 0:
--
--   select deposito, count(*) codigos, sum(fantasma) cajas
--     from public.gv_stock_empresa_fantasma group by 1 order by 3 desc;
--
-- Lo que impide que vuelva a crecer por el lado del guardado está en
-- sql/trg_normalizar_empresa_stock_v1886.sql (el trigger resuelve la empresa del montón) y en
-- `stockFetchSaldos` / la lista de MG de index.html (el total manda sobre el desglose).

-- ⚠ v18.91 — LA VISTA AHORA DISTINGUE `es_dual`, y eso cambia cómo se lee el número.
-- Un código **NO DUAL tiene UNA SOLA PILA FÍSICA**: hay una góndola, un rack. El desglose por
-- empresa de ese código **no significa nada** — es una etiqueta, no dos montones. Así que un
-- "fantasma" ahí es ruido, no mercadería que falte. En un DUAL sí son dos góndolas separadas
-- (un 809E de LK va a J13/J14 y uno de CH a M13/M15) y la diferencia es real.
--
-- Al 16/09 la vista devuelve **62 códigos / 1.709 cajas, TODOS no duales** → 0 cajas en riesgo.
-- Repartidas: racks 1.105 · góndola 368 · excedente 236, y CERO en `a_guardar`.
--
-- CAUSA (una sola, para los tres depósitos): la app empezó a marcar la empresa en las SALIDAS
-- antes de que el saldo histórico —las ENTRADAS— la tuviera. El `picking` pasó de 'Mixto' a
-- LK/CH el 11/09 (2.222 filas viejas en Mixto contra 204 nuevas en LK/CH) y la `baja_racks`
-- el 14/09 (todo lo que ENTRÓ a racks está en Mixto: ingreso, inicial y traslado, 100 %).
-- O sea: se saca con etiqueta de un pozo sin etiqueta, y el pozo no se vacía. **Crece todos
-- los días**: entre dos mediciones de la misma tarde pasó de 1.474 a 1.709.
--
-- POR QUÉ NO SE CORRIGIÓ REASIGNANDO: no hay nada que reasignar. El total por código está
-- bien en los 62. El arreglo de fondo es de una línea —que para un código NO dual el trigger
-- fuerce `empresa = 'Mixto'` siempre, entradas y salidas, porque la pila es una— pero toca
-- una tabla compartida que miran **13 funciones** (reconciliadores, conteos, faltantes,
-- racks). No se hizo un día hábil con los operarios pickeando. Tarea de Planify 3527.
--
-- QUÉ LO VUELVE INOFENSIVO MIENTRAS TANTO: que ninguna pantalla lea el desglose sin netear
-- contra el total. Mover a Góndola era la única que lo hacía y se corrigió en la v18.86.
-- «Bajar de racks» lee el TOTAL, así que las 1.105 cajas de racks no se ven en pantalla.

drop view if exists public.gv_stock_empresa_fantasma;
create view public.gv_stock_empresa_fantasma
with (security_invoker = true) as
with e as (
  select regexp_replace(upper(btrim(m.cod_art)),'^0+(?=.)','') cod, m.deposito,
         coalesce(nullif(m.empresa,''),'Mixto') empresa, sum(m.delta) saldo,
         max(m.ts) ultimo
    from public."Movimientos_Stock" m
   where m.deposito in ('a_guardar','terminado','excedente','racks','racks_ch','para_envasar')
   group by 1,2,3
), t as (
  select cod, deposito, sum(saldo) total, sum(greatest(saldo,0)) positivo
    from e group by 1,2
), du as (
  select distinct regexp_replace(upper(btrim(cod)),'^0+(?=.)','') cod from public.codigos_duales
)
select t.cod, t.deposito, t.total, t.positivo, (t.positivo - t.total) as fantasma,
       (du.cod is not null) as es_dual,
       -- un codigo NO DUAL tiene UNA sola pila fisica: el desglose por empresa no significa
       -- nada ahi, asi que el fantasma es ruido de etiqueta, no mercaderia que falte. En un
       -- DUAL si hay dos gondolas separadas y la diferencia es real.
       case when du.cod is not null then 'REAL: el codigo es dual, son dos pilas separadas'
            else 'etiqueta: codigo no dual, una sola pila' end as riesgo,
       (select string_agg(e2.empresa || ': ' || e2.saldo, '  ' order by e2.empresa)
          from e e2 where e2.cod = t.cod and e2.deposito = t.deposito and e2.saldo <> 0) as detalle,
       (select max(e3.ultimo) from e e3 where e3.cod = t.cod and e3.deposito = t.deposito and e3.saldo < 0) as ultimo_negativo
  from t left join du on du.cod = t.cod
 where t.positivo - t.total > 0;

-- security_invoker explicito (un CREATE OR REPLACE VIEW sin WITH borra las reloptions).
alter view public.gv_stock_empresa_fantasma set (security_invoker = true);

-- Chequeo: lo que importa es que `es_dual = true` este VACIO y que `a_guardar` no aparezca.
-- select es_dual, deposito, count(*) codigos, sum(fantasma) cajas
--   from public.gv_stock_empresa_fantasma group by 1,2 order by 1 desc, 4 desc;
