-- v15.26 — Pedidos Importación: el stock de los TERMINADOS cuenta como stock de la PARTE (2026-09-11, YA APLICADO)
-- Proyecto Supabase: hrxfctzncixxqmpfhskv. Detalle y medición: docs/SUPABASE-GESTION-VIRGILIO.md §3.bm.18
--
-- Regla del dueño (11/09): "en los insumos hay que considerar el stock de las partes" — el pedido de una parte
-- (1546903 → 546, 1000900 → espirales 520/521/530/531/581/730/731/735, 523C → 523, 505C → cuchillas 505/586/713/186/
-- 123/114, 587C → 587) tiene que descontar lo que ya está armado en Virgilio (góndola, racks, a guardar…), no sólo el
-- stock de la parte suelta. Supuesto: 1 parte por unidad terminada (la tabla de mapa no tiene cantidad).
--
-- 1) Mapa: 505C también arma el 114 (backup GV_Importados_Partes_Map_bkp_20260911)
insert into public."Importados_Partes_Map"(parte, terminado) values ('505C','114') on conflict do nothing;

-- 2) Vista: mismas columnas que antes (cod, proy_uni_mes, detalle) + stock_term_uni; el detalle suma stock por terminado.
create or replace view public.vista_importados_partes as
with dep as (
  select ltrim(upper(split_part(btrim(s.cod_art),' ',1)),'0') as ckey,
         sum(coalesce(s.terminado,0)+coalesce(s.excedente,0)+coalesce(s.separar_pedidos,0)+coalesce(s.a_facturar,0)
            +coalesce(s.a_guardar,0)+coalesce(s.racks,0)+coalesce(s.racks_ch,0)+coalesce(s.para_envasar,0)) as cajas
  from public.vista_saldos_stock s
  group by 1
), uxc as (
  select ltrim(upper(btrim(codn::text)),'0') as ckey, max(uni_x_caja) as uni_x_caja
  from public.vista_uni_x_caja group by 1
), t as (
  select m.parte, m.terminado, ltrim(upper(btrim(m.terminado)),'0') as tkey
  from public."Importados_Partes_Map" m
), det as (
  select t.parte, t.terminado,
         (select max(p.proy_uni_mes) from public.vista_proyeccion_super p where ltrim(upper(btrim(p.cod)),'0') = t.tkey) as proy,
         coalesce(d.cajas,0) as stock_cajas,
         u.uni_x_caja,
         round(coalesce(d.cajas,0) * coalesce(u.uni_x_caja,0)) as stock_uni
  from t left join dep d on d.ckey = t.tkey left join uxc u on u.ckey = t.tkey
)
select parte as cod,
       round(sum(coalesce(proy,0))::numeric,0) as proy_uni_mes,
       jsonb_agg(jsonb_build_object('cod', terminado, 'proy', round(coalesce(proy,0)::numeric,0),
                                    'stock_cajas', stock_cajas, 'uxc', uni_x_caja, 'stock_uni', stock_uni)
                 order by terminado) as detalle,
       round(sum(stock_uni),0) as stock_term_uni
from det group by parte;
alter view public.vista_importados_partes set (security_invoker = on);   -- create or replace lo pierde: volver a ponerlo
grant select on public.vista_importados_partes to anon, authenticated;

-- Chequeo (11/09): 1546903 → 19.524 u (546: 1.627 cajas × 12) · 505C 61.122 · 1000900 25.560 · 523C 3.420 · 587C 5.400
select cod, proy_uni_mes, stock_term_uni from public.vista_importados_partes order by cod;

-- ROLLBACK
--   delete from public."Importados_Partes_Map" where parte = '505C' and terminado = '114';
--   vista: bloque "vista_importados_partes" de sql/importados_partes_y_super.sql (sin stock_term_uni) + alter view … security_invoker.
--   El front (index.html v15.26) tolera que la columna no exista: stock_term_uni → 0.
