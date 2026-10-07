-- v28.43 (Luis, 07/10/2026): PIEZAS E INSUMOS COMPARTIDOS, REPARTIDOS POR E.M.
--
-- (los comentarios adentro de las funciones y las notas de la tabla dicen v28.42: así quedaron en la base; la versión de la app es v28.43)
--   633E→942E · 630E→943E · 637E→944E · 636E→945E · 631E→948E: el de Chef usa las MISMAS piezas
--   que el importado de LK (GP2: Z47 + Z47-M505 + 942E… y la parte 942P en Virgilio).
--   438E y 439E: el insumo de Virgilio (colador suelto) sirve al de LK y al de Chef.
--   Cada uno se lleva una parte proporcional a su Estadística Madre del mes (dinámica:
--   gv_proyeccion_articulo, en unidades = cajas × UxB). Sin E.M. en todo el grupo → partes iguales.
--   323E / 838E: GRJ31 y la parte 323ES van 100 % al 838E (cada uno conserva su terminado de GP2).
--
-- Vale para las DOS cosas que pidió:
--   · si se le compra al chino  → gv_importados_ordenes (stock_gp2, stock_insumos, stock_total_neto)
--                                  + vista_importados_stock_parte
--   · el cartel "sin stock" de la página → gv_reingresos_feed (cuenta piezas GP2 + insumos +
--     parte, con su %; el que comparte sin ser importado —633E…— también lleva cartel, con la
--     fecha de reingreso del importado).
--
-- Centinelas 362-366. Lo aplicó la sesión el 07/10 (este archivo es el registro).
-- Medido: gv_reingresos_feed LK 1.237 → 726 ms, CH 275 → 497 ms; gv_importados_ordenes 133 ms.

-- 1) quién comparte las piezas de quién --------------------------------------------------------
create table if not exists public."GV_Piezas_Reparto" (
  grupo text not null,          -- importado dueño de las piezas (942E, 438E…)
  cod_art text not null,        -- artículo que las comparte
  empresa text not null check (empresa in ('LK','CH')),
  peso_fijo numeric,            -- null = proporcional a la E.M. del mes (dinámico)
  nota text,
  creado_por text default 'Luis (claude)',
  creado_en timestamptz default now(),
  primary key (grupo, cod_art, empresa)
);
alter table public."GV_Piezas_Reparto" enable row level security;
-- (revoke insert/update/del-ete/trunc-ate a anon y authenticated; grant select; policy de select)
grant select on public."GV_Piezas_Reparto" to anon, authenticated;
create policy gv_piezas_reparto_sel on public."GV_Piezas_Reparto" for select to anon, authenticated using (true);

insert into public."GV_Piezas_Reparto"(grupo,cod_art,empresa,nota) values
 ('942E','942E','LK','v28.43 Luis 07/10: piezas 942E compartidas con 633E CH, por E.M.'),('942E','633E','CH','v28.43 Luis 07/10'),
 ('943E','943E','LK','v28.43 Luis 07/10'),('943E','630E','CH','v28.43 Luis 07/10'),
 ('944E','944E','LK','v28.43 Luis 07/10'),('944E','637E','CH','v28.43 Luis 07/10'),
 ('945E','945E','LK','v28.43 Luis 07/10'),('945E','636E','CH','v28.43 Luis 07/10'),
 ('948E','948E','LK','v28.43 Luis 07/10'),('948E','631E','CH','v28.43 Luis 07/10'),
 ('438E','438E','LK','v28.43 Luis 07/10: insumo 438E de Virgilio, LK/CH por E.M.'),('438E','438E','CH','v28.43 Luis 07/10'),
 ('439E','439E','LK','v28.43 Luis 07/10: insumo 439E de Virgilio, LK/CH por E.M.'),('439E','439E','CH','v28.43 Luis 07/10')
on conflict do nothing;

