-- ════════════════════════════════════════════════════════════════════
-- GV_Lugar / GV_Lugar_Item / gv_ocupacion_lugar  (v2, 2026-09-11)
-- Fuente única de "qué artículo/insumo va en qué lugar del depósito".
-- Aplicado en Gestión (hrxfctzncixxqmpfhskv) como migración
-- `gv_lugar_fuente_unica_v1`. Pedido de Luis.
--
-- ⚠ TODAVÍA NO CONECTA A NADA. Se crea vacía y desconectada a propósito:
--    primero se releva el depósito (docs/relevamiento-lugares-deposito-20260911.xlsx),
--    después se carga, y recién ahí se migran TODOS los lectores de una sola vez.
--
-- Reemplazará a: Planimetria · planimetria.js · Capacidad_Sector ·
-- Racks_Planimetria · Insumos_Ubicaciones · Insumos_Ubicaciones_Unificadas ·
-- Ubicaciones_Articulos · Stock_Ubicaciones.
--
-- POR QUÉ DOS TABLAS Y NO UNA (medido sobre los datos el 11/09):
--   · 36 sectores tienen más de un código   → un lugar, varios ítems
--   · 112 códigos están en más de un sector → un ítem, varios lugares
--   · 53 códigos tienen cajas_max DISTINTO según el sector
--     → la capacidad es del PAR (lugar, ítem), no del lugar ni del ítem
--   · 9 códigos existen como ARTÍCULO y como INSUMO a la vez (035E, 437E,
--     437E CH, 438E, 439E LK, 440E, 523C, 584E, 590E) y son cosas distintas
--     → `clase` va en la PRIMARY KEY, para que un mismo lugar pueda tener el
--       artículo 437E y el insumo 437E sin chocar (v2; la v1 lo prohibía)
--   · 684 de 685 sectores tienen UNA sola empresa
--     → la empresa es propiedad del LUGAR, no del artículo. Por eso acá no
--       existe el sufijo "809E LK": J13 es un lugar de LK y M13 uno de CH.
--       Eso elimina de raíz el fallback que hacía que un picking de LK del
--       809E mandara al operario a la góndola de Chef.
--
-- LA OCUPACIÓN NO SE GUARDA: se deriva de Movimientos_Stock (event sourcing,
-- 55.714 filas). Guardarla como estado mutable es lo que generó las 6 fuentes
-- que esto viene a reemplazar.
--
-- ROLLBACK: drop view public.gv_ocupacion_lugar;
--           drop table public."GV_Lugar_Item"; drop table public."GV_Lugar";
--           (no toca ningún objeto existente, así que el rollback es total)
-- ════════════════════════════════════════════════════════════════════

