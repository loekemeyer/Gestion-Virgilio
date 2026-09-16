-- v18.85 — CENTINELA de stock partido por empresa ("cajas fantasma").
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
-- sql/trg_normalizar_empresa_stock_v1885.sql (el trigger resuelve la empresa del montón) y en
-- `stockFetchSaldos` / la lista de MG de index.html (el total manda sobre el desglose).

create or replace view public.gv_stock_empresa_fantasma
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
)
select t.cod, t.deposito, t.total, t.positivo, (t.positivo - t.total) as fantasma,
       (select string_agg(e2.empresa || ': ' || e2.saldo, '  ' order by e2.empresa)
          from e e2 where e2.cod = t.cod and e2.deposito = t.deposito and e2.saldo <> 0) as detalle,
       (select max(e3.ultimo) from e e3 where e3.cod = t.cod and e3.deposito = t.deposito and e3.saldo < 0) as ultimo_negativo
  from t
 where t.positivo - t.total > 0;

-- security_invoker explícito (un CREATE OR REPLACE VIEW sin WITH borra las reloptions).
alter view public.gv_stock_empresa_fantasma set (security_invoker = true);
