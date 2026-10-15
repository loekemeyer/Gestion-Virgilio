-- v31.12 (Luis, 15/10, D2): registrar_baja_racks rechaza una posición que el Mapa no conoce como rack.
-- Caso 438E 14/10: «F15» (la góndola) se grabó sin posición → −54 en el Mapa y AD11 inflado.
-- Se aplicó ENCIMA de la definición viva (inserta el bloque después del guard RACKS_FALTA_PARTE).
-- Marcador: v31.12-no-es-rack · centinela 493 (patrón RACKS_NO_ES_RACK).
-- Rollback: el mismo replace al revés (sacar el bloque «v31.12-no-es-rack»).
do $do$
declare d text := pg_get_functiondef('public.registrar_baja_racks(jsonb)'::regprocedure);
 a text := E'using errcode = ''23514'';\n end if;\n v_ref := coalesce(';
 b text := E'using errcode = ''23514'';\n end if;\n -- v31.12-no-es-rack (Luis, 15/10, D2): una posicion que el Mapa no conoce como rack (F15 = gondola) no se graba\n if v_sec is not null and v_ubic is null then\n  raise exception ''RACKS_NO_ES_RACK: «%» no es una posicion de rack (¿es la gondola?). Deci de que rack bajas. No se grabo nada.'', v_sec using errcode = ''23514'';\n end if;\n v_ref := coalesce(';
begin
 if position('v31.12-no-es-rack' in d) > 0 then return; end if;
 if (length(d) - length(replace(d, a, ''))) / length(a) <> 1 then raise exception 'ancla no unica'; end if;
 execute replace(d, a, b);
end $do$;
