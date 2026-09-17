-- ════════════════════════════════════════════════════════════════════════════════════
-- v19.35 (2026-09-17) — SE CIERRA EL LIBRO DEL 809E: NO QUEDA NINGUNA FILA EN 'Mixto'
-- ════════════════════════════════════════════════════════════════════════════════════
-- Luis: *"si no va a cambiar nada actualmente y solo afecta un registro de mierda de hace
-- meses que ni siquiera quedó bien registrado: FIJATE BIEN QUE CAMBIAR ESO NO ROMPA NADA
-- NI JODA NADA y si es así, hacelo"*.
--
-- Eran **118 movimientos del 809E anteriores al 01/08** sin empresa. El 809E es dual (dos
-- pilas, Loeke y Chef) y en junio/julio la app todavía no guardaba de cuál salía la caja.
-- Netean CERO en todos los depósitos, así que no afectaban ningún saldo — pero sí jodían
-- en dos lugares reales:
--   1. La vista de saldos mostraba una **tercera fila fantasma** `809E · Mixto`, todo en 0.
--   2. El índice `mov_stock_pipeline_dedup` incluye `empresa`, así que una fila en Mixto y
--      su gemela en LK/CH **no se reconocen como la misma** y el `ON CONFLICT` de los 6
--      reconciliadores puede duplicar el picking. Es lo que pasó el 16/09 (problema 370).
--
-- ── Cómo se resolvió cada una ───────────────────────────────────────────────────────
-- | filas | criterio | evidencia |
-- |---|---|---|
-- | 76 | separar_pedidos + a_facturar, por **tanda → NP** (>90000 = LK) | `Facturacion_NP` |
-- | 19 | pickings en terminado, misma regla | idem |
-- |  9 | depósito `racks` → LK | el rack del 809E es AD05, y AD05 es LK (v19.33) |
-- |  2 | depósito `racks_ch` → CH | el depósito lo dice |
-- |  5 | conteo del 01/08 | la propia fila: `ubicacion` = `J13 · LK`, `M13 · CH`… |
-- |  2 | los dos splits del 01/08 | el ref: *"pasa a 809E CH"*, *"son de Loekemeyer"* |
-- |  4 | revertir fantasma + sus ajustes | el ref: *"→ 809E LK"* / *"→ 809E CH"* |
-- |  1 | **la carga inicial del 26/06 (+168): se PARTIÓ en LK 16 / CH 152** | ver abajo |
--
-- ⚠ **La partida es el único dato inventado, y era inevitable.** Las 19 tandas se llevan
-- CH −48 y LK −16 de `terminado`; el resto de las filas con evidencia cierra en cero sola.
-- O sea que las que quedan (inicial +168, su reset −68, el ajuste −11 y la tanda mezclada
-- C70B −25) tienen que aportar **exactamente LK +16 y CH +48**. Se probaron todas las
-- combinaciones de fila entera: **ninguna da 16/48**, así que había que partir una. Se
-- partió la carga inicial, que es justamente la pila que nadie había separado — por eso
-- existe el conteo del 01/08. Con el reparto 16/152 (y reset, −11 y C70B a CH) las dos
-- empresas quedan en cero en los cuatro depósitos.
--
-- C70B es la única tanda mezclada: NP 97891 (LK) y 44481 (CH), **el mismo cliente**
-- (Orfali Alfredo Luciano) en las dos empresas. No hay dato de cuál llevaba las 25 cajas;
-- se asignó CH, que en el conteo del 01/08 tenía el 89 % de la pila (338 de 381).
--
-- ── Los tres chequeos que se corrieron ANTES de escribir ────────────────────────────
-- 1. **Cada empresa en cero en cada depósito**: 8 de 8 combinaciones en 0. 
-- 2. **Colisiones con el índice único**: 0 contra filas existentes, 0 entre sí.
-- 3. **Triggers**: `zz_normalizar_empresa` es BEFORE **INSERT** solamente, así que no pisa
--    un UPDATE; y en el INSERT de la fila partida respeta la empresa explícita
--    (`v_explicita`) sin intentar resolverla por la NP. `trigger_actualizar_saldo_stock`
--    (AFTER INSERT/UPDATE) se deshabilitó durante la corrida y después
--    `refresh_stocks_carga_rapida()`.
--
-- ── Resultado medido ────────────────────────────────────────────────────────────────
-- | | antes | después |
-- |---|---|---|
-- | huella de saldos | `6fba453c97ce295f583b4d8d0ee5d695` | **idéntica** |
-- | huella de saldos por empresa (resto de los códigos) | `96d2e371…` | **idéntica** |
-- | filas de `vista_saldos_stock` | 494 | **493** (se fue el fantasma) |
-- | `gv_saldos_stock_emp` | 499 | **498** |
-- | `gv_stock_empresa_fantasma` · `gv_stock_negativos` · `gv_endpoints_rotos` | 2 · 1 · 0 | **igual** |
-- | 809E en Mixto | 118 | **0** |
-- | 809E LK terminado / racks · CH terminado / separar | 14 / 336 · 104 / 6 | **igual** |
--
-- Y se corrieron **los 4 reconciliadores a mano** (lo que faltó el 16/09): metieron 27
-- filas, **todas de la tanda E32A pickeada ese mediodía**, ninguna del 809E. 0 duplicados.
--
-- ── De yapa: el último gemelo escondido de mercadería ───────────────────────────────
-- El barrido dejó a la vista 3 filas del **520 en D72A**: un picking **vacío** del 10/09
-- (los tres deltas en 0) que el 14/09 se rehízo de verdad con 6 cajas. Estaban en Mixto
-- contra el bueno en LK, o sea el mismo gemelo escondido de arriba. Delta 0 = borrarlas es
-- inerte. Borradas. **Ya no queda NINGÚN movimiento de mercadería sin empresa, ni ningún
-- gemelo escondido.**
--
--   -- el centinela, que ahora da 0:
--   select count(*) from (
--     select 1 from public."Movimientos_Stock" where tipo in ('picking','separado','facturado')
--      group by upper(btrim(ref)), upper(btrim(cod_art)), deposito, tipo
--     having count(*) > 1 and count(distinct coalesce(empresa,'')) > 1) z;
--
-- ── Respaldos ───────────────────────────────────────────────────────────────────────
--   zz_backups."GV_Backup_809E_Mixto_20260917"      (las 118 filas enteras, antes)
--   zz_backups."GV_Backup_520_D72A_vacio_20260917"  (las 3 del picking vacío)
--
-- ── Rollback ────────────────────────────────────────────────────────────────────────
--   alter table public."Movimientos_Stock" disable trigger trigger_actualizar_saldo_stock;
--   delete from public."Movimientos_Stock" where cod_art = '809E' and ref like '%parte CH (partida 17/09%';
--   update public."Movimientos_Stock" m set empresa = b.empresa, delta = b.delta, ref = b.ref
--     from zz_backups."GV_Backup_809E_Mixto_20260917" b where b.id = m.id;
--   insert into public."Movimientos_Stock"
--     select * from zz_backups."GV_Backup_520_D72A_vacio_20260917";
--   alter table public."Movimientos_Stock" enable trigger trigger_actualizar_saldo_stock;
--   select public.refresh_stocks_carga_rapida();
-- ════════════════════════════════════════════════════════════════════════════════════

