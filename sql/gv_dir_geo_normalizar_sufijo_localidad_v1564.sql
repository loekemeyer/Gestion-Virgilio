-- v15.64 (2026-09-11) — gv_dir_geo_normalizar(dir, barrio): pela el " - <localidad>" que la página pega
-- después de la altura. Pedido de Thomas ("2 sí") tras tapar de a una en GV_Geo_Correccion:
-- "Caamaño 1315 - Villa Rosa" (4 intentos, cayó a 32 km), "Donofrio 20 - Ciudadela" (13 intentos),
-- "Julio Godoy 4656 - Villa Lynch", "Pacífic Rodri 6137 - Villa Bal" (truncada a 30 por la página).
--
-- REGLA (se suma a la de la v14.28, barrio repetido después de una coma):
--   si después de un número viene " - <cola>" y la cola es el barrio, un PREFIJO del barrio de 3+
--   letras (truncada), o el barrio es prefijo de la cola → se saca. "Pinedo 50 - Galpon 3" no matchea
--   el barrio y sigue el camino de siempre (la v14.26 ya le saca la cola de depósito).
--   NO cambia dir_key (regla v14.26: lo ya geocodificado no se despega).
--
-- MEDICIÓN (11/09, antes de aplicar): 12 casos, 12 OK (ver select de abajo) · PPP_Web_Programacion:
--   25 direcciones cambian (todas con el patrón) · GV_Clientes_Direcciones: 1 · gv_geo_faltantes: 8 → 8.
--   Después de la corrida: 4024 Ciudadela y 3927 Villa Ballester ubicados.
-- ROLLBACK: recrear la función con la versión de sql/gv_geo_normalizar_v1428.sql (sólo la coma).
--
-- Migración: gv_dir_geo_normalizar_sufijo_localidad_v1564
create or replace function public.gv_dir_geo_normalizar(p_dir text, p_barrio text)
returns text
language sql
immutable
set search_path to 'public', 'pg_temp'
as $function$
  with n as (
    select public.gv_dir_geo_normalizar(p_dir) as d,
           btrim(lower(translate(coalesce(p_barrio,''), 'áéíóúüñÁÉÍÓÚÜÑ', 'aeiouunAEIOUUN'))) as b
  ), c as (
    select d, b,
           case when d is not null and position(',' in d) > 0
                then btrim(split_part(d, ',', array_length(string_to_array(d, ','), 1))) end as cola_coma,
           -- v15.64: " - <localidad>" después de la altura (la página). Sólo si antes del guion hay un número.
           btrim((regexp_match(d, '^(.*\d[0-9a-z/]*)\s+-\s+([^-]+)$', 'i'))[1]) as sin_guion,
           btrim((regexp_match(d, '^(.*\d[0-9a-z/]*)\s+-\s+([^-]+)$', 'i'))[2]) as cola_guion
    from n
  ), p as (
    select d, b, cola_coma, sin_guion, cola_guion,
           btrim(lower(translate(coalesce(cola_coma,''),  'áéíóúüñÁÉÍÓÚÜÑ', 'aeiouunAEIOUUN'))) as coma_plana,
           btrim(lower(translate(coalesce(cola_guion,''), 'áéíóúüñÁÉÍÓÚÜÑ', 'aeiouunAEIOUUN'))) as guion_plana
    from c
  )
  select case
    when d is null or b = '' then d
    when cola_guion is not null and length(guion_plana) >= 3
         and (guion_plana in (b, 'la ' || b, ltrim(b, 'la '))
              or b like guion_plana || '%' or ('la ' || b) like guion_plana || '%'
              or guion_plana like b || '%')
      then sin_guion
    when cola_coma is not null
         and (coma_plana in (b, 'la ' || b, ltrim(b, 'la ')) or b in (coma_plana, 'la ' || coma_plana))
      then btrim(btrim(left(d, length(d) - length(cola_coma) - 1)), ',')
    else d end
  from p;
$function$;

comment on function public.gv_dir_geo_normalizar(text, text) is
  'v15.64 — limpia la direccion para geocodificar: barrio repetido despues de una coma (v14.28) y sufijo " - <localidad>" que pega la pagina despues de la altura, aunque venga truncado. No cambia dir_key.';

-- PRUEBA (tiene que dar ok=true en las 12 filas):
-- select dir, barrio, gv_dir_geo_normalizar(gv_dir_geo_query(dir), barrio) res, esperado,
--        gv_dir_geo_normalizar(gv_dir_geo_query(dir), barrio) is not distinct from esperado ok
-- from (values
--   ('Caamaño 1315 - Villa Rosa','Villa Rosa','Caamaño 1315'), ('Donofrio 20 - Ciudadela','Ciudadela','Donofrio 20'),
--   ('Julio Godoy 4656 - Villa Lynch','Villa Lynch','Julio Godoy 4656'), ('Pacífic Rodri 6137 - Villa Bal','Villa Ballester','Pacífic Rodri 6137'),
--   ('Ayacucho 56 - San Antonio de P','San Antonio de Padua','Ayacucho 56'), ('Panamericana 54,5 - Pilar','Pilar','Panamericana 54,5'),
--   ('Triunvirato Av. 5463-V. Urquiza','Villa Urquiza','Triunvirato Av. 5463-V. Urquiza'),   -- sin espacios alrededor del guion: no se toca
--   ('Pinedo 50 - Galpon 3','Barracas','Pinedo 50'),                                          -- la v14.26 ya saca la cola de depósito
--   ('Artigas Jose G. 4927','Villa Lugano','Artigas Jose G. 4927'), ('Avalos 188, Paternal','Paternal','Avalos 188'),
--   ('Av. Suarez Y Pinedo - Barracas','Barracas','Av. Suarez Y Pinedo - Barracas'),          -- sin número antes del guion: no se toca
--   ('Rivadavia 969','Lujan','Rivadavia 969')
-- ) t(dir, barrio, esperado);
