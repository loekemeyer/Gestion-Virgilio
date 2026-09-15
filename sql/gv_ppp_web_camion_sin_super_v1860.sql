-- =============================================================================
-- gv_ppp_web_camion_sin_super_v1860.sql — EL CAMIÓN DE UN SÚPER NO ES "CAMIÓN A ESA ZONA"
-- 2026-09-15 (v18.60) · pedido de Luis · problema 305
-- =============================================================================
-- CÓMO SE ARMÓ E11 DEL 16/09 (medido en GV_Tandas_Auto_Log y PPP_Web_Programacion):
--   E11A  98651 Extralimp (ISIS, Zona 5)             ← ancla legítima del camión E11
--   E11B  CH 0025 Dorinka (SÚPER, con "Zona 5")      ← 10:12, automático (corrida 616), regla vieja
--   E11C  LK 0092/0093 Todo Bazar (Zona 5)           ← 12:16, automático (642): "ya hay camión a zona 5"
--   E11D  LK 0099 Goldar (Zona 5)                    ← 15:00, automático (677): idem
--
-- La v18.31 (mismo día) ya evita el paso 2: `ppp_web_armar_tandas` borra de `_sin_tanda` todo
-- cliente que esté en GV_Supers (`gv_es_super`), así que un súper no se programa solo nunca más.
-- Lo que SEGUÍA abierto es el paso 3/4 al revés: un súper YA programado (a mano, o de antes)
-- con zona numérica contaba como "camión a esa zona" en DOS lugares, y el automático le sumaba
-- clientes comunes:
--   1) gv_ppp_web_dia_camion(zona, desde): elige el día mirando cualquier tanda con "Zona N".
--   2) ppp_web_armar_tandas, bloque `_ex` (camiones que YA van ese día, v13.60): filtraba sólo
--      zona ~ 'super|retira|expo'. Dorinka dice "Zona 5 - GBA Oeste" → pasaba.
--
-- QUÉ CAMBIA: en los dos, la fila de un súper no cuenta. Web: `not gv_es_super(w.empresa,
-- w.cod_cliente)`; ISIS: `not gv_es_super_np(i.np, i.cod)`. Nada más.
--
-- MEDIDO: gv_ppp_web_dia_camion('Zona 5 - GBA Oeste', mañana) sigue dando 2026-09-16 (Extralimp
-- es un cliente común, el camión existe). Control positivo en transacción abortada: ocultando a
-- Extralimp y sacando Todo Bazar/Goldar, con SÓLO Dorinka en zona 5 el 16/09, la función ya NO
-- devuelve el 16/09. Simulación de mañana para lk y chef: sin tandas nuevas, sin error.
--
-- Backup de las dos definiciones anteriores: zz_backups."GV_Backup_Funcdefs_20260915_v1860".
-- ROLLBACK: for r in select def from zz_backups."GV_Backup_Funcdefs_20260915_v1860" loop execute r.def; end loop;
-- =============================================================================

-- 1) ppp_web_armar_tandas — parche mecánico sobre la definición viva (dos anclas únicas; si una
--    no está, no se toca nada):
do $$
declare d text; d2 text;
begin
  select pg_get_functiondef(p.oid) into d from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='ppp_web_armar_tandas';
  if d ~ 'gv_es_super\(w\.empresa, w\.cod_cliente\)' then raise notice 'ya aplicado'; return; end if;
  d2 := regexp_replace(d,
    '(w\.fecha_entrega = v_fecha\s+and coalesce\(nullif\(btrim\(w\.tanda\),''''\),''''\) <> '''')(\s+union all)',
    E'\\1\n                 and not public.gv_es_super(w.empresa, w.cod_cliente)   -- v18.60: el camión de un SÚPER no se reusa para clientes\\2');
  if d2 = d then raise exception 'ppp_web_armar_tandas: ancla web no encontrada'; end if;
  d := d2;
  d2 := regexp_replace(d,
    '(and coalesce\(i\.tipo,''''\) <> ''KRIKOS'')(\s*\)\s*t\s+cross join lateral)',
    E'\\1\n                 and not public.gv_es_super_np(i.np, i.cod)   -- v18.60: idem para una NP de ISIS de un súper\\2');
  if d2 = d then raise exception 'ppp_web_armar_tandas: ancla isis no encontrada'; end if;
  execute d2;
end $$;

-- 2) gv_ppp_web_dia_camion — definición completa
CREATE OR REPLACE FUNCTION public.gv_ppp_web_dia_camion(p_zona text, p_desde date)
 RETURNS date
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- v15.48 (dueno, 2026-09-11: "si ya hay programado algo para x dia para esa zona, hay que
  -- agregarlo ahi"): el piso NUNCA es mas tarde que manana. Antes el llamador pasaba
  -- gv_ppp_web_dia_minimo() (hoy + 4 dias habiles) y un camion ya armado para pasado manana
  -- quedaba fuera de la ventana -> devolvia null -> el pedido se quedaba "sin camion previsto".
  -- La anticipacion minima es para ELEGIR un dia nuevo; un dia que ya existe no se elige.
  -- Se resuelve aca y no en el llamador porque el otro consumidor es la Edge Function
  -- gv-ppp-web-tandas-diarias (guard del umbral intradia), que asi no hay que redeployar.
  -- v18.60 (Luis, 15/09): la tanda de un SÚPER no cuenta como "camion a esa zona". Dorinka
  -- (GV_Supers) viene con "Zona 5 - GBA Oeste", y por eso E11 del 16/09 juntó a la super con
  -- Todo Bazar y Goldar. Regla del dueño v14.23: el super no se junta con clientes.
  with zn as (select (regexp_match(btrim(coalesce(p_zona, '')), '^Zona\s*([0-9]+)'))[1] as n),
       piso as (select least(coalesce(p_desde, current_date + 1), current_date + 1) as d)
  select min(dia) from (
    select w.fecha_entrega as dia
      from public."PPP_Web_Programacion" w, zn, piso
     where zn.n is not null
       and w.fecha_entrega >= piso.d
       and coalesce(nullif(btrim(w.tanda), ''), '') <> ''
       and (regexp_match(btrim(coalesce(w.zona, '')), '^Zona\s*([0-9]+)'))[1] = zn.n
       and not public.gv_es_super(w.empresa, w.cod_cliente)          -- v18.60
    union all
    select left(btrim(i.fecha_entrega::text), 10)::date
      from public.gv_ppp_programacion_diaria i, zn, piso
     where zn.n is not null
       and btrim(i.fecha_entrega::text) ~ '^\d{4}-\d{2}-\d{2}'
       and left(btrim(i.fecha_entrega::text), 10)::date >= piso.d
       and coalesce(nullif(btrim(i.tanda), ''), '') <> ''
       and coalesce(i.tipo, '') <> 'KRIKOS'   -- v13.59
       and (regexp_match(btrim(coalesce(i.zona, '')), '^Zona\s*([0-9]+)'))[1] = zn.n
       and not public.gv_es_super_np(i.np, i.cod)                     -- v18.60
  ) d;
$function$;
