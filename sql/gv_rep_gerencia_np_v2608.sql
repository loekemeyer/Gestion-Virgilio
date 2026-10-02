-- v26.08 (Luis, 02/10/2026) — vista para los REPORTES DE GERENCIA (Telegram, chat privado de gerencia).
-- La lee el proyecto de LK por el FDW (rol lk_ppp_reader) como virgilio.gv_rep_gerencia_np, desde
-- pagina-LK-copia/sql/reporte_gerencia_v2.sql.
--
-- Una fila por NP con el PEDIDO al que pertenece y cuando salio:
--   salio_el   = primera Carga Camion (CCN) de la NP, que es lo que Gestion llama "Salio".
--                Medido: el 100 % de las NP web ya entregadas (164, Retira incluidos) tiene su CCN, y
--                todas las NP con CCN desde julio estan en la vista.
--   pedido_key = web: empresa:order_id (un pedido grande son varias NP: sept, 347 NP = 220 pedidos);
--                ISIS: empresa:cod_cliente:tanda (la NP tipeada en ISIS no trae pedido).
--
-- Objeto NUEVO: no toca ninguna tabla ni vista existente. security_invoker = true; lk_ppp_reader ya tenia
-- SELECT y policy en las cuatro tablas que lee (verificado: LK ve las 1.626 filas, las mismas que postgres).
create view public.gv_rep_gerencia_np with (security_invoker = true) as
with ccn as (
  select upper(btrim(split_part(r.texto, '|', 1))) as np,
         min((r.ts_cliente at time zone 'America/Argentina/Buenos_Aires')::date) as salio_el
    from public."Registros_Produccion_Virgilio" r
   where r.opcion = 'CCN' and not public.es_legajo_test(r.legajo)
     and btrim(split_part(r.texto, '|', 1)) <> ''
   group by 1),
fac as (
  select regexp_replace(upper(btrim(f.np)), '\.0+$', '') as np,
         max(f.cod_cliente) as cod_cliente, max(f.tanda) as tanda, sum(f.m3) as m3,
         min((f.facturado_at at time zone 'America/Argentina/Buenos_Aires')::date) as facturado_el
    from public."Facturacion_NP" f where f.np is not null group by 1),
web as (
  select lower(w.empresa) as empresa,
         upper(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx)) as np,
         w.order_id, w.cod_cliente, w.tanda, w.zona, w.fecha_entrega, w.m3, w.cajas,
         (c.order_id is not null) as cancelado
    from public."PPP_Web_Programacion" w
    left join (select distinct empresa, order_id from public."GV_Web_Cancelados") c
           on c.empresa = w.empresa and c.order_id = w.order_id),
isis_prog as (
  select regexp_replace(btrim(g.np), '\.0+$', '') as np,
         case when btrim(g.np) ~ '^4' then 'chef' else 'lk' end as empresa,
         g.cod as cod_cliente, g.tanda, g.zona,
         nullif(left(g.fecha_entrega, 10), '')::date as fecha_entrega, g.m3
    from public.gv_ppp_programacion_diaria g),
isis as (
  select coalesce(p.np, f.np) as np,
         coalesce(p.empresa, case when coalesce(p.np, f.np) ~ '^4' then 'chef' else 'lk' end) as empresa,
         coalesce(p.cod_cliente, f.cod_cliente) as cod_cliente, coalesce(p.tanda, f.tanda) as tanda,
         p.zona, p.fecha_entrega, coalesce(p.m3, f.m3) as m3
    from isis_prog p
    full join (select * from fac where np !~ '^(LK|CH) ') f on f.np = p.np)
select w.empresa, true as es_web, w.np, w.order_id, w.empresa || ':' || w.order_id as pedido_key,
       w.cod_cliente, w.tanda, w.zona, w.fecha_entrega, w.m3, w.cajas, f.facturado_el, c.salio_el, w.cancelado
  from web w left join fac f on f.np = w.np left join ccn c on c.np = w.np
union all
select i.empresa, false, i.np, null::bigint,
       i.empresa || ':' || coalesce(i.cod_cliente, '?') || ':' || coalesce(i.tanda, i.np),
       i.cod_cliente, i.tanda, i.zona, i.fecha_entrega, i.m3, null::numeric, f.facturado_el, c.salio_el, false
  from isis i left join fac f on f.np = i.np left join ccn c on c.np = i.np;

revoke all on public.gv_rep_gerencia_np from anon, authenticated;
grant select on public.gv_rep_gerencia_np to lk_ppp_reader;

-- Chequeo: todas las NP con CCN tienen que estar en la vista (nps_ccn = en_vista).
-- with c as (select upper(btrim(split_part(texto,'|',1))) np, min((ts_cliente at time zone 'America/Argentina/Buenos_Aires')::date) d
--              from public."Registros_Produccion_Virgilio" where opcion='CCN' and not public.es_legajo_test(legajo) group by 1)
-- select date_trunc('month', c.d)::date mes, count(*) nps_ccn, count(g.np) en_vista
--   from c left join public.gv_rep_gerencia_np g on g.np = c.np where c.d >= '2026-07-01' group by 1 order by 1;
--
-- ROLLBACK (antes, en LK: drop foreign table virgilio.gv_rep_gerencia_np):
-- drop view if exists public.gv_rep_gerencia_np;
