-- v15.27 — Pedidos Importación: el depósito INSUMOS cuenta como stock (partes y reenvasados) (2026-09-11, YA APLICADO)
-- Proyecto Supabase: hrxfctzncixxqmpfhskv. Detalle y medición: docs/SUPABASE-GESTION-VIRGILIO.md §3.bm.19
--
-- Dueño (11/09): "ojo con lo que está en insumos de importados". Hasta acá el módulo NUNCA miraba el depósito
-- `insumos` (el sync v15.11 lo excluyó y las partes quedaron con el seed del Excel QUIEBRE del 16/07: 505C 262.400,
-- 1000900 68.000). Reglas cerradas con el dueño:
--   · 1000900 (espiral, Hugo Wong) = insumos H201Part "Espiral TN" + 007 "Espiral (Chef)": todo cuenta.
--   · 546P "bastidor corta queso" = parte 1546903 (Ownland).  · 522ES suelto = 522E sin caja.
--   · H201Lever y CB01: partes sin uso todavía → fuera.  · Mgo Pelador 505 / Ergonómico: inyectadas nacionales → fuera.
--   · 337P arma el 337: sin fila en Importados (falta proveedor/FOB) → pendiente del dueño.
--   · 733E / 692E / 814E: se empezaron a vender ahora → se piden con el seed, no se tocan.
-- Unidades: el saldo se toma de vista_saldos_insumos_x_unidad (por unidad) y se convierte con Insumos_Factores;
-- si falta el factor de MC/Cajas, cae a Importados_Volumen.uni_master; Uni/(s/u) = 1. Así 505C = 142.000 − 3 MC×4.000
-- = 130.000 (la vista cruda decía 141.997) y 590E = 2.400 − 4 MC×600 = 0 (cruda 2.396).

-- 1) Mapa insumo → importado (los códigos iguales se enlazan solos; acá van sólo los renombrados)
create table if not exists public."GV_Importados_Insumo_Map" (
  insumo_cod text not null, importado_cod text not null, nota text, creado timestamptz default now(),
  primary key (insumo_cod, importado_cod));
alter table public."GV_Importados_Insumo_Map" enable row level security;
create policy gv_imp_insumo_map_read on public."GV_Importados_Insumo_Map" for select to anon, authenticated using (true);
grant select on public."GV_Importados_Insumo_Map" to anon, authenticated;
insert into public."GV_Importados_Insumo_Map"(insumo_cod, importado_cod, nota) values
 ('546P','1546903','bastidor corta queso = parte 1546903 (Insumos.isis); dueño 11/09'),
 ('H201Part','1000900','espiral TN: es el mismo espiral que 1000900 (dueño 11/09)'),
 ('007','1000900','espiral Chef: ídem (dueño 11/09)'),
 ('522ES','522E','sacacorcho premium suelto = 522E sin caja (20 master × 100)')
on conflict do nothing;

-- 2) Vista: stock de insumos por código de Importados, en unidades
create or replace view public.gv_importados_stock_insumos as
with sal as (
  select s.cod_art, coalesce(nullif(btrim(s.unidad),''),'(s/u)') as unidad, s.saldo
  from public.vista_saldos_insumos_x_unidad s
), map as (select insumo_cod, importado_cod from public."GV_Importados_Insumo_Map"),
link as (
  select insumo_cod, importado_cod from map
  union
  select s.cod_art, i.cod_art
  from (select distinct cod_art from sal) s
  join (select distinct cod_art from public."Importados" where principal and activo) i on upper(i.cod_art) = upper(s.cod_art)
  where s.cod_art not in (select insumo_cod from map)
), det as (
  select l.importado_cod, s.cod_art as insumo_cod, s.unidad, s.saldo,
         case when lower(s.unidad) in ('uni','unidad','unidades','(s/u)') then 1
              else coalesce(f.factor,
                            case when lower(s.unidad) in ('mc','master','cajas','caja') then v.uni_master end) end as factor
  from link l
  join sal s on s.cod_art = l.insumo_cod
  left join public."Insumos_Factores" f on f.cod_art = s.cod_art and lower(f.unidad) = lower(s.unidad)
  left join (select upper(cod) as cod, uni_master from public."Importados_Volumen") v on v.cod = upper(l.importado_cod)
)
select importado_cod as cod,
       round(sum(saldo * coalesce(factor, 1)), 0) as stock_uni,
       bool_or(factor is null) as sin_factor,
       jsonb_agg(jsonb_build_object('insumo', insumo_cod, 'unidad', unidad, 'saldo', saldo, 'factor', factor,
                                    'uni', round(saldo * coalesce(factor,1),0)) order by insumo_cod, unidad) as detalle
from det group by importado_cod;
alter view public.gv_importados_stock_insumos set (security_invoker = on);
grant select on public.gv_importados_stock_insumos to anon, authenticated;

-- 3) v_importados_ordenes: + stock_insumos, es_parte, stock_total (definición anterior guardada en
--    GV_bkp_def_v_importados_ordenes_20260911). Lo nuevo respecto de v15.24 son los CTE `partes`/`ch_rows`, el join a
--    gv_importados_stock_insumos (el insumo va a la fila CH si el código tiene una — Paquete A — y si no a la LK) y:
--      coalesce(si.stock_uni,0)                                   as stock_insumos,
--      (pt.cod is not null)                                       as es_parte,
--      case when pt.cod is not null and si.cod is not null then si.stock_uni      -- parte: insumos REEMPLAZA el seed
--           else stock_actual + coalesce(si.stock_uni,0) end       as stock_total
--    (cuerpo completo: select def from "GV_bkp_def_v_importados_ordenes_20260911" para la vieja; la nueva es la vigente:
--     select pg_get_viewdef('public.v_importados_ordenes'::regclass, true)).

-- Chequeo (11/09): 505C 130.000 · 1000900 107.500 · 1546903 16.848 · 523C 6.000 · 437E·CH 2.976 · 522E 4.604
select cod_art, marca, stock_actual, stock_insumos, es_parte, stock_total from public.v_importados_ordenes
 where principal and activo and (stock_insumos <> 0 or es_parte) order by 1, 2;

-- ROLLBACK
--   create or replace view public.v_importados_ordenes as <def de GV_bkp_def_v_importados_ordenes_20260911>;
--   drop view public.gv_importados_stock_insumos; drop table public."GV_Importados_Insumo_Map";
--   El front (v15.27) cae a stock_actual si stock_total no viene.
