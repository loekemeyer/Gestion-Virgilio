-- gv_padron_direcciones — v14.16 (2026-09-07) · Virgilio (hrxfctzncixxqmpfhskv)
--
-- QUÉ PIDIÓ EL DUEÑO (07/09)
-- ==========================
--     "tenés que tener a todo ubicado. sin falta de ninguno, inclusive aunque no hayan
--      mandado pedido"
--
-- Hasta hoy el geocodificador (`gv-geocodificar`, cron 75) sólo miraba `gv_geo_faltantes`:
-- las direcciones **que estaban programadas** en los últimos 7 días o hacia adelante. Un
-- cliente que no pidió nunca —o que no pidió esta semana— no tenía ubicación, y el día que
-- entra su pedido el reparto se arma a ciegas (sin lat/lng el orden de carga lo manda al final).
--
-- Ahora se ubica **todo el padrón**: las 1.603 direcciones de entrega de LK + las 710 de Chef,
-- hayan pedido o no.
--
-- LO QUE SE AGREGA (todo nuevo y con prefijo nuestro; nada compartido se modifica)
--   · tabla  public."GV_Clientes_Direcciones"  — espejo del padrón de direcciones de entrega
--   · vista  public.gv_geo_faltantes_padron    — lo del padrón que todavía no tiene ubicación
--   · vista  public.gv_geo_cobertura           — para medir cuánto falta de un vistazo
--
-- La tabla la llena la Edge Function `gv-sync-padron-direcciones` (lee LK con WEB_SERVICE_KEY;
-- `chef_customers` y `chef_customer_delivery_addresses` viven también en el proyecto de LK, así
-- que con una sola clave se traen las dos empresas).
--
-- ⚠ El padrón se geocodifica SÓLO contra `GV_Geo_Cliente` (nuestra). A `PPP_Geo` —compartida con
--   Producción— se le siguen agregando únicamente las direcciones que de verdad se programaron.
--
-- MEDIDO EL MISMO DÍA (07/09)
--   · `GV_Clientes_Direcciones` → 2.307 direcciones: LK 918 AMBA + 684 interior,
--     Chef 337 AMBA + 368 interior.
--   · `gv_geo_faltantes_padron` → 2.066 por ubicar (1.025 AMBA + 1.041 interior); las 241 de
--     diferencia son Retira o dirección que `gv_dir_geo_query` descarta.
--   · corrida de prueba con max=8 → 4 ubicadas, 4 fallaron (`GV_Geo_Log` id 19).
--   · el DEPÓSITO quedó ubicado: `PPP_Geo.__deposito_virgilio_2788__` = -34.6157998, -58.5252267
--     (Virgilio 2788, Villa Real, CABA). Sin eso el front caía al fallback "centro de CABA"
--     (-34.6037, -58.4), a 11 km del depósito real, y no se podía calcular ni un tiempo de viaje.
--
-- CRONS
--   · 79 `gv-sync-padron-direcciones` — 40 8 * * * (05:40 ART), refresca el padrón.
--   · 75 `gv-geocodificar` — se aceleró de `20 */6 * * *` a `*/10 * * * *` para drenar las 2.066
--     (40 por corrida × 6 corridas/h ≈ 9 h). **Volver a `20 */6 * * *` cuando `gv_geo_cobertura`
--     esté en verde**; con 1 llamada por segundo a Nominatim el promedio queda muy por debajo de
--     su límite de uso, pero no hay motivo para dejarlo corriendo cada 10 min para siempre.
--
-- ROLLBACK
--   drop view if exists public.gv_geo_cobertura;
--   drop view if exists public.gv_geo_faltantes_padron;
--   drop table if exists public."GV_Clientes_Direcciones";
--   select cron.unschedule('gv-sync-padron-direcciones');
--   select cron.alter_job(75, schedule := '20 */6 * * *');
--   delete from public."PPP_Geo" where dir_key = '__deposito_virgilio_2788__';   -- fila NUESTRA

