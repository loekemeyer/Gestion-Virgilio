-- v23.05 · Coronitas: plazo de contado (25 %) por cliente, desde la planilla de Thomas del 28/09
-- ("Clientes con 25 superados los 14 dias.xlsx", base de clientes LK, columna E = días).
-- LA TABLA CANÓNICA ES public.cobranzas_excepciones (por CUIT: sirve para LK y Chef y para
-- cualquier repo que pegue contra esta base: la leen gv_cobranza_imputar y
-- gv_cobranza_deuda_viva_refrescar; el bot de GestOpClientes corre sus funciones acá mismo).
-- Rollback: delete from public.cobranzas_excepciones where creado_por = 'claude-remote' and motivo like 'Coronita planilla 28/09%';
--           drop policy if exists sup_lee on public.cobranzas_excepciones;

-- 0) backup (la tabla tenía 1 fila: Torres y Liva a 30)
create table if not exists zz_backups."GV_Backup_cobranzas_excepciones_20260928" as select * from public.cobranzas_excepciones;
alter table zz_backups."GV_Backup_cobranzas_excepciones_20260928" enable row level security;
revoke insert, update, delete, truncate on zz_backups."GV_Backup_cobranzas_excepciones_20260928" from anon, authenticated;

-- 1) carga: CUIT resuelto por la última factura de LK del código. Sin CUIT no se carga (4268 La Luguenze).
--    '30/60' (18 clientes de "Fabrica P") entra como 60 hasta que Thomas defina qué significa.
--    288 Torres y Liva NO se toca: la base dice 30 (25/09) y la planilla 60 → lo define Thomas.
with src(cod, nombre, plazo) as (values
  -- ⚠ la lista (175 clientes · código LK · nombre · días) NO va al repo (es público): sale de la planilla
  -- "Clientes con 25 superados los 14 dias.xlsx" de Thomas, columna E. Pegar acá las filas ('cod','nombre','días').
  ('288','Torres Y Liva S.A Cif','60')),
cu as (
  select s.cod, s.nombre, s.plazo,
         (select regexp_replace(d.contraparte_cuit,'\D','','g') from isis_lk.documentos d
           where regexp_replace(coalesce(d.contraparte_codigo,''),'^0+','') = s.cod and d.contraparte_cuit is not null
           order by d.fecha desc limit 1) cuit
    from src s)
insert into public.cobranzas_excepciones
  (deudor_id, cod_cliente, empresa, escalon, dias, dto, vigente_desde, vigente_hasta, autorizado_por, motivo, creado_por)
select cuit, 'LK ' || cod, null, 'contado',
       case when plazo = '30/60' then 60 else plazo::int end, 0.25, date '2025-01-01', null,
       'Thomas', 'Coronita planilla 28/09: ' || nombre || ' · ' || plazo || ' días', 'claude-remote'
  from cu
 where cuit is not null and cod <> '288'
   and not exists (select 1 from public.cobranzas_excepciones e where e.deudor_id = cu.cuit and e.escalon = 'contado');

-- 2) lectura para el panel (supervisor) — hoy la tabla no tiene policy y anon/authenticated no la ven
drop policy if exists sup_lee on public.cobranzas_excepciones;
create policy sup_lee on public.cobranzas_excepciones for select to authenticated using (public.es_supervisor_virgilio());
grant select on public.cobranzas_excepciones to authenticated;

-- 3) verificación
select escalon, dias, count(*) from public.cobranzas_excepciones group by 1, 2 order by 2;
-- después: select public.gv_cobranza_imputacion_refrescar(true);  (recalcula el agente con las coronitas)
