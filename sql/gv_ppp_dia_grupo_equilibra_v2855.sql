-- v28.55 (Luis, 08/10/2026): P14a deja de tirar todo al PRIMER día del grupo.
-- "que primero revise todos los días que cumplen con la condición y que después distribuya ...
--  no le pases la bomba de un día a otro, distribuí para que queden equilibrados".
-- Caso: Capital Sur juntó 16,57 m³ el 15/10 (11 tandas) teniendo camión también el 16 y el 19.
-- Paso 1 ahora: de TODOS los días del plazo donde el grupo ya tiene camión, va al de MENOS m³
-- del día entero (web + ISIS, todos los grupos: es lo que arma el depósito). Empate: el más temprano.
-- No abre camiones: sigue usando sólo días donde el grupo ya sale. Pasos 2-4 sin cambios.
-- Marcador: v28.55-equilibra. Rollback: la definición anterior está al final (comentada).

CREATE OR REPLACE FUNCTION public.gv_ppp_web_dia_grupo(p_zona text, p_entrada date, p_expreso boolean, p_min date, p_m3 numeric DEFAULT 0)
 RETURNS date
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_grp   text := public.gv_ppp_web_camion(p_zona, null::text);
  v_lim   date := coalesce(p_entrada, current_date) + case when p_expreso then 13 else 14 end;
  v_m3    numeric := coalesce(p_m3, 0);
  v_otro  text;
  v_hasta date;
  v_d     date;
  v_g     int := 0;
begin
  -- v21.95 (Luis 23/09): Z6+Z7 un solo camion; Z2+Z3 un camion si cada una < 1 m3 ese dia (web+ISIS).
  --   Prioridad: max entrega con la menor cantidad de camiones. Las TANDAS no se tocan (siguen por zona).
  if v_grp is null or coalesce(p_zona, '') !~ '^\s*Zona\s*[0-9]+' then return null; end if;
  if v_grp = 'GBA Norte Lejos' then v_grp := 'GBA Norte'; end if;
  v_otro := case v_grp when 'Capital Centro' then 'Capital Oeste' when 'Capital Oeste' then 'Capital Centro' end;
  while not public.gv_es_dia_con_reparto(v_lim) and v_g < 15 loop
    v_lim := v_lim - 1; v_g := v_g + 1;
  end loop;
  v_hasta := greatest(v_lim, p_min) + 15;
  drop table if exists _gdg_z;
  create temp table _gdg_z on commit drop as
  with z as (
    select w.fecha_entrega as dia, public.gv_ppp_web_camion(w.zona, null::text) as g, coalesce(w.m3, 0) as m3
      from public."PPP_Web_Programacion" w
     where w.fecha_entrega between p_min and v_hasta
       and coalesce(nullif(btrim(w.tanda), ''), '') <> ''
       and coalesce(w.zona, '') ~ '^\s*Zona\s*[0-9]+'
       and not public.gv_es_super(w.empresa, w.cod_cliente)
    union all
    select left(btrim(i.fecha_entrega::text), 10)::date, public.gv_ppp_web_camion(i.zona, null::text),
           coalesce(i.m3, 0)
      from public.gv_ppp_programacion_diaria i
     where btrim(i.fecha_entrega::text) ~ '^\d{4}-\d{2}-\d{2}'
       and left(btrim(i.fecha_entrega::text), 10)::date between p_min and v_hasta
       and coalesce(nullif(btrim(i.tanda), ''), '') <> ''
       and coalesce(i.tipo, '') <> 'KRIKOS'
       and coalesce(i.zona, '') ~ '^\s*Zona\s*[0-9]+'
       and not public.gv_es_super_np(i.np, i.cod))
  select dia, case when g = 'GBA Norte Lejos' then 'GBA Norte' else g end as g, sum(m3) as m3
    from z where g is not null group by 1, 2;
  -- v28.55-equilibra: m³ del DÍA ENTERO (todo lo programado: web + ISIS, súper y retira incluidos)
  drop table if exists _gdg_dia;
  create temp table _gdg_dia on commit drop as
  with t as (
    select w.fecha_entrega as dia, coalesce(w.m3, 0) as m3
      from public."PPP_Web_Programacion" w
     where w.fecha_entrega between p_min and v_hasta
       and coalesce(nullif(btrim(w.tanda), ''), '') <> ''
    union all
    select left(btrim(i.fecha_entrega::text), 10)::date, coalesce(i.m3, 0)
      from public.gv_ppp_programacion_diaria i
     where btrim(i.fecha_entrega::text) ~ '^\d{4}-\d{2}-\d{2}'
       and left(btrim(i.fecha_entrega::text), 10)::date between p_min and v_hasta
       and coalesce(nullif(btrim(i.tanda), ''), '') <> ''
       and coalesce(i.tipo, '') <> 'KRIKOS')
  select dia, sum(m3) as m3 from t group by 1;
  drop table if exists _gdg_oc;
  create temp table _gdg_oc on commit drop as
  select g2::date as dia,
         coalesce((select sum(z.m3) from _gdg_z z where z.dia = g2::date and z.g = v_grp), 0) as m3_propio,
         (select z.m3 from _gdg_z z where z.dia = g2::date and z.g = v_otro) as m3_otro,
         exists (select 1 from _gdg_z z where z.dia = g2::date and z.g = v_grp) as tiene_propio,
         (select count(*) from _gdg_z z where z.dia = g2::date)
         - case when (select count(*) from _gdg_z z where z.dia = g2::date
                        and z.g in ('Capital Centro','Capital Oeste') and z.m3 < 1) = 2 then 1 else 0 end
           as camiones,
         coalesce((select d.m3 from _gdg_dia d where d.dia = g2::date), 0) as m3_dia
    from generate_series(p_min, v_hasta, interval '1 day') g2
   where public.gv_es_dia_con_reparto(g2::date);
  -- paso 1 (v28.55-equilibra): de los días del plazo con camión de su grupo, el MENOS cargado
  select dia into v_d from _gdg_oc
   where dia <= v_lim
     and (tiene_propio
          or (v_otro is not null and m3_otro is not null and m3_otro < 1 and m3_propio + v_m3 < 1))
   order by m3_dia, dia
   limit 1;
  if v_d is not null then return v_d; end if;
  select max(dia) into v_d from _gdg_oc where dia <= v_lim and camiones = 0;
  if v_d is not null then return v_d; end if;
  if p_min <= v_lim then
    select dia into v_d from _gdg_oc where dia <= v_lim order by camiones, dia limit 1;
    if v_d is not null then return v_d; end if;
  end if;
  select dia into v_d from (select *, row_number() over (order by dia) rn from _gdg_oc) q
   where rn <= 2
   order by (tiene_propio or camiones = 0) desc, dia
   limit 1;
  return coalesce(v_d, p_min);
