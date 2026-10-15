-- v31.15 (Luis, 15/10, D4): registrar_baja_racks rechaza una bajada SIN posición (dejaba negativo «sin posición» en el Mapa).
-- Se aplicó ENCIMA de la definición viva, antes del guard v31.12-no-es-rack. Marcador v31.15-sin-posicion, centinela 494.
-- El único front que mandaba sector null era la bajada por orden (showBajarRacks), que se sacó en la misma versión.
do $do$
declare d text := pg_get_functiondef('public.registrar_baja_racks(jsonb)'::regprocedure);
 a text := E' if v_sec is not null and v_ubic is null then\n';
 b text := E' -- v31.15-sin-posicion (Luis, 15/10, D4): sin posicion tampoco se graba (dejaba negativo «sin posicion» en el Mapa)\n if v_sec is null then\n  raise exception ''RACKS_SIN_POSICION_BAJA: % sin posicion de rack. Deci de que rack bajas. No se grabo nada.'', v_cod using errcode = ''23514'';\n end if;\n if v_sec is not null and v_ubic is null then\n';
begin
 if position('v31.15-sin-posicion' in d) > 0 then return; end if;
 if (length(d) - length(replace(d, a, ''))) / length(a) <> 1 then raise exception 'ancla no unica'; end if;
 execute replace(d, a, b);
end $do$;
