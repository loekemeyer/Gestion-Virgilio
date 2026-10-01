-- v25.9 (Luis, 30/09): "un insumo no deberia tener empresa ... deberia ser Mixto desde el vamos".
-- Insumo importado = parte de vista_importados_partes cuyo propio codigo NO esta entre los terminados
-- que la usan (1000900, 505C, 523C, 587C, 1546903; 590E no: se vende). Igual que los movimientos del
-- deposito insumos (v24.89), su empresa es 'Mixto'.
-- Efectos medidos: 'Mixto' se lee igual que LK en todos los lectores (tratan todo lo que no es CH como LK):
-- gv_importados_ordenes (stock identico), gv_reingresos_feed('lk') sigue trayendo los 5, ('ch') ninguno.
-- Los baches nuevos heredan la marca del maestro (gv_importado_bache_add).
create table zz_backups."GV_Backup_Importados_marca_insumos_20260930" as
  select 'Importados' tabla, id, cod_art, marca from public."Importados" where cod_art in ('1000900','505C','523C','587C','1546903')
  union all
  select 'GV_Importados_Baches', id, cod_art, marca from public."GV_Importados_Baches" where cod_art in ('1000900','505C','523C','587C','1546903');
alter table zz_backups."GV_Backup_Importados_marca_insumos_20260930" enable row level security;
revoke insert, update, delete, truncate on zz_backups."GV_Backup_Importados_marca_insumos_20260930" from anon, authenticated;
update public."Importados" set marca = 'Mixto' where cod_art in ('1000900','505C','523C','587C','1546903');           -- 5
update public."GV_Importados_Baches" set marca = 'Mixto' where cod_art in ('1000900','505C','523C','587C','1546903');  -- 7

-- Centinela: vacia = ningun insumo importado quedo con empresa.
create or replace view public.gv_importados_insumo_con_empresa with (security_invoker = true) as
select i.id, i.cod_art, i.marca, i.proveedor
  from public."Importados" i
  join public.vista_importados_partes p on upper(p.cod) = upper(i.cod_art)
 where not exists (select 1 from jsonb_array_elements(p.detalle) d
                    where ltrim(upper(d->>'cod'),'0') = ltrim(upper(i.cod_art),'0'))
   and coalesce(i.marca,'') <> 'Mixto'
union all
select b.id, b.cod_art, b.marca, b.proveedor
  from public."GV_Importados_Baches" b
  join public.vista_importados_partes p on upper(p.cod) = upper(b.cod_art)
 where not exists (select 1 from jsonb_array_elements(p.detalle) d
                    where ltrim(upper(d->>'cod'),'0') = ltrim(upper(b.cod_art),'0'))
   and coalesce(b.marca,'') <> 'Mixto';

-- Rollback:
-- update public."Importados" i set marca = b.marca from zz_backups."GV_Backup_Importados_marca_insumos_20260930" b where b.tabla='Importados' and b.id=i.id;
-- update public."GV_Importados_Baches" i set marca = b.marca from zz_backups."GV_Backup_Importados_marca_insumos_20260930" b where b.tabla='GV_Importados_Baches' and b.id=i.id;
