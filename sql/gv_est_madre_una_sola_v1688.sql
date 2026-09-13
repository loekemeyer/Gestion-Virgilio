-- =====================================================================================
-- UNA SOLA "EST MADRE" (v16.88, 2026-09-13)
-- Dueno: "Que quede una sola y que todos los repos que las miren miren esa."
--
-- ESTADO ANTES: cinco copias en dos proyectos.
--   LK      fn_proyeccion_madre() / fn_proyeccion_oc_virgilio()  <- EL MOTOR
--   LK      estadistica_madre_cache (537, con descripcion) y estadistica_madre (vista)
--   Virgilio  proyeccion_madre (410)   <- lo que LK empuja
--   Virgilio  GP2.est_madre (404)      <- copia de GP2, legitima (Regla 0)
--   Virgilio  "E. Madre LK" (290, congelada el 24/08) y "E. Madre CH" (302, 12/03)
--
-- ⚠ Y AL TOCARLO APARECIERON DOS COSAS ROTAS, LAS DOS POR EL RENOMBRE DE `uxb` DEL 12/09:
--   1. La foreign table virgilio.proyeccion_madre (FDW en LK) declaraba `uxb` SIN
--      options column_name, y en Virgilio la columna pasó a llamarse uxb_obsoleto_v1629.
--      `select uxb from virgilio.proyeccion_madre` daba ERROR 42703. El count(*) andaba
--      porque no toca la columna: por eso nadie lo vio.
--   2. El trigger GP2.fn_est_madre_sync() leia NEW.uxb, que ya no existe.
--   El cron sync-proyeccion-madre-virgilio corre los MIERCOLES 09:20. Ultima corrida buena:
--   09/09, antes del renombre. La del 16/09 habria fallado y la Estadistica Madre se
--   quedaba congelada sin aviso. Problema 120 de la auditoria.
--
-- QUE SE HIZO
--   a) FDW: se saca `uxb` de la foreign table (la columna quedo obsoleta) y entra
--      `gv_descripcion`.
--   b) proyeccion_madre: columna nueva `gv_descripcion` (nullable, prefijo gv_, como manda
--      el protocolo de tablas compartidas).
--   c) sync_proyeccion_madre_virgilio() (en LK) deja de mandar uxb y manda la DESCRIPCION,
--      que ya estaba en estadistica_madre_cache. Asi el NOMBRE viaja por donde viaja el
--      NUMERO, y Virgilio deja de depender de las tablas congeladas.
--   d) GP2.fn_est_madre_sync(): NEW.uxb -> NEW.uxb_obsoleto_v1629. Nada mas.
--   e) GV_Articulo_Nombre_Historico: 236 nombres (51 de LK, 185 de CH) que NINGUNA fuente
--      viva tenia. Sin esto, borrar las viejas dejaba 59 articulos sin nombre, entre ellos
--      el 505I, que tiene 32 movimientos de stock.
--   f) vista_nombres_articulos repuntada: proyeccion_madre -> Articulos Virgilio X
--      Tallerista -> OC_Maximos -> historico. Pasa de 428 a 697 codigos con nombre y
--      CERO pierden el nombre (medido contra las fuentes de antes).
--   g) Se borran "E. Madre LK", "E. Madre CH", el trigger trg_proyeccion_madre_e_madre que
--      las alimentaba, y las funciones trg_e_madre_desde_proyeccion() y
--      actualizar_e_madre_desde_proyeccion(). Backups en
--      zz_backups.GV_Backup_E_Madre_LK_20260913 y _CH_20260913.
--
-- VERIFICADO corriendo el sync ENTERO dos veces (un CREATE OR REPLACE limpio no prueba
-- nada): 410 filas, las 410 con nombre; GP2.est_madre 405 copiada al instante por su
-- trigger; vista_nombres_articulos 697; gv_endpoints_rotos 0. Los 5 que GP2 no copia son
-- las filas contables del origen (E, GASTOTRRECH, CHEQRECHAZAO, ANTICIPO VTA MERCAERIA,
-- TRANSFRECH), que el trigger saltea a proposito con `NEW.cod !~ '^[0-9]'`.
--
-- QUEDA: proyeccion_madre (la unica) -> GP2.est_madre (la copia de GP2, por trigger).
--
-- ROLLBACK: restaurar las dos tablas desde zz_backups, recrear el trigger y las dos
-- funciones desde el historial de git, y volver vista_nombres_articulos a su version
-- anterior (esta en el commit previo de este archivo).
-- =====================================================================================

