-- ============================================================================
-- [35] DICCIONARIO barrio→zona + config — correr en VIRGILIO (hrxfctzncixxqmpfhskv)
-- ----------------------------------------------------------------------------
-- Faltaba en el volcado original de la rama `claude/pipeline-estructura-supabase-1haka4`
-- (§5 del HANDOFF lo marcaba como pendiente). Se reconstruyó leyendo la base viva
-- el 2026-09-04: 113 filas en `pipeline.barrio_zona`, 1 en `pipeline.config`.
--
-- ⚠ ESTE NO ES EL DICCIONARIO PRODUCTIVO. El que usa la app es
--   `public."Zonas_Barrios"` (87 filas, con auto-aprendizaje vía `trg_ppp_autozona`
--   y alta manual vía la RPC `zona_barrio_set`). Éste es la lista canónica que
--   pasó el dueño, importada en el esquema aislado durante aquella sesión.
--   La comparación de los dos y el merge propuesto están en
--   `sql/zonas_barrios_dic_canonico_20260904.sql` — SIN EJECUTAR.
--
-- ⚠ TIENE AL MENOS UN ERROR CONOCIDO: `burzaco → Zona 2 - CABA Centro`.
--   Burzaco es GBA Sur, y `Zonas_Barrios` ya lo tiene bien (Zona 4). No copiar
--   esta tabla encima de la productiva sin revisar fila por fila.
--
-- La clave es `barrio_norm`, ya normalizada con `public._norm_barrio`.
-- ============================================================================

create table if not exists pipeline.barrio_zona (
  barrio_norm text primary key,
  zona        text not null
);

