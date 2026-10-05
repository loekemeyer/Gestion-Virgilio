-- =====================================================================================
-- v26.67 · «FRENAR la tanda» — parte 3: CRÉDITO por operario y día (Luis, 2026-10-05, D6)
-- Proyecto Gestión Virgilio (hrxfctzncixxqmpfhskv). APLICADO el 05/10 (el pedido es la autorización).
--
-- Una tanda FRENADA la hicieron varios (o el mismo en varios días). Cada uno se lleva el m³ de lo
-- que hizo, en el día en que lo hizo:
--   picking: sus cajas pickeadas (el ÚLTIMO PKC de cada código) × m³/caja;
--   armado:  las cajas de los líos que cerró (lío.leg / lío.ts de GV_Armado_Avance); en súper /
--            retira (no arman líos), lo que separó cada uno (código.sepLeg / sepTs).
-- Una tanda SIN freno no sale acá: sigue entera al que dio el TP/TAP, como siempre.
--
-- Lectores (front): index.html gvCreditoTandas + gvM3ConCredito (fetchMonitorDayStats y
-- showDayBreakdown) y monitor/tv.html cargarCredito (≡). La parte de un operario entra cuando ÉL
-- cierra su tramo ese día (TP/TAP/PKF/APF) — mismo criterio de siempre: el m³ entra al cerrar.
-- Sin respuesta de la RPC → como antes (fail-open).
--
-- Centinelas 313-315.
-- =====================================================================================