-- 2) el % de cada uno ------------------------------------------------------------------------------
create or replace view public.gv_piezas_reparto_share with (security_invoker = true) as
with m as (
  select r.grupo, upper(btrim(r.cod_art)) as cod_art, r.empresa, r.peso_fijo,
         coalesce(case when r.empresa = 'CH' then pa.proy_ch else pa.proy_lk end, 0) as em_cajas,
         coalesce(
           (select max(u.uxb) from public."GV_UxB" u where u.uxb > 1 and gv_cod_stock(u.cod) = gv_cod_stock(r.cod_art)
              and (case when u.empresa = 'CH' then 'CH' else 'LK' end) = r.empresa),
           (select max(v.uxb::numeric) from public.vista_uxb_articulo v where gv_cod_stock(v.cod) = gv_cod_stock(r.cod_art) and v.uxb::numeric > 1)
         ) as uxb_propia
  from public."GV_Piezas_Reparto" r
  left join public.gv_proyeccion_articulo pa on pa.cod = gv_cod_stock(r.cod_art)
), m2 as (
  select m.*,
         coalesce(m.uxb_propia,
           (select o.uxb_propia from m o where o.grupo = m.grupo and o.cod_art = upper(m.grupo) and o.uxb_propia is not null limit 1), 1) as uxb
  from m
), m3 as (
  select m2.*, m2.em_cajas * m2.uxb as em_uni,
         coalesce(m2.peso_fijo, m2.em_cajas * m2.uxb) as peso
  from m2
)
select grupo, cod_art, empresa, em_cajas, uxb, uxb_propia is null as uxb_supuesta, em_uni, peso_fijo,
       case when sum(peso) over (partition by grupo) > 0 then round(peso / sum(peso) over (partition by grupo), 4)
            else round(1.0 / count(*) over (partition by grupo), 4) end as share,
       string_agg(cod_art || ' ' || empresa || ' ' || round(em_uni) || ' u', ' · ') over (partition by grupo) as reparto
from m3;
grant select on public.gv_piezas_reparto_share to anon, authenticated;

-- 3) 323E / 838E: 100 % al 838E (backup en zz_backups."GV_Backup_Equiv323_838_20261007") -------
--   sale (323E, GRJ31), (323E, 838E), (838E, 323E) de GV_Importados_Equiv_GP2
--   sale (323E, 323ES) de Importados_Stock_Parte
--   quedan: 838E ← GRJ31 + 838E (GP2) + 323ES (parte) · 323E ← 323E (GP2)
-- Rollback: insert into public."GV_Importados_Equiv_GP2"(importado_cod, componente_codigo, factor)
--   select a, b, factor from zz_backups."GV_Backup_Equiv323_838_20261007" where tabla = 'equiv_gp2' on conflict do nothing;
--   insert into public."Importados_Stock_Parte"(terminado, parte, parte_x_caja)
--   select a, b, factor from zz_backups."GV_Backup_Equiv323_838_20261007" where tabla = 'stock_parte' on conflict do nothing;

-- 4) parte en Virgilio repartida -------------------------------------------------------------------
create or replace view public.vista_importados_stock_parte with (security_invoker = true) as
 SELECT sp.terminado AS cod,
    -- v28.42 (Luis 07/10): si la parte es de un grupo de GV_Piezas_Reparto, al terminado le toca su % por E.M.
    round(sum(COALESCE(mv.saldo, 0::numeric) * COALESCE(sh.share, 1::numeric)), 0) AS stock_parte,
    string_agg(DISTINCT sp.parte, ', '::text ORDER BY sp.parte) AS partes
   FROM "Importados_Stock_Parte" sp
     LEFT JOIN LATERAL ( SELECT sum(m.delta) AS saldo
           FROM "Movimientos_Stock" m
          WHERE ltrim(upper(btrim(m.cod_art)), '0'::text) = ltrim(upper(btrim(sp.parte)), '0'::text)) mv ON true
     LEFT JOIN gv_piezas_reparto_share sh ON sh.grupo = upper(btrim(sp.terminado)) AND sh.cod_art = upper(btrim(sp.terminado))
  GROUP BY sp.terminado;

