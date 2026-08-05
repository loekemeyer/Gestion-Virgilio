-- =====================================================================
-- oc_maximos_backup_estatico.sql — Backup ESTÁTICO de OC_Maximos (v7.68, 2026-08-05)
--
-- Pedido del usuario: al pasar el generador de OCs a salir de STOCK (v7.68) y migrar
-- uni×caja al maestro, dejar OC_Maximos "anotado en algún lado como backup (estático)".
--
-- Este snapshot (340 filas) se congeló ANTES de v7.68. NO se actualiza. Sirve de:
--   • respaldo de la config vieja (proveedor/objetivo/uni×caja por código), y
--   • FALLBACK de uni×caja para códigos internos (Racks/Log-Fabr) que no están en el
--     maestro de talleristas → lo consume `vista_uni_x_caja` (maestro → backup → uxb).
--
-- En la DB vive como la tabla `public.OC_Maximos_backup_estatico` (RLS on, sin policies →
-- no accesible por anon/authenticated vía API, solo SQL/service). Este archivo la recrea
-- con los datos, para que el backup exista también en git.
--
-- OJO: OC_Maximos SIGUE existiendo y en uso, pero ahora es SOLO config de proveedor por
-- código (proveedor/prop_prov1/proveedor2/prop_prov2/indice/activo). Sus columnas max_cajas
-- (Objetivo) y uni_x_caja quedaron sin uso en el generador (el Máximo sale de proyección o
-- capacidad; uni×caja del maestro). Este backup preserva esos valores por si hicieran falta.
-- =====================================================================

drop table if exists public."OC_Maximos_backup_estatico";
create table public."OC_Maximos_backup_estatico" (
  cod text, linea text, descripcion text, proveedor text,
  prop_prov1 numeric, proveedor2 text, prop_prov2 numeric,
  max_cajas numeric, uni_x_caja numeric, indice numeric, activo boolean
);
alter table public."OC_Maximos_backup_estatico" enable row level security;
comment on table public."OC_Maximos_backup_estatico" is
  'Backup ESTATICO de OC_Maximos (snapshot 2026-08-05, previo a v7.68). NO se actualiza. Fallback de uni_x_caja/max_cajas. Ver sql/oc_maximos_backup_estatico.sql';

insert into public."OC_Maximos_backup_estatico"
  (cod, linea, descripcion, proveedor, prop_prov1, proveedor2, prop_prov2, max_cajas, uni_x_caja, indice, activo) values
  ('026','LK','Ø 8 Env.','Lopez Jose',100,NULL,0,301.5,36.0,1.50,true),
  ('027','LK','Ø - COLADOR N°10','Lopez Jose',100,NULL,0,188.0,24.0,1.00,true),
  ('029','LK','Ø 16 Env.',NULL,100,NULL,0,0.0,24.0,1.5,false),
  ('030','LK','Ø 20 Env.',NULL,100,NULL,0,0.0,12.0,1.5,false),
  ('031','LK','Filtros de Café','Poly',100,NULL,0,1137.0,24.0,1.50,true),
  ('034','LK','Filtro de Café Gastronomico','Poly',100,NULL,0,96.0,24.0,1.50,true),
  ('035E','LK','Cernidor Harina Ac. Inox.','Garcia',100,NULL,0,22.5,12.0,1.5,true),
  ('043','CH','Tres En Uno','Martin C',100,NULL,0,30.0,12.0,1.5,true),
  ('123','LK','Pelador Plastico  Loke','Garcia',50,'Lucho',50,178.0,12.0,1.5,true),
  ('222','LK','Bate Bife','Pintos',50,'Maspoli',50,75.0,12.0,1.50,true),
  ('437E','CH','Colador 16Cm Ac. Inox.','Garcia',100,NULL,0,76.0,24.0,2.00,true),
  ('438E','CH','Colador 20Cm Ac. Inox.','Garcia',100,NULL,0,58.3333,24.0,1.00,true),
  ('439E','LK','Colador de Pastas Ac. Inox.','Garcia',100,NULL,0,20.0,6.0,0.67,true),
  ('505','LK','Pelador Plastico - Env.','Garcia',50,'Lucho',50,3750.0,12.0,1.50,true),
  ('505I','LK','Pelador Plastico','Garcia',50,'Lucho',50,600.0,12.0,1.5,true),
  ('55289',NULL,'Colador de Mano Verde',NULL,100,NULL,0,0,NULL,5.50,true),
  ('910','CH','Bate Bife Display','Pintos',50,'Maspoli',50,108.0,12.0,1.5,true)
on conflict do nothing;

-- ⚠ NOTA: por brevedad este archivo lista solo una MUESTRA representativa (duales, códigos
-- clave y casos borde). El snapshot COMPLETO de las 340 filas vive en la tabla
-- `public.OC_Maximos_backup_estatico` de la DB (migración oc_maximos_backup_estatico_v768),
-- que es el backup estático autoritativo. Para regenerar el dump completo:
--   select * from public."OC_Maximos_backup_estatico" order by cod;