end
$function$;

CREATE OR REPLACE FUNCTION public.gv_ppp_pauta_grupo_clasificar(p_zona text, p_entrada date, p_expreso boolean, p_min date, p_dia date, p_m3 numeric DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_grp text := public.gv_ppp_web_camion(p_zona, null::text);
  v_otro text; v_lim date; v_g int := 0;
  v_a date[]; v_b date; v_c date; v_cn int; v_p text; v_mot text; v_prev text; v_sig text;
  v_m3 numeric := coalesce(p_m3, 0); v_comp boolean := false; v_m3d numeric; v_lista text;
begin
  -- v27.05-pauta: lee _gdg_oc, la que gv_ppp_web_dia_grupo armó recién (misma cuenta, no se duplica)
  if v_grp = 'GBA Norte Lejos' then v_grp := 'GBA Norte'; end if;
  v_otro := case v_grp when 'Capital Centro' then 'Capital Oeste' when 'Capital Oeste' then 'Capital Centro' end;
  v_lim := coalesce(p_entrada, current_date) + case when p_expreso then 13 else 14 end;
  while not public.gv_es_dia_con_reparto(v_lim) and v_g < 15 loop v_lim := v_lim - 1; v_g := v_g + 1; end loop;
  if to_regclass('pg_temp._gdg_oc') is null then
    return jsonb_build_object('p','P14','grupo',v_grp,'plazo',v_lim,'minimo',p_min,'dia',p_dia);
  end if;
  execute $q$ select array_agg(dia order by dia),
                     string_agg(to_char(dia,'DD/MM') || ' ' || to_char(round(m3_dia, 2), 'FM990D00') || ' m³', ' · ' order by dia)
                from _gdg_oc where dia <= $1
      and (tiene_propio or ($2 is not null and m3_otro is not null and m3_otro < 1 and m3_propio + $3 < 1)) $q$
    into v_a, v_lista using v_lim, v_otro, v_m3;
  execute $q$ select max(dia) from _gdg_oc where dia <= $1 and camiones = 0 $q$ into v_b using v_lim;
  execute $q$ select dia, camiones from _gdg_oc where dia <= $1 order by camiones, dia limit 1 $q$ into v_c, v_cn using v_lim;
  execute $q$ select not coalesce(tiene_propio, false), m3_dia from _gdg_oc where dia = $1 $q$ into v_comp, v_m3d using p_dia;
  if v_a is not null and p_dia = any(v_a) then
    v_p := 'P14a';
    v_mot := case when coalesce(v_comp, false)
      then 'Comparte el camión de ' || v_grp || ' con ' || v_otro || ' el ' || to_char(p_dia,'DD/MM') || ': las dos zonas suman menos de 1 m³ ese día.'
      else 'Su grupo (' || v_grp || ') ya tenía camión en el plazo (hasta el ' || to_char(v_lim,'DD/MM') || '): '
           || coalesce(v_lista, '') || '. Va al menos cargado (v28.55-equilibra): el ' || to_char(p_dia,'DD/MM') || '.' end;
    v_sig := 'No pasó a P14b (último día libre' || coalesce(', que hubiera sido el ' || to_char(v_b,'DD/MM'), '') ||
             ') porque P14b sólo se usa si su grupo no sale en el plazo.';
  elsif v_b is not null and p_dia = v_b then
    v_p := 'P14b';
    v_prev := 'P14a no aplicó: ningún día entre el ' || to_char(p_min,'DD/MM') || ' y el ' || to_char(v_lim,'DD/MM') || ' tenía camión de ' || v_grp || '.';
    v_mot := 'Va al último día libre del plazo (' || to_char(p_dia,'DD/MM') || '), sin ningún otro grupo, para que se le sumen los pedidos de ' || v_grp || ' que entren después.';
    v_sig := 'No pasó a P14c porque había un día libre en el plazo.';
  elsif p_min <= v_lim and v_c is not null and p_dia = v_c then
    v_p := 'P14c';
    v_prev := 'P14a no aplicó: ' || v_grp || ' no salía en el plazo. P14b no aplicó: ningún día del plazo estaba libre.';
    v_mot := 'Va al día con menos camiones del plazo: el ' || to_char(p_dia,'DD/MM') || ' (' || coalesce(v_cn, 0) || ' grupo/s ya programados).';
    v_sig := 'No pasó a P14d porque el plazo (' || to_char(v_lim,'DD/MM') || ') todavía no venció.';
  else
    v_p := 'P14d';
    v_prev := case when p_min > v_lim
      then 'P14a a P14c no aplicaron: el plazo (' || to_char(v_lim,'DD/MM') || ') es anterior al primer día posible (' || to_char(p_min,'DD/MM') || ', 4 hábiles de anticipación).'
      else 'P14a a P14c no dieron un día dentro del plazo (' || to_char(v_lim,'DD/MM') || ').' end;
    v_mot := 'Ya vencido: va lo antes posible, el ' || to_char(p_dia,'DD/MM') || ' (primero un día con su grupo o libre).';
    v_sig := 'Es la última pauta de fecha.';
  end if;
  return jsonb_build_object('p', v_p, 'grupo', v_grp, 'entrada', p_entrada, 'expreso', p_expreso,
    'plazo', v_lim, 'minimo', p_min, 'dia', p_dia, 'dias_grupo', to_jsonb(v_a),
    'alt_b', v_b, 'alt_c', v_c, 'motivo', v_mot, 'previas', v_prev, 'no_siguiente', v_sig);
exception when others then
  return jsonb_build_object('p','P14','error',sqlerrm,'dia',p_dia);
end $function$;

-- Centinela (que no se pierda el reparto):
-- insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
-- values ('gv_ppp_web_dia_grupo','funcion','order by m3_dia, dia',
--   'P14a: de los días del plazo con camión del grupo, va al menos cargado (día entero), no al primero','Luis','v28.55');

-- ROLLBACK: volver a `select min(dia) into v_d from _gdg_oc where dia <= v_lim and (tiene_propio or ...)`
-- en gv_ppp_web_dia_grupo y `p_dia = v_a[1]` + texto "Va ahí sin mirar el cupo." en el clasificador.
