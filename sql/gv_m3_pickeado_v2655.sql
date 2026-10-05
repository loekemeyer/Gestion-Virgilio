-- =====================================================================================================
-- v26.55 (Luis, 04/10/2026): «Una vez que ya se pickea, ya no se mira más el dato de los m³ del pedido
-- entero. Se analiza con los m³ PICKEADOS y nada más, porque lo que se carga en el camión es lo pickeado,
-- no lo que había pedido el cliente. El camión se pide en función de lo pickeado.»
--
-- Retira lo de la v26.51 «el armado no se prorratea»: desde acá, una tanda con TP vale su m³ pickeado
-- en TODO (picking, armado, carga, días, camiones, Programación, Resumen de la PPP).
--
-- APLICADO el 05/10 desde la sesión (el pedido es la autorización, regla del 04/10). Idempotente.
-- Lo del front (TV, Mon. Admin, monitor del index, PPP) va en el mismo commit.
-- =====================================================================================================

-- 1) La fracción pickeada por tanda: caché GV_Picking_Tanda + en vivo el TP de las últimas 48 h que la
--    caché (cron gv-picking-tanda-refresh, c/10 min) todavía no tiene. Sin fila = sin pickear = ×1.
create or replace function public.gv_tanda_m3_pickeado(p_tandas text[] default null)
returns table (tanda text, fraccion numeric, tp timestamptz, calc_at timestamptz)
language sql stable security definer set search_path = public as $fn$
  -- v26.55 (Luis, 04/10): «una vez que se pickea, ya no se mira más el m³ del pedido: se analiza con el m³
  -- PICKEADO y nada más, porque lo que se carga en el camión es lo pickeado». Por tanda pickeada (con TP), la
  -- fracción en m³ de lo pedido que se pickeó: de la caché GV_Picking_Tanda (cron gv-picking-tanda-refresh c/10
  -- min; último PKC por código) y, para un TP de las últimas 48 h que la caché todavía no tiene, en vivo con
  -- gv_picking_pickeado. Sin fila = todavía no pickeada = m³ del pedido (×1). Sólo lectura.
  with c as (
    select distinct on (t.tanda) t.tanda, least(1, greatest(0, t.m3_frac))::numeric fr, t.tp, t.calc_at
      from public."GV_Picking_Tanda" t
     where t.m3_frac is not null
       and (p_tandas is null or t.tanda = any (select upper(btrim(x)) from unnest(p_tandas) x))
     order by t.tanda, t.tp desc),
  tpv as (
    select upper(btrim(r.texto)) tanda, max(r.ts_cliente) tp
      from public."Registros_Produccion_Virgilio" r
     where r.opcion = 'TP' and r.ts_cliente >= now() - interval '48 hours'
       and coalesce(r.legajo::text, '') not in ('0', '1')
       and (p_tandas is null or upper(btrim(r.texto)) = any (select upper(btrim(x)) from unnest(p_tandas) x))
     group by 1),
  falta as (select array_agg(v.tanda) arr from tpv v where not exists (select 1 from c where c.tanda = v.tanda)),
  viva as (
    select p.tanda, least(1, greatest(0, p.fraccion))::numeric fr
      from falta, public.gv_picking_pickeado(falta.arr) p
     where falta.arr is not null)
  select c.tanda, c.fr, c.tp, c.calc_at from c
  union all
  select v.tanda, v.fr, t.tp, now() from viva v join tpv t on t.tanda = v.tanda
$fn$;
revoke all on function public.gv_tanda_m3_pickeado(text[]) from public;
grant execute on function public.gv_tanda_m3_pickeado(text[]) to anon, authenticated;

