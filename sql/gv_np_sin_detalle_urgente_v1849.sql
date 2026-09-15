-- v18.49 — NP programadas SIN renglones que igual hay que entregar.
-- Caso 97889 / D71A (15/09): cabecera en la PPP, cero artículos en GV_PPP_Base_Pedidos (el
-- pedido se cargó en ISIS el 23/06 y la importación del detalle arranca el 01/07). El operario
-- le dio EP, la lista salió vacía y la tanda quedó trabada.
-- A diferencia de vista_np_prog_sin_base, esta NO se puede silenciar con NP_Sin_Base_Revisadas:
-- a la 97889 la marcaron "no_es_problema / 3 meses de ant" el 15/09 09:46 y el centinela dejó de
-- avisar mientras el pedido seguía programado para entregar al día siguiente.
create or replace view public.gv_np_sin_detalle_urgente as
with prog as (
  select regexp_replace(btrim(p.np),'\.0+$','') np,
         nullif(btrim(coalesce(p.tanda,'')),'') tanda,
         nullif(btrim(coalesce(p.razon_social,'')),'') cliente,
         left(btrim(coalesce(p.fecha_recep,'')),10) fecha_recep,
         left(btrim(coalesce(p.fecha_entrega,'')),10) fecha_entrega,
         coalesce(p.m3,0) m3
    from public.gv_ppp_programacion_diaria p
   where p.np is not null and btrim(p.np) <> ''
), base as (
  select distinct regexp_replace(btrim(pedido),'\.0+$','') np
    from public."GV_PPP_Base_Pedidos" where pedido is not null
), salidas as (
  select regexp_replace(btrim(np),'\.0+$','') np from public."Facturacion_NP" where np is not null
  union select regexp_replace(btrim(np),'\.0+$','') from public."GV_PPP_Entregados_Historico" where np is not null
  union select regexp_replace(btrim(np),'\.0+$','') from public."NP_Canceladas" where np is not null
)
select p.np, max(p.tanda) tanda, max(p.cliente) cliente,
       max(p.fecha_recep) fecha_recep, max(p.fecha_entrega) fecha_entrega,
       round(sum(p.m3),2) m3,
       (max(p.fecha_entrega) < to_char((now() at time zone 'America/Argentina/Buenos_Aires')::date,'YYYY-MM-DD')) vencida
  from prog p
 where not exists (select 1 from base b where b.np = p.np)
   and not exists (select 1 from salidas s where s.np = p.np)
   and p.fecha_entrega >= to_char((now() at time zone 'America/Argentina/Buenos_Aires')::date - 7, 'YYYY-MM-DD')
 group by p.np
 order by 5;

alter view public.gv_np_sin_detalle_urgente set (security_invoker = true);

-- Chequeo:  select * from public.gv_np_sin_detalle_urgente;   -- vacía = todo bien
