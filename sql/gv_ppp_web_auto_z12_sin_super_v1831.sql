-- ═══════════════════════════════════════════════════════════════════════════════════════
-- v18.31 (Luis, 2026-09-15) — EL ARMADO AUTOMÁTICO: SOLO ZONA 1 Y 2, NUNCA UN SÚPER,
--                             Y UNA TANDA NO MEZCLA CAMIONES
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Luis, textual:
--   · *"se están programando automáticamente pedidos que no deberían programarse
--      automáticamente (la regla era solo los de zona 1 y zona 2, tengo Dorinka tanda E11B
--      que se programó automáticamente). Regla clara: solo se pueden programar
--      automáticamente los pedidos de zona 1 y zona 2 que no sean súper. Todos los demás
--      van «A programar» para que un humano arme las tandas."*
--   · *"estaba armando mal las tandas, tanda D69H por ejemplo mezcló zona 2 con zona 6 (y
--      puso en la tanda que era «Zona 6 +1»). Eso está mal. ¿Por qué lo hacía? Que lo deje
--      de hacer."*
--
-- ─── POR QUÉ PASÓ ──────────────────────────────────────────────────────────────────────
-- 1) DORINKA (súper) SE PROGRAMÓ SOLA. `ppp_web_armar_tandas` decidía "esto es un súper"
--    mirando el GRUPO DE ZONA (`gv_ppp_web_grupo_zona` = 'Super'), y Dorinka viene con
--    zona "Zona 5 - GBA Oeste". O sea que para la función NO era un súper: era un cliente
--    común de zona 5. `gv_es_super('chef','2686')` sí devuelve true — ese es el padrón real
--    (`GV_Supers`) y es el que hay que mirar.
--
-- 2) D69H MEZCLÓ CAPITAL CON GBA NORTE. Al buscar una tanda abierta para meterle un cliente,
--    la función sólo exigía `gv_ppp_web_compat` (sectores vecinos) y NO que fuera el MISMO
--    camión. El par de sectores H–N ("V. Pueyrredón/V. Urquiza – San Martín/V. Ballester")
--    está cargado como vecino, pero H es camión **Capital** y N es **GBA Norte**: son dos
--    camiones distintos. Así entró LK 0083 (Núñez, Zona 2) a una tanda de Villa Ballester /
--    Villa Lynch / San Miguel (Zona 6), y la pantalla la etiquetó "Zona 6 +1".
--    Medido antes del cambio: de todas las tandas web vivas (entrega ≥ hoy − 7), **una sola**
--    mezcla camiones — D69H. O sea que la regla nueva no rompe nada que hoy esté bien.
--
-- ─── QUÉ CAMBIA ────────────────────────────────────────────────────────────────────────
--   1) `PPP_Web_Config.zonas_automaticas` : '1,2,3' → **'1,2'**  (la zona 3 vuelve a mano).
--   2) `PPP_Web_Config.zonas_manuales_con_camion` (clave nueva, arranca en **1** = como hoy):
--      interruptor del bloque (c) de `gv_ppp_web_armar_pendientes`, el que engancha una zona
--      manual (4/5/6/7) al día en que YA hay un camión a esa zona. Eso lo pidió el dueño el
--      2026-09-11 (*"si ya hay programado algo para x día para esa zona, hay que agregarlo
--      ahí"*), así que NO se apaga por cuenta propia: queda el interruptor listo.
--      Para apagarlo:  update public."PPP_Web_Config" set valor = 0 where clave = 'zonas_manuales_con_camion';
--   3) `gv_ppp_web_compat` : dos paradas de CAMIONES distintos nunca son compatibles. Los
--      pares explícitos de `GV_Barrios_Pares` siguen mandando (son excepciones del dueño,
--      cargadas a mano) y se evalúan ANTES.
--   4) `ppp_web_armar_tandas` :
--        a) un cliente que está en `GV_Supers` NUNCA entra al armado automático, tenga la
--           zona que tenga → queda en "A Programar" para que lo arme una persona;
--        b) una tanda abierta sólo recibe un cliente del MISMO camión;
--        c) una tanda que ya quedó con paradas de dos camiones (D69H) no se reusa más.
--
-- Backups previos: zz_backups."GV_Backup_Funcdefs_20260915_v1831" (las 3 funciones enteras)
--                  zz_backups."GV_Backup_PPP_Web_Config_20260915_v1831" (la config entera).
-- ROLLBACK al final del archivo.
-- ═══════════════════════════════════════════════════════════════════════════════════════

begin;

-- ───────────────────────────────────────────────────────────── 1) config
update public."PPP_Web_Config" set valor_texto = '1,2' where clave = 'zonas_automaticas';

