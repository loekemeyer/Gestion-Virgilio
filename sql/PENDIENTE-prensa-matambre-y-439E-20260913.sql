-- ============================================================================
-- PENDIENTE DE EJECUTAR — espera el "dale" de Thomas. NADA de esto se corrió.
-- v16.72 · 2026-09-13 · (a) Prensa Matambre: 246 y 55219 se llaman igual · (b) 439E: Chef no tiene
-- lugar de góndola (problema 88, abierto).
--
-- QUÉ LEE CADA TABLA QUE SE TOCA:
--   "Articulos x Prov AT"  → ES LA FUENTE de `vista_articulos_prov_at` (DISTINCT ON (Cod_Art, Proveedor)
--       sobre esa tabla con Activo = true; la `linea` la trae por LATERAL de "Articulos Virgilio X
--       Tallerista"). La vista devuelve proveedor, cod_art, descripcion, linea — la descripción sale
--       de "Articulos x Prov AT".Descripcion, de ninguna otra tabla. RLS con políticas abiertas.
--   OC_Maximos             → `vista_generador_oc` (1ª fuente de nombre) y el editor ⚙ del generador.
--   "Articulos Virgilio X Tallerista" → tabla MADRE de Cervantes (CLAUDE.md: cadena de talleristas;
--       trigger reconstruye "Partes x Tallerista"). Acá sólo se le cambia el texto `Desc`, no el
--       Cod_Art ni el Tallerista — el trigger recalcula la derivada con el mismo dato. Opcional.
--   Capacidad_Sector       → tabla madre de capacidades (cap del generador, vista_ocupacion…).
--       UNIQUE (sector, cod). `empresa` en uso: LK 477, CH 197, LOKE 58, lk 4.
--   GV_Lugar_Item          → `gv_lugar_articulo` (lugares del picking por artículo), `gv_ocupacion_lugar`,
--       `gv_gondola_divergente`. PK (sector, cod, clase); FK sector → GV_Lugar(sector).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- (0) BACKUP
-- ---------------------------------------------------------------------------
create table zz_backups."GV_Backup_prensa_439E_20260913" as
  select 'Articulos x Prov AT' tabla, id::text clave, "Cod_Art" cod, "Descripcion" texto, "Proveedor" extra, "N_Caja"::text n
    from public."Articulos x Prov AT" where upper(btrim("Cod_Art")) in ('246','55219')
  union all
  select 'Articulos Virgilio X Tallerista', id::text, "Cod_Art", "Desc", "Tallerista", "Uni_x_Caja"::text
    from public."Articulos Virgilio X Tallerista" where upper(btrim("Cod_Art")) in ('246','55219')
  union all
  select 'OC_Maximos', cod || '|' || linea, cod, descripcion, proveedor, max_cajas::text
    from public."OC_Maximos" where upper(btrim(cod)) in ('246','55219','439E')
  union all
  select 'Capacidad_Sector', id::text, cod, sector, empresa, cajas_max::text
    from public."Capacidad_Sector" where upper(btrim(cod)) = '439E'
  union all
  select 'GV_Lugar_Item', sector || '|' || cod || '|' || clase, cod, sector, unidad, cajas_max::text
    from public."GV_Lugar_Item" where upper(btrim(cod)) = '439E';
alter table zz_backups."GV_Backup_prensa_439E_20260913" enable row level security;
revoke insert, update, delete, truncate on zz_backups."GV_Backup_prensa_439E_20260913" from anon, authenticated;

-- ---------------------------------------------------------------------------
-- (a) PRENSA MATAMBRE: 246 vs 55219
--     Medido el 13/09:
--       Articulos_Cajas:   246 "PRENSA MATAMBRE", LK, N_Caja 10, Uni_x_Caja 6 · 55219 SIN FILA (sin N° de caja)
--       OC_Maximos:        246 "Prensa Matambre" LK Maspoli max 30 · 55219 "Prensa Matambre" LK Maspoli max 0
--       Articulos x Prov AT: id 10 246/Maspoli "Prensa Matambre" N_Caja 2 · id 58 246/Cabral
--                          "Prensa Matambre          " (con 10 espacios) N_Caja 6 · id 108 55219/Maspoli
--                          "Prensa Matambre" N_Caja 10
--       Articulos Virgilio X Tallerista: id 152 246 Maspoli "Prensa Matambre          " · id 633 55219 Maspoli
--       GV_UxB: 246 LK 6 (curado, "PRENSA MATAMBRE") · 55219 LK 6 (descripción NULL)
--       vista_generador_oc: 55219 stock 72, pedidos 333,33, máximo 0, total 262 — ⚠ 333 cajas pedidas
--                          en NPs pendientes contra 72 de stock: revisar aparte si `gv_demanda_pedidos`
--                          está contando unidades como cajas para este código.
--     ⚠ Los N° de caja NO coinciden entre tablas: el prompt tenía "246 caja 10 / 55219 sin caja"
--       (Articulos_Cajas) y "Articulos x Prov AT" dice 246 → 2 (Maspoli) / 6 (Cabral) y 55219 → 10.
--       Cuál es el bueno lo sabe Thomas; acá no se toca ningún N_Caja.
--
--     ELECCIÓN: no se puede diferenciar por N° de caja (55219 no tiene fila en Articulos_Cajas), así que
--     la salida limpia es que el NOMBRE los distinga en la fuente que alimenta la vista
--     ("Articulos x Prov AT") y en las otras dos tablas que muestran el nombre (OC_Maximos, y la madre
--     de Cervantes). Como no sé QUÉ los diferencia (¿tamaño? ¿modelo? ¿proveedor?), el texto queda con
--     un marcador que Thomas reemplaza; si no dice nada, el mínimo útil es agregar el código.
-- ---------------------------------------------------------------------------
-- <DESC_55219> = por ejemplo 'Prensa Matambre Chica' / 'Prensa Matambre 55219' — lo define Thomas
update public."Articulos x Prov AT" set "Descripcion" = '<DESC_55219>' where id = 108;                 -- 55219 Maspoli
update public."OC_Maximos"          set descripcion   = '<DESC_55219>' where cod = '55219' and linea = 'LK';
update public."Articulos Virgilio X Tallerista" set "Desc" = '<DESC_55219>' where id = 633;             -- opcional (madre)
-- y de paso los 10 espacios colgados del 246 (Cabral) y de la madre, que hacen que el mismo 246 se vea
-- como dos nombres distintos en la vista:
update public."Articulos x Prov AT" set "Descripcion" = btrim("Descripcion") where id = 58;
update public."Articulos Virgilio X Tallerista" set "Desc" = btrim("Desc") where id = 152;

-- verificación
select * from public.vista_articulos_prov_at where upper(btrim(cod_art)) in ('246','55219') order by cod_art, proveedor;
select cod, linea, descripcion from public."OC_Maximos" where upper(btrim(cod)) in ('246','55219');

-- ---------------------------------------------------------------------------
-- (b) 439E EN CHEF: hoy no tiene lugar
--     Medido: saldos CH 8 en góndola + 8 a facturar, LK 16. `gv_lugar_articulo('439E')` devuelve sólo
--     lugares LK (H33, H34, Ñ54). Capacidad_Sector 439E: H33 15 LK · H34 15 LK · Ñ53 18 LOKE · Ñ54 18
--     LOKE = 66 por LK, 0 por CH. GV_Lugar_Item 439E: H33, H34, Ñ54 (clase articulo, cajas_max null).
--     OC_Maximos 439E: sólo linea LK (Garcia, max 20). Problema 88 abierto.
--     El sector de Chef lo sabe la chica del depósito: NO se adivina. Góndolas CH en GV_Lugar:
--     L01–L60, M01–M60, P01–P40, Ñ56–Ñ59 (tipo gondola, empresa CH). <SECTOR_CHEF> tiene que ser una
--     de ésas (la FK de GV_Lugar_Item lo exige) y <CAJAS_MAX> lo que entra en esa góndola.
-- ---------------------------------------------------------------------------
-- 0. el sector existe y es de Chef
select sector, tipo, empresa, activo from public."GV_Lugar" where sector = '<SECTOR_CHEF>';        -- 1 fila, gondola, CH

insert into public."Capacidad_Sector" (sector, cod, cajas_max, empresa)
values ('<SECTOR_CHEF>', '439E', <CAJAS_MAX>, 'CH')
on conflict (sector, cod) do update set cajas_max = excluded.cajas_max, empresa = 'CH';

insert into public."GV_Lugar_Item" (sector, cod, clase, cajas_max, unidad, activo, notas)
values ('<SECTOR_CHEF>', '439E', 'articulo', <CAJAS_MAX>, null, true, 'v16.72: góndola de Chef para el 439E (problema 88)')   -- unidad: las 782 filas la tienen null
on conflict (sector, cod, clase) do update set cajas_max = excluded.cajas_max, activo = true, notas = excluded.notas, updated_at = now();

-- ¿y la OC? OC_Maximos tiene PK (cod, linea) y 439E sólo está en LK. Si Chef compra su 439E aparte,
-- hace falta la fila CH (a definir por Thomas; NO se inserta acá):
-- insert into public."OC_Maximos" (cod, descripcion, linea, max_cajas, proveedor, uni_x_caja, activo, indice, prop_prov1)
-- values ('439E', 'Colador de Pastas Ac. Inox.', 'CH', <MAX_CH>, 'Garcia', 6, true, 1.5, 100);

-- verificación
select * from public.gv_lugar_articulo where cod = '439E';                                -- aparece <SECTOR_CHEF>
select sector, cod, cajas_max, empresa from public."Capacidad_Sector" where upper(btrim(cod)) = '439E' order by sector;
select * from public.gv_gondola_divergente where cod = '439E';

-- ---------------------------------------------------------------------------
-- ROLLBACK
-- ---------------------------------------------------------------------------
-- update public."Articulos x Prov AT" a set "Descripcion" = b.texto from zz_backups."GV_Backup_prensa_439E_20260913" b where b.tabla = 'Articulos x Prov AT' and a.id = b.clave::bigint;
-- update public."Articulos Virgilio X Tallerista" a set "Desc" = b.texto from zz_backups."GV_Backup_prensa_439E_20260913" b where b.tabla = 'Articulos Virgilio X Tallerista' and a.id = b.clave::bigint;
-- update public."OC_Maximos" o set descripcion = b.texto from zz_backups."GV_Backup_prensa_439E_20260913" b where b.tabla = 'OC_Maximos' and o.cod || '|' || o.linea = b.clave;
-- delete from public."Capacidad_Sector" where sector = '<SECTOR_CHEF>' and cod = '439E';
-- delete from public."GV_Lugar_Item" where sector = '<SECTOR_CHEF>' and cod = '439E' and clase = 'articulo';