insert into pipeline.barrio_zona (barrio_norm, zona) values
  ('santa cruz de la sierra','Expo'),
  ('retira','Retira'),
  ('campo de mayo','Super'),
  ('esteban echeverria','Super'),
  ('tortuguita','Super'),
  ('tortuguitas','Super'),
  ('barracas','Zona 1 - CABA Sur'),
  ('constitucion','Zona 1 - CABA Sur'),
  ('la boca','Zona 1 - CABA Sur'),
  ('lugano','Zona 1 - CABA Sur'),
  ('nueva pompeya','Zona 1 - CABA Sur'),
  ('p. patricios','Zona 1 - CABA Sur'),
  ('p.patricios','Zona 1 - CABA Sur'),
  ('parque avellaneda','Zona 1 - CABA Sur'),
  ('parque patricios','Zona 1 - CABA Sur'),
  ('pompeya','Zona 1 - CABA Sur'),
  ('soldati','Zona 1 - CABA Sur'),
  ('villa lugano','Zona 1 - CABA Sur'),
  ('villa riachuelo','Zona 1 - CABA Sur'),
  ('villa soldati','Zona 1 - CABA Sur'),
  ('almagro','Zona 2 - CABA Centro'),
  ('balvanera','Zona 2 - CABA Centro'),
  ('belgrano','Zona 2 - CABA Centro'),
  ('boedo','Zona 2 - CABA Centro'),
  ('burzaco','Zona 2 - CABA Centro'),   -- ⚠ MAL: Burzaco es GBA Sur (ver header)
  ('caballito','Zona 2 - CABA Centro'),
  ('colegiales','Zona 2 - CABA Centro'),
  ('micro centro','Zona 2 - CABA Centro'),
  ('microcentro','Zona 2 - CABA Centro'),
  ('monserrat','Zona 2 - CABA Centro'),
  ('nuñez','Zona 2 - CABA Centro'),
  ('once','Zona 2 - CABA Centro'),
  ('palermo','Zona 2 - CABA Centro'),
  ('puerto madero','Zona 2 - CABA Centro'),
  ('recoleta','Zona 2 - CABA Centro'),
  ('retiro','Zona 2 - CABA Centro'),
  ('san cristobal','Zona 2 - CABA Centro'),
  ('v.devoto','Zona 2 - CABA Centro'),  -- ⚠ discutido: geográficamente es Oeste (§6.1)
  ('villa crespo','Zona 2 - CABA Centro'),
  ('villa devoto','Zona 2 - CABA Centro'),
  ('villa ortuzar','Zona 2 - CABA Centro'),
  ('villa pueyrredon','Zona 2 - CABA Centro'),
  ('villa urquiza','Zona 2 - CABA Centro'),
  ('flores','Zona 3 - CABA Oeste'),
  ('liniers','Zona 3 - CABA Oeste'),
  ('mataderos','Zona 3 - CABA Oeste'),
  ('mataderos (8:30 a 14)','Zona 3 - CABA Oeste'),
  ('parque chacabuco','Zona 3 - CABA Oeste'),
  ('paternal','Zona 3 - CABA Oeste'),
  ('villa del parque','Zona 3 - CABA Oeste'),
  ('villa general mitre','Zona 3 - CABA Oeste'),
  ('villa luro','Zona 3 - CABA Oeste'),
  ('adrogue','Zona 4 - GBA Sur'),
  ('avellaneda','Zona 4 - GBA Sur'),
  ('banfield','Zona 4 - GBA Sur'),
  ('berazategui','Zona 4 - GBA Sur'),
  ('bernal','Zona 4 - GBA Sur'),
  ('f.varela','Zona 4 - GBA Sur'),
  ('florencio varela','Zona 4 - GBA Sur'),
  ('guernica','Zona 4 - GBA Sur'),
  ('lanus','Zona 4 - GBA Sur'),
  ('lanus este','Zona 4 - GBA Sur'),
  ('lanus oeste','Zona 4 - GBA Sur'),
  ('lomas de zamora','Zona 4 - GBA Sur'),
  ('longchamps','Zona 4 - GBA Sur'),
  ('monte grande','Zona 4 - GBA Sur'),
  ('platanos','Zona 4 - GBA Sur'),
  ('quilmes','Zona 4 - GBA Sur'),
  ('quilmes oeste','Zona 4 - GBA Sur'),
  ('rafael calzada','Zona 4 - GBA Sur'),
  ('remedios de escalada','Zona 4 - GBA Sur'),
  ('temperley','Zona 4 - GBA Sur'),
  ('v.alsina','Zona 4 - GBA Sur'),
  ('valentin alsina','Zona 4 - GBA Sur'),
  ('caseros','Zona 5 - GBA Oeste'),
  ('castelar','Zona 5 - GBA Oeste'),
  ('ciudadela','Zona 5 - GBA Oeste'),
  ('gonzalez catan','Zona 5 - GBA Oeste'),
  ('gregorio de laferrere','Zona 5 - GBA Oeste'),
  ('hurlingham','Zona 5 - GBA Oeste'),
  ('ituzaingo','Zona 5 - GBA Oeste'),
  ('laferrere','Zona 5 - GBA Oeste'),
  ('lujan','Zona 5 - GBA Oeste'),
  ('mercado central','Zona 5 - GBA Oeste'),
  ('merlo','Zona 5 - GBA Oeste'),
  ('moreno','Zona 5 - GBA Oeste'),
  ('moron','Zona 5 - GBA Oeste'),
  ('palomar','Zona 5 - GBA Oeste'),
  ('ramos mejia','Zona 5 - GBA Oeste'),
  ('san antonio de padua','Zona 5 - GBA Oeste'),
  ('san justo','Zona 5 - GBA Oeste'),
  ('villa bosch','Zona 5 - GBA Oeste'),
  ('villa sarmiento','Zona 5 - GBA Oeste'),
  ('bella vista','Zona 6 - GBA Norte'),
  ('chilavert','Zona 6 - GBA Norte'),
  ('jose c paz','Zona 6 - GBA Norte'),
  ('jose c. paz','Zona 6 - GBA Norte'),
  ('jose leon suarez','Zona 6 - GBA Norte'),
  ('martinez','Zona 6 - GBA Norte'),
  ('muñiz','Zona 6 - GBA Norte'),
  ('munro','Zona 6 - GBA Norte'),
  ('san martin','Zona 6 - GBA Norte'),
  ('san miguel','Zona 6 - GBA Norte'),
  ('v. maipu - san martin','Zona 6 - GBA Norte'),
  ('villa adelina','Zona 6 - GBA Norte'),
  ('villa ballester','Zona 6 - GBA Norte'),
  ('villa lynch','Zona 6 - GBA Norte'),
  ('garin','Zona 7 - GBA Norte Lejos'),
  ('olivos','Zona 7 - GBA Norte Lejos'),
  ('pilar','Zona 7 - GBA Norte Lejos'),
  ('san isidro','Zona 7 - GBA Norte Lejos'),
  ('tigre','Zona 7 - GBA Norte Lejos'),
  ('vicente lopez','Zona 7 - GBA Norte Lejos')
on conflict (barrio_norm) do update set zona = excluded.zona;

-- Parámetros de la pipeline. `tanda_m3_max` = tope de m³ para juntar pedidos
-- chicos de zonas distintas en una misma tanda (§4.4 del HANDOFF).
create table if not exists pipeline.config (
  clave text primary key,
  valor numeric not null
);
insert into pipeline.config (clave, valor) values ('tanda_m3_max', 1.0)
on conflict (clave) do update set valor = excluded.valor;

revoke all on all tables in schema pipeline from anon, authenticated;

-- ----------------------------------------------------------------------------
-- `pipeline.calendario_zona` existe en la base y HAY QUE BORRARLA: el calendario
-- día→zona no existe en la realidad, fue un invento de aquella sesión (§3 del
-- HANDOFF). No se dropea acá porque es un cambio de datos y necesita permiso.
--   -- drop table pipeline.calendario_zona;
-- `pipeline.zonas_sucursales` tiene direcciones de clientes → su volcado está en
-- .gitignore (repo público). Además quedó incompleto (cortado en "Lanus").
-- ----------------------------------------------------------------------------

-- Verificación:
-- select zona, count(*) from pipeline.barrio_zona group by 1 order by 1;
