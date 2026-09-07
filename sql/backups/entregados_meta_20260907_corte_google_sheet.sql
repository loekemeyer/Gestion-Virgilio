-- BACKUP + CAMBIO · PPP_Entregados_Meta — 2026-09-07 · proyecto Virgilio (hrxfctzncixxqmpfhskv)
--
-- QUÉ PASÓ. El dueño vio en la hoja de entregados un pedido con fecha 08/09/2026 — mañana — y
-- preguntó: "¿cómo 8/9? eso es mañana". Tenía razón: era un tipeo.
--
--   NP 97719 · Merajver Marcelo Fabian (cód 2193) · tanda C39A · 0,031 m³
--   la hoja decía  fecha_entrega = 2026-09-08
--   la facturación dice  facturado_at = 2026-06-08 16:45  ·  fecha_salida = 2026-06-09
--   → se le dieron vuelta el día y el mes al cargarlo. Lo real es el 9 de JUNIO.
--
-- NO ES SISTEMÁTICO. Se cruzaron las 1.072 NP que están a la vez en PPP_Entregados_Meta y en
-- Facturacion_NP: 241 con la misma fecha, 567 a -1 día, 226 entre -2 y -4, 17 hasta -13 (todo
-- normal: la hoja lleva la entrega y la facturación el día de salida). UNA SOLA fila cae fuera de
-- escala, con +91 días: ésta. Y no hay ningún caso de día/mes invertidos en serie.
--
-- POR QUÉ SE APAGÓ EL CRON. Dueño, el mismo día: "la planilla de Google no se tiene que usar para
-- nada". La tabla NO se cargaba a mano: la pisaba entera el cron 27 `sync-ppp-entregados-meta`
-- (7,37 * * * *, cada 30 min), que hace `http_get` del CSV de la hoja "PPP Pedidos Entregados
-- 2026" (gid 2146771217), `truncate` de la tabla y la vuelve a llenar. Corregir la fila sin apagar
-- el cron no servía de nada: a los minutos volvía el 08/09.
--
--   select cron.alter_job(27, active := false);   -- HECHO
--
-- Se apagó ANTES de corregir, y por eso el cambio queda. La tabla queda CONGELADA como foto
-- histórica: 2.783 filas, del 02/01/2026 al 02/09/2026. No se borró nada.
--
-- ⚠ ESTO TAMBIÉN LO TOMA PRODUCCIÓN (base compartida). En el repo de Producción leen
-- PPP_Entregados_Meta: `vista_tanda_m3`, `vista_productividad_semanal`,
-- `picking_sin_base_telegram` y su propio index.html. Con el cron apagado esas vistas dejan de
-- incorporar entregas nuevas desde la hoja (las viejas siguen estando). Desde el 07/09 los
-- operarios usan Gestión, así que en Gestión el estado "entregado" sale de Recepción Remitos
-- (`gv_ppp_entregados`, evento CRN) y no necesita la hoja.
--
-- BACKUP: la foto previa quedó en una tabla del proyecto, con las 2.783 filas ORIGINALES
-- (incluida la fila con el 08/09):
--
--   public."GV_Backup_Entregados_Meta_20260907"     -- 2.783 filas
--
-- ROLLBACK COMPLETO (deja todo como estaba a las 13:50 del 07/09):
--
--   truncate public."PPP_Entregados_Meta";
--   insert into public."PPP_Entregados_Meta" select * from public."GV_Backup_Entregados_Meta_20260907";
--   select cron.alter_job(27, active := true);
--
-- ROLLBACK SÓLO DE LA FECHA (dejando el cron apagado):
--
--   update public."PPP_Entregados_Meta" set fecha_entrega = '2026-09-08' where np = '97719';

-- ===== LO QUE SE EJECUTÓ, EN ORDEN =====

-- 1) backup
create table if not exists public."GV_Backup_Entregados_Meta_20260907" as
select * from public."PPP_Entregados_Meta";

-- 2) cortar la planilla (si no, el cron vuelve a pisar la corrección a los minutos)
select cron.alter_job(27, active := false);

-- 3) la corrección
update public."PPP_Entregados_Meta"
   set fecha_entrega = '2026-06-09'
 where np = '97719' and fecha_entrega = '2026-09-08';

-- 4) verificación
--    ultima_entrega_en_la_hoja = 2026-09-02 · futuras = 0 · filas = 2783
select max(nullif(fecha_entrega,'')::date) ultima_entrega_en_la_hoja,
       count(*) filter (where nullif(fecha_entrega,'')::date > current_date) futuras,
       count(*) filas
from public."PPP_Entregados_Meta";