-- 2) vista_tanda_m3 (la leen vista_productividad_diaria/_semanal, gv_horas_operario_detalle(_v2),
--    gv_horas_operario_tandas_v2, gv_ppp_atrasados, reporte_agentes_evento_imposible): m3 = lo pickeado;
--    las dos columnas nuevas van AL FINAL (m3_pedido, fraccion).
create or replace view public.vista_tanda_m3 as
 WITH ent AS (
         SELECT upper(btrim(m.tanda)) AS tanda, sum(m.m3) AS m3
           FROM "GV_PPP_Entregados_Historico" m
          WHERE m.m3 > 0::numeric AND btrim(COALESCE(m.tanda, ''::text)) <> ''::text
          GROUP BY (upper(btrim(m.tanda)))
        ), prog AS (
         SELECT upper(btrim(p_1.tanda)) AS tanda, sum(p_1.m3) AS m3
           FROM gv_ppp_programacion_diaria p_1
          WHERE p_1.m3 > 0::numeric AND btrim(COALESCE(p_1.tanda, ''::text)) <> ''::text
          GROUP BY (upper(btrim(p_1.tanda)))
        ), web AS (
         SELECT upper(btrim(w.tanda)) AS tanda, sum(w.m3) AS m3
           FROM "PPP_Web_Programacion" w
          WHERE w.m3 > 0::numeric AND btrim(COALESCE(w.tanda, ''::text)) <> ''::text
          GROUP BY (upper(btrim(w.tanda)))
        ), u AS (
         SELECT ent.tanda FROM ent UNION SELECT prog.tanda FROM prog UNION SELECT web.tanda FROM web
        ), pf AS (
         SELECT z.tanda, z.fraccion FROM gv_tanda_m3_pickeado(NULL::text[]) z(tanda, fraccion, tp, calc_at)
        )
 SELECT u.tanda,
    round(COALESCE(p.m3, b.m3, e.m3) * COALESCE(pf.fraccion, 1::numeric), 3) AS m3,
    e.m3 IS NOT NULL AND p.m3 IS NULL AND b.m3 IS NULL AS entregado,
    round(COALESCE(p.m3, b.m3, e.m3), 3) AS m3_pedido,
    pf.fraccion
   FROM u
     LEFT JOIN ent e ON e.tanda = u.tanda
     LEFT JOIN prog p ON p.tanda = u.tanda
     LEFT JOIN web b ON b.tanda = u.tanda
     LEFT JOIN pf ON pf.tanda = u.tanda
  WHERE COALESCE(p.m3, b.m3, e.m3) > 0::numeric;
alter view public.vista_tanda_m3 set (security_invoker = true);

-- 3) gv_monitor_tanda_camion: el camión (y la unión Z2+Z3 < 1 m³) con el m³ PICKEADO.
--    Parche por texto sobre la definición viva, idempotente; falla si el texto no matchea.
do $p$ declare d text; n text; begin
  d := pg_get_viewdef('public.gv_monitor_tanda_camion'::regclass, true);
  if d ~ 'gv_tanda_m3_pickeado' then raise notice 'gv_monitor_tanda_camion ya tiene la regla'; return; end if;
  n := replace(d, 'sum(src.m3) AS m3,', 'sum(src.m3) * COALESCE(max(pf.fraccion), 1::numeric) AS m3,');
  n := replace(n, E'FROM src\n          GROUP BY src.tanda, src.fecha',
    E'FROM src\n             LEFT JOIN ( SELECT z.tanda, z.fraccion FROM public.gv_tanda_m3_pickeado(NULL::text[]) z(tanda, fraccion, tp, calc_at)) pf ON pf.tanda = src.tanda\n          GROUP BY src.tanda, src.fecha');
  if n = d or n !~ 'gv_tanda_m3_pickeado' or n !~ 'max\(pf\.fraccion\)' then raise exception 'gv_monitor_tanda_camion: el texto no matchea, no se aplicó'; end if;
  execute 'create or replace view public.gv_monitor_tanda_camion as ' || n;
  execute 'alter view public.gv_monitor_tanda_camion set (security_invoker = true)';
end $p$;