create table if not exists public."GV_Lugar" (
  sector      text primary key,
  tipo        text not null check (tipo in ('gondola','rack')),
  empresa     text check (empresa in ('LK','CH','LOKE')),
  orden       integer,
  activo      boolean not null default true,
  notas       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
comment on table public."GV_Lugar" is
  'Catálogo de lugares físicos del depósito (góndola y rack). Una fila por lugar. `sector` normalizado LETRAS+2 dígitos (J01, no J1). `orden` = orden de recorrido del picking. `empresa` = dueña del espacio. v1 2026-09-11, todavía sin lectores.';
comment on column public."GV_Lugar".empresa is
  'LK / CH / LOKE. Es del LUGAR, no del artículo: 684 de 685 sectores tienen una sola empresa. Esto elimina el sufijo de empresa en el código (809E LK).';

create table if not exists public."GV_Lugar_Item" (
  sector      text not null references public."GV_Lugar"(sector) on update cascade on delete restrict,
  cod         text not null,
  clase       text not null default 'articulo' check (clase in ('articulo','insumo')),
  cajas_max   numeric,
  unidad      text,
  activo      boolean not null default true,
  notas       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  primary key (sector, cod, clase)
);
comment on table public."GV_Lugar_Item" is
  'Asignación lugar <-> artículo/insumo (muchos a muchos). `cajas_max` vive acá y no en GV_Lugar porque 53 códigos tienen capacidad distinta según el sector. `clase` unifica artículos e insumos en una sola tabla y forma parte de la PK. v2 2026-09-11, todavía sin lectores.';
comment on column public."GV_Lugar_Item".clase is
  'articulo | insumo. Va en la PK porque 9 códigos existen en los dos padrones y son cosas distintas: el mismo lugar puede tener el artículo 437E y el insumo 437E. Toda consulta de ubicación debe filtrar por clase; sin eso un artículo puede resolver contra la ubicación de un insumo homónimo.';

-- El lookup del picking es por (cod, clase): un artículo nunca debe resolver
-- contra la ubicación de un insumo homónimo, ni al revés.
create index if not exists gv_lugar_item_cod_clase_idx on public."GV_Lugar_Item" (cod, clase);
create index if not exists gv_lugar_item_clase_idx on public."GV_Lugar_Item" (clase);
create index if not exists gv_lugar_empresa_idx    on public."GV_Lugar" (empresa, tipo);

alter table public."GV_Lugar"      enable row level security;
alter table public."GV_Lugar_Item" enable row level security;

drop policy if exists gv_lugar_sel      on public."GV_Lugar";
drop policy if exists gv_lugar_item_sel on public."GV_Lugar_Item";
create policy gv_lugar_sel      on public."GV_Lugar"      for select to anon, authenticated using (true);
create policy gv_lugar_item_sel on public."GV_Lugar_Item" for select to anon, authenticated using (true);

-- ── Vista de ocupación (derivada, nunca se escribe) ──────────────────
-- OJO con lo que NO dice: Movimientos_Stock no guarda el sector de forma
-- confiable (`ubicacion` es texto libre: conviven 'F09 · LK', 'F09-F11',
-- 'L7', 'P5' y hasta números de NP), así que el saldo es POR CÓDIGO, no
-- por sector. Cuando un código ocupa varios lugares, `saldo_cod` se repite
-- en cada fila y el % va contra la capacidad TOTAL asignada a ese código.
-- Repartir por sector requiere que el picking empiece a grabar el sector:
-- eso es trabajo aparte.
create or replace view public.gv_ocupacion_lugar
with (security_invoker = true) as
with saldo as (
  select upper(btrim(m.cod_art)) cod,
         upper(btrim(coalesce(m.empresa,''))) empresa,
         case when m.deposito in ('racks','racks_ch') then 'rack'
              when m.deposito = 'insumos'            then 'insumo'
              else 'gondola' end destino,
         sum(m.delta) saldo
  from public."Movimientos_Stock" m
  group by 1,2,3
)
select l.sector, l.tipo, l.empresa, l.orden,
       li.cod, li.clase, li.cajas_max,
       sum(li.cajas_max) over (partition by li.cod, l.empresa) cajas_max_total_cod,
       s.saldo saldo_cod,
       case when sum(li.cajas_max) over (partition by li.cod, l.empresa) > 0
            then round(100 * s.saldo / sum(li.cajas_max) over (partition by li.cod, l.empresa), 1)
       end pct_ocupado_cod
from public."GV_Lugar" l
join public."GV_Lugar_Item" li on li.sector = l.sector and li.activo
left join saldo s
       on s.cod = upper(btrim(li.cod))
      and s.empresa = l.empresa
      and s.destino = case when li.clase = 'insumo' then 'insumo' else l.tipo end
where l.activo;

comment on view public.gv_ocupacion_lugar is
  'Ocupación DERIVADA de Movimientos_Stock: nunca se escribe. saldo_cod es por CÓDIGO (Movimientos_Stock.ubicacion no es confiable para repartir por sector), así que en un código con varios lugares el saldo se repite por fila y el % va contra la capacidad total del código. v1 2026-09-11.';

-- ════════════════════════════════════════════════════════════════════
-- v3 (2026-09-11) — el código de lugar se guarda SIEMPRE con el cero.
-- Pedido de Luis: algunas tablas actuales tienen J1; en las definitivas va J01.
--
-- Medido sobre los 946 sectores distintos de las 6 tablas actuales:
--   826  ya venían LETRAS+2 dígitos (J01, AA03, Ñ53)  → quedan igual
--    92  vienen con 1 dígito (J1, A5, AD6)            → se padean a J01, A05, AD06
--    28  son racks de INSUMOS con otro esquema         → R1AD, V9 AD, MEDIO
-- Normalizados quedan 873 lugares distintos (112 grafías se unifican).
--
-- Los 28 salen sólo de Insumos_Ubicaciones y Stock_Ubicaciones: racks de
-- insumos con sufijo AD/AT = ADELANTE / ATRÁS (confirmado por Luis, 11/09).
-- Mismo criterio: R1AD → R01AD, 'V9 AD' → V09AD (además se come el espacio).
--
-- 'MEDIO' es el único que no entra en el formato: no tiene número.
-- DECISIÓN (Luis, 11/09): se DESCARTA, no se carga en GV_Lugar. Verificado
-- antes de descartarlo: las 2 filas se crearon el 2026-08-11, tienen
-- cantidad 0 y capacidad null, su updated_at == created_at (nunca se
-- tocaron desde el alta) y hay 0 movimientos en Movimientos_Stock con esa
-- ubicación.
-- ⚠ Consecuencia a tener presente al cargar: 'MEDIO' es el ÚNICO lugar que
--   tienen los insumos A1 (Mgo Plano 501 Pint., parte_procesado) y H1
--   (Manija Redonda p/cromar, partes_crudo) — no figuran en ningún otro
--   sector. Al descartarlo esos dos insumos quedan sin ubicación asignada.
--   Si alguna vez se les da lugar físico, hay que darlos de alta en
--   GV_Lugar_Item con clase='insumo'.
--
-- ⚠ N y Ñ son lugares DISTINTOS, no un error de tipeo. Los N (N04, N10, N12,
--   N3..N8) salen de Racks_Planimetria con códigos 501, 504, 505, 546, 315;
--   los Ñ salen de Capacidad_Sector con 104 y 106E. N = racks, Ñ = góndola.
--   Fusionarlos mezclaría un rack con una góndola.
-- ════════════════════════════════════════════════════════════════════

create or replace function public.gv_norm_sector(p text)
returns text language sql immutable as $$
  select case when m is null then upper(btrim(p))
              else m[1] || lpad(m[2], 2, '0') || coalesce(m[3], '') end
  from (select regexp_match(upper(btrim(p)), '^([A-ZÑ]{1,2})0*([0-9]+)\s*(AD|AT)?$') m) x;
$$;
comment on function public.gv_norm_sector(text) is
  'Normaliza un código de lugar al formato canónico LETRAS + 2 dígitos (+ AD/AT opcional para racks de insumos): J1->J01, AD6->AD06, ''V9 AD''->V09AD. Lo que no matchea vuelve en mayúsculas sin espacios de borde. v3 2026-09-11.';

alter table public."GV_Lugar" drop constraint if exists gv_lugar_sector_fmt;
alter table public."GV_Lugar" add constraint gv_lugar_sector_fmt
  check (sector ~ '^[A-ZÑ]{1,2}[0-9]{2,}(AD|AT)?$');

comment on column public."GV_Lugar".sector is
  'Código de lugar en formato canónico: LETRAS + 2 dígitos, SIEMPRE con el cero (J01, nunca J1). Los racks de insumos admiten sufijo AD/AT (R01AD). Lo garantiza el check gv_lugar_sector_fmt; para normalizar una entrada usar gv_norm_sector(). N y Ñ son lugares distintos (N = racks, Ñ = góndola): no unificarlos.';


-- ════════════════════════════════════════════════════════════════════
-- v5 (2026-09-11) — LOKE deja de ser una empresa: es LK.
-- Pedido de Luis. Loke es una LÍNEA de Loekemeyer, no una empresa: la vista
-- de stock ya trae sus artículos con linea='LK', así que tener LOKE acá
-- hacía que el cruce stock<->lugar diera 24 falsos positivos (el pasillo Ñ
-- entero: el 186, el 123, el 124E... figuraban "sin lugar de su empresa").
-- Son 57 lugares, todos góndola de Ñ01..Ñ55 y Ñ58..Ñ60.
-- Reversible: los 57 quedan marcados en `notas`.
-- ════════════════════════════════════════════════════════════════════

update public."GV_Lugar"
set empresa = 'LK',
    notas = coalesce(notas || ' · ', '') || 'era LOKE hasta el 11/09; Luis: Loke es linea de LK, no empresa aparte',
    updated_at = now()
where empresa = 'LOKE';

alter table public."GV_Lugar" drop constraint if exists "GV_Lugar_empresa_check";
alter table public."GV_Lugar" add constraint "GV_Lugar_empresa_check"
  check (empresa is null or empresa in ('LK','CH'));

comment on column public."GV_Lugar".empresa is
  'LK / CH. Es del LUGAR, no del artículo. LOKE NO es un valor válido: Loke es una línea de Loekemeyer, no una empresa (los 57 lugares del pasillo Ñ pasaron a LK el 11/09). v5 2026-09-11.';
