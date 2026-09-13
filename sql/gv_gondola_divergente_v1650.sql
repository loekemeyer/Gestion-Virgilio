-- v16.50 — Centinela: dónde NO coinciden el mapa de góndola y la capacidad
-- Problema 84, mitad "góndola" (la mitad "duales" se cerró en v16.49).
--
-- Hay dos fuentes que deberían decir lo mismo y no lo dicen:
--   * public."Capacidad_Sector" (736 filas, 669 con cajas_max) → de dónde sale HOY la
--     capacidad de góndola: el máximo de la OC, el ajuste "llenar góndola", el % de ocupación.
--   * public."GV_Lugar_Item" + public."GV_Lugar" (782 filas, cajas_max NULL en las 782) → de
--     dónde sale HOY el mapa que ve el operario (vista gv_lugar_articulo → window.GONDOLA).
--
-- La migración está declarada en index.html ("GV_Lugar / GV_Lugar_Item reemplazan a
-- Planimetria + Capacidad_Sector") pero quedó a medias: la tabla nueva no tiene ni una
-- capacidad cargada, así que conviven el mapa nuevo y la capacidad vieja.
--
-- ⚠ La medición vieja del problema 84 decía 204 divergencias. Estaba mal: de las "125 solo
-- en la nueva", 97 son racks (GV_Lugar.tipo = 'rack'), que Capacidad_Sector no tiene por
-- diseño. Mirando sólo tipo = 'gondola', la divergencia real es 107.
--
-- Uso:  select * from public.gv_gondola_divergente;   -- vacía = todo bien
--
-- NO toca ningún dato: cuál de los dos mapas manda es de quien cargó la góndola.

create or replace view public.gv_gondola_divergente with (security_invoker = true) as
with cs as (
  select public.gv_cod_stock(cod) as cod, upper(btrim(sector)) as sector,
         max(cajas_max) as cajas_max
    from public."Capacidad_Sector"
   group by 1,2
), gl as (
  select public.gv_cod_stock(i.cod) as cod, upper(btrim(i.sector)) as sector
    from public."GV_Lugar_Item" i
    join public."GV_Lugar" l on upper(btrim(l.sector)) = upper(btrim(i.sector))
   where l.tipo = 'gondola'
   group by 1,2
)
select 'solo_capacidad'::text as motivo, cs.cod, cs.sector, cs.cajas_max,
       'la capacidad cuenta esta celda pero el mapa (GV_Lugar_Item) no pone el artículo ahí'::text as que_pasa
  from cs where not exists (select 1 from gl where gl.cod = cs.cod and gl.sector = cs.sector)
    and exists (select 1 from public."GV_Lugar" l where upper(btrim(l.sector)) = cs.sector)
union all
select 'solo_mapa', gl.cod, gl.sector, null,
       'el mapa muestra el artículo en esta celda pero no tiene capacidad cargada (Capacidad_Sector)'
  from gl where not exists (select 1 from cs where cs.cod = gl.cod and cs.sector = gl.sector)
union all
select 'sector_inexistente', cs.cod, cs.sector, cs.cajas_max,
       'la capacidad apunta a un sector que no existe en GV_Lugar'
  from cs where not exists (select 1 from public."GV_Lugar" l where upper(btrim(l.sector)) = cs.sector);

grant select on public.gv_gondola_divergente to anon, authenticated;

-- Estado al 2026-09-13:
--   solo_capacidad      70
--   solo_mapa           28
--   sector_inexistente   9
--   → 40 códigos afectados, 832 cajas de capacidad fantasma, 26 códigos en el mapa sin
--     capacidad (21 con stock real).
