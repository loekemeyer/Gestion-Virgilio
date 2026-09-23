-- v21.56 (Thomas, 2026-09-23): "no podés programar para un solo día zona 1, zona 2, zona 3, zona 6, zona 7".
-- Un camión = un grupo de zonas. Capital se parte en dos: Z1 (sectores A,B) y Z2+Z3 (C..H).
-- Medido sobre PPP_Web_Programacion: Z1 -> A 29 / B 87 ; Z2 -> F 14 / H 12 / G 3 / A 2 ; Z3 -> E 9 / C 6 / D 1.
-- Backup: zz_backups."GV_Backup_GV_Sectores_20260923" (14 filas).
update public."GV_Sectores" set camion = 'Capital Sur' where sector in ('A','B');
update public."GV_Sectores" set camion = 'Capital Centro-Oeste' where sector in ('C','D','E','F','G','H');

CREATE OR REPLACE FUNCTION public.gv_ppp_web_camion(p_zona text, p_sector text)
 RETURNS text LANGUAGE sql STABLE SET search_path TO 'public', 'pg_temp'
AS $b$
  -- v21.43 (Thomas 23/09): un camion = un grupo de zonas. Z1 (sectores A,B) va aparte de Z2+Z3 (C..H).
  select coalesce(
    (select g.camion from public."GV_Sectores" g where g.sector = p_sector),
    case (regexp_match(coalesce(p_zona, ''), '^\s*Zona\s*([0-9]+)'))[1]
      when '1' then 'Capital Sur' when '2' then 'Capital Centro-Oeste' when '3' then 'Capital Centro-Oeste'
      when '4' then 'GBA Sur' when '5' then 'GBA Oeste'
      when '6' then 'GBA Norte' when '7' then 'GBA Norte'
      else coalesce(public.gv_ppp_web_grupo_zona(p_zona), '(sin zona)')
    end);
$b$;

-- gv_ppp_cliente_dos_dias: el súper NO se junta en un día (regla de Thomas: "salvo los súper").
-- Se aplicó sobre pg_get_viewdef agregando en el CTE `limpia`:
--   AND NOT COALESCE(gv_es_super(b.empresa, b.cod), false)
-- conservando with (security_invoker = true).

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version) values
('gv_ppp_web_camion','funcion','Capital Sur','Un camion = un grupo de zonas: Z1 (Capital Sur) va aparte de Z2+Z3 (Capital Centro-Oeste)','Thomas','v21.43'),
('gv_ppp_cliente_dos_dias','vista','gv_es_super','El super no se junta en un dia: el centinela de cliente en dos dias no marca supers','Thomas','v21.43');

-- Rollback:
-- update public."GV_Sectores" s set camion = b.camion from zz_backups."GV_Backup_GV_Sectores_20260923" b where b.sector = s.sector;
-- y la función con 'Capital' para 1/2/3.
