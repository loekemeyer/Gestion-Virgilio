-- gv_geo_barrio_entrega — v14.20 (2026-09-07) · Virgilio (hrxfctzncixxqmpfhskv)
--
-- LA CORRECCIÓN DEL DUEÑO
-- =======================
--     "no entrego en ninguno del interior"
--     "quién del interior tenés? está mal, no entrego en esa dirección"
--
-- Tenía razón, y el error estaba en cómo leí el padrón. En
-- `customer_delivery_addresses`, **`localidad` y `provincia` son del CLIENTE, no de la
-- dirección de entrega**. Ejemplo real (cliente 15, Bazar Tifni):
--
--     direccion_entrega  = "Las Casas 3553"
--     localidad          = "Rosario"          ← del cliente
--     provincia          = "Santa Fe"         ← del cliente
--     direccion_expreso  = "LAS CASAS 3553, Boedo"   ← DONDE SE ENTREGA (CABA)
--
-- Misma calle y altura, pero en Boedo. La entrega es en el depósito del expreso, en Buenos
-- Aires. Yo pegué la calle con la localidad del cliente y le pedí a Nominatim
-- "Las Casas 3553, Rosario, Santa Fe" — que no existe. **Por eso fallaban todas.**
--
-- MEDIDO sobre las 573 filas de "interior" que tienen dato de expreso:
--   · 533 (93,0 %) tienen la MISMA calle y altura en `direccion_entrega` y `direccion_expreso`
--   · 573 (100 %) tienen barrio de CABA en `direccion_expreso` y `zona_expreso` cargada
--
-- CONCLUSIÓN: **no existe una entrega en el interior**. Las 2.307 direcciones son de AMBA.
--
-- QUÉ CAMBIA
-- ==========
--   · `GV_Clientes_Direcciones` suma `barrio_entrega`, `dir_expreso` y `nombre_expreso`.
--     `barrio_entrega` = `zona_expreso` → barrio de `direccion_expreso` → `localidad`.
--   · El `dir_key` pasa a armarse con el barrio DE ENTREGA (era con la localidad del cliente).
--   · `amba` queda en `true` para todas; se deja la columna por compatibilidad.
--   · `gv_geo_faltantes_padron` usa `barrio_entrega` y **no manda la provincia** al
--     geocodificador: mandarla lo hacía buscar a 800 km.
--   · `gv_geo_cobertura` se parte por si el CLIENTE es del interior (que es el corte que
--     importa: esas se entregan al expreso), no por `amba`, que ahora es siempre true.
--   · Edge Function `gv-sync-padron-direcciones` v3. Pide `direccion_expreso` y, si el proyecto
--     no la tiene (Chef puede no tenerla), reintenta sin ella en vez de perder el padrón entero.
--
-- RESULTADO MEDIDO, la corrida siguiente al cambio:
--   19:03 (antes) →  7 ubicadas de 40
--   19:11 (después) → 30 ubicadas de 40
--
-- DOS COSAS QUE HUBO QUE ARREGLAR DE PASO
--   1. Los fallos anotados en `GV_Geo_Fallidas` eran contra la clave vieja: se borraron, esas
--      direcciones merecían otra oportunidad con el barrio correcto.
--   2. Al cambiar el `dir_key`, las ~300 ya ubicadas dejaron de matchear (Chef AMBA cayó de
--      303 a 23 en la vista). Las coordenadas no se habían perdido: se copiaron a la clave
--      nueva con el INSERT de abajo en vez de volver a pedírselas a Nominatim.
--
-- ROLLBACK: restaurar la vista de `sql/gv_geo_fallidas_v1419.sql` y desplegar la v2 de la
-- Edge Function. Las columnas nuevas pueden quedar: son nullable y nadie más las lee.

alter table public."GV_Clientes_Direcciones"
  add column if not exists barrio_entrega text,
  add column if not exists dir_expreso    text,
  add column if not exists nombre_expreso text;

-- La vista de faltantes, con el barrio de entrega y sin la provincia del cliente.
create or replace view public.gv_geo_faltantes_padron
with (security_invoker = true) as
  select 'PADRON'::text as fuente, d.cod, d.razon_social, d.direccion,
         d.barrio_entrega as barrio, d.zona_expreso as zona, d.dir_key,
         coalesce(x.direccion_ok, gv_dir_geo_query(d.direccion)) as dir_query,
         coalesce(x.barrio_ok, d.barrio_entrega) as barrio_geo,
         (x.dir_key is not null) as corregida, null::date as fecha_entrega,
         d.empresa,
         null::text as provincia,   -- la entrega es en AMBA; la provincia del cliente desorienta
         true as amba
    from public."GV_Clientes_Direcciones" d
    left join public."GV_Geo_Correccion" x on x.dir_key = d.dir_key
    left join public."GV_Geo_Cliente"    c on c.cod = d.cod and c.dir_key = d.dir_key
    left join public."PPP_Geo"           g on g.dir_key = d.dir_key and g.lat is not null
    left join public."GV_Geo_Fallidas"   f on f.cod = d.cod and f.dir_key = d.dir_key
   where gv_dir_geo_query(d.direccion) is not null
     and coalesce(btrim(d.barrio_entrega),'') <> ''
     and c.cod is null and g.dir_key is null
     and coalesce(f.intentos,0) < 3
     and lower(coalesce(d.zona_expreso,'')) not like '%retira%'
   order by d.empresa, d.cod;

create or replace view public.gv_geo_cobertura
with (security_invoker = true) as
  with p as (select * from public."GV_Clientes_Direcciones"),
       u as (select distinct cod, dir_key from public."GV_Geo_Cliente" where lat is not null)
  select case when coalesce(p.provincia,'') in ('CABA','Buenos Aires')
              then 'Cliente AMBA' else 'Cliente del interior (entrega al expreso)' end as ambito,
         p.empresa,
         count(*) as direcciones,
         count(*) filter (where u.cod is not null) as ubicadas,
         count(*) filter (where u.cod is null) as faltan,
         round(100.0*count(*) filter (where u.cod is not null)/nullif(count(*),0),1) as pct
    from p left join u on u.cod = p.cod and u.dir_key = p.dir_key
   group by 1,2 order by 1,2;

-- Rescate de las ya ubicadas: copiar sus coordenadas de la clave vieja a la nueva.
insert into public."GV_Geo_Cliente"
  (cod, dir_key, razon_social, direccion, barrio, lat, lng, comp, fuente, precision, actualizado_at)
select d.cod, d.dir_key, d.razon_social, d.direccion, d.barrio_entrega,
       g.lat, g.lng, g.comp, g.fuente, g.precision, now()
  from public."GV_Clientes_Direcciones" d
  join public."GV_Geo_Cliente" g
    on g.cod = d.cod and g.dir_key = gv_dir_key(d.direccion, d.localidad) and g.lat is not null
  left join public."GV_Geo_Cliente" nuevo on nuevo.cod = d.cod and nuevo.dir_key = d.dir_key
 where nuevo.cod is null and d.dir_key <> gv_dir_key(d.direccion, d.localidad)
on conflict (cod, dir_key) do nothing;

-- Los fallos viejos se anotaron contra la clave equivocada.
delete from public."GV_Geo_Fallidas";