insert into public."PPP_Web_Config" (clave, valor, valor_texto, descripcion)
values ('zonas_manuales_con_camion', 1, null,
 'Interruptor del bloque (c) de gv_ppp_web_armar_pendientes: 1 = un pedido de zona manual '
 '(4/5/6/7) se engancha solo al dia en que YA hay un camion a esa zona (regla del dueno del '
 '2026-09-11); 0 = ninguna zona fuera de zonas_automaticas se programa sola, todo va a A Programar '
 '(regla de Luis del 2026-09-15). v18.31.')
on conflict (clave) do nothing;

-- ──────────────────────────────── 2) compat: dos camiones distintos nunca comparten tanda
create or replace function public.gv_ppp_web_compat(
  p_zona_a text, p_sector_a text, p_barrio_a text,
  p_zona_b text, p_sector_b text, p_barrio_b text)
returns boolean
language plpgsql
stable
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_on  boolean := coalesce((select valor from public."PPP_Web_Config" where clave = 'sectores_activos'), 1) <> 0;
  v_ga  text := public.gv_ppp_web_grupo_zona(p_zona_a);
  v_gb  text := public.gv_ppp_web_grupo_zona(p_zona_b);
  v_par boolean;
begin
  if not v_on then
    return v_ga is not distinct from v_gb;
  end if;
  -- Los pares explícitos del dueño mandan sobre todo lo demás (incluso sobre el camión).
  if p_barrio_a is not null and p_barrio_b is not null and p_barrio_a <> p_barrio_b then
    select permitido into v_par from public."GV_Barrios_Pares"
     where barrio_a = least(p_barrio_a, p_barrio_b) and barrio_b = greatest(p_barrio_a, p_barrio_b);
    if found then return v_par; end if;
  end if;
  -- v18.31 (Luis): una tanda es de UN camión. Núñez (sector H, camión Capital) y San Miguel
  -- (sector N, camión GBA Norte) figuran como sectores vecinos, pero son dos camiones: si se
  -- mezclan, la tanda sale "Zona 6 +1" y el reparto no cierra. Ese era el caso D69H.
  if public.gv_ppp_web_camion(p_zona_a, p_sector_a)
     is distinct from public.gv_ppp_web_camion(p_zona_b, p_sector_b) then
    return false;
  end if;
  if p_sector_a is not distinct from p_sector_b then return true; end if;
  if p_sector_a is null or p_sector_b is null or p_sector_a like '~%' or p_sector_b like '~%' then
    return v_ga is not distinct from v_gb;
  end if;
  return coalesce((select v.permitido from public."GV_Sectores_Vecinos" v
                    where v.sector_a = least(p_sector_a, p_sector_b)
                      and v.sector_b = greatest(p_sector_a, p_sector_b)), false);
end
$function$;

