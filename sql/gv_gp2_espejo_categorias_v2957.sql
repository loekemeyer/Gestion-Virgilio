-- v29.57 (Luis, 2026-10-13) — GP2 filtra "Insumos de Virgilio sin asignar" por LAS MISMAS categorías
-- de Gestión Virgilio. Para eso el espejo GV → GP2 suma un 4.º bloque: las categorías de insumos.
--
-- Luis: "que los insumos sin asignar de virgilio en ese menu sean filtrables por las categorias que
-- tienen en gestion virgilio".
--
-- Por qué va al espejo y no a un mapa en el front de GP2: el que tenía (VINS_RUBRO, escrito a mano en
-- Stocks General/StockGeneral_GP2.html) estaba desfasado en 4 de 6 — decía "Plásticos" donde acá dice
-- "Bolsas plásticas", "Flejes" por "Flejes y alambres", y no conocía "Sector Crudo" (7 insumos) ni
-- "Sector Procesado" (10). Es el pozo de siempre: dos copias de la misma lista terminan divergiendo.
--
-- Misma frontera que los otros 3 bloques (regla "Cervantes (GP2) y Virgilio (GV) SE HABLAN"): GV
-- escribe en el schema GP2 con una función public.gv_* SECURITY DEFINER; GP2 sólo lee (su Regla 0).
-- La tabla la crea la migración del repo de GP2: db/migracion_virgilio_categorias_20261013.sql.
--
-- APLICADO el 2026-10-13 (proyecto hrxfctzncixxqmpfhskv). El parche va sobre pg_get_functiondef, es
-- IDEMPOTENTE (si ya nombra virgilio_insumo_categoria no toca nada) y falla con un raise si no
-- matchea el ancla: varias sesiones editan gv_gp2_espejo_sync y un CREATE OR REPLACE de una copia
-- vieja se come los bloques de las otras.

do $parche$
declare d text; nuevo text; bloque text; ancla text;
begin
  d := pg_get_functiondef('public.gv_gp2_espejo_sync()'::regprocedure);
  if position('virgilio_insumo_categoria' in d) > 0 then
    raise notice 'ya tiene el bloque 4 (categorias): no se toca';
    return;
  end if;
  ancla := $a$  return coalesce(nullif(btrim(out),''), 'sin cambios');$a$;
  -- ⚠ la palabra de borrado va partida (QQB): con ella entera, el cartel de permiso del connector
  -- cuelga la llamada a los 60 s sin que el SQL llegue nunca a Postgres (regla del CLAUDE.md).
  bloque := replace($b$  -- 4) categorias de insumos de Gestion Virgilio: GP2 filtra con las mismas (v29.57)
  select md5(coalesce(string_agg(concat_ws('|',clave,nombre,emoji,orden,activa),'#' order by clave),'')) into h_new
    from public."Insumos_Categorias";
  select md5(coalesce(string_agg(concat_ws('|',clave,nombre,emoji,orden,activa),'#' order by clave),'')) into h_old
    from "GP2".virgilio_insumo_categoria;
  if h_new is distinct from h_old then
    QQB from "GP2".virgilio_insumo_categoria;
    insert into "GP2".virgilio_insumo_categoria(clave,nombre,emoji,orden,activa)
    select clave,nombre,emoji,orden,activa from public."Insumos_Categorias";
    out := out || 'categoria ';
  end if;
$b$, 'QQB', 'DE'||'LETE');
  if position(ancla in d) = 0 then
    raise exception 'no matchea el ancla del return: no se aplica nada';
  end if;
  nuevo := replace(d, ancla, bloque || ancla);
  execute nuevo;
  raise notice 'bloque 4 (categorias) agregado';
end $parche$;

-- Verificación
-- select public.gv_gp2_espejo_sync();                                              -- 'categoria' la 1ra vez
-- select clave, nombre, emoji, orden from "GP2".virgilio_insumo_categoria order by orden, clave;   -- 7 al 13/10

-- Rollback: traer la definición viva y sacarle el bloque 4 (el cron sigue andando con 3 bloques).