-- 5) gv_importados_ordenes: stock GP2 e insumos × su % (se aplicó como parche sobre pg_get_viewdef:
--    si.stock_uni → si.stock_uni * COALESCE(sh.share, 1), g2.stock_gp2 → g2.stock_gp2 * COALESCE(sh.share, 1),
--    + LEFT JOIN gv_piezas_reparto_share sh y columnas nuevas al final: piezas_share, piezas_reparto).
--    CREATE completo, como quedó vivo el 07/10:
create or replace view public.gv_importados_ordenes with (security_invoker = true) as
 WITH gux AS (
         SELECT
                CASE
                    WHEN "GV_UxB".empresa = 'CH'::text THEN 'CH'::text
                    ELSE 'LK'::text
                END AS emp,
            gv_cod_stock("GV_UxB".cod) AS c,
            max("GV_UxB".uxb) AS u
           FROM "GV_UxB"
          WHERE "GV_UxB".uxb > 1::numeric
          GROUP BY (
                CASE
                    WHEN "GV_UxB".empresa = 'CH'::text THEN 'CH'::text
                    ELSE 'LK'::text
                END), (gv_cod_stock("GV_UxB".cod))
        ), cfg AS (
         SELECT "Importados_Config".meses_objetivo
           FROM "Importados_Config"
          WHERE "Importados_Config".id = 1
        ), fam AS (
         SELECT gv_cod_stock("Equivalencias_Familia".cod_principal) AS ppal,
            gv_cod_stock("Equivalencias_Familia".cod_secundario) AS sec
           FROM "Equivalencias_Familia"
          WHERE NULLIF(btrim("Equivalencias_Familia".cod_principal), ''::text) IS NOT NULL AND NULLIF(btrim("Equivalencias_Familia".cod_secundario), ''::text) IS NOT NULL
        ), pe AS (
         SELECT pa.cod AS cod_norm,
            e.empresa,
            e.proy_cajas_mes
           FROM gv_proyeccion_articulo pa
             CROSS JOIN LATERAL ( VALUES ('lk'::text,pa.proy_lk), ('chef'::text,pa.proy_ch)) e(empresa, proy_cajas_mes)
          WHERE NOT pa.es_secundario AND e.proy_cajas_mes > 0::numeric
        ), partes AS (
         SELECT DISTINCT upper("Importados_Partes_Map".parte) AS cod
           FROM "Importados_Partes_Map"
        ), ch_rows AS (
         SELECT DISTINCT upper("Importados".cod_art) AS cod
           FROM "Importados"
          WHERE "Importados".principal AND "Importados".activo AND upper(COALESCE("Importados".marca, ''::text)) = 'CH'::text
        ), dup AS (
         SELECT gv_cod_stock("Importados".cod_art) AS cod_norm
           FROM "Importados"
          WHERE "Importados".principal AND "Importados".activo
          GROUP BY (gv_cod_stock("Importados".cod_art))
         HAVING count(*) > 1
        ), conv AS (
         SELECT upper(x.imp) AS imp,
            sum(GREATEST(x.b - x.p, 0::numeric) * COALESCE(gq.u, 1::numeric) * x.factor) AS stock_conv
           FROM ( SELECT e3.importado_cod AS imp,
                    e3.cod_art,
                    e3.empresa,
                    e3.factor,
                    COALESCE(sum(d3.cajas_bruto), 0::numeric) AS b,
                    COALESCE(sum(d3.cajas_pedidas), 0::numeric) AS p
                   FROM "GV_Importados_Equiv_Virgilio" e3
                     LEFT JOIN gv_importados_stock_dep d3 ON d3.cod_norm = gv_cod_stock(e3.cod_art) AND (d3.empresa = ANY (ARRAY[e3.empresa, 'MIXTO'::text]))
                  GROUP BY e3.importado_cod, e3.cod_art, e3.empresa, e3.factor) x
             LEFT JOIN gux gq ON gq.emp = x.empresa AND gq.c = gv_cod_stock(x.cod_art)
          GROUP BY (upper(x.imp))
        ), stk AS (
         SELECT i_1.id,
            COALESCE(sum(d.cajas_bruto), 0::numeric) AS cajas_bruto,
            COALESCE(sum(d.cajas_pedidas), 0::numeric) AS cajas_pedidas
           FROM "Importados" i_1
             LEFT JOIN gv_importados_stock_dep d ON d.cod_norm = gv_cod_stock(i_1.cod_art) AND (NOT (EXISTS ( SELECT 1
                   FROM dup
                  WHERE dup.cod_norm = gv_cod_stock(i_1.cod_art))) OR upper(COALESCE(i_1.marca, ''::text)) = 'CH'::text AND d.empresa = 'CH'::text OR upper(COALESCE(i_1.marca, ''::text)) <> 'CH'::text AND (d.empresa = ANY (ARRAY['LK'::text, 'MIXTO'::text])))
          GROUP BY i_1.id
        )
 SELECT i.id,
    i.cod_art,
    i.marca,
    i.proveedor,
    i.descripcion,
    i.fob_uni,
    COALESCE(gx.u, i.uni_x_caja) AS uni_x_caja,
    i.principal,
    i.activo,
    i.notas,
    i.est_madre_seed,
    i.est_madre_override,
    i.pedido_manual,
    COALESCE(i.pedido_curso, 0::numeric) AS pedido_curso,
        CASE
            WHEN upper(COALESCE(i.marca, ''::text)) = 'CH'::text THEN 'Chef'::text
            ELSE 'Loeke'::text
        END AS planta,
        CASE
            WHEN p.proy_cajas_mes IS NOT NULL THEN round(p.proy_cajas_mes * COALESCE(gx.u, i.uni_x_caja, 1::numeric), 2)
            ELSE NULL::numeric
        END AS est_madre_live,
    COALESCE(( SELECT gip.meses_objetivo
           FROM "GV_Imp_Proveedor" gip
          WHERE gip.proveedor = btrim(i.proveedor)), ( SELECT cfg.meses_objetivo
           FROM cfg)) AS meses_objetivo,
    COALESCE(i.est_madre_override,
        CASE
            WHEN p.proy_cajas_mes IS NOT NULL THEN round(p.proy_cajas_mes * COALESCE(gx.u, i.uni_x_caja, 1::numeric), 2)
            ELSE NULL::numeric
        END, 0::numeric) AS est_madre_eff,
        CASE
            WHEN i.est_madre_override IS NOT NULL THEN 'override'::text
            WHEN p.proy_cajas_mes IS NOT NULL THEN 'live'::text
            ELSE 'sin proyeccion'::text
        END AS est_madre_fuente,
    round(GREATEST(COALESCE(st.cajas_bruto, 0::numeric) - COALESCE(st.cajas_pedidas, 0::numeric), 0::numeric) * COALESCE(gx.u, i.uni_x_caja, 0::numeric)) AS stock_actual,
    GREATEST(COALESCE(st.cajas_bruto, 0::numeric) - COALESCE(st.cajas_pedidas, 0::numeric), 0::numeric) AS stock_cajas,
    COALESCE(st.cajas_bruto, 0::numeric) AS stock_cajas_bruto,
    COALESCE(st.cajas_pedidas, 0::numeric) AS cajas_pedidas,
    round(COALESCE(st.cajas_pedidas, 0::numeric) * COALESCE(gx.u, i.uni_x_caja, 0::numeric)) AS unidades_pedidas,
    COALESCE(si.stock_uni * COALESCE(sh.share, 1::numeric), 0::numeric) AS stock_insumos,
    pt.cod IS NOT NULL AS es_parte,
        CASE
            WHEN pt.cod IS NOT NULL AND si.cod IS NOT NULL THEN si.stock_uni * COALESCE(sh.share, 1::numeric)
            ELSE round(GREATEST(COALESCE(st.cajas_bruto, 0::numeric) - COALESCE(st.cajas_pedidas, 0::numeric), 0::numeric) * COALESCE(gx.u, i.uni_x_caja, 0::numeric)) + COALESCE(si.stock_uni * COALESCE(sh.share, 1::numeric), 0::numeric)
        END AS stock_total,
    COALESCE(g2.stock_gp2 * COALESCE(sh.share, 1::numeric), 0::numeric) AS stock_gp2,
        CASE
            WHEN pt.cod IS NOT NULL AND si.cod IS NOT NULL THEN si.stock_uni * COALESCE(sh.share, 1::numeric)
            ELSE round((COALESCE(st.cajas_bruto, 0::numeric) - COALESCE(st.cajas_pedidas, 0::numeric)) * COALESCE(gx.u, i.uni_x_caja, 0::numeric)) + COALESCE(si.stock_uni * COALESCE(sh.share, 1::numeric), 0::numeric)
        END + COALESCE(g2.stock_gp2 * COALESCE(sh.share, 1::numeric), 0::numeric) + COALESCE(cv.stock_conv, 0::numeric) AS stock_total_neto,
    COALESCE(cv.stock_conv, 0::numeric) AS stock_conv,
    COALESCE(sh.share, 1::numeric) AS piezas_share,
    sh.reparto AS piezas_reparto
   FROM "Importados" i
     LEFT JOIN stk st ON st.id = i.id
     LEFT JOIN gux gx ON gx.emp =
        CASE
            WHEN upper(COALESCE(i.marca, ''::text)) = 'CH'::text THEN 'CH'::text
            ELSE 'LK'::text
        END AND gx.c = gv_cod_stock(i.cod_art)
     LEFT JOIN pe p ON p.cod_norm = gv_cod_stock(i.cod_art) AND p.empresa =
        CASE
            WHEN upper(COALESCE(i.marca, ''::text)) = 'CH'::text THEN 'chef'::text
            ELSE 'lk'::text
        END
     LEFT JOIN partes pt ON pt.cod = upper(i.cod_art)
     LEFT JOIN gv_importados_stock_insumos si ON upper(si.cod) = upper(i.cod_art) AND i.principal AND i.activo AND (upper(COALESCE(i.marca, ''::text)) = 'CH'::text OR NOT (EXISTS ( SELECT 1
           FROM ch_rows c
          WHERE c.cod = upper(i.cod_art))))
     LEFT JOIN LATERAL ( SELECT sum(sc.cantidad * e_mismo.factor) AS stock_gp2
           FROM ( SELECT e0.componente_codigo,
                    e0.factor
                   FROM "GV_Importados_Equiv_GP2" e0
                  WHERE upper(e0.importado_cod) = upper(i.cod_art)
                UNION ALL
                 SELECT i.cod_art AS componente_codigo,
                    1::numeric AS factor
                  WHERE NOT (EXISTS ( SELECT 1
                           FROM "GV_Importados_Equiv_GP2" e1
                          WHERE upper(e1.importado_cod) = upper(i.cod_art) AND upper(e1.componente_codigo) = upper(i.cod_art))) AND NOT (EXISTS ( SELECT 1
                           FROM dup
                          WHERE dup.cod_norm = gv_cod_stock(i.cod_art)))) e_mismo
             JOIN gv_gp2_stock_componente sc ON upper(sc.codigo) = upper(e_mismo.componente_codigo)
          WHERE i.principal AND i.activo) g2 ON true
     LEFT JOIN conv cv ON cv.imp = upper(i.cod_art) AND i.principal AND i.activo
     LEFT JOIN gv_piezas_reparto_share sh ON sh.grupo = upper(i.cod_art) AND sh.cod_art = upper(i.cod_art) AND sh.empresa =
        CASE
            WHEN upper(COALESCE(i.marca, ''::text)) = 'CH'::text THEN 'CH'::text
            ELSE 'LK'::text
        END;

