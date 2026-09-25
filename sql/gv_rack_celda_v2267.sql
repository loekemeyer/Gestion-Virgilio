-- v22.67 (Luis 25/09): pestaña 📦 Racks del Mapa de góndolas. Solo lectura.
-- Layout = GV_Lugar tipo rack (la tabla que vale). Contenido = Racks_Planimetria (lo mueven
-- racks_plani_ingreso / _descontar / _mover, que dejan además el movimiento de stock).
-- Un sector de Racks_Planimetria sin fila de rack en GV_Lugar sale igual con estado
-- 'sin_lugar' (al 25/09: O2, O5, Z07, Z7) para que no quede escondido.
-- Medido al crearla: 189 posiciones (89 ocupadas, 96 libres, 4 sin_lugar), 1.673 MC; anon ve las 189.
create or replace view public.gv_rack_celda with (security_invoker = true) as
with lug as (
  select upper(btrim(sector)) sector, empresa, orden, uso
    from public."GV_Lugar" where activo and tipo = 'rack'
), rp as (
  select upper(btrim(sector)) sector, emp, nullif(btrim(cod_art),'') cod,
         coalesce(master_cajas,0) master_cajas, coalesce(innercajas,0) innercajas
    from public."Racks_Planimetria" where estado = 'ocupado' and nullif(btrim(cod_art),'') is not null
), sec as (
  select sector from lug union select sector from rp
), nom as (
  select gv_cod_stock(cod) k, min(descripcion) descripcion from public.vista_nombres_articulos
   where descripcion is not null and btrim(descripcion) <> '' group by 1
)
select s.sector,
       substring(s.sector, '^[A-ZÑ]+') as rack,
       l.orden,
       coalesce(l.empresa, r.emp) as empresa,
       l.uso,
       r.cod,
       n.descripcion,
       r.master_cajas,
       r.innercajas,
       r.emp as emp_carga,
       case when l.sector is null then 'sin_lugar'
            when r.cod is null then 'libre'
            else 'ocupado' end as estado
  from sec s
  left join lug l on l.sector = s.sector
  left join rp r on r.sector = s.sector
  left join nom n on n.k = gv_cod_stock(r.cod);
grant select on public.gv_rack_celda to anon, authenticated;
-- Rollback: drop view public.gv_rack_celda;
