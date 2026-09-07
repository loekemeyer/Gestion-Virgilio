-- gv_dir_geo_normalizar — v14.26 (2026-09-07) · Virgilio (hrxfctzncixxqmpfhskv)
--
-- EL PROBLEMA
-- ===========
-- Con la cola destapada (v14.19) y el padrón acotado a los clientes habituales de CABA/AMBA
-- (v14.21/v14.22), el geocodificador venía resolviendo la mitad de lo que pedía. La otra mitad
-- fallaba **siempre por lo mismo**: no es que Nominatim no conozca la calle, es que la dirección
-- que sale de ISIS no está escrita como una dirección.
--
-- Los tres patrones, medidos sobre las 29 direcciones que se habían dado por perdidas:
--
--   1. Punto pegado a la letra siguiente   "Av.Fco.Beiro 5425"   "Int.Rabanal 2876"
--   2. Cola de depósito del expreso        "Pinedo 50 Galpon 3"  "Pinedo 50 G 4 Pta 5"
--                                          "Av.Pinedo 50 Galpon 3 Est.Sola"
--   3. Abreviaturas de tratamiento         "Int Perez Quintana"  "Gral Madariaga"  "Pte Peron"
--
-- Un depósito del expreso en Estación Sola aparece escrito de **nueve formas distintas** en el
-- padrón; todas son la misma esquina de Pinedo y Av. Suárez, en Barracas.
--
-- LA SOLUCIÓN
-- ===========
-- Una función que limpia el texto **antes** de consultarlo. Va en el `dir_query` de las dos
-- vistas de faltantes, después de `gv_dir_geo_query` (que es la que saca el "Exp. … —" y el
-- paréntesis del final) y antes de `GV_Geo_Correccion` (una corrección a mano siempre gana).
--
-- ⚠ NO toca `dir_key`. El `dir_key` se arma con la dirección cruda + el barrio de entrega, así
--   que nada de lo ya geocodificado se despega. Cambiar el dir_key fue el error del 07/09 a la
--   mañana: desenganchó ~300 filas ya ubicadas y hubo que copiarlas de la clave vieja a la nueva.
--
-- Cuidados que se tomaron (probados uno por uno, ver "MEDICIÓN"):
--   · La "G" suelta de galpón sólo se saca **si viene después de la altura y al final**, para no
--     comerse una inicial: "Artigas Jose G. 4927" tiene que quedar entero (y queda).
--   · El punto pegado se reemplaza en dos pasadas porque `regexp_replace` no solapa:
--     "J.A.Roca" necesita la segunda para dar "J. A. Roca".
--   · Al final se limpia la puntuación colgada, si no "Av. Suarez Y Pinedo - Galpon 3" quedaba
--     como "Av. Suarez Y Pinedo -".
--
-- MEDICIÓN (antes de aplicar)
-- ===========================
--   select distinct gv_dir_geo_query(direccion),
--          gv_dir_geo_normalizar(gv_dir_geo_query(direccion))
--     from public."GV_Clientes_Direcciones"
--    where gv_dir_geo_normalizar(gv_dir_geo_query(direccion))
--          is distinct from gv_dir_geo_query(direccion);
--   → 160 filas / 85 direcciones distintas cambian. Se revisaron las 85 a ojo, una por una.
--
--   Y que las programadas no se rompan:
--   select count(*) from public.gv_geo_faltantes;   → 0 antes y 0 después.
--
-- ROLLBACK
-- ========
--   Sacar el `gv_dir_geo_normalizar(...)` del `dir_query` de las dos vistas (volver a
--   `gv_dir_geo_query(...)` pelado) y `drop function public.gv_dir_geo_normalizar(text);`.
--   Nada que restaurar: la función no escribe.

create or replace function public.gv_dir_geo_normalizar(p_dir text)
returns text
language sql
immutable
set search_path to 'public','pg_temp'
as $$
  with a as (select coalesce(p_dir,'') as d),
  -- 1) punto pegado entre letras: "Av.Fco.Beiro" -> "Av. Fco. Beiro". Dos pasadas porque
  --    regexp_replace no solapa: "J.A.Roca" necesita la segunda.
  b as (select regexp_replace(regexp_replace(d, '([[:alpha:]])\.([[:alpha:]])', '\1. \2', 'g'),
                              '([[:alpha:]])\.([[:alpha:]])', '\1. \2', 'g') as d from a),
  -- 2) cola de deposito: galpon/puerta/local/piso/dto + numero, hasta el final
  c as (select btrim(regexp_replace(d,
         '[ ,]+(galp[oó]n|galp|gal|pta|puerta|dep[oó]sito|dto|local|piso)\.?\s*[0-9]+.*$', '', 'i')) as d from b),
  -- 3) "G 4" / "50G3" = galpon abreviado. SOLO si viene despues de la altura y al final,
  --    para no comerse una inicial ("Artigas Jose G. 4927" tiene que quedar entero).
  d2 as (select btrim(regexp_replace(d, '([0-9])\s*g\.?\s*[0-9]+\s*$', '\1', 'i')) as d from c),
  -- 4) "Est.Sola" / "Estacion Sola" al final (la estacion del expreso, no la calle)
  e as (select btrim(regexp_replace(d, '[ ,]+est(aci[oó]n)?\.?\s*sola\s*$', '', 'i')) as d from d2),
  -- 5) abreviaturas que Nominatim no resuelve
  f as (select
         regexp_replace(
         regexp_replace(
         regexp_replace(
         regexp_replace(
         regexp_replace(d,
           '\yint\.?\s+', 'Intendente ', 'i'),
           '\yfco\.?\s+', 'Francisco ', 'i'),
           '\ygral\.?\s+', 'General ', 'i'),
           '\ypte\.?\s+', 'Presidente ', 'i'),
           '\ybme\.?\s+', 'Bartolome ', 'i') as d from e),
  -- 6) puntuacion colgada al final ("Av. Suarez Y Pinedo -")
  g as (select btrim(regexp_replace(d, '[\s,;:.\-]+$', '')) as d from f)
  select case when btrim(d) = '' then null else btrim(regexp_replace(d, '\s+', ' ', 'g')) end from g;
