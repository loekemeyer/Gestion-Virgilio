-- v21.92 (Luis, 2026-09-23) — Z2 y Z3 son camiones DISTINTOS.
-- "¿cual seria la logica de tener separadas las zonas Z2 y Z3 si son lo mismo?"
-- Se retira "Capital Centro-Oeste = Z2 + Z3" (v21.43). Para Z2 y Z3 manda la ZONA, no el sector.
-- Lo usan: el armado por grupo (gv_ppp_web_dia_grupo), la fusion de tandas, los centinelas de
-- tanda en dos camiones y el retorno del retenido. El Resumen de la PPP (PPP_RES_CAMIONES en
-- index.html) se ajusto igual. Aplicado en la base el 23/09 (el comentario interno dice v21.91).
CREATE OR REPLACE FUNCTION public.gv_ppp_web_camion(p_zona text, p_sector text)
 RETURNS text LANGUAGE sql STABLE SET search_path TO 'public', 'pg_temp'
AS $b$
  -- v21.43 (Thomas 23/09): un camion = un grupo de zonas. Z1 (sectores A,B) va aparte de Z2+Z3 (C..H).
  -- v21.91 (Luis 23/09): Z2 y Z3 son camiones DISTINTOS ("por algo son zonas diferentes"). Para esas
  --   dos manda la ZONA, no el sector: el sector (C..H) sigue sirviendo para armar la tanda por
  --   cercania, no para decidir el camion.
  select coalesce(
    case (regexp_match(coalesce(p_zona, ''), '^\s*Zona\s*([0-9]+)'))[1]
      when '2' then 'Capital Centro' when '3' then 'Capital Oeste' end,
    (select g.camion from public."GV_Sectores" g where g.sector = p_sector),
    case (regexp_match(coalesce(p_zona, ''), '^\s*Zona\s*([0-9]+)'))[1]
      when '1' then 'Capital Sur'
      when '4' then 'GBA Sur' when '5' then 'GBA Oeste'
      when '6' then 'GBA Norte' when '7' then 'GBA Norte'
      else coalesce(public.gv_ppp_web_grupo_zona(p_zona), '(sin zona)')
    end);
$b$;

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
select 'gv_ppp_web_camion','funcion','Capital Oeste','Z2 y Z3 son camiones distintos: la zona manda sobre el sector para esas dos','Luis','v21.91'
 where not exists (select 1 from public."GV_Reglas_Centinela" where objeto='gv_ppp_web_camion' and patron='Capital Oeste');

-- Rollback: volver a la definicion de sql/gv_camion_un_grupo_zonas_v2156.sql (sin el primer case).
