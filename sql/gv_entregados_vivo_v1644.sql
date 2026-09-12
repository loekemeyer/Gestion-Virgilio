-- ============================================================================
-- v16.44 — Se corta el espejo muerto: "entregado" pasa a salir de Recepción Remitos
-- Proyecto Supabase: hrxfctzncixxqmpfhskv (Gestion Virgilio)
--
-- POR QUE
-- -------
-- Dueño, 2026-09-12: "la hoja PPP entregados ya dejó de existir, porque ya no se usa
-- más esa tabla, ya que fue el cambio fundamental entre el repositorio gestión Virgilio
-- y producción Virgilio".
--
-- El cron 27 (sync-ppp-entregados-meta) esta en active=false y "PPP_Entregados_Meta"
-- quedo congelada el 2026-09-02. Pero seguia cableada en 16 objetos y la app la leia en
-- 6 lugares, asi que:
--   * la pantalla de Entregados estaba congelada en el 02/09
--   * Recepcion Remitos no tenia el nombre del cliente de las NP posteriores
--   * vista_tanda_m3 se comia 32 tandas web (20,71 m3) porque solo miraba ISIS
--
-- El CLAUDE.md (Quick-ref) y la GUIA todavia decian que el Sheet era el upstream vivo.
-- Eso es lo que hizo que se tratara al espejo muerto como si estuviera vivo; se corrigio
-- en el mismo commit.
--
-- QUE SE HIZO
-- -----------
-- 1) gv_ppp_entregados_meta pasa a ser: historico del Sheet UNION entregados VIVOS por
--    Recepcion Remitos (opcion='CRN'), resolviendo cod/rs/tanda/m3 desde la programacion
--    viva (ISIS via gv_ppp_programacion_diaria, web via "PPP_Web_Programacion") y, si la
--    NP ya no esta ahi, desde "Facturacion_NP". Columna nueva `fuente` = 'hoja' | 'remito'.
--    Con eso los 6 usos de la app quedan bien sin tocar el front.
-- 2) vista_tanda_m3 suma "PPP_Web_Programacion" como tercera fuente del COALESCE.
--
-- La tabla "PPP_Entregados_Meta" NO se borra: queda como historia (2.783 filas hasta el
-- 02/09) y es el primer termino del COALESCE para las tandas viejas.
--
-- MEDICION (2026-09-12, antes -> despues)
-- ----------------------------------------
--   gv_ppp_entregados_meta   2783 -> 2866   (+83 entregas vivas; las 83 con cod, rs,
--                                            tanda y m3 resueltos, ninguna en blanco)
--   vista_tanda_m3 filas     1164 -> 1196   (+32 tandas web)
--   vista_tanda_m3 m3        1020 -> 1041   (+20,71)
--   gv_clientes_habituales    615 ->  629
--   gv_ppp_entregados         426 ->  426   (sin cambio: ya era CRN)
--   gv_ppp_en_salida           20 ->   20   (sin cambio)
--
-- Backup de las definiciones previas: zz_backups."GV_Backup_defs_entmeta_20260912".
--
-- NOTA sobre la cadena de demanda: "cerradas" de vista_stock_procesada usa la TABLA cruda,
-- no esta vista, asi que este cambio no la toca. Se midio aparte que sacar el espejo de
-- "cerradas" mueve la demanda 1 caja (NP 98275 art 501, entregada el 31/07 y nunca
-- facturada), o sea que ese cableado tambien se puede cortar cuando se quiera.
-- ============================================================================

