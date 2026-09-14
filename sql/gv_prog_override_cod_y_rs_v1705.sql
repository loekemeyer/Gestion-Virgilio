-- gv_prog_override_cod_y_rs_v1705.sql — APLICADO 2026-09-14 (v17.05).
--
-- Marianela: "los pedidos 98669/70/71 pertenecen al cliente de Loeke 2145 Pettish Lacroze 2481;
-- los 98672/73/74/75 al 2384 Pettish Villa Crespo". Las siete estaban con cod 1792 Dapelo.
-- Son TRES CUIT distintos (1792 → 20202038507 · 2145 → 30715210963 · 2384 → 30716050935),
-- así que no es una sucursal del mismo titular: facturadas así iban al CUIT equivocado.
-- Origen: los pedidos web se cargaron desde la cuenta de Dapelo en la página LK
-- (orders 1330/1331/1332 del 01/09 y 1337/1338 del 02/09, customer_code 1792).
--
-- Dos arreglos en la misma pasada:
--   (2) el cod se puede pisar por NP desde GV_PPP_Prog_Override, que es tabla NUESTRA — no se
--       toca el espejo de ISIS (GV_PPP_Programacion_Diaria), que es compartido.
--   (3) las vistas pisaban la razón social BUENA de la fila con la del cod. `GV_Cliente_Razon_Social`
--       está indexada sólo por (cod, empresa), así que con un cod que arrastra varias razones
--       sociales el nombre de la tabla ganaba y borraba el que trajo ISIS. Ahora, cuando el cod es
--       ambiguo (más de una razón social en el espejo), manda la fila. Con cod unívoco sigue
--       mandando la tabla, que es lo que pidió la v16.90 ("nunca el nombre de fantasía").
--
-- Backup: zz_backups."GV_Backup_ProgOverride_20260914" (120 filas, la tabla entera antes de tocarla).
-- Las dos vistas son `create or replace` sin cambiar la lista de columnas, así que los 18 objetos
-- que cuelgan de gv_ppp_programacion_diaria siguen válidos (gv_endpoints_rotos = 0 después).

alter table public."GV_PPP_Prog_Override" add column if not exists cod text;
alter table public."GV_PPP_Prog_Override" add column if not exists razon_social text;

create or replace view public.gv_ppp_programacion_diaria as
with multi as (
  select regexp_replace(btrim(cod), '\.0+$', '') as cod
    from public."GV_PPP_Programacion_Diaria"
   where coalesce(btrim(razon_social), '') <> ''
   group by 1
  having count(distinct lower(btrim(razon_social))) > 1
)
select p.id,
       p.np,
       case when coalesce(o.desprogramada, false) then ''::text
            else coalesce(nullif(btrim(o.tanda), ''), p.tanda) end as tanda,
       p.tipo,
       p.fecha_recep,
       coalesce(nullif(btrim(o.cod), ''), p.cod) as cod,
       coalesce(
         nullif(btrim(o.razon_social), ''),
         case when m.cod is not null then nullif(btrim(p.razon_social), '') end,
         rs.razon_social,
         p.razon_social) as razon_social,
       p.m3,
       p.v,
       p.direccion,
       p.barrio,
       p.op,
       case when coalesce(o.desprogramada, false) then ''::text
            else coalesce(o.fecha_entrega::text || ' 00:00:00'::text, p.fecha_entrega) end as fecha_entrega,
       p.fecha_fc,
       coalesce(nullif(btrim(o.zona), ''), p.zona) as zona,
       p.observaciones
  from public."GV_PPP_Programacion_Diaria" p
  cross join public.gv_espejo_corte() c(lk, chef)
  left join public."GV_PPP_Prog_Override" o
    on o.np = regexp_replace(p.np, '\.0+$', '')
  left join public."GV_Cliente_Razon_Social" rs
    on rs.cod = regexp_replace(btrim(coalesce(nullif(btrim(o.cod), ''), p.cod)), '\.0+$', '')
   and rs.empresa = public.gv_empresa_de_np_texto(p.np)
  left join multi m
    on m.cod = regexp_replace(btrim(coalesce(nullif(btrim(o.cod), ''), p.cod)), '\.0+$', '')
 where public.gv_espejo_np_pasa(p.np, c.lk, c.chef)
   and not coalesce(o.oculto, false);

alter view public.gv_ppp_programacion_diaria set (security_invoker = true);

create or replace view public.gv_ppp_prog_rs as
with multi as (
  select regexp_replace(btrim(cod), '\.0+$', '') as cod
    from public."GV_PPP_Programacion_Diaria"
   where coalesce(btrim(razon_social), '') <> ''
   group by 1
  having count(distinct lower(btrim(razon_social))) > 1
)
select p.id, p.np, p.tanda, p.tipo, p.fecha_recep, p.cod,
       coalesce(
         case when m.cod is not null then nullif(btrim(p.razon_social), '') end,
         rs.razon_social,
         p.razon_social) as razon_social,
       p.m3, p.v, p.direccion, p.barrio, p.op, p.fecha_entrega, p.fecha_fc, p.zona, p.observaciones
  from public."GV_PPP_Programacion_Diaria" p
  left join public."GV_Cliente_Razon_Social" rs
    on rs.cod = regexp_replace(btrim(p.cod), '\.0+$', '')
   and rs.empresa = public.gv_empresa_de_np_texto(p.np)
  left join multi m on m.cod = regexp_replace(btrim(p.cod), '\.0+$', '');

alter view public.gv_ppp_prog_rs set (security_invoker = true);

-- Las 7 NP, por override (el espejo de ISIS no se toca)
update public."GV_PPP_Prog_Override"
   set cod = case when np in ('98669','98670','98671') then '2145' else '2384' end,
       razon_social = case when np in ('98669','98670','98671')
                           then 'Pettish Lacroze 2481' else 'Pettish Villa Crespo' end,
       nota = coalesce(nota, '') || ' | v17.05 2026-09-14 · Marianela: el cod real es '
              || case when np in ('98669','98670','98671') then '2145 Pettish Lacroze 2481'
                      else '2384 Pettish Villa Crespo' end
              || ', no 1792 Dapelo (tres CUIT distintos). El pedido web se cargo desde la cuenta de Dapelo.'
 where np in ('98669','98670','98671','98672','98673','98674','98675');

-- ── MEDICIÓN ─────────────────────────────────────────────────────────────────────────────
--   gv_ppp_programacion_diaria: 123 filas (igual que antes) · las 7 NP con cod 2145/2384 y
--     razón social Pettish, tandas D67E y D67F, entrega 15/09.
--   gv_ppp_prog_rs: 133 filas · 7 Pettish.
--   gv_endpoints_rotos: 0. gv_ppp_entregados 426 · gv_fac_armado_sin_facturar 8 · gv_viaje_np 903.
--
-- ── ROLLBACK ─────────────────────────────────────────────────────────────────────────────
-- update public."GV_PPP_Prog_Override" o
--    set cod = null, razon_social = null, nota = b.nota
--   from zz_backups."GV_Backup_ProgOverride_20260914" b where o.np = b.np;
-- y volver las dos vistas a la versión de git anterior a este archivo.