-- ─────────────────── 3) ppp_web_armar_tandas: súper afuera + una tanda = un camión
-- La función es de ~14 k caracteres y lo que cambia son 5 líneas, así que se parcha sobre su
-- propia definición y se vuelve a ejecutar entera, en la MISMA transacción y con guardas: si
-- un ancla no aparece exactamente una vez, no se toca nada (mismo patrón que la v17.85).
do $do$
declare v_def text; v_new text; v_a text; v_b text;
begin
  v_def := pg_get_functiondef('public.ppp_web_armar_tandas(text,date,jsonb,text[],boolean)'::regprocedure);
  if v_def like '%v18.31%' then raise notice 'ya estaba parchada'; return; end if;
  v_new := v_def;

  -- (a) los SÚPER no entran al armado automático, tengan la zona que tengan
  v_a := '  delete from _sin_tanda where zona = ''(sin zona)'';';
  if (length(v_new) - length(replace(v_new, v_a, ''))) / length(v_a) <> 1 then
    raise exception 'ancla (a) no aparece exactamente una vez';
  end if;
  v_new := replace(v_new, v_a, v_a || E'\n\n' ||
'  -- v18.31 (Luis): un SUPER nunca se programa solo. Antes esto se decidia por el GRUPO DE
  -- ZONA (''Super''), asi que un super con zona numerica -- Dorinka, "Zona 5 - GBA Oeste" --
  -- pasaba de largo y se programaba como un cliente cualquiera (tanda E11B del 15/09). El
  -- padron real es GV_Supers; queda en A Programar para que lo arme una persona.
  delete from _sin_tanda s where public.gv_es_super(p_empresa, s.cliente);');

  -- (b) una tanda ya abierta sólo recibe clientes del MISMO camión
  v_b := '           and o.m3 < v_tope' || E'\n';
  if (length(v_new) - length(replace(v_new, v_b, ''))) / length(v_b) <> 1 then
    raise exception 'ancla (b) no aparece exactamente una vez';
  end if;
  v_new := replace(v_new, v_b, v_b ||
'           -- v18.31 (Luis): una tanda es de UN camion. Sin esto, dos sectores vecinos de
           -- camiones distintos (H Capital / N GBA Norte) terminaban en la misma tanda: D69H.
           and o.camion = r_cli.camion' || E'\n');

  -- (c) una tanda que YA quedó con dos camiones no se vuelve a reusar
  v_b := '               bool_and(coalesce(w.zona,'''') !~* ''super|retira|expo'') as reparto,';
  if (length(v_new) - length(replace(v_new, v_b, ''))) / length(v_b) <> 1 then
    raise exception 'ancla (c) no aparece exactamente una vez';
  end if;
  v_new := replace(v_new, v_b, v_b || E'\n' ||
'               -- v18.31: si la tanda ya tiene paradas de dos camiones (caso D69H), no se reusa.
               count(distinct public.gv_ppp_web_camion(w.zona, public.gv_ppp_web_sector(w.zona, w.barrio, w.direccion))) as ncam,');

  v_b := '     where q.m3 < v_tope and q.reparto and not q.tiene_solo';
  if (length(v_new) - length(replace(v_new, v_b, ''))) / length(v_b) <> 1 then
    raise exception 'ancla (d) no aparece exactamente una vez';
  end if;
  v_new := replace(v_new, v_b, '     where q.m3 < v_tope and q.reparto and not q.tiene_solo and q.ncam = 1');

  execute v_new;
end $do$;

-- ───────────── 4) gv_ppp_web_armar_pendientes: el bloque (c) detrás del interruptor
do $do$
declare v_def text; v_a text;
begin
  v_def := pg_get_functiondef('public.gv_ppp_web_armar_pendientes(text,date,jsonb,jsonb)'::regprocedure);
  -- v18.61: NO usar LIKE acá. El "_" es comodín: '%zonas_manuales_con_camion%' matcheaba el comentario
  -- "-- (c) zonas manuales con camion" que la función YA tenía, decía "ya estaba parchada" y salía
  -- sin aplicar nada. Por eso este bloque figuró como aplicado el 15/09 y no lo estaba (problema 291).
  if position('zonas_manuales_con_camion' in v_def) > 0 then raise notice 'ya estaba parchada'; return; end if;
  v_a := '           and not public.gv_ppp_web_zona_automatica(x->>''zona'')';
  if (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a) <> 1 then
    raise exception 'el ancla del bloque (c) no aparece exactamente una vez';
  end if;
  execute replace(v_def, v_a, v_a || E'\n' ||
'           -- v18.31 (Luis): interruptor. En 0, NINGUNA zona fuera de zonas_automaticas se
           -- programa sola y todo lo demas queda en A Programar.
           and coalesce((select valor from public."PPP_Web_Config"
                          where clave = ''zonas_manuales_con_camion''), 1) <> 0');
end $do$;

commit;

-- ═══ COMPROBACIONES ════════════════════════════════════════════════════════════════════
-- 1) Núñez (Zona 2) ya no comparte tanda con San Miguel (Zona 6) — tiene que dar false:
-- select public.gv_ppp_web_compat('Zona 2 - CABA Centro','H','nuñez','Zona 6 - GBA Norte','N','san miguel');
-- 2) Ninguna tanda web viva mezcla camiones — tiene que dar vacío (hoy devuelve D69H, que
--    es la que quedó mal armada ANTES del cambio y hay que separar a mano):
-- with f as (select tanda, public.gv_ppp_web_camion(zona, public.gv_ppp_web_sector(zona, barrio, direccion)) cam
--              from public."PPP_Web_Programacion"
--             where coalesce(nullif(btrim(tanda),''),'') <> '' and fecha_entrega >= current_date - 7)
-- select tanda, string_agg(distinct cam, ' | ') from f group by 1 having count(distinct cam) > 1;
-- 3) Súper que no entra más al automático:
-- select public.gv_es_super('chef','2686');   -- Dorinka → true
-- 4) Config:
-- select clave, valor, valor_texto from public."PPP_Web_Config"
--  where clave in ('zonas_automaticas','zonas_manuales_con_camion');

-- ═══ ROLLBACK ══════════════════════════════════════════════════════════════════════════
-- update public."PPP_Web_Config" set valor_texto = '1,2,3' where clave = 'zonas_automaticas';
-- delete from public."PPP_Web_Config" where clave = 'zonas_manuales_con_camion';
-- do $$ declare r record; begin
--   for r in select def from zz_backups."GV_Backup_Funcdefs_20260915_v1831" loop execute r.def; end loop;
-- end $$;