-- ============ gv_ppp_entregados_meta ============
create or replace view public.gv_ppp_entregados_meta with (security_invoker = true) as
with hist as (
  select m.np, m.cod, m.rs, m.updated_at, m.tanda, m.m3, m.fecha_entrega, 'hoja'::text as fuente
    from public."PPP_Entregados_Meta" m
    cross join public.gv_espejo_corte() c(lk, chef)
   where public.gv_espejo_np_pasa(m.np, c.lk, c.chef)
     and not exists (select 1 from public."GV_PPP_Prog_Override" o
                      where o.oculto and o.np = regexp_replace(btrim(m.np), '\.0+$', ''))
), crn as (
  select regexp_replace(upper(btrim(split_part(r.texto,'|',1))),'\.0+$','') as np,
         max(r.ts_cliente) as ts,
         max((r.ts_cliente at time zone 'America/Argentina/Buenos_Aires')::date) as fecha
    from public."Registros_Produccion_Virgilio" r
   where r.opcion = 'CRN' and nullif(btrim(coalesce(r.texto,'')),'') is not null
     and not public.es_legajo_test(r.legajo)
   group by 1
), vivo as (
  select k.np,
         coalesce(i.cod, w.cod_cliente, f.cod_cliente)            as cod,
         coalesce(i.razon_social, w.razon_social, f.razon_social) as rs,
         k.ts                                                     as updated_at,
         coalesce(i.tanda, w.tanda, f.tanda)                      as tanda,
         coalesce(i.m3, w.m3, f.m3)                               as m3,
         k.fecha::text                                            as fecha_entrega,
         'remito'::text                                           as fuente
    from crn k
    left join lateral (select g.cod, g.razon_social, g.tanda, g.m3
                         from public.gv_ppp_programacion_diaria g
                        where regexp_replace(btrim(g.np),'\.0+$','') = k.np limit 1) i on true
    left join lateral (select p.cod_cliente, p.razon_social, p.tanda, p.m3
                         from public."PPP_Web_Programacion" p
                        where public.gv_ppp_web_np_label(p.empresa,p.np,p.np_idx) = k.np limit 1) w on true
    left join lateral (select x.cod_cliente, x.razon_social, x.tanda, x.m3
                         from public."Facturacion_NP" x
                        where regexp_replace(upper(btrim(x.np)),'\.0+$','') = k.np limit 1) f on true
   where not exists (select 1 from hist h where regexp_replace(btrim(h.np),'\.0+$','') = k.np)
)
select np, cod, rs, updated_at, tanda, m3, fecha_entrega, fuente from hist
union all
select np, cod, rs, updated_at, tanda, m3, fecha_entrega, fuente from vivo;
grant select on public.gv_ppp_entregados_meta to anon, authenticated, service_role;

-- ============ vista_tanda_m3 ============
-- Orden del COALESCE: entregado historico (hoja) -> programado ISIS -> programado web.
-- La columna `entregado` sigue significando "el m3 salio del historico"; la app nunca la
-- selecciona (todos los usos son select=tanda,m3).
create or replace view public.vista_tanda_m3 with (security_invoker = true) as
with ent as (
  select upper(btrim(m.tanda)) as tanda, sum(m.m3) as m3
    from public."PPP_Entregados_Meta" m
   where m.m3 > 0 and btrim(coalesce(m.tanda,'')) <> '' group by 1
), prog as (
  select upper(btrim(p.tanda)) as tanda, sum(p.m3) as m3
    from public."PPP_Programacion_Diaria" p
   where p.m3 > 0 and btrim(coalesce(p.tanda,'')) <> '' group by 1
), web as (
  select upper(btrim(w.tanda)) as tanda, sum(w.m3) as m3
    from public."PPP_Web_Programacion" w
   where w.m3 > 0 and btrim(coalesce(w.tanda,'')) <> '' group by 1
), u as (
  select tanda from ent union select tanda from prog union select tanda from web
)
select u.tanda,
       round(coalesce(e.m3, p.m3, b.m3), 3) as m3,
       e.m3 is not null as entregado
  from u
  left join ent  e on e.tanda = u.tanda
  left join prog p on p.tanda = u.tanda
  left join web  b on b.tanda = u.tanda
 where coalesce(e.m3, p.m3, b.m3) > 0;
grant select on public.vista_tanda_m3 to anon, authenticated, service_role;

-- ============ Verificacion ============
-- select * from public.gv_endpoints_rotos;   -- vacio = nada roto
-- select fuente, count(*) from public.gv_ppp_entregados_meta group by 1;  -- hoja 2783 | remito 83
-- select count(*), round(sum(m3)) from public.vista_tanda_m3;             -- 1196 | 1041
