-- ============================================================================
-- v19.54 — BARRIDO RETROACTIVO: CANCELADOS QUE YA ESTABAN FACTURADOS
-- Gestión Virgilio · proyecto hrxfctzncixxqmpfhskv · 2026-09-17
-- ============================================================================
--
-- Regla del dueño (Luis, 17/09):
--   *"Asumí que cualquier pedido que se marca o se marcó como cancelado y que estaba
--    facturado tiene NC y el stock tiene que volver a «A guardar», y ninguno de esos
--    movimientos se tienen que duplicar."*
--
-- La v19.51 dejó eso resuelto para ADELANTE (el desarme escribe la reversa del facturado).
-- Esto es el barrido HACIA ATRÁS, más el centinela para que no se escape ninguna.
--
-- ============================================================================
-- 1. LO QUE SE BARRIÓ — 27 NP canceladas, UNA sola quedaba pendiente
-- ============================================================================
-- Canceladas al 17/09, de las cuatro puertas que existen (`NP_Canceladas`, `GV_Desarmes`
-- con `vuelve = false`, `GV_Web_Cancelados`, `GV_PPP_Web_NP_Cancelada`): **27**. De ésas,
-- las que además tenían un drenaje de `facturado` a su nombre (`TANDA|NP` o `NP|CP`):
--
--   98507 · D53C · 3 cajas → ya repuestas (v19.50)
--   98050 · C98F · 3 cajas → **PENDIENTE** ← la única
--
-- Y las que NO tenían nada que devolver, con el motivo a la vista:
--
--   98582 · 98502 · 98450 → *"Tildada como facturada pero NO se facturó … nunca salió:
--                            0 cajas armadas, faltó todo"* (limpieza de atrasados, Thomas)
--   98049 → se resolvió a mano el 05/08 (ajuste de 18 cajas a góndola); nunca se facturó,
--           sus cajas seguían en la pila
--   LK 0052 · LK 0024 · LK 0014 · LK 0058 · 98272 y las 12 de agosto → sin factura
--
-- ⚠ **98615 y 98616 NO son cancelaciones.** Figuran en `GV_Desarmes` con `vuelve = true`
--   (*"enviado a A Programar desde la tabla de Programación"*) y después se facturaron el
--   17/09. Devolverles las 55 cajas habría sido inventar stock. Por eso el barrido y el
--   centinela filtran `not coalesce(vuelve,false)`: desarmar para reprogramar no es cancelar.

-- ── La corrección de la 98050 (2 códigos, 3 cajas) ──────────────────────────
-- Cancelada el 11/09 por Thomas ("Cancelado por el cliente") pero facturada el 28/07, con
-- su drenaje `C98F|98050` nunca repuesto. Se asume la NC, así que la mercadería nunca salió.
insert into public."Movimientos_Stock" (cod_art, descripcion, deposito, delta, tipo, ref, legajo, empresa)
select d.cod, x.desc_txt, x.dep, x.signo * d.cajas, 'desarme', '98050', 'sistemas', 'LK'
  from (values ('360E', 2::numeric), ('501', 1::numeric)) d(cod, cajas)
  cross join lateral (values
    ('a_facturar',  1,
     'Reversa del facturado de la NP 98050 (tanda C98F): el pedido se cancela despues de facturado ("Cancelado por el cliente", 11/09), asi que la mercaderia nunca salio y se repone lo que el facturado habia descontado. Se compensa con nota de credito. v19.54 - barrido retroactivo de cancelados ya facturados.'),
    ('a_facturar', -1,
     'Cancelacion del pedido 98050 (tanda C98F): vuelve a A guardar. v19.54 - barrido retroactivo de cancelados ya facturados.'),
    ('a_guardar',   1,
     'Cancelacion del pedido 98050 (tanda C98F): vuelve a A guardar. v19.54 - barrido retroactivo de cancelados ya facturados.')
  ) as x(dep, signo, desc_txt);
-- después: select public.refresh_stocks_carga_rapida();
-- Resultado: a_facturar neto 0 y 3 cajas (360E x2, 501 x1) esperando en A guardar.