-- (b) columna nueva en Virgilio
alter table public.proyeccion_madre add column if not exists gv_descripcion text;

-- (d) el trigger de GP2 apuntado a la columna renombrada
--     (se aplico con un replace sobre pg_get_functiondef, guardando que hubiera
--      EXACTAMENTE 2 referencias a NEW.uxb: ni una mas ni una menos)

-- (e) rescate de los nombres que solo vivian en las viejas
create table if not exists public."GV_Articulo_Nombre_Historico" (
  cod          text primary key,
  descripcion  text not null,
  origen       text not null,
  guardado_at  timestamptz not null default now()
);
alter table public."GV_Articulo_Nombre_Historico" enable row level security;
drop policy if exists gv_articulo_nombre_hist_lectura on public."GV_Articulo_Nombre_Historico";
create policy gv_articulo_nombre_hist_lectura on public."GV_Articulo_Nombre_Historico"
  for select to anon, authenticated using (true);
revoke insert, update, delete, truncate on public."GV_Articulo_Nombre_Historico" from anon, authenticated;

-- (f) la vista de nombres, con la fuente viva primero
create or replace view public.vista_nombres_articulos
with (security_invoker = true) as
with norm_pm as (
  select distinct on (k) upper(regexp_replace(coalesce(btrim(cod),''),'^0+(.)','\1')) k,
         nullif(btrim(gv_descripcion),'') d
    from public.proyeccion_madre
   where nullif(btrim(coalesce(gv_descripcion,'')),'') is not null
   order by k, d),
norm_vxt as (
  select distinct on (k) upper(regexp_replace(coalesce(btrim("Cod_Art"),''),'^0+(.)','\1')) k,
         nullif(btrim("Desc"),'') d
    from public."Articulos Virgilio X Tallerista"
   where nullif(btrim(coalesce("Desc",'')),'') is not null
   order by k, d),
norm_oc as (
  select distinct on (k) upper(regexp_replace(coalesce(btrim(cod),''),'^0+(.)','\1')) k,
         nullif(btrim(descripcion),'') d
    from public."OC_Maximos" where activo = true
     and nullif(btrim(coalesce(descripcion,'')),'') is not null
   order by k, d),
norm_hist as (select cod k, descripcion d from public."GV_Articulo_Nombre_Historico"),
keys as (select k from norm_pm union select k from norm_vxt
         union select k from norm_oc union select k from norm_hist)
select kk.k as cod,
       coalesce(pm.d, v.d, o.d, h.d) as descripcion,
       case when pm.d is not null then 'proyeccion_madre'
            when v.d  is not null then 'virgilio_x_tall'
            when o.d  is not null then 'excel'
            else 'historico' end as fuente
  from keys kk
  left join norm_pm   pm on pm.k = kk.k
  left join norm_vxt  v  on v.k  = kk.k
  left join norm_oc   o  on o.k  = kk.k
  left join norm_hist h  on h.k  = kk.k
 where kk.k <> '' and coalesce(pm.d, v.d, o.d, h.d) is not null;

-- (g) fuera las viejas y lo que las alimentaba
drop trigger if exists trg_proyeccion_madre_e_madre on public.proyeccion_madre;
drop function if exists public.trg_e_madre_desde_proyeccion();
drop function if exists public.actualizar_e_madre_desde_proyeccion();
drop table if exists public."E. Madre LK";
drop table if exists public."E. Madre CH";

-- chequeo
-- select count(*) from public.proyeccion_madre;          -- 410, todas con gv_descripcion
-- select count(*) from public.vista_nombres_articulos;   -- 697, ninguno sin nombre
-- select count(*) from public.gv_endpoints_rotos;        -- 0
