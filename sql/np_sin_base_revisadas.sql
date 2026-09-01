-- =====================================================================
-- np_sin_base_revisadas.sql — "tachar" una NP programada sin artículos en
-- la base cuando NO es un error.
--
-- ✅ APLICADO 2026-09-01 (migraciones np_sin_base_revisadas,
--    vista_np_prog_sin_base_excluye_revisadas). v12.27.
--
-- POR QUÉ
-- La alerta "NP programada SIN artículos en la base" (ver
-- picking_sin_base_telegram.sql) asume que si el pedido está programado y la
-- base no tiene sus líneas, falta importarlo del ERP. Pero hay un caso real
-- donde no falta nada: el cliente pide con MUCHA anticipación.
--
-- Caso testigo — Matiz SA (cod 4263), pedidos con ~85-90 días entre carga y
-- entrega:
--   NP 97889 · D61A · OC 032112 · carga 23/06 · entrega 16/09 · 9.25 m³
--   NP 97964 · D62A · OC 032264 · carga 03/07 · entrega 07/10 · 6.47 m³
--   NP 98426 · D63A · OC 032613 · carga 13/08 · entrega 28/10 · 6.17 m³
-- La hoja "PPP Excel Base Datos Pedidos" que alimenta PPP_Base_Pedidos
-- arrastra una ventana de ~2 meses POR FECHA DE CARGA (al 01/09/2026 va del
-- 01/07 al 01/09). El 97889 se cargó el 23/06 → queda afuera, aunque su
-- entrega todavía no pasó. Los otros dos entran.
--
-- ⚠ La ventana NO se define en Virgilio: `sync_ppp_base_pedidos()`
-- (sql/sync_ppp_pull_server_side.sql) trae la pestaña entera del Sheet sin
-- ningún filtro de fecha. El recorte viene aguas arriba, en lo que escribe
-- esa hoja. Por eso acá sólo se puede silenciar el aviso, no traer el dato.
--
-- QUÉ HACE
-- Un administrativo toca la ✕ en el módulo "Pedidos sin cargar en PPP" del
-- panel supervisor y la NP queda tachada para todos. Como el cron
-- notificar_picking_sin_base() lee la MISMA vista, el tachado también apaga
-- la alerta de Telegram — no hay dos lugares que puedan discrepar.
--
-- Mismo patrón que NP_Secuencia_Revisadas (v11.21, chips "no interesa").
-- =====================================================================

create table if not exists public."NP_Sin_Base_Revisadas" (
  np          text primary key,
  estado      text        not null default 'no_es_problema',
  motivo      text,                                    -- ej: "pide con 3 meses de anticipación"
  creado_en   timestamptz not null default now()
);

alter table public."NP_Sin_Base_Revisadas" enable row level security;

drop policy if exists np_sin_base_rev_sel on public."NP_Sin_Base_Revisadas";
drop policy if exists np_sin_base_rev_ins on public."NP_Sin_Base_Revisadas";
drop policy if exists np_sin_base_rev_upd on public."NP_Sin_Base_Revisadas";
drop policy if exists np_sin_base_rev_del on public."NP_Sin_Base_Revisadas";

create policy np_sin_base_rev_sel on public."NP_Sin_Base_Revisadas" for select to anon, authenticated using (true);
create policy np_sin_base_rev_ins on public."NP_Sin_Base_Revisadas" for insert to anon, authenticated with check (true);
create policy np_sin_base_rev_upd on public."NP_Sin_Base_Revisadas" for update to anon, authenticated using (true) with check (true);
create policy np_sin_base_rev_del on public."NP_Sin_Base_Revisadas" for delete to anon, authenticated using (true);

grant select, insert, update, delete on public."NP_Sin_Base_Revisadas" to anon, authenticated;

-- ---------------------------------------------------------------------
-- La vista suma un tercer NOT EXISTS: las tachadas.
-- (El resto es idéntico a picking_sin_base_telegram.sql — esta es ahora la
--  definición vigente.)
-- ---------------------------------------------------------------------
create or replace view public.vista_np_prog_sin_base as
with prog as (
  select regexp_replace(btrim(np), '\.0+$', '')      as np,
         nullif(btrim(coalesce(tanda, '')), '')      as tanda,
         nullif(btrim(coalesce(razon_social, '')), '') as cliente,
         nullif(left(btrim(coalesce(fecha_entrega, '')), 10), '') as fecha_entrega,
         coalesce(m3, 0)                             as m3
  from "PPP_Programacion_Diaria"
  where np is not null and btrim(np) <> ''
),
base as (
  select distinct regexp_replace(btrim(pedido), '\.0+$', '') as np
  from "PPP_Base_Pedidos"
  where pedido is not null
),
salidas as (
  select regexp_replace(btrim(np), '\.0+$', '') as np from "Facturacion_NP"     where np is not null
  union
  select regexp_replace(btrim(np), '\.0+$', '')        from "PPP_Entregados_Meta" where np is not null
  union
  select regexp_replace(btrim(np), '\.0+$', '')        from "NP_Canceladas"       where np is not null
),
revisadas as (
  select regexp_replace(btrim(np), '\.0+$', '') as np
  from "NP_Sin_Base_Revisadas" where np is not null
)
select p.np,
       max(p.tanda)                        as tanda,
       max(p.cliente)                      as cliente,
       max(p.fecha_entrega)                as fecha_entrega,
       round(sum(p.m3)::numeric, 2)        as m3
from prog p
where not exists (select 1 from base      b where b.np = p.np)
  and not exists (select 1 from salidas   s where s.np = p.np)
  and not exists (select 1 from revisadas r where r.np = p.np)
group by p.np;

alter view public.vista_np_prog_sin_base set (security_invoker = on);
grant select on public.vista_np_prog_sin_base to anon, authenticated;

-- Destachar una NP (vuelve a aparecer y a avisar):
--   delete from public."NP_Sin_Base_Revisadas" where np = '97889';
-- Ver las tachadas:
--   select * from public."NP_Sin_Base_Revisadas" order by creado_en desc;