-- 6) cartel de la página (backup de la anterior: zz_backups."GV_Backup_ReingresosFeed_def_20261007") ------
CREATE OR REPLACE FUNCTION public.gv_reingresos_feed(p_emp text)
 RETURNS TABLE(cod text, reingreso_est date, sin_stock boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- Cartel "Sin stock / hasta dd/mm" de importados para la página de p_emp ('LK' o 'CH').
  -- v21.95 (Luis, 23/09): SIN STOCK = disponible <= 0 O pedidos >= disponible.
  -- Demanda = NP de ISIS + NP web programadas, menos facturadas.
  -- DUALES (codigos_duales): stock y pedidos de la pila de ESA empresa; un pedido con
  -- L (438EL) es de LK, si no manda la empresa de la NP. Los no duales: todo el artículo.
  -- v28.43 (Luis, 07/10): las PIEZAS de Cervantes (GV_Importados_Equiv_GP2 + mismo código) y los
  -- INSUMOS de Virgilio (gv_importados_stock_insumos) cuentan como stock. Si las comparten varios
  -- artículos (GV_Piezas_Reparto: 942E/633E…, 438E LK/CH…) cada uno se lleva su % por E.M. del mes,
  -- y el que comparte sin ser importado (633E) también lleva cartel, con la fecha del importado.
  with _rf_emp as (select upper(btrim(p_emp)) as e),
  _rf_sh as materialized (select * from public.gv_piezas_reparto_share),
  _rf_sc as materialized (select upper(codigo) as c, sum(cantidad) as cantidad from public.gv_gp2_stock_componente group by upper(codigo)),
  imp0 as (
    select gv_cod_stock(cod_art) as cod,
           max(reingreso_est)         as reingreso_est,
           max(nullif(uni_x_caja, 0)) as uxc
    from public."Importados", _rf_emp x
    where coalesce(activo, true)
      and case when x.e = 'CH' then upper(coalesce(marca, '')) = 'CH'
               else upper(coalesce(marca, '')) <> 'CH' end
    group by gv_cod_stock(cod_art)
  ),
  imp as materialized (
    select i0.cod, i0.reingreso_est, i0.uxc from imp0 i0
    union all
    select gv_cod_stock(sh.cod_art), max(io.reingreso_est), max(sh.uxb)
    from _rf_sh sh
    cross join _rf_emp x
    join public."Importados" io on coalesce(io.activo, true) and upper(btrim(io.cod_art)) = sh.grupo
    where sh.empresa = x.e and gv_cod_stock(sh.cod_art) not in (select i0.cod from imp0 i0)
    group by gv_cod_stock(sh.cod_art)
  ),
  _rf_g as materialized (
    select i.cod, coalesce(sh.grupo, upper(i.cod)) as grupo, coalesce(sh.share, 1) as share
    from imp i cross join _rf_emp x
    left join _rf_sh sh on gv_cod_stock(sh.cod_art) = i.cod and sh.empresa = x.e
  ),
  _rf_dup as (
    select gv_cod_stock(cod_art) as cod from public."Importados"
    where principal and activo group by gv_cod_stock(cod_art) having count(*) > 1
  ),
  _rf_gp2 as materialized (
    select g.grupo, sum(sc.cantidad * e.factor) as uni
    from (select distinct grupo from _rf_g) g
    join lateral (
      select e0.componente_codigo, e0.factor from public."GV_Importados_Equiv_GP2" e0
       where upper(e0.importado_cod) = g.grupo
      union all
      select g.grupo, 1::numeric
       where not exists (select 1 from public."GV_Importados_Equiv_GP2" e1
                          where upper(e1.importado_cod) = g.grupo and upper(e1.componente_codigo) = g.grupo)
         and not exists (select 1 from _rf_dup d where d.cod = gv_cod_stock(g.grupo))
    ) e on true
    join _rf_sc sc on sc.c = upper(e.componente_codigo)
    group by g.grupo
  ),
  _rf_ins as materialized (
    select upper(si.cod) as grupo, sum(si.stock_uni) as uni
    from public.gv_importados_stock_insumos si
    where upper(si.cod) in (select grupo from _rf_g)
    group by upper(si.cod)
  ),
  _rf_dual as (select gv_cod_stock(d.cod) as cod from public.codigos_duales d),
  _rf_stk as (
    select gv_cod_stock(s.cod_art) as cod,
           sum(coalesce(s.terminado,0) + coalesce(s.excedente,0) + coalesce(s.separar_pedidos,0)
             + coalesce(s.a_facturar,0) + coalesce(s.a_guardar,0) + coalesce(s.racks,0)
             + coalesce(s.racks_ch,0) + coalesce(s.para_envasar,0)) as stock
    from public.vista_saldos_stock s, _rf_emp x
    where gv_cod_stock(s.cod_art) not in (select cod from _rf_dual)
       or upper(coalesce(s.empresa,'')) = x.e
    group by gv_cod_stock(s.cod_art)
  ),
  -- v24.84 (Luis 30/09): una regla por fila de Importados_Stock_Parte ("el stock de la parte cuenta como
  -- stock del producto"), con su conversion: parte_x_caja = unidades de la parte por CAJA del producto
  -- (NULL = la UxB del producto, o sea 1 unidad de la parte por unidad). Es POSIBILIDAD de armar: sólo apaga el cartel.
  -- v28.43: la parte es del GRUPO (942P sirve al 942E y al 633E) y cada uno toma su %.
  parte as materialized (
    select gv_cod_stock(sp.terminado) as cod, sp.parte_x_caja,
           greatest(0, coalesce(mv.s, 0)) as stock_parte
    from public."Importados_Stock_Parte" sp
    left join (select ltrim(upper(btrim(m.cod_art)), '0') as c, sum(m.delta) as s from public."Movimientos_Stock" m
                where ltrim(upper(btrim(m.cod_art)), '0') in (select ltrim(upper(btrim(x.parte)), '0') from public."Importados_Stock_Parte" x)
                group by 1) mv on mv.c = ltrim(upper(btrim(sp.parte)), '0')
  ),
  _rf_pend as (
    select btrim(np) as np from public."GV_PPP_Programacion_Diaria" where np is not null
    union
    select (case when lower(empresa) = 'lk' then 'LK ' else 'CH ' end) || lpad(np::text, 4, '0')
      from public."PPP_Web_Programacion" where np is not null
  ),
  _rf_dem as (
    select gv_cod_stock(b.articulo) as cod, sum(coalesce(b.cajas, 0)) as pedidos
    from public.gv_demanda_pedidos b
    join _rf_pend p on p.np = btrim(b.pedido)
    cross join _rf_emp x
    where nullif(btrim(b.articulo), '') is not null
      and not exists (select 1 from public."Facturacion_NP" f where btrim(f.np) = p.np)
      and ( gv_cod_stock(b.articulo) not in (select cod from _rf_dual)
            or (case when upper(btrim(b.articulo)) ~ '[0-9E]L$' then 'LK'
                     when gv_empresa_de_np_texto(p.np) = 'chef' then 'CH'
                     else 'LK' end) = x.e )
    group by gv_cod_stock(b.articulo)
  ),
  -- v24.91 (Luis 30/09): el cartel toma la fecha MÁS TEMPRANA entre el pedido del producto y el de
  -- sus partes (la parte es un importado con ese código, o un insumo vinculado a su pedido por GV_Importados_Insumo_Map)
  _rf_pfecha as (
    select gv_cod_stock(sp.terminado) as cod, min(im.reingreso_est) as f
    from public."Importados_Stock_Parte" sp
    join public."Importados" im on coalesce(im.activo, true) and im.reingreso_est is not null
     and (upper(btrim(im.cod_art)) = upper(btrim(sp.parte))
          or upper(btrim(im.cod_art)) in (select upper(btrim(m.importado_cod)) from public."GV_Importados_Insumo_Map" m
                                          where upper(btrim(m.insumo_cod)) = upper(btrim(sp.parte))))
    group by 1
  ),
  _rf_disp as (
    select i.cod, i.reingreso_est,
           coalesce(st.stock, 0)
             + coalesce((select sum(floor(pt.stock_parte * g.share / nullif(coalesce(pt.parte_x_caja, i.uxc), 0)))
                          from parte pt where pt.cod = gv_cod_stock(g.grupo)), 0)
             + coalesce(floor(coalesce(gp.uni, 0) * g.share / nullif(i.uxc, 0)), 0)
             + coalesce(floor(greatest(coalesce(ins.uni, 0), 0) * g.share / nullif(i.uxc, 0)), 0) as disponible,
           coalesce(d.pedidos, 0) as pedidos
    from imp i
    join _rf_g g on g.cod = i.cod
    left join _rf_stk st on st.cod = i.cod
    left join _rf_dem d on d.cod = i.cod
    left join _rf_gp2 gp on gp.grupo = g.grupo
    left join _rf_ins ins on ins.grupo = g.grupo
  )
  select cod, least(reingreso_est, (select pf.f from _rf_pfecha pf where pf.cod = _rf_disp.cod)) as reingreso_est,
         (disponible <= 0 or pedidos >= disponible) as sin_stock
  from _rf_disp
  -- Luis 23/09: codigos sin cartel ni pedido partido (tabla editable)
  where not exists (select 1 from public."GV_Reingreso_Excluido" x where x.cod = _rf_disp.cod);
$function$;

-- Rollback del cartel: select def from zz_backups."GV_Backup_ReingresosFeed_def_20261007"; → execute.
-- Chequeo: select * from public.gv_piezas_reparto_share order by grupo, empresa desc;
--          select * from public.gv_reglas_perdidas;   -- vacía

-- =====================================================================================================
-- v28.44 (Luis, 07/10): 323E / 838E "los dos lo ven, pero el split es 0-100 — y es así para todas las
-- partes; se netea con Art Term en Cervantes, así que contempla de la misma forma 0-100 esos".
--   · un pozo único, dueño 838E: GRJ31 + 838E y 323E terminados de GP2 + parte 323ES
--   · GV_Piezas_Reparto con peso_fijo: 838E CH 1 · 323E LK 0
insert into public."GV_Piezas_Reparto"(grupo,cod_art,empresa,peso_fijo,nota) values
  ('838E','838E','CH',1,'v28.44 Luis 07/10: pozo GRJ31 + 323E/838E terminados GP2 + parte 323ES; 0-100 fijo'),
  ('838E','323E','LK',0,'v28.44 Luis 07/10: lo ve pero le toca 0 %')
on conflict do nothing;
insert into public."GV_Importados_Equiv_GP2"(importado_cod, componente_codigo, factor, nota, creado_por)
  values ('838E','323E',1,'v28.44 Luis 07/10: el terminado 323E de Cervantes netea en el pozo del 838E','Luis (claude)')
on conflict do nothing;
--   · gv_piezas_reparto_share: reparto dice "323E LK 0 % (fijo) · 838E CH 100 % (fijo)" (m4 + share en texto)
--   · gv_importados_ordenes: el miembro usa las piezas del DUEÑO de su pozo (lateral g2 con
--     COALESCE((select upper(r.grupo) from "GV_Piezas_Reparto" r where cod_art = i.cod_art and empresa), cod_art)),
--     el join a la vista es por cod_art + empresa (sin sh.grupo = cod_art) y columna nueva piezas_grupo.
--   · gv_reingresos_feed: SE SACA el cartel automático del que comparte sin ser importado (633E…):
--     "yo controlo los carteles en la página con los botones" (Luis, D4/D5). El cartel es sólo de importados.
-- Se aplicó como parche sobre la definición viva (idempotente); las definiciones vivas mandan.
