-- =====================================================================
--  PPP en Supabase  —  espeja en Postgres las hojas de Google que hoy
--  lee la app (programación / pedidos / m³). Objetivo: sacar la
--  dependencia de Google y poder calcular m³ por SQL.
--
--  Proyecto: hrxfctzncixxqmpfhskv ("Control Partes Talleristas").
--  Ejecutar UNA vez en el SQL Editor de Supabase.
--
--  Tablas (1 = 1 con las hojas que pidió el dueño):
--    PPP_Programacion_Diaria  ←  "PPP Excel Programacion Diaria"  (gid 1947169223)
--    PPP_Pedidos_Entregados   ←  "PPP Excel Pedidos Entregados 2026" (gid 2146771217)
--    PPP_Base_Pedidos         ←  "PPP Excel Base Datos Pedidos"   (~20k filas)
--
--  Quién escribe / quién lee:
--    • La app lee con la key PUBLISHABLE (rol anon / authenticated) → SOLO SELECT.
--    • La macro del Excel escribe con la SERVICE_ROLE key → bypassa RLS
--      (no hace falta policy de escritura; NUNCA exponer write al rol anon).
--
--  Convenciones: nombres de tabla en PascalCase (como el resto del proyecto:
--  Registros_Produccion_Virgilio, Facturacion_NP); columnas en snake_case
--  minúsculas (así PostgREST no necesita comillas y el select queda limpio).
--
--  m³: se guarda como NUMERIC (no texto). La hoja trae coma decimal ("0,289");
--  la macro debe convertir a punto antes de enviar (ver MIGRACION-SUPABASE-PPP.md).
-- =====================================================================

-- ── 1) Programación diaria ───────────────────────────────────────────
--  Grano: una fila por pedido (N° NP). Snapshot del día: la macro la
--  reemplaza en cada push (upsert por np + borrado de lo viejo por synced_at).
--  Columnas en el MISMO orden/semántica que el layout fijo del Excel que lee
--  fetchMonitorSheet (Tanda=0, Tipo=1, NP=2, FechaRecep=3, Cod=4, RazonSocial=5,
--  M3=6, V=7, Direccion=8, Barrio=9, Op=10, FechaEntrega=11, FechaFc=12, Zona=13,
--  Observaciones=14).
create table if not exists public."PPP_Programacion_Diaria" (
  np            text primary key,        -- "N° NP" — identifica al pedido (clave de upsert)
  tanda         text,
  tipo          text,
  fecha_recep   text,
  cod           text,
  razon_social  text,
  m3            numeric,
  v             text,
  direccion     text,
  barrio        text,
  op            text,                     -- "SI" / "" (planificado)
  fecha_entrega text,                     -- texto, mismo formato que la hoja (la app lo parsea)
  fecha_fc      text,
  zona          text,
  observaciones text,
  synced_at     timestamptz not null default now()
);
create index if not exists ppp_prog_tanda_idx  on public."PPP_Programacion_Diaria" (upper(tanda));
create index if not exists ppp_prog_synced_idx on public."PPP_Programacion_Diaria" (synced_at);

-- ── 2) Pedidos entregados (histórico, fuente del m³ fallback) ─────────
--  Grano: una fila por pedido entregado (N° NP, único en el año). Acumulativo.
--  La app suma mt3 por tanda. ⚠ usar SIEMPRE col "Mt3", NO "Mt3 FC".
create table if not exists public."PPP_Pedidos_Entregados" (
  np           text primary key,
  tanda        text,
  fecha        text,
  cod          text,
  razon_social text,
  mt3          numeric,                   -- col "Mt3" (NO "Mt3 FC")
  synced_at    timestamptz not null default now()
);
create index if not exists ppp_entr_tanda_idx on public."PPP_Pedidos_Entregados" (upper(tanda));

-- ── 3) Base de pedidos (artículos por pedido, para el picking) ────────
--  Grano: una fila por (pedido, artículo) con las cajas. La macro PRE-AGREGA
--  (suma cajas por pedido+artículo) antes de enviar → la PK compuesta no choca
--  y el picking, que suma por código igual, da el MISMO resultado que la hoja.
create table if not exists public."PPP_Base_Pedidos" (
  pedido    text not null,                -- N° de pedido (col "Pedido")
  articulo  text not null,                -- código de artículo (col "Artículo")
  cajas     numeric,                      -- col "Cantidad Cajas"
  synced_at timestamptz not null default now(),
  primary key (pedido, articulo)
);
create index if not exists ppp_base_pedido_idx on public."PPP_Base_Pedidos" (pedido);

-- ── RLS: la app (anon/authenticated) solo lee; la macro escribe con service_role ──
alter table public."PPP_Programacion_Diaria" enable row level security;
alter table public."PPP_Pedidos_Entregados"  enable row level security;
alter table public."PPP_Base_Pedidos"        enable row level security;

drop policy if exists "ppp_prog_select" on public."PPP_Programacion_Diaria";
drop policy if exists "ppp_entr_select" on public."PPP_Pedidos_Entregados";
drop policy if exists "ppp_base_select" on public."PPP_Base_Pedidos";

create policy "ppp_prog_select" on public."PPP_Programacion_Diaria"
  for select to anon, authenticated using (true);
create policy "ppp_entr_select" on public."PPP_Pedidos_Entregados"
  for select to anon, authenticated using (true);
create policy "ppp_base_select" on public."PPP_Base_Pedidos"
  for select to anon, authenticated using (true);
-- (Sin policy de INSERT/UPDATE/DELETE a propósito: solo service_role escribe.)

-- =====================================================================
--  VERIFICACIÓN — m³ por tanda YA calculable por SQL (la limitación #1):
--
--    select upper(tanda) tanda, round(sum(m3)::numeric, 3) m3
--    from "PPP_Programacion_Diaria" where coalesce(tanda,'') <> ''
--    group by upper(tanda) order by 1;
--
--    select upper(tanda) tanda, round(sum(mt3)::numeric, 3) m3
--    from "PPP_Pedidos_Entregados" group by upper(tanda) order by 1;
-- =====================================================================