-- ============================================================================
-- 2. EL CENTINELA
-- ============================================================================
create or replace view public.gv_cancelados_sin_devolver as
with cancel as (
  select regexp_replace(upper(btrim(np)),'\.0+$','') np, 'isis' via, creado ts
    from public."NP_Canceladas"
  union
  select regexp_replace(upper(btrim(np)),'\.0+$',''), 'desarme', creado_at
    from public."GV_Desarmes" where not coalesce(vuelve,false)   -- ⚠ vuelve = reprogramar, NO cancelar
  union
  select regexp_replace(upper(btrim(np_label)),'\.0+$',''), 'web', creado_at
    from public."GV_Web_Cancelados" where coalesce(btrim(np_label),'') <> ''
  union
  select regexp_replace(upper(btrim(np_label)),'\.0+$',''), 'web_np', creado_at
    from public."GV_PPP_Web_NP_Cancelada" where coalesce(btrim(np_label),'') <> ''
),
np as (select np, min(ts) cancelada_en, string_agg(distinct via,'+' order by via) via from cancel group by 1),
dren as (   -- lo que el facturado de esa NP sacó de a_facturar
  select n.np, regexp_replace(upper(btrim(m.cod_art)),'^0+(?=.)','') cod, -sum(m.delta) cajas
    from np n join public."Movimientos_Stock" m
      on m.deposito='a_facturar' and m.tipo='facturado' and m.delta < 0
     and (upper(btrim(m.ref)) like '%|' || n.np or upper(btrim(m.ref)) = n.np || '|CP')
   group by 1,2
),
rep as (    -- lo que ya se repuso (es lo que evita duplicar)
  select n.np, regexp_replace(upper(btrim(m.cod_art)),'^0+(?=.)','') cod, sum(m.delta) cajas
    from np n join public."Movimientos_Stock" m
      on m.deposito='a_facturar' and m.delta > 0 and m.tipo in ('desarme','ajuste')
     and upper(btrim(m.ref)) like '%' || n.np || '%'
   group by 1,2
)
select d.np, n.via, n.cancelada_en, d.cod,
       d.cajas                                    as facturado_saco,
       coalesce(r.cajas, 0)                       as ya_repuesto,
       d.cajas - coalesce(r.cajas, 0)             as falta_devolver,
       'El pedido se cancelo despues de facturado: se asume nota de credito, asi que la mercaderia nunca salio y tiene que volver a A guardar. Reponer en a_facturar lo que el facturado descontó y mandarlo a a_guardar.' as que_hacer
  from dren d
  join np n on n.np = d.np
  left join rep r on r.np = d.np and r.cod = d.cod
 where d.cajas - coalesce(r.cajas, 0) > 0
 order by n.cancelada_en, d.np, d.cod;

alter view public.gv_cancelados_sin_devolver set (security_invoker = true);

comment on view public.gv_cancelados_sin_devolver is
 'v19.54 - CENTINELA. Vacia = todo bien. Una fila = una NP marcada como cancelada que YA estaba facturada y cuyo stock nunca volvio. Regla del dueno (Luis, 17/09): "asumi que cualquier pedido que se marca o se marco como cancelado y que estaba facturado tiene NC y el stock tiene que volver a A guardar, y ninguno de esos movimientos se tiene que duplicar". El desarme (gv_ppp_np_desarmar, v19.51) ya lo hace solo; esta vista caza las cancelaciones que entran por otra puerta, como la de la NP 98050 (marcada a mano en NP_Canceladas el 11/09).';

-- ============================================================================
-- 3. CÓMO SE PROBÓ — rompiéndolo a propósito
-- ============================================================================
-- Una vista que da vacío no prueba nada: puede estar vacía porque no mira donde tiene que
-- mirar. Se le saca la reposición dentro de una transacción abortada y tiene que cantar:
--
--   do $p$ declare n int; d text;
--   begin
--     delete from public."Movimientos_Stock"
--      where upper(btrim(ref)) = '98050' and tipo='desarme' and deposito='a_facturar' and delta > 0;
--     select count(*), string_agg(np||'/'||cod||'='||falta_devolver, ', ')
--       into n, d from public.gv_cancelados_sin_devolver;
--     raise exception 'SIN LA REPOSICION >>> % filas: %', n, d;
--   end $p$;
--   → "SIN LA REPOSICION >>> 2 filas: 98050/360E=2, 98050/501=1" ✔  (y no borró nada)
--
-- ============================================================================
-- 4. LO QUE NO SE HIZO, Y POR QUÉ
-- ============================================================================
-- No se le puso un trigger a `NP_Canceladas` para que la devolución salga sola desde
-- cualquier puerta. Hoy la pantalla de cancelar pasa por `gv_ppp_np_desarmar`, que ya lo
-- hace; la fila de la 98050 la escribió una pantalla anterior. Un trigger que mueve stock
-- desde una tabla que escriben varias cosas es mucho más fácil de romper que de arreglar, y
-- el centinela canta el mismo día. Si aparece una segunda, ahí sí conviene el trigger.
--
-- ============================================================================
-- ROLLBACK
-- ============================================================================
--   delete from public."Movimientos_Stock" where upper(btrim(ref))='98050' and legajo='sistemas';
--   drop view if exists public.gv_cancelados_sin_devolver;
--   select public.refresh_stocks_carga_rapida();
-- ============================================================================
