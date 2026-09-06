-- ============================================================================
-- v13.41 — Correcciones de dirección para GEOCODIFICAR, sin tocar ISIS
--
-- Dueño (2026-09-06): *"sí, dale. Ambas"* — que se corrija en ISIS y, además,
-- que Gestión tenga su propia corrección para no depender de eso.
--
-- De las 64 direcciones programadas quedaron 16 sin ubicar, TODAS por cómo las
-- escribe ISIS: "PEGAMINO 3751" (Pergamino), "Chilavet M Cnel." (Coronel
-- Martiniano Chilavert), "Ohiggins" (O'Higgins), "Pacifico Rodrigrez" (Pacífico
-- Rodríguez), "B DE ASTRADA" (Berón de Astrada)… El geocodificador no adivina, y
-- no corresponde que adivine: una dirección inventada manda el camión a otro
-- lado. Por eso la corrección es un DATO, cargado y revisable.
--
-- ⚠ Esto se usa SÓLO para preguntarle al geocodificador. La dirección que ve el
--   operario, la que se imprime en la etiqueta y la que viaja a ISIS siguen
--   siendo las de ISIS. Ni una fila de `PPP_Programacion_Diaria` se toca.
-- ============================================================================
create table if not exists public."GV_Geo_Correccion" (
  dir_key       text primary key,          -- clave (gv_dir_key) de la dirección MAL escrita
  cod           text,                      -- informativo: de qué cliente salió
  direccion_mal text,                      -- lo que escribe ISIS, para poder leerla
  direccion_ok  text not null,             -- la dirección buena
  barrio_ok     text,                      -- barrio corregido (null = queda el de ISIS)
  nota          text,
  creado_en     timestamptz not null default now()
);
comment on table public."GV_Geo_Correccion" is
  'v13.41 — dirección corregida para GEOCODIFICAR, por dir_key de la dirección mal escrita en ISIS. No cambia lo que se muestra, se imprime ni se manda a ISIS: sólo lo que se le pregunta a Nominatim.';

alter table public."GV_Geo_Correccion" enable row level security;
drop policy if exists gv_geo_correccion_sel on public."GV_Geo_Correccion";
drop policy if exists gv_geo_correccion_esc on public."GV_Geo_Correccion";
create policy gv_geo_correccion_sel on public."GV_Geo_Correccion" for select to anon, authenticated using (true);
create policy gv_geo_correccion_esc on public."GV_Geo_Correccion" for all to authenticated using (true) with check (true);
grant select on public."GV_Geo_Correccion" to anon, authenticated;
grant insert, update, delete on public."GV_Geo_Correccion" to authenticated;

-- `gv_geo_faltantes` entrega la dirección YA corregida en `dir_query` y el barrio
-- en `barrio_geo`, así la Edge Function no sabe nada de correcciones: pregunta lo
-- que le den. `corregida` dice si se aplicó una (para poder auditarlo).
drop view if exists public.gv_geo_faltantes;
create view public.gv_geo_faltantes
with (security_invoker = true) as
with prog as (
  select 'ISIS'::text as fuente, i.cod, i.razon_social, i.direccion, i.barrio, i.zona,
         left(btrim(i.fecha_entrega::text), 10)::date as fecha_entrega
    from public.gv_ppp_programacion_diaria i
   where btrim(coalesce(i.tanda, '')) <> ''
     and btrim(i.fecha_entrega::text) ~ '^\d{4}-\d{2}-\d{2}'
     and left(btrim(i.fecha_entrega::text), 10)::date >= current_date - 7
  union all
  select 'WEB', w.cod_cliente, w.razon_social, w.direccion, w.barrio, w.zona, w.fecha_entrega
    from public."PPP_Web_Programacion" w
   where btrim(coalesce(w.tanda, '')) <> ''
     and w.fecha_entrega >= current_date - 7
), uno as (
  select distinct on (public.gv_dir_key(p.direccion, p.barrio))
         p.fuente, btrim(coalesce(p.cod, '')) as cod, p.razon_social, p.direccion, p.barrio, p.zona,
         public.gv_dir_key(p.direccion, p.barrio) as dir_key,
         public.gv_dir_geo_query(p.direccion) as dir_limpia,
         p.fecha_entrega
    from prog p
   where public.gv_dir_geo_query(p.direccion) is not null
     and lower(coalesce(p.zona, '')) not like '%retira%'
     -- v13.45 (dueño: "es súper y va separado"): camión propio, una parada, sin orden de carga
     and lower(btrim(coalesce(p.zona, ''))) not in ('super', 'súper')
   order by public.gv_dir_key(p.direccion, p.barrio), p.fecha_entrega
)
select u.fuente, u.cod, u.razon_social, u.direccion, u.barrio, u.zona, u.dir_key,
       coalesce(x.direccion_ok, u.dir_limpia) as dir_query,
       coalesce(x.barrio_ok, u.barrio)        as barrio_geo,
       (x.dir_key is not null)                as corregida,
       u.fecha_entrega
  from uno u
  left join public."GV_Geo_Correccion" x on x.dir_key = u.dir_key
  left join public."PPP_Geo" g on g.dir_key = u.dir_key and g.lat is not null
  left join public."GV_Geo_Cliente" c on c.cod = u.cod and c.dir_key = u.dir_key
 where g.dir_key is null and c.cod is null;

