-- gv_dir_geo_normalizar(dir, barrio) — v14.28 (2026-09-08) · Virgilio (hrxfctzncixxqmpfhskv)
--
-- EL PROBLEMA, QUE YA PASÓ TRES VECES EN DOS DÍAS
-- ==============================================
-- ISIS escribe el barrio **adentro de la calle** y además lo manda aparte, en su propia
-- columna. El geocodificador arma la consulta pegando las dos cosas:
--
--   direccion = "Avalos 188, Paternal"   barrio = "Paternal"
--   → "Avalos 188, Paternal, Paternal, Buenos Aires, Argentina"   → sin resultado
--
-- Los tres casos:
--   · cód 45   `B DE ASTRADA 2796, Soldati`      (07/09, se arregló a mano)
--   · cód 4045 `Ayacucho 56 - San Antonio de P`  (07/09, se arregló a mano)
--   · cód 738  `Avalos 188, Paternal`            (08/09, tanda E03D del mar 15)
--
-- Tres correcciones a mano para el mismo patrón es la señal de que el patrón va en el código.
--
-- LA SOLUCIÓN
-- ===========
-- Una versión de dos argumentos de `gv_dir_geo_normalizar` que, además de todo lo que hace la
-- de uno (v14.26), saca la cola `", Barrio"` **sólo cuando repite el barrio de entrega**.
--
-- ⚠ El "sólo cuando repite" es la parte importante. Hay un caso que se parece y NO hay que
--   tocar: las direcciones de expreso del padrón, donde la cola es el barrio del **depósito**
--   y es distinto del que viene aparte —`"Las Casas 3553, Boedo"` con barrio Barracas—. Ahí la
--   cola es el dato bueno y sacarla rompería lo que hoy funciona.
--
-- La comparación va sin acentos ni mayúsculas y tolerando el artículo, porque ISIS escribe
-- "Paternal" y el barrio oficial es "La Paternal".
--
-- MEDIDO
-- ======
-- Sobre lo programado de los últimos 30 días, cambian 9 direcciones y las 9 están bien:
--   AUSTRALIA 2959, Barracas → AUSTRALIA 2959      Ferre 1455, Pompeya   → Ferre 1455
--   Av. Pinedo 50, Barracas → Av. Pinedo 50        Paracas 253, Barracas → Paracas 253
--   Avalos 188, Paternal    → Avalos 188           PERGAMINO 3750/1, Soldati → PERGAMINO 3750/1
--   B DE ASTRADA 2796, Soldati → B DE ASTRADA 2796 Virgilio 2788, Retira → Virgilio 2788
--
-- Sobre el padrón entero: **0 cambios** (el padrón de LK/Chef no trae el barrio pegado; el que
-- lo trae es ISIS). O sea que el cambio no puede despegar nada de lo ya geocodificado.
--
-- Y la consulta nueva resuelve, probado contra Nominatim antes de dar por bueno el arreglo:
--   "Avalos 188, Paternal, Buenos Aires, Argentina"
--   → 200 · "188, Ávalos, La Paternal, Buenos Aires" · -34.5944902, -58.4660598
--
-- ROLLBACK
-- ========
--   Volver el `dir_query` de las dos vistas a la versión de un argumento
--   (`gv_dir_geo_normalizar(gv_dir_geo_query(...))`) y
--   `drop function public.gv_dir_geo_normalizar(text, text);`.
--   No escribe nada: no hay datos que restaurar.

create or replace function public.gv_dir_geo_normalizar(p_dir text, p_barrio text)
returns text
language sql
immutable
set search_path to 'public','pg_temp'
as $$
  with n as (
    select public.gv_dir_geo_normalizar(p_dir) as d,
           btrim(lower(translate(coalesce(p_barrio,''), 'áéíóúüñÁÉÍÓÚÜÑ', 'aeiouunAEIOUUN'))) as b
  ), c as (
    select d, b,
           btrim(split_part(d, ',', array_length(string_to_array(d, ','), 1))) as cola
    from n
  ), p as (
    select d, b, cola,
           btrim(lower(translate(cola, 'áéíóúüñÁÉÍÓÚÜÑ', 'aeiouunAEIOUUN'))) as cola_plana
    from c
  )
  select case
    when b = '' or d is null or position(',' in d) = 0 then d
    when cola_plana in (b, 'la ' || b, ltrim(b, 'la ')) or b in (cola_plana, 'la ' || cola_plana)
      then btrim(btrim(left(d, length(d) - length(cola) - 1)), ',')
    else d end
  from p;
$$;

comment on function public.gv_dir_geo_normalizar(text, text) is
  'v14.28 - ademas de lo que hace la version de un argumento, saca la cola ", Barrio" cuando repite '
  'el barrio de entrega. ISIS lo manda las dos veces y Nominatim no encuentra nada con el duplicado.';

-- Las dos vistas pasan a la versión de dos argumentos. El cuerpo completo está en
-- `sql/gv_geo_normalizar_v1426.sql`; acá sólo cambia la línea del `dir_query`:
--
--   gv_geo_faltantes        … gv_dir_geo_normalizar(gv_dir_geo_query(p.direccion), p.barrio)
--   gv_geo_faltantes_padron … COALESCE(x.direccion_ok,
--                               gv_dir_geo_normalizar(gv_dir_geo_query(d.direccion), d.barrio_entrega))
--
-- VERIFICADO: `select * from public.gv_geo_faltantes;` sigue devolviendo la única fila
-- pendiente (cód 738), pero ahora con `dir_query = 'Avalos 188'` en vez de
-- `'Avalos 188, Paternal'`. La próxima corrida del cron 75 la ubica sola.