-- 4) gv_ppp_prog_arbol (Programación de la PPP y resumen de días de la TV): la NP de una tanda pickeada
--    lleva el m³ pickeado (fracción de su tanda). Protegida: va con la marca del hook.
-- REGLA_CONFIRMADA_POR_USUARIO
do $p$ declare d text; n text; begin
  d := pg_get_functiondef('public.gv_ppp_prog_arbol'::regproc);
  if d ~ 'gv_tanda_m3_pickeado' then raise notice 'gv_ppp_prog_arbol ya tiene la regla'; return; end if;
  n := replace(d, 'select d.fe_dia as fe, d.np, d.tanda, d.m3, d.cod,',
                  'select d.fe_dia as fe, d.np, d.tanda, round(d.m3 * coalesce(pf.fraccion, 1::numeric), 3) as m3, d.cod,');
  n := replace(n, E'    left join public."GV_PPP_NP_Estado" he on he.np = upper(d.np)\n',
    E'    left join public."GV_PPP_NP_Estado" he on he.np = upper(d.np)\n    -- v26.55 (Luis, 04/10): una tanda PICKEADA vale su m³ pickeado (lo que sube al camión), no el del pedido\n    left join (select z.tanda, z.fraccion from public.gv_tanda_m3_pickeado(null) z) pf on pf.tanda = d.tanda and d.tanda <> \'\'\n');
  if n = d or (length(n) - length(replace(n, 'gv_tanda_m3_pickeado', ''))) / 20 <> 1 then
    raise exception 'gv_ppp_prog_arbol: el texto no matchea, no se aplicó'; end if;
  execute n;
end $p$;

-- 5) Centinelas (ids 292-295 al aplicarse)
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
select v.* from (values
  ('vista_tanda_m3','vista','gv_tanda_m3_pickeado','Una vez pickeada, la tanda vale su m³ PICKEADO (fracción de gv_tanda_m3_pickeado), no el del pedido: lo que se carga en el camión es lo pickeado','Luis','v26.55'),
  ('gv_monitor_tanda_camion','vista','gv_tanda_m3_pickeado','El camión del día se arma con el m³ PICKEADO de cada tanda, no con el del pedido','Luis','v26.55'),
  ('gv_ppp_prog_arbol','funcion','gv_tanda_m3_pickeado','La NP de una tanda pickeada va con el m³ PICKEADO (fracción de su tanda) en la Programación y el resumen de días','Luis','v26.55'),
  ('gv_tanda_m3_pickeado','funcion','gv_picking_pickeado','El TP reciente que la caché todavía no tiene se calcula en vivo (gv_picking_pickeado): sin eso, la tanda recién pickeada vale el m³ del pedido hasta 10 min','Luis','v26.55')
) v(objeto, clase, patron, regla, quien_pidio, version)
where not exists (select 1 from public."GV_Reglas_Centinela" c where c.objeto = v.objeto and c.patron = v.patron);

-- Chequeo:
--   select * from public.gv_reglas_perdidas;                                  -- vacía
--   select * from public.gv_tanda_m3_pickeado(null) where calc_at > now() - interval '1 minute';  -- las vivas
--   select tanda, m3, m3_pedido, fraccion from public.vista_tanda_m3 where fraccion < 1 order by fraccion limit 20;
-- Medido el 05/10 como anon: gv_tanda_m3_pickeado 33 ms · vista_tanda_m3 40 ms · gv_monitor_tanda_camion 59 ms ·
-- gv_ppp_prog_arbol 451 ms. 356 tandas con fracción, media 0,906.
--
-- ROLLBACK (vuelve al m³ del pedido en todos lados; el front cae solo a ×1 si la función no existe):
--   delete from public."GV_Reglas_Centinela" where version = 'v26.55';   -- primero, o el hook frena
--   -- gv_ppp_prog_arbol: replace inverso del paso 4 (sacar el join pf y volver a «d.m3,»)
--   -- gv_monitor_tanda_camion: replace inverso del paso 3
--   -- vista_tanda_m3: m3 = round(COALESCE(p.m3, b.m3, e.m3), 3) (las 2 columnas del final pueden quedar)
--   drop function public.gv_tanda_m3_pickeado(text[]);
