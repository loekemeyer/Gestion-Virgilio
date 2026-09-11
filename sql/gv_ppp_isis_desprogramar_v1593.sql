-- =============================================================================
-- v15.93 (2026-09-11) — "SIN PROGRAMAR" para una NP de ISIS
-- Migraciones: `gv_ppp_isis_desprogramar_v1593` + `gv_ppp_isis_sin_tanda_desprogramadas_v1593`
-- =============================================================================
-- Thomas, sobre los 15 pedidos vencidos/sin fecha que quedaron en Programación:
--   *"No lo sé, por las dudas, ponelos todos sin programar para que los revise, los que no se
--     cargaron el camión nunca, y son claramente viejos."*
--
-- El agujero: `GV_PPP_Prog_Override` sabía PISAR tanda/fecha y OCULTAR una NP de ISIS, pero no
-- VACIARLA. La vista hace `coalesce(nullif(btrim(o.tanda),''), p.tanda)`, así que un '' caía al
-- valor de ISIS. Para las web ya existía `gv_ppp_web_desprogramar`; para ISIS no había nada:
-- sólo 📅 Reprogramar (a un día nuevo) o 🚫 Cancelar (que las saca para siempre).
--
-- LO QUE SE AGREGÓ
--   1. `GV_PPP_Prog_Override.desprogramada` boolean not null default false  (aditivo).
--   2. `gv_ppp_programacion_diaria`: con la marca en true devuelve tanda = '' y fecha_entrega = ''
--      → el front la cuenta como NO programada (`programmed` de `_pppRowFromSupa`) y cae en
--      📥 A Programar. La tabla compartida `PPP_Programacion_Diaria` NO se toca.
--   3. `gv_ppp_isis_desprogramar(p_nps text[], p_motivo text, p_por text)` — sólo supervisor.
--      **Guarda**: corta si alguna NP ya tiene CCN (Carga Camión) o CRN (Recepción Remitos).
--      Si salió de verdad no se saca de la programación: se cierra con el remito.
--   4. `gv_ppp_isis_sin_tanda`: una NP desprogramada entra **aunque esté facturada**. Sin esto las
--      8 de Thomas (todas facturadas) quedaban invisibles en A Programar y `gv_ppp_isis_programar`
--      las rechazaba con "ya no están sin tanda". Cancelada sigue afuera siempre.
--   5. `gv_ppp_isis_programar`: al volver a programarla, `desprogramada = false` (si no, la vista
--      le seguiría vaciando la tanda recién asignada).
--
-- APLICADO el 11/09 a 8 NP — las que nunca tuvieron Carga Camión y ya eran viejas:
--   98585..98590  D56D  Lin Liqin / Zhang Qikuan · armada 03/09, facturada 04/09, **con CCR**
--   98480 98481   D47B  Alesso Vilarino          · armada 27/08, facturada 28/08
--   Las 8 quedaron sin tanda y sin fecha, y aparecen en A Programar (verificado como `anon`).
--   La PPP sigue con 123 filas: no se perdió ninguna.
--   NO se tocaron (son de esta semana, no son "claramente viejos"): 98530 D60C (armada 09/09),
--   44612/13/14 D72B (armadas 10/09) y 44615/16/17 D72C (armadas hoy 11/09 14:11).
--
-- OBJETOS: todos NUESTROS (`GV_*` / `gv_*`). Ninguno de Producción.
-- BACKUP de la tabla antes de escribir: `public."GV_PPP_Prog_Override_bkp_20260911_v1593"` (105 filas).
-- ROLLBACK:
--   update public."GV_PPP_Prog_Override" set desprogramada = false where desprogramada;   -- vuelve todo
--   -- o, para deshacer entero: restaurar la tabla desde el backup y recrear las 2 vistas y las
--   -- 2 funciones desde su versión anterior (la de `gv_ppp_isis_programar` está en el git de este
--   -- archivo; las vistas salen de `pg_get_viewdef` del backup documentado en §3.cn.2).
-- =============================================================================

alter table public."GV_PPP_Prog_Override"
  add column if not exists desprogramada boolean not null default false;

comment on column public."GV_PPP_Prog_Override".desprogramada is
  'v15.93 — true = la NP de ISIS queda SIN tanda y SIN fecha en gv_ppp_programacion_diaria, o sea vuelve a A Programar para revisarla. No toca PPP_Programacion_Diaria (tabla compartida).';

-- El resto del DDL (las 2 vistas y las 2 funciones) se aplicó con las migraciones nombradas
-- arriba; su texto completo está en la base (`pg_get_viewdef` / `pg_get_functiondef`) y en el
-- cuerpo de las migraciones. Lo único que cambia respecto de la versión anterior:
--
--   gv_ppp_programacion_diaria:
--     tanda         → case when coalesce(o.desprogramada,false) then '' else <lo de antes> end
--     fecha_entrega → case when coalesce(o.desprogramada,false) then '' else <lo de antes> end
--
--   gv_ppp_isis_sin_tanda (CTE `d` suma el left join al override y `o.desprogramada`):
--     where (d.desprogramada or not exists (… "Facturacion_NP" …))
--       and (d.desprogramada or not exists (… "PPP_Entregados_Meta" …))
--       and not exists (… "NP_Canceladas" …)
--
--   gv_ppp_isis_programar (insert … on conflict do update):
--     + desprogramada = false
--
--   gv_ppp_isis_desprogramar: función nueva (ver migración).

-- Controles
--   select np, tanda, fecha_entrega from public.gv_ppp_programacion_diaria
--    where regexp_replace(btrim(np),'\.0+$','') in ('98585','98480');   -- '' y ''
--   select count(*) from public.gv_ppp_isis_sin_tanda;                  -- 8
--   select count(*) from public.gv_ppp_programacion_diaria;             -- 123 (igual que antes)
