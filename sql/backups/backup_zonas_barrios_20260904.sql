-- ============================================================================
-- BACKUP de public."Zonas_Barrios" — 2026-09-04, ANTES del alta de la lista canónica
-- ============================================================================
-- Estado: 87 filas. Tomado justo antes de correr el INSERT-only de
-- `sql/zonas_barrios_dic_canonico_20260904.sql` (v12.76).
--
-- RESTORE: `delete from public."Zonas_Barrios";` y después estos inserts.
-- ROLLBACK SÓLO DEL ALTA (más seguro, no toca lo que había):
--   delete from public."Zonas_Barrios" where creado::date = '2026-09-04';
-- ============================================================================

insert into public."Zonas_Barrios" (barrio_norm, zona) values ('adrogue','Zona 4 - GBA Sur');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('almagro','Zona 2 - CABA Centro');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('avellaneda','Zona 4 - GBA Sur');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('balvanera','Zona 2 - CABA Centro');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('barracas','Zona 1 - CABA Sur');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('belgrano','Zona 2 - CABA Centro');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('bella vista','Zona 6 - GBA Norte');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('berazategui','Zona 4 - GBA Sur');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('bernal','Zona 4 - GBA Sur');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('boedo','Zona 2 - CABA Centro');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('burzaco','Zona 4 - GBA Sur');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('caballito','Zona 2 - CABA Centro');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('caseros','Zona 5 - GBA Oeste');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('castelar','Zona 5 - GBA Oeste');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('chilavert','Zona 6 - GBA Norte');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('ciudadela','Zona 5 - GBA Oeste');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('colegiales','Zona 2 - CABA Centro');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('constitucion','Zona 1 - CABA Sur');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('devoto','Zona 2 - CABA Centro');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('esteban echeverria','Super');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('f.varela','Zona 4 - GBA Sur');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('flores','Zona 3 - CABA Oeste');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('gregorio de laferrere','Zona 5 - GBA Oeste');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('guernica','Zona 4 - GBA Sur');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('hurlingham','Zona 5 - GBA Oeste');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('ituzaingo','Zona 5 - GBA Oeste');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('jose c paz','Zona 6 - GBA Norte');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('jose leon suarez','Zona 6 - GBA Norte');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('la boca','Zona 1 - CABA Sur');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('lanus','Zona 4 - GBA Sur');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('lomas de zamora','Zona 4 - GBA Sur');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('longchamps','Zona 4 - GBA Sur');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('lugano','Zona 1 - CABA Sur');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('lujan','Zona 5 - GBA Oeste');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('martinez','Zona 6 - GBA Norte');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('mataderos','Zona 3 - CABA Oeste');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('mercado central','Zona 5 - GBA Oeste');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('merlo','Zona 5 - GBA Oeste');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('micro centro','Zona 2 - CABA Centro');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('monte grande','Zona 4 - GBA Sur');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('moreno','Zona 5 - GBA Oeste');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('moron','Zona 5 - GBA Oeste');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('muñiz','Zona 6 - GBA Norte');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('munro','Zona 6 - GBA Norte');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('nueva pompeya','Zona 1 - CABA Sur');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('olivos','Zona 7 - GBA Norte Lejos');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('once','Zona 2 - CABA Centro');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('p.patricios','Zona 1 - CABA Sur');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('palermo','Zona 2 - CABA Centro');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('parque avellaneda','Zona 1 - CABA Sur');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('parque chacabuco','Zona 3 - CABA Oeste');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('parque patricios','Zona 1 - CABA Sur');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('paternal','Zona 3 - CABA Oeste');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('pilar','Zona 7 - GBA Norte Lejos');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('pompeya','Zona 1 - CABA Sur');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('quilmes','Zona 4 - GBA Sur');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('quilmes oeste','Zona 4 - GBA Sur');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('rafael calzada','Zona 4 - GBA Sur');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('ramos mejia','Zona 5 - GBA Oeste');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('recoleta','Zona 2 - CABA Centro');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('remedios de escalada','Zona 4 - GBA Sur');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('retira','Retira');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('retiro','Zona 2 - CABA Centro');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('san cristobal','Zona 2 - CABA Centro');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('san justo','Zona 5 - GBA Oeste');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('san martin','Zona 6 - GBA Norte');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('san miguel','Zona 6 - GBA Norte');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('santa cruz de la sierra','Expo');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('soldati','Zona 1 - CABA Sur');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('temperley','Zona 4 - GBA Sur');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('tigre','Zona 7 - GBA Norte Lejos');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('tortuguita','Super');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('v.alsina','Zona 4 - GBA Sur');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('v.bosch','Zona 5 - GBA Oeste');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('v.devoto','Zona 3 - CABA Oeste');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('vicente lopez','Zona 7 - GBA Norte Lejos');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('villa ballester','Zona 6 - GBA Norte');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('villa bosch','Zona 6 - GBA Norte');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('villa crespo','Zona 2 - CABA Centro');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('villa devoto','Zona 2 - CABA Centro');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('villa lugano','Zona 1 - CABA Sur');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('villa luro','Zona 3 - CABA Oeste');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('villa ortuzar','Zona 2 - CABA Centro');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('villa pueyrredon','Zona 2 - CABA Centro');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('villa sarmiento','Zona 5 - GBA Oeste');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('villa soldati','Zona 1 - CABA Sur');
insert into public."Zonas_Barrios" (barrio_norm, zona) values ('villa urquiza','Zona 2 - CABA Centro');
