-- v20.76 — Dar por cerrada una NP en Pedidos atrasados, sin tocar la facturacion
-- Pedido de Thomas, 2026-09-21: "marcá los 21 como cerrados".
--
-- QUE SON LOS 21
-- NP de julio y agosto que quedaron en el barrido historico de atrasados: facturadas, con
-- fecha de salida vencida, SIN carga de camion (CCN) y SIN recepcion de remito (CRN). 14 de las
-- 21 tienen control de remito (CCR). O sea: salieron y nadie registro el cierre. 8,645 m3 en
-- total, del 27/07 al 28/08.
--
-- ⚠ NO SE BORRAN DE Facturacion_NP. Ahi vive la facturacion, que alimenta el reporte diario de
-- LK por Telegram (ppp_np_feed -> gv_lk_np_feed -> rep_despacho_diario), vista_tanda_m3 y el
-- cruce NP-factura. Borrar 21 filas de ahi para limpiar una pantalla habria movido la plata
-- facturada de julio y agosto en los reportes.
--
-- ⚠ Y TAMPOCO SE INVENTAN EVENTOS. La otra tentacion era insertarles un CCN/CRN para que
-- "cierren solos": eso es escribir en el registro de produccion de los operarios un evento que
-- nadie hizo, con un legajo que no existe. El cierre administrativo es otra cosa y se llama
-- distinto a proposito.
--
-- ⚠ LA PANTALLA YA NO LOS VEIA. gv_ppp_atrasados tiene un piso configurable
-- (PPP_Web_Config.atrasados_desde = 2026-09-01) y los 21 son todos anteriores: el front pide la
-- funcion sin argumento y recibia 0. Aparecian solo en un barrido con p_desde hacia atras. Esta
-- tabla es para que tampoco aparezcan ahi.

create table if not exists public."GV_PPP_Atrasado_Cerrado" (
  np            text primary key,
  empresa       text,
  tanda         text,
  fecha_salida  date,
  m3            numeric,
  razon_social  text,
  motivo        text not null,
  cerrado_por   text,
  cerrado_en    timestamptz not null default now()
);
alter table public."GV_PPP_Atrasado_Cerrado" enable row level security;
revoke insert, update, delete, truncate on public."GV_PPP_Atrasado_Cerrado" from anon, authenticated;
comment on table public."GV_PPP_Atrasado_Cerrado" is
  'v20.76: NP que se dan por cerradas en Pedidos atrasados sin tocar la facturacion. gv_ppp_atrasados las saltea.';

-- gv_ppp_atrasados: se le agrego al WHERE (con el loop pg_get_functiondef -> replace -> execute,
-- sobre la definicion VIVA del 21/09)
--
--   and not exists (select 1 from public."GV_PPP_Atrasado_Cerrado" c
--                    where c.np = regexp_replace(upper(btrim(a.np)), '\.0+$', ''))
--
-- Para cerrar una NP a mano:
--   insert into public."GV_PPP_Atrasado_Cerrado" (np, empresa, tanda, fecha_salida, m3, razon_social, motivo, cerrado_por)
--   values ('<np>','lk','<tanda>', date '<fecha>', <m3>, '<cliente>', '<por que se da por cerrada>', '<quien>');
-- Para reabrirla: delete from public."GV_PPP_Atrasado_Cerrado" where np = '<np>';
--
-- ── CHEQUEO ──────────────────────────────────────────────────────────────────
-- select count(*) from public.gv_ppp_atrasados(current_date - 60);  -- 0 al 21/09
-- select count(*) from public."Facturacion_NP";                     -- 1.351, intacta
-- select np, fecha_salida, m3, motivo from public."GV_PPP_Atrasado_Cerrado" order by fecha_salida;