comment on view public.gv_geo_faltantes is
  'v13.41 — direcciones programadas (ISIS + web, desde 7 días atrás) sin ubicación. dir_query y barrio_geo vienen YA corregidos por GV_Geo_Correccion cuando corresponde; corregida dice si se aplicó una.';
grant select on public.gv_geo_faltantes to anon, authenticated;

-- ── Las 11 correcciones aprobadas por el dueño el 2026-09-06 ────────────────
insert into public."GV_Geo_Correccion" (dir_key, cod, direccion_mal, direccion_ok, barrio_ok, nota) values
 (public.gv_dir_key('PEGAMINO 3751','Soldati'),            '1941','PEGAMINO 3751',           'Pergamino 3751',                   'Villa Soldati',   'ISIS: PEGAMINO → Pergamino'),
 (public.gv_dir_key('AV. INT. RAVANAL 3159','VILLA SOLDATI'),'3938','AV. INT. RAVANAL 3159',  'Av. Intendente Rabanal 3159',      'Villa Soldati',   'ISIS: RAVANAL → Rabanal'),
 (public.gv_dir_key('Chilavet M Cnel.  6546','Villa Lugano'),'4061','Chilavet M Cnel. 6546',  'Coronel Martiniano Chilavert 6546','Villa Lugano',    'ISIS: Chilavet → Chilavert'),
 (public.gv_dir_key('Pacifico Rodrigrez  6137','Villa Ballester'),'3927','Pacifico Rodrigrez 6137','Pacífico Rodríguez 6137',     'Villa Ballester', 'ISIS: Rodrigrez → Rodríguez'),
 (public.gv_dir_key('Ohiggins   454','Pilar'),              '4254','Ohiggins 454',            'O''Higgins 454',                   'Pilar',           'ISIS: Ohiggins → O''Higgins'),
 (public.gv_dir_key('B DE ASTRADA 2796','Soldati'),         '1323','B DE ASTRADA 2796',       'Berón de Astrada 2796',            'Villa Soldati',   'ISIS: B DE ASTRADA → Berón de Astrada'),
 (public.gv_dir_key('Av. F. Lacroze  2481','Colegiales'),   '1792','Av. F. Lacroze 2481',     'Avenida Federico Lacroze 2481',    'Colegiales',      'ISIS: F. Lacroze → Federico Lacroze'),
 (public.gv_dir_key('Av Otto Krausse  5108','Tortuguita'),  '1651','Av Otto Krausse 5108',    'Otto Krause 5108',                 'Malvinas Argentinas','ISIS: Krausse → Krause. Tortuguitas es la localidad; con el PARTIDO (Malvinas Argentinas) sí lo encuentra'),
 (public.gv_dir_key('Jufre   339','Palermo'),               '1587','Jufre 339',               'Jufré 339',                        'Villa Crespo',    'ISIS: Jufre sin acento; Jufré al 300 es Villa Crespo, no Palermo'),
 (public.gv_dir_key('PEDRO CHUTRO 2735','Soldati'),         '2336','PEDRO CHUTRO 2735',       'Pedro Chutro 2735',                'Parque Patricios','ISIS: Pedro Chutro está en Parque Patricios, no Soldati'),
 (public.gv_dir_key('CHUTRO 2735','P.Patricios'),           '1562','CHUTRO 2735',             'Pedro Chutro 2735',                'Parque Patricios','ISIS: falta el nombre de pila de la calle')