-- REGLA_CONFIRMADA_POR_USUARIO (Luis, 05/10, D6)
CREATE OR REPLACE FUNCTION public.gv_tanda_credito(p_tandas text[])
 RETURNS TABLE(tanda text, fase text, legajo text, dia date, cajas numeric, m3 numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- v26.66-credito (Luis, 05/10, D6): una tanda FRENADA la hicieron varios (o el mismo en varios días).
  -- Cada uno se lleva lo que hizo, en el día en que lo hizo:
  --   picking: sus cajas pickeadas (el ÚLTIMO PKC de cada código; corregir pisa la fila y queda a
  --            nombre del que corrigió) × m³/caja (misma fuente que gv_picking_pickeado);
  --   armado:  las cajas de los líos que cerró (lío.leg / lío.ts de la copia del servidor); en
  --            súper / retira (no arman líos), la NP: lo que separó cada uno (código.sepLeg / sepTs).
  -- Sólo tandas con freno en esa fase: el resto sigue entero al que dio el TP/TAP.
  with t as (select distinct upper(btrim(x)) tanda from unnest(coalesce(p_tandas, '{}')) x where btrim(coalesce(x, '')) <> ''),
  fr as (select distinct z.tanda, z.fase from public."GV_Tanda_Freno" z join t on t.tanda = z.tanda),
  vol as (select regexp_replace(upper(btrim(codigo)), '^0+(?=.)', '') ck, max(m3) m3 from public.vista_volumen_articulo_resuelto group by 1),
  pk0 as (
    select upper(btrim(split_part(r.texto,'|',1))) tanda,
           regexp_replace(regexp_replace(regexp_replace(upper(btrim(split_part(r.texto,'|',2))), '\s+(LK|CH)$', ''), '([0-9E])L$', '\1'), '^0+(?=.)', '') ck,
           case when split_part(r.texto,'|',4) ~ '^[0-9]+(\.[0-9]+)?$' then split_part(r.texto,'|',4)::numeric else 0 end re,
           btrim(r.legajo) legajo, r.ts_cliente
      from public."Registros_Produccion_Virgilio" r
      join fr on fr.fase = 'picking' and fr.tanda = upper(btrim(split_part(r.texto,'|',1)))
     where r.opcion = 'PKC' and not public.es_legajo_test(r.legajo)
  ),
  pk as (select distinct on (tanda, ck) * from pk0 order by tanda, ck, ts_cliente desc),
  pkm as (select pk.*, coalesce(v.m3, avg(v.m3) over (partition by pk.tanda), 0) m3c from pk left join vol v on v.ck = pk.ck),
  ar0 as (
    select a.tanda, coalesce(nullif(btrim(y->>'leg'), ''), a.legajo) legajo,
           case when (y->>'ts') ~ '^[0-9]{11,}$' then to_timestamp((y->>'ts')::numeric / 1000) else a.ts_cliente end ts,
           regexp_replace(regexp_replace(regexp_replace(upper(btrim(it->>'cod')), '\s+(LK|CH)$', ''), '([0-9E])L$', '\1'), '^0+(?=.)', '') ck,
           greatest(0, coalesce(case when (it->>'qty') ~ '^[0-9]+(\.[0-9]+)?$' then (it->>'qty')::numeric end, 0)) c
      from public."GV_Armado_Avance" a
      join fr on fr.fase = 'armado' and fr.tanda = a.tanda
      cross join lateral jsonb_array_elements(coalesce(a.snapshot -> 'nps', '[]'::jsonb)) x
      cross join lateral jsonb_array_elements(coalesce(x -> 'liosArr', '[]'::jsonb)) y
      cross join lateral jsonb_array_elements(coalesce(y -> 'items', '[]'::jsonb)) it
     where coalesce(x->>'clase', 'lio') not in ('etiqueta', 'nada')
    union all
    select a.tanda, coalesce(nullif(btrim(cd->>'sepLeg'), ''), a.legajo),
           case when (cd->>'sepTs') ~ '^[0-9]{11,}$' then to_timestamp((cd->>'sepTs')::numeric / 1000) else a.ts_cliente end,
           regexp_replace(regexp_replace(regexp_replace(upper(btrim(coalesce(cd->>'cod', cd->>'raw'))), '\s+(LK|CH)$', ''), '([0-9E])L$', '\1'), '^0+(?=.)', ''),
           greatest(0, coalesce(case when (cd->>'sale') ~ '^[0-9]+(\.[0-9]+)?$' then (cd->>'sale')::numeric end, 0))
      from public."GV_Armado_Avance" a
      join fr on fr.fase = 'armado' and fr.tanda = a.tanda
      cross join lateral jsonb_array_elements(coalesce(a.snapshot -> 'nps', '[]'::jsonb)) x
      cross join lateral jsonb_array_elements(coalesce(x -> 'codes', '[]'::jsonb)) cd
     where x->>'clase' in ('etiqueta', 'nada') and coalesce((cd->>'sep')::boolean, false)
  ),
  arm as (select ar0.*, coalesce(v.m3, avg(v.m3) over (partition by ar0.tanda), 0) m3c from ar0 left join vol v on v.ck = ar0.ck)
  select p.tanda, 'picking'::text, p.legajo, (p.ts_cliente at time zone 'America/Argentina/Buenos_Aires')::date,
         sum(p.re), round(sum(p.re * p.m3c)::numeric, 3)
    from pkm p where p.re > 0 and coalesce(p.legajo, '') <> ''
   group by 1, 2, 3, 4
  union all
  select a.tanda, 'armado'::text, a.legajo, (a.ts at time zone 'America/Argentina/Buenos_Aires')::date,
         sum(a.c), round(sum(a.c * a.m3c)::numeric, 3)
    from arm a where a.c > 0 and coalesce(a.legajo, '') <> ''
   group by 1, 2, 3, 4;
$function$;
revoke all on function public.gv_tanda_credito(text[]) from public;
grant execute on function public.gv_tanda_credito(text[]) to anon, authenticated, service_role;

-- Centinelas (aplicados, ids 313-315):
-- insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version) values
--  ('gv_tanda_credito','funcion', $p$from public\."GV_Tanda_Freno" z join t on t\.tanda = z\.tanda$p$, 'Sólo se reparte una tanda FRENADA…', 'Luis (D6)', 'v26.66'),
--  ('gv_tanda_credito','funcion', $p$distinct on \(tanda, ck\) \* from pk0 order by tanda, ck, ts_cliente desc$p$, 'Picking: el ÚLTIMO PKC de cada código…', 'Luis (D6)', 'v26.66'),
--  ('gv_tanda_credito','funcion', $p$coalesce\(nullif\(btrim\(y->>'leg'\), ''\), a\.legajo\)$p$, 'Armado: cada lío a quien lo cerró…', 'Luis (D6)', 'v26.66');

-- Chequeo:
--   select * from public.gv_tanda_credito((select array_agg(distinct tanda) from public."GV_Tanda_Freno"));
--   select * from public.gv_reglas_perdidas;     -- vacía

-- ROLLBACK (front y base, independientes):
--   front: revertir el commit v26.67 (sin gvCreditoTandas el monitor vuelve a dar la tanda entera al del TP/TAP).
--   base:  la función no tiene otros lectores; se puede dejar. Para sacarla:
--          update public."GV_Reglas_Centinela" set activo = false where id between 313 and 315;
--          drop function public.gv_tanda_credito(text[]);   -- (desde el SQL Editor; el MCP se cuelga con DROP)