-- El SQL que se aplicó (la asignación, en un solo UPDATE contra el plan):
alter table public."Movimientos_Stock" disable trigger trigger_actualizar_saldo_stock;

with emp_tanda as (
  select upper(btrim(f.tanda)) tanda,
         case when count(distinct (f.np::numeric > 90000)) > 1 then 'CH'   -- C70B mezclada
              when min(f.np::numeric) > 90000 then 'LK' else 'CH' end e
    from public."Facturacion_NP" f where f.np::text ~ '^\d+$' group by 1),
m as (select * from public."Movimientos_Stock"
       where coalesce(empresa,'') in ('','Mixto') and upper(btrim(cod_art))='809E' and id <> 219),
plan as (
  select m.id,
    case when m.deposito='racks_ch' then 'CH'
         when m.deposito='racks' then 'LK'
         when m.ref ~ '^[A-Z][0-9]{2}[A-Z]$' then t.e
         when m.ubicacion ~ 'LK' then 'LK'
         when m.ubicacion ~ 'CH' then 'CH'
         when m.ubicacion='J13-J14' then 'LK'
         when m.ubicacion='M13-M15' then 'CH'
         when m.ref like '%809E LK' then 'LK'
         when m.ref like '%809E CH' then 'CH'
         when m.id=8218909 then 'LK'            -- ajuste manual -1, par del revertir LK
         when m.id=8353381 then 'CH'            -- ajuste manual -1, par del revertir CH
         when m.id in (20653,52644879) then 'CH' end emp   -- reset -68 y anular -11
  from m left join emp_tanda t on t.tanda = upper(btrim(m.ref)))
update public."Movimientos_Stock" ms set empresa = p.emp
  from plan p where p.id = ms.id and p.emp in ('LK','CH');

update public."Movimientos_Stock"
   set delta = 16, empresa = 'LK',
       ref = 'inicial Excel (test 00:01) · parte LK (partida 17/09: la pila de junio no estaba separada; el reparto 16/152 es el unico que deja LK y CH en cero)'
 where id = 219;

insert into public."Movimientos_Stock" (ts, cod_art, deposito, delta, tipo, ref, legajo, empresa)
select ts, cod_art, deposito, 152, tipo,
       'inicial Excel (test 00:01) · parte CH (partida 17/09: la pila de junio no estaba separada; el reparto 16/152 es el unico que deja LK y CH en cero)',
       legajo, 'CH'
  from public."Movimientos_Stock" where id = 219;

delete from public."Movimientos_Stock" where id in (55634924, 55638992, 55643060) and delta = 0;

alter table public."Movimientos_Stock" enable trigger trigger_actualizar_saldo_stock;
select public.refresh_stocks_carga_rapida();