on conflict (dir_key) do nothing;

-- ── Cómo agregar una corrección nueva ──────────────────────────────────────
-- 1. mirar qué falta:  select cod, razon_social, direccion, barrio, dir_key from public.gv_geo_faltantes where not corregida;
-- 2. cargarla:
--    insert into public."GV_Geo_Correccion" (dir_key, cod, direccion_mal, direccion_ok, barrio_ok, nota)
--    values (public.gv_dir_key('<direccion tal cual ISIS>','<barrio tal cual ISIS>'), '<cod>',
--            '<direccion tal cual ISIS>', '<la buena>', '<barrio bueno o null>', '<por qué>')
--    on conflict (dir_key) do update set direccion_ok = excluded.direccion_ok, barrio_ok = excluded.barrio_ok, nota = excluded.nota;
-- 3. el cron 75 la toma en la próxima corrida (o dispararlo a mano con body '{"max": 20}').
--
-- ROLLBACK: drop table public."GV_Geo_Correccion" cascade;  y volver a crear la
-- vista con la versión de sql/gv_geo_cliente.sql.

-- ── Correcciones cargadas después, el mismo 2026-09-06 ───────────────────────
insert into public."GV_Geo_Correccion" (dir_key, cod, direccion_mal, direccion_ok, barrio_ok, nota) values
 (public.gv_dir_key('I. Catolica 6- Rio Cuarto','Soldati'), '2466', 'I. Catolica 6- Rio Cuarto', 'Pergamino 3751', 'Villa Soldati',
  'Chef: la sucursal del cliente está en Río Cuarto; nuestra entrega es el expreso (chef_customer_delivery_addresses.direccion_entrega). Desde v13.43 el feed ya lo manda.'),
 (public.gv_dir_key('Av. La Salle 1923','Flores'), '1821', 'Av. La Salle 1923', 'Avenida San Juan Bautista de La Salle 1923', 'Parque Avellaneda',
  'Dueño 2026-09-06: es Av. San Juan Bautista de la Salle (C1407, esq. Av. Olivera = Parque Avellaneda, no Flores como dice ISIS)')
on conflict (dir_key) do nothing;
-- (la de "Trole 163" → "Pasaje Trole" se borró: quedó como ubicación MANUAL en GV_Geo_Cliente)

-- ── Ubicaciones MANUALES (pin del dueño en Google Maps, 2026-09-06) ──────────
-- Las tres calles existen en Google pero no en OpenStreetMap. Van con precision='manual'
-- y manual=true; el cron nunca las pisa porque gv_geo_faltantes las excluye por (cod, dir_key).
--   732  Bertola Enrique       Trole 163, Parque Patricios        -34.64181, -58.41944
--   888  Distribuidora Pezzali La Salle 2174 (ISIS: Flores)       -34.65450, -58.47567  (cae en Mataderos)
--   4114 Extralimp             J. M. Pérez 977, Luján             -34.56350, -59.13658
-- Cómo cargar una nueva:
--   insert into public."GV_Geo_Cliente" (cod, dir_key, razon_social, direccion, barrio, lat, lng, fuente, manual, precision)
--   values ('<cod>', public.gv_dir_key('<direccion tal cual ISIS>','<barrio tal cual ISIS>'), '<cliente>', '<direccion>', '<barrio>', <lat>, <lng>, 'google_maps_dueño', true, 'manual')
--   on conflict (cod, dir_key) do update set lat = excluded.lat, lng = excluded.lng, manual = true, precision = 'manual', actualizado_at = now();
--   y la misma fila a PPP_Geo con `on conflict (dir_key) do nothing` (compartida con Producción: sólo agregar).