-- ── 1) El padrón de direcciones de entrega ────────────────────────────────────────────────
create table if not exists public."GV_Clientes_Direcciones" (
  empresa        text not null check (empresa in ('lk', 'chef')),
  cod            text not null,
  slot           integer not null default 1,
  razon_social   text,
  direccion      text not null,
  localidad      text,
  provincia      text,
  cp             text,
  zona_expreso   text,
  dir_key        text not null,
  amba           boolean not null default false,
  actualizado_at timestamptz not null default now(),
  primary key (empresa, cod, slot)
);

create index if not exists gv_cli_dir_dirkey_idx on public."GV_Clientes_Direcciones" (dir_key);
create index if not exists gv_cli_dir_amba_idx   on public."GV_Clientes_Direcciones" (amba, empresa, cod);

alter table public."GV_Clientes_Direcciones" enable row level security;

drop policy if exists gv_cli_dir_lectura on public."GV_Clientes_Direcciones";
create policy gv_cli_dir_lectura on public."GV_Clientes_Direcciones"
  for select to authenticated using (true);

comment on table public."GV_Clientes_Direcciones" is
  'v14.16 — espejo del padrón de direcciones de entrega de LK y Chef, para poder ubicar en el '
  'mapa a TODOS los clientes aunque no hayan pedido nunca. La llena gv-sync-padron-direcciones.';

-- ── 2) Lo del padrón que falta ubicar ─────────────────────────────────────────────────────
-- Mismo contrato de columnas que `gv_geo_faltantes`, así la Edge Function las trata igual.
-- Orden: primero AMBA (son las que suben a nuestros camiones), después el interior (expreso).
create or replace view public.gv_geo_faltantes_padron
with (security_invoker = true) as
  select 'PADRON'::text                         as fuente,
         d.cod,
         d.razon_social,
         d.direccion,
         d.localidad                            as barrio,
         d.zona_expreso                         as zona,
         d.dir_key,
         coalesce(x.direccion_ok, gv_dir_geo_query(d.direccion)) as dir_query,
         coalesce(x.barrio_ok, d.localidad)     as barrio_geo,
         (x.dir_key is not null)                as corregida,
         null::date                             as fecha_entrega,
         d.empresa,
         d.provincia,
         d.amba
    from public."GV_Clientes_Direcciones" d
    left join public."GV_Geo_Correccion" x on x.dir_key = d.dir_key
    left join public."GV_Geo_Cliente"    c on c.cod = d.cod and c.dir_key = d.dir_key
    left join public."PPP_Geo"           g on g.dir_key = d.dir_key and g.lat is not null
   where gv_dir_geo_query(d.direccion) is not null
     and c.cod is null
     and g.dir_key is null
     and lower(coalesce(d.zona_expreso, '')) not like '%retira%'
   order by d.amba desc, d.empresa, d.cod;

comment on view public.gv_geo_faltantes_padron is
  'v14.16 — direcciones del padrón (pidieron o no) que todavía no tienen ubicación. AMBA primero.';

-- ── 3) Un número para saber cuánto falta ──────────────────────────────────────────────────
create or replace view public.gv_geo_cobertura
with (security_invoker = true) as
  with p as (select * from public."GV_Clientes_Direcciones"),
       u as (select distinct cod, dir_key from public."GV_Geo_Cliente" where lat is not null)
  select case when p.amba then 'AMBA' else 'Interior' end as ambito,
         p.empresa,
         count(*)                                                        as direcciones,
         count(*) filter (where u.cod is not null)                       as ubicadas,
         count(*) filter (where u.cod is null)                           as faltan,
         round(100.0 * count(*) filter (where u.cod is not null) / nullif(count(*), 0), 1) as pct
    from p left join u on u.cod = p.cod and u.dir_key = p.dir_key
   group by 1, 2
   order by 1, 2;

comment on view public.gv_geo_cobertura is
  'v14.16 — cuántas direcciones del padrón están ubicadas y cuántas faltan, por ámbito y empresa.';