$$;

comment on function public.gv_dir_geo_normalizar(text) is
  'v14.26 - limpia la direccion ANTES de preguntarle a Nominatim: punto pegado, cola de galpon/puerta, '
  'Est.Sola y abreviaturas (Int./Fco./Gral./Pte./Bme.). No toca dir_key: solo cambia el texto que se consulta.';

-- ── Las dos vistas, con el normalizador metido en el dir_query ──────────────────────────────
create or replace view public.gv_geo_faltantes
with (security_invoker = true) as
 WITH prog AS (
         SELECT 'ISIS'::text AS fuente, i.cod, i.razon_social, i.direccion, i.barrio, i.zona,
            "left"(btrim(i.fecha_entrega), 10)::date AS fecha_entrega
           FROM gv_ppp_programacion_diaria i
          WHERE btrim(COALESCE(i.tanda, ''::text)) <> ''::text
            AND btrim(i.fecha_entrega) ~ '^\d{4}-\d{2}-\d{2}'::text
            AND "left"(btrim(i.fecha_entrega), 10)::date >= (CURRENT_DATE - 7)
        UNION ALL
         SELECT 'WEB'::text, w.cod_cliente, w.razon_social, w.direccion, w.barrio, w.zona, w.fecha_entrega
           FROM "PPP_Web_Programacion" w
          WHERE btrim(COALESCE(w.tanda, ''::text)) <> ''::text AND w.fecha_entrega >= (CURRENT_DATE - 7)
        ), uno AS (
         SELECT DISTINCT ON ((gv_dir_key(p.direccion, p.barrio))) p.fuente,
            btrim(COALESCE(p.cod, ''::text)) AS cod, p.razon_social, p.direccion, p.barrio, p.zona,
            gv_dir_key(p.direccion, p.barrio) AS dir_key,
            -- v14.26: se normaliza antes de consultar (galpon/puerta, punto pegado, abreviaturas)
            gv_dir_geo_normalizar(gv_dir_geo_query(p.direccion)) AS dir_limpia,
            p.fecha_entrega
           FROM prog p
          WHERE gv_dir_geo_query(p.direccion) IS NOT NULL
            AND lower(COALESCE(p.zona, ''::text)) !~~ '%retira%'::text
            AND (lower(btrim(COALESCE(p.zona, ''::text))) <> ALL (ARRAY['super'::text, 'súper'::text]))
          ORDER BY (gv_dir_key(p.direccion, p.barrio)), p.fecha_entrega
        )
 SELECT u.fuente, u.cod, u.razon_social, u.direccion, u.barrio, u.zona, u.dir_key,
    COALESCE(x.direccion_ok, u.dir_limpia) AS dir_query,
    COALESCE(x.barrio_ok, u.barrio) AS barrio_geo,
    x.dir_key IS NOT NULL AS corregida,
    u.fecha_entrega
   FROM uno u
     LEFT JOIN "GV_Geo_Correccion" x ON x.dir_key = u.dir_key
     LEFT JOIN "PPP_Geo" g ON g.dir_key = u.dir_key AND g.lat IS NOT NULL
     LEFT JOIN "GV_Geo_Cliente" c ON c.cod = u.cod AND c.dir_key = u.dir_key
  WHERE g.dir_key IS NULL AND c.cod IS NULL;

