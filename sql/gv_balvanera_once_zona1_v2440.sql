-- =====================================================================
-- v24.40 — Balvanera y Once pasan a ZONA SUR (Z1)   ·   Luis, 29/09/2026
-- ---------------------------------------------------------------------
-- Luis, textual: "balvanera pasa a ser zona sur" · "z1" · "once tambien".
--
-- ⚠ CAMBIAR LA ZONA SOLA NO ALCANZA. El camion de Z1 lo decide el SECTOR,
--   no la zona: gv_ppp_web_camion resuelve por zona unicamente 2, 3, 6 y 7
--   (v21.43 / v21.91) y para el resto cae a GV_Sectores.camion del sector.
--   Balvanera y Once eran sector F (Capital Centro), asi que con solo el
--   cambio de zona habrian quedado "Zona 1" saliendo en Capital Centro-Oeste.
--   Por eso van los dos: zona -> Z1 y sector F -> A.
--
-- Sector A = Capital Sur-Este (Barracas, Constitucion, La Boca, P. Patricios,
-- San Cristobal, San Telmo). Balvanera linda con San Cristobal; Once esta
-- adentro de Balvanera.
--
-- La zona la resuelve gv_zona_de_barrio, que mira PRIMERO GV_Zonas_Barrios
-- (el override de Gestion) y despues Zonas_Barrios (la tabla base, que sigue
-- diciendo "Zona 2 - CABA Centro" y NO se toca: sobre una tabla compartida se
-- agrega, no se modifica). La pagina manda el BARRIO en zona_expreso
-- ("Balvanera", "Once"), no la zona: por eso el mapeo vive aca y no en LK.
--
-- ⚠ FORWARD-FACING: PPP_Web_Programacion.zona esta GUARDADA, asi que las 13 NP
--   ya programadas siguen en Zona 2 (Bazar y Cia, R Cuarto, Jazquel; tandas
--   F17D 01/10, E97A y F18B 05/10, F11A 11/11). Mismo criterio que la v21.87.
--   Moverlas es otra decision: parte F18B y E97A en dos camiones.
--
-- Medido despues de aplicar:
--   Balvanera/Once (en cualquier grafia) -> Zona 1 - CABA Sur · sector A ·
--   camion Capital Sur. gv_ppp_tanda_camion_mezclado sigue VACIA.
-- =====================================================================

-- backups (hechos antes de escribir)
-- create table zz_backups."GV_Backup_BarriosSector_20260929" as select * from public."GV_Barrios_Sector";  -- 139 filas
-- create table zz_backups."GV_Backup_ZonasBarrios_20260929"  as select * from public."GV_Zonas_Barrios";   -- 11 filas
-- (las dos con RLS prendida y sin escritura para anon/authenticated)

insert into public."GV_Zonas_Barrios" (barrio_norm, zona, motivo, creado)
values ('balvanera','Zona 1 - CABA Sur','Luis 29/09/2026: Balvanera y Once pasan a zona sur',now()),
       ('once',     'Zona 1 - CABA Sur','Luis 29/09/2026: Balvanera y Once pasan a zona sur',now())
on conflict (barrio_norm) do update set zona = excluded.zona, motivo = excluded.motivo;

update public."GV_Barrios_Sector" set sector = 'A' where barrio_norm in ('balvanera','once');

-- verificacion
select b as barrio,
       public.gv_zona_de_barrio(b) zona,
       public.gv_ppp_web_sector(public.gv_zona_de_barrio(b), b, null) sector,
       public.gv_ppp_web_camion(public.gv_zona_de_barrio(b),
            public.gv_ppp_web_sector(public.gv_zona_de_barrio(b), b, null)) camion
  from unnest(array['Balvanera','Once','once','BALVANERA']) b;
-- las 4 -> Zona 1 - CABA Sur · A · Capital Sur

select * from public.gv_ppp_tanda_camion_mezclado;   -- vacia = todo bien

-- ROLLBACK
-- delete from public."GV_Zonas_Barrios" where barrio_norm in ('balvanera','once');
-- update public."GV_Barrios_Sector" set sector = 'F' where barrio_norm in ('balvanera','once');