create or replace view public.gv_geo_faltantes_padron
with (security_invoker = true) as
 SELECT 'PADRON'::text AS fuente, d.cod, d.razon_social, d.direccion,
    d.barrio_entrega AS barrio, d.zona_expreso AS zona, d.dir_key,
    -- v14.26: se normaliza antes de consultar (galpon/puerta, punto pegado, abreviaturas)
    COALESCE(x.direccion_ok, gv_dir_geo_normalizar(gv_dir_geo_query(d.direccion))) AS dir_query,
    COALESCE(x.barrio_ok, d.barrio_entrega) AS barrio_geo,
    x.dir_key IS NOT NULL AS corregida,
    NULL::date AS fecha_entrega,
    d.empresa, NULL::text AS provincia, true AS amba
   FROM "GV_Clientes_Direcciones" d
     JOIN gv_clientes_habituales h ON h.cod = d.cod AND h.empresa = d.empresa
     LEFT JOIN "GV_Geo_Correccion" x ON x.dir_key = d.dir_key
     LEFT JOIN "GV_Geo_Cliente" c ON c.cod = d.cod AND c.dir_key = d.dir_key
     LEFT JOIN "PPP_Geo" g ON g.dir_key = d.dir_key AND g.lat IS NOT NULL
     LEFT JOIN "GV_Geo_Fallidas" f ON f.cod = d.cod AND f.dir_key = d.dir_key
  WHERE (COALESCE(d.provincia, ''::text) = ANY (ARRAY['CABA'::text, 'Buenos Aires'::text]))
    AND gv_dir_geo_query(d.direccion) IS NOT NULL
    AND COALESCE(btrim(d.barrio_entrega), ''::text) <> ''::text
    AND c.cod IS NULL AND g.dir_key IS NULL
    AND COALESCE(f.intentos, 0) < 3
    AND lower(COALESCE(d.zona_expreso, ''::text)) !~~ '%retira%'::text
  ORDER BY d.empresa, d.cod;

-- ── Lo que el normalizador NO puede arreglar: correcciones a mano ───────────────────────────
-- Son las que quedaron después de normalizar. Cada una con el motivo, que es lo que sirve
-- cuando dentro de seis meses alguien se pregunte por qué esta dirección está escrita distinta.
--
-- ⚠ El `dir_key` se arma con la dirección CRUDA + el barrio de entrega. Por eso el insert sale
--   de un select contra `GV_Clientes_Direcciones` y no de una constante: escribirlo a mano fue
--   el error del 07/09 con el cód 45 (se usó el dir_query limpio y la corrección no enganchó).

with fix(cod, dir_like, dir_ok, barrio_ok, nota) as (values
  ('1329','Av. Suarez Esq Pinedo%','Pinedo 50',              'Barracas',      'esquina + galpon: es el hub del expreso en Pinedo 50 (Est. Sola)'),
  ('2532','Av. Suarez Esq Pinedo%','Pinedo 50',              'Barracas',      'esquina + galpon: es el hub del expreso en Pinedo 50 (Est. Sola)'),
  ('1284','Av Jujuy 1481',         'Avenida Jujuy 1481',     'San Cristobal', 'el barrio "Constitucion" resolvia a 640 km (Constitucion del interior)'),
  ('1917','Av Jujuy 1240',         'Avenida Jujuy 1240',     'San Cristobal', 'el barrio "Constitucion" resolvia a 640 km (Constitucion del interior)'),
  ('1206','Av Lacroze 2433',       'Avenida Federico Lacroze 2433','Colegiales','Lacroze es Federico Lacroze; la altura 2433 cae en Colegiales, no Belgrano'),
  ('1206','Constitucion 2587',     'Calle Constitucion 2587','Balvanera',     'se aclara "Calle" para que no lo tome como el barrio Constitucion'),
  ('1987','Av J B Justo 8587',     'Avenida Juan B. Justo 8587','Liniers',    'iniciales'),
  ('2128','Juan D Peron 2323',     'Peron 2323',             'Balvanera',     'en CABA la calle es Peron (ex Cangallo); Once no es barrio oficial'),
  ('1954','San Juan B De La Salle 1926','San Juan Bautista de La Salle 1926','Parque Avellaneda','abreviatura'),
  ('1916','A Circunvalacio 550',   'Avenida Circunvalacion 550','Tapiales',   'truncado; el Mercado Central esta en Tapiales, La Matanza'),
  ('1321','A.Cafarena 36',         'Caffarena 36',           'La Boca',       'se escribe Caffarena, con dos efes'),
  ('2525','Sta.Domingo 3930',      'Santo Domingo 3930',     'Pompeya',       'Sta. aca es Santo, no Santa'),
  ('1409','Virgilio 2788, Retira, CABA','Virgilio 2788',     'Villa Real',    'le sobraba ", Retira, CABA"'),
  ('2039','Arenales 2000',         'Arenales 2000',          'Recoleta',      'la altura 2000 de Arenales es Recoleta, no San Nicolas')
)
insert into public."GV_Geo_Correccion" (dir_key, cod, direccion_mal, direccion_ok, barrio_ok, nota)
select distinct on (d.dir_key) d.dir_key, d.cod, d.direccion, f.dir_ok, f.barrio_ok, f.nota
  from fix f
  join public."GV_Clientes_Direcciones" d
    on d.cod = f.cod and d.direccion like f.dir_like
on conflict (dir_key) do nothing;
-- → 13 filas (1329 y 2532 comparten dir_key: es la misma direccion, la correccion vale para las dos)

-- Y devolver a la cola todo lo que se habia dado por perdido, ahora que la consulta es otra.
select public.gv_geo_reintentar();   -- → 70
