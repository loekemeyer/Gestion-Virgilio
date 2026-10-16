-- ============================================================================================
-- v29.64 (Luis, 13/10/2026) — ANÁLISIS PRODUCTIVO POR TANDA
--
-- Luis: "en el modulo de operarios de Juan y en el Admin, un boton Analisis Productivo. Cuando
-- se abre, permite ver, por tanda, el analisis tecnico (ritmo, velocidad, dificultad, ritmo en
-- relacion a la dificultad). Deberia tambien analizar si hubo algo muy anomalo en el picking
-- (por ejemplo, normalmente se toman 2 segundos por caja de codigo X pero este picking se tardo
-- 0.2 segundos por caja)".
--
-- El monitor ya evalúa por OPERARIO y por DÍA (gv_ritmo_picking / gv_ritmo_armado, v29.47-48).
-- Lo que faltaba es la MISMA cuenta abierta POR TANDA, con el detalle línea por línea.
-- Nada de esto recalcula nada: lee lo que ya calcularon GV_Picking_Tanda, GV_Armado_Tanda y sus
-- estimados, y le agrega el detalle de los PKC y del registro por paso.
--
-- ⚠ LO QUE SE MIDIÓ ANTES DE ELEGIR EL DETECTOR DE ANOMALÍAS (13/10, 120 días):
--   · El ts del PKC es CUÁNDO TOCÓ OK, no cuándo levantó la caja. Marcando por línea
--     "< 1 s por caja con 5+ cajas" saltan 368 líneas en 148 de 560 tandas (26 %) — y agrupando
--     las ráfagas, 283 de 588 (48 %). Eso NO es fraude: es que se confirma en bloque.
--     → Por eso el s/caja del PKC va como DATO de la tabla, con la mediana del código al lado,
--       y NO dispara una alarma por sí solo.
--   · El registro por paso (GV_Picking_Paso_Evento, v26.25, desde el 05/10) sí mide trabajo:
--     de «mostrado» a «ok» la mediana es 29 s, el p10 9,5 s y sólo 8 de 769 pasos (1 %) bajan
--     de 2 s. ESA es la fuente del aviso fuerte, y sólo existe para las tandas nuevas.
--   · El detector que no depende del reloj: el picking dijo COMPLETO y el armado declaró
--     faltante de ese código → 14 casos en 13 de 486 tandas (2,7 %), 44 cajas.
--
-- Objetos (todos nuevos; nada existente se toca):
--   GV_Analisis_Acceso        legajos que ven el Análisis desde el módulo de operarios (hoy: Juan, 8).
--   gv_analisis_acceso_ok()   supervisor, o legajo activo de esa tabla.
--   gv_analisis_cod_base()    por código: cuánto tarda normalmente una línea (mediana de 120 días).
--   gv_analisis_lista()       las tandas del período con su ritmo y sus avisos (para elegir).
--   gv_analisis_tanda()       el detalle de UNA tanda: ritmo, dificultad, línea por línea, avisos.
--
-- ⚠ El DDL de primer nivel se cuelga en el MCP (v26.50): la tabla, la semilla y los grants van
--   adentro de gv_analisis_instalar(). Sin el cuelgue, este archivo se corre entero tal cual.
--
-- ROLLBACK:
--   drop function if exists public.gv_analisis_tanda(text, text);
--   drop function if exists public.gv_analisis_lista(int, text, text);
--   drop function if exists public.gv_analisis_cod_base(int);
--   drop function if exists public.gv_analisis_acceso_ok(text);
--   drop function if exists public.gv_analisis_instalar();
--   drop table if exists public."GV_Analisis_Acceso";
--   delete from public."GV_Reglas_Centinela" where version = 'v29.64';
-- ============================================================================================

-- ─────────────────────────── 1. quién lo ve desde el celular ───────────────────────────
create or replace function public.gv_analisis_instalar()
returns text language plpgsql security definer set search_path = public as $$
begin
  create table if not exists public."GV_Analisis_Acceso" (
    legajo     text primary key,
    nombre     text,
    activo     boolean not null default true,
    nota       text,
    creado_at  timestamptz not null default now()
  );
  alter table public."GV_Analisis_Acceso" enable row level security;
  revoke all on public."GV_Analisis_Acceso" from anon, authenticated;
  insert into public."GV_Analisis_Acceso" (legajo, nombre, nota)
  values ('8', 'Farias Juan Hilario', 'Luis, 13/10/2026: el Análisis Productivo en el módulo de operarios')
  on conflict (legajo) do nothing;
  return 'ok';
end $$;
revoke all on function public.gv_analisis_instalar() from public, anon, authenticated;
select public.gv_analisis_instalar();

-- supervisor (sesión de Google) o un legajo habilitado.
-- ⚠ NO ES UN CANDADO: el legajo lo manda el celular y no se puede verificar (el operario entra
--   con el código de la TV, no con una sesión). Frena a quien lo lee, como el semáforo de repos.
create or replace function public.gv_analisis_acceso_ok(p_legajo text default null)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
  v_l text := nullif(btrim(coalesce(p_legajo, '')), '');
  v_regla constant text := 'v29.64-acceso';   -- marcador de la regla, en CODIGO (el centinela saca los comentarios)
begin
  if public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio() then return true; end if;
  if v_l is null or v_l = v_regla then return false; end if;
  return exists (select 1 from public."GV_Analisis_Acceso" a
                  where a.legajo = v_l and a.activo);
end $$;
grant execute on function public.gv_analisis_acceso_ok(text) to anon, authenticated;

-- ─────────────────── 2. cuánto tarda NORMALMENTE una línea de cada código ───────────────────
-- Por código: la mediana del tiempo entre confirmaciones (PKC), y la misma mediana descontando
-- el término por caja del esquema D17 (3,74 s = 0,0623 min). Con eso el esperado de una línea es
--   base_cod + 3,74 · min(cajas, 30)
-- Sólo los códigos con 8+ líneas medidas (194 de 289 cubren el 96 % de las líneas, medido 13/10).
create or replace function public.gv_analisis_cod_base(p_dias int default 120)
returns table(ck text, n int, base_seg numeric, med_seg numeric, med_seg_caja numeric)
language sql stable security definer set search_path = public as $$
  with pk as (
    select upper(btrim(split_part(texto, '|', 1))) tanda, legajo,
           regexp_replace(regexp_replace(regexp_replace(upper(btrim(split_part(texto, '|', 2))),
             '\s+(LK|CH)$', ''), '([0-9E])L$', '\1'), '^0+(?=.)', '') c,
           case when split_part(texto, '|', 4) ~ '^[0-9]+(\.[0-9]+)?$' then split_part(texto, '|', 4)::numeric else 0 end re,
           ts_cliente t
      from public."Registros_Produccion_Virgilio"
     where opcion = 'PKC' and ts_cliente > now() - make_interval(days => greatest(coalesce(p_dias, 120), 7))
       and not public.es_legajo_test(legajo)
  ),
  g as (select p.*, extract(epoch from p.t - lag(p.t) over (partition by p.tanda, p.legajo order by p.t)) seg from pk p),
  f as (select * from g where seg between 1 and 900 and re > 0)
  select f.c, count(*)::int,
         round(percentile_cont(0.5) within group (order by f.seg - 3.74 * least(f.re, 30))::numeric, 1),
         round(percentile_cont(0.5) within group (order by f.seg)::numeric, 1),
         round(percentile_cont(0.5) within group (order by f.seg / f.re)::numeric, 2)
    from f group by f.c having count(*) >= 8;
$$;
revoke all on function public.gv_analisis_cod_base(int) from public, anon;
grant execute on function public.gv_analisis_cod_base(int) to authenticated;

-- ─────────────────────────── 3. la lista de tandas para elegir ───────────────────────────
create or replace function public.gv_analisis_lista(p_dias int default 14, p_legajo text default null,
                                                    p_buscar text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_hoy date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
  v_desde date := v_hoy - greatest(least(coalesce(p_dias, 14), 120), 1) + 1;
  v_b text := nullif(upper(btrim(coalesce(p_buscar, ''))), '');
  v_out jsonb;
begin
  if not public.gv_analisis_acceso_ok(p_legajo) then
    raise exception 'ACCESO: el Analisis Productivo es para el supervisor y los legajos habilitados';
  end if;
  with p as (
    select distinct on (t.tanda) t.tanda, t.legajo, t.tp, t.tamano, t.real_min, t.indice, t.grado, t.nivel, t.lineas, t.cajas
      from public."GV_Picking_Tanda" t
     where (t.tp at time zone 'America/Argentina/Buenos_Aires')::date between v_desde and v_hoy
       and not public.es_legajo_test(t.legajo)
     order by t.tanda, t.lineas desc nulls last, t.real_min asc nulls last, t.tp desc   -- D3 (a): 1 fila por tanda = el pick real (más líneas; empate -> real_min sano, descarta la fila abandonada)
  ), a as (
    select t.tanda, t.legajo, t.tp, t.tamano, t.real_min, t.indice, t.grado, t.nivel, t.nps
      from public."GV_Armado_Tanda" t
     where (t.tp at time zone 'America/Argentina/Buenos_Aires')::date between v_desde and v_hoy
       and not public.es_legajo_test(t.legajo)
  ), u as (
    select coalesce(p.tanda, a.tanda) tanda from p full join a on a.tanda = p.tanda group by 1
  ), m3 as (
    select u.tanda, (select coalesce(sum(w.m3), 0) from public."PPP_Web_Programacion" w
                      where upper(btrim(w.tanda)) = u.tanda)
                  + (select coalesce(sum(d.m3), 0) from public."GV_PPP_Programacion_Diaria" d
                      where upper(btrim(d.tanda)) = u.tanda) m3
      from u
  ),
  -- avisos DUROS, calculados para todo el periodo de una (los que no dependen del reloj del PKC)
  pkc as (
    select upper(btrim(split_part(r.texto, '|', 1))) tanda,
           regexp_replace(regexp_replace(regexp_replace(upper(btrim(split_part(r.texto, '|', 2))),
             '\s+(LK|CH)$', ''), '([0-9E])L$', '\1'), '^0+(?=.)', '') ck,
           max(case when split_part(r.texto, '|', 3) ~ '^[0-9]+(\.[0-9]+)?$' then split_part(r.texto, '|', 3)::numeric else 0 end) esp,
           max(case when split_part(r.texto, '|', 4) ~ '^[0-9]+(\.[0-9]+)?$' then split_part(r.texto, '|', 4)::numeric else 0 end) re
      from public."Registros_Produccion_Virgilio" r
     where r.opcion = 'PKC' and r.ts_cliente > (v_desde - 2)::timestamptz and not public.es_legajo_test(r.legajo)
       and upper(btrim(split_part(r.texto, '|', 1))) in (select u.tanda from u)
     group by 1, 2
  ), falto as (
    select e.t tanda, count(*) n from (
      select upper(btrim(x.tanda)) t,
             regexp_replace(regexp_replace(regexp_replace(upper(btrim(x.cod_art)),
               '\s+(LK|CH)$', ''), '([0-9E])L$', '\1'), '^0+(?=.)', '') ck,
             sum(coalesce(x.cajas_falto, 0)) f
        from public."Entregas_Virgilio" x
       where upper(btrim(x.tanda)) in (select u.tanda from u) group by 1, 2) e
      join pkc on pkc.tanda = e.t and pkc.ck = e.ck
     where e.f > 0 and pkc.re >= pkc.esp and pkc.esp > 0 group by 1
  ), paso as (
    select s.tanda, count(*) n from public.gv_picking_paso s
     where s.tanda in (select u.tanda from u)
       and (select extract(epoch from s.primera_conf - coalesce((select max(m.ts_cliente)
              from public."GV_Picking_Paso_Evento" m
             where m.evento = 'mostrado' and upper(btrim(m.tanda)) = s.tanda and m.paso = s.paso
               and m.legajo = s.legajo and m.ts_cliente <= s.primera_conf), s.primera_vez))) >= 0
       and ((coalesce(s.real_final, 0) >= 3 and (select extract(epoch from s.primera_conf - coalesce((select max(m.ts_cliente)
              from public."GV_Picking_Paso_Evento" m
             where m.evento = 'mostrado' and upper(btrim(m.tanda)) = s.tanda and m.paso = s.paso
               and m.legajo = s.legajo and m.ts_cliente <= s.primera_conf), s.primera_vez))) < 2)
         or (coalesce(s.real_final, 0) >= 5 and (select extract(epoch from s.primera_conf - coalesce((select max(m.ts_cliente)
              from public."GV_Picking_Paso_Evento" m
             where m.evento = 'mostrado' and upper(btrim(m.tanda)) = s.tanda and m.paso = s.paso
               and m.legajo = s.legajo and m.ts_cliente <= s.primera_conf), s.primera_vez))) / nullif(s.real_final, 0) < 1))
     group by 1
  ), f as (
    select u.tanda, p.legajo pleg, p.tp ptp, p.indice pind, p.grado pgr, p.nivel pniv,
           p.tamano ptam, p.real_min preal, p.lineas plin, p.cajas pcaj,
           a.legajo aleg, a.tp atp, a.indice aind, a.grado agr, a.nivel aniv,
           a.tamano atam, a.real_min areal, a.nps anps, m3.m3,
           coalesce(falto.n, 0) n_falto, coalesce(paso.n, 0) n_paso, coalesce(p.tp, a.tp) ord
      from u left join p on p.tanda = u.tanda left join a on a.tanda = u.tanda left join m3 on m3.tanda = u.tanda
           left join falto on falto.tanda = u.tanda left join paso on paso.tanda = u.tanda
     where v_b is null or u.tanda like '%' || v_b || '%'
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'tanda', f.tanda, 'dia', (coalesce(f.ptp, f.atp) at time zone 'America/Argentina/Buenos_Aires')::date,
           'm3', round(coalesce(f.m3, 0), 3),
           'alerta', f.n_falto + f.n_paso, 'n_falto', f.n_falto, 'n_paso', f.n_paso,
           'pick', case when f.ptp is null then null else jsonb_build_object(
             'legajo', f.pleg, 'nombre', (select max(e."Empleado") from public."Empleados" e where e."Legajo"::text = f.pleg),
             'ts', f.ptp, 'indice', f.pind, 'grado', f.pgr, 'nivel', f.pniv,
             'esperado_min', round(f.ptam, 1), 'real_min', round(f.preal, 1),
             'lineas', f.plin, 'cajas', f.pcaj) end,
           'arm', case when f.atp is null then null else jsonb_build_object(
             'legajo', f.aleg, 'nombre', (select max(e."Empleado") from public."Empleados" e where e."Legajo"::text = f.aleg),
             'ts', f.atp, 'indice', f.aind, 'grado', f.agr, 'nivel', f.aniv,
             'esperado_min', round(f.atam, 1), 'real_min', round(f.areal, 1), 'nps', f.anps) end)
           order by f.ord desc), '[]'::jsonb)
    into v_out from f;
  return jsonb_build_object('desde', v_desde, 'hasta', v_hoy, 'tandas', v_out);
end $$;
revoke all on function public.gv_analisis_lista(int, text, text) from public;
grant execute on function public.gv_analisis_lista(int, text, text) to anon, authenticated;

-- ─────────────────────────── 4. el detalle de UNA tanda ───────────────────────────
-- Mapa de la función (los comentarios van ACÁ y no adentro: así el cuerpo del repo es byte a byte
-- el de la base — md5(prosrc) c4d8cd98dc42122c4a5c060bed75fe7a — y la huella se puede comparar):
--   1. guard de acceso y las dos filas de caché (GV_Picking_Tanda / GV_Armado_Tanda) de esa tanda.
--   2. cabecera: NP, clientes y m³, web + ISIS. fecha_entrega va a texto: en una tabla es date y en la otra no.
--   3. picking y armado: ritmo, dificultad, composición del tiempo y el promedio del operario y del grado.
--   4. línea por línea: PKC + lo normal de ese código (gv_analisis_cod_base) + el registro por paso. El
--      lateral busca el ÚLTIMO «mostrado» anterior a la confirmación: ESE tramo es el trabajo frente a la góndola.
--   5. conteo cíclico de góndola de ese picking (CG, v28.58).
--   6. avisos: (a) paso relámpago y (b) paso imposible, del registro por paso · (c) el picking dio completo
--      y el armado declaró faltante · (d) confirmación rápida del PKC, que es DATO y no acusación ·
--      (e) línea lenta · (f) sin stock / sin góndola · (g) huecos y celular bloqueado · (h) reconfirmado ·
--      (i) ritmo alto o bajo contra su dificultad · (j) conteo que no cierra.
create or replace function public.gv_analisis_tanda(p_tanda text, p_legajo text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_t text := upper(btrim(coalesce(p_tanda, '')));
  v_pk public."GV_Picking_Tanda"%rowtype;
  v_ar public."GV_Armado_Tanda"%rowtype;
  v_cab jsonb; v_lin jsonb; v_av jsonb := '[]'::jsonb; v_pick jsonb; v_arm jsonb;
  v_paso_hay boolean := false; v_m3 numeric; v_nps int;
  v_est_pk numeric; v_est_ar numeric; v_gr_prom numeric; v_op_prom numeric;
  v_int_veces int; v_int_seg numeric; v_cg jsonb;
  c jsonb;
begin
  if v_t = '' then raise exception 'Falta la tanda'; end if;
  if not public.gv_analisis_acceso_ok(p_legajo) then
    raise exception 'ACCESO: el Analisis Productivo es para el supervisor y los legajos habilitados';
  end if;
  select jsonb_object_agg(e.clave, e.valor) into c from public."GV_Picking_Esquema" e;

  select * into v_pk from public."GV_Picking_Tanda" t
   where t.tanda = v_t and not public.es_legajo_test(t.legajo) order by t.lineas desc nulls last, t.real_min asc nulls last, t.tp desc limit 1;
  select * into v_ar from public."GV_Armado_Tanda" t
   where t.tanda = v_t and not public.es_legajo_test(t.legajo) order by t.lineas desc nulls last, t.real_min asc nulls last, t.tp desc limit 1;

  with w as (
    select public.gv_ppp_web_np_label(x.empresa, x.np, x.np_idx) np, x.razon_social rs, coalesce(x.m3, 0) m3,
           x.zona, x.fecha_entrega::text
      from public."PPP_Web_Programacion" x where upper(btrim(x.tanda)) = v_t
    union all
    select d.np::text, d.razon_social, coalesce(d.m3, 0), d.zona, d.fecha_entrega::text
      from public."GV_PPP_Programacion_Diaria" d where upper(btrim(d.tanda)) = v_t
  )
  select jsonb_build_object(
           'tanda', v_t, 'nps', coalesce(jsonb_agg(w.np order by w.np), '[]'::jsonb),
           'clientes', (select coalesce(jsonb_agg(distinct y.rs), '[]'::jsonb) from w y where y.rs is not null),
           'm3', round(coalesce(sum(w.m3), 0), 3), 'zona', min(w.zona),
           'fecha_entrega', min(w.fecha_entrega)),
         count(*)::int, coalesce(sum(w.m3), 0)
    into v_cab, v_nps, v_m3 from w;

  select e.tamano_inicial into v_est_pk from public."GV_Picking_Estimado" e where e.tanda = v_t;
  select e.tamano_inicial into v_est_ar from public."GV_Armado_Estimado" e where e.tanda = v_t;

  if v_pk.tanda is not null then
    select round(avg(t.indice), 3) into v_gr_prom from public."GV_Picking_Tanda" t
     where t.grado = v_pk.grado and not public.es_legajo_test(t.legajo)
       and t.tp > now() - interval '120 days' and t.real_min between 0.5 and 240 and t.lineas > 0;
    select round(sum(t.tamano) / nullif(sum(t.real_min), 0), 3) into v_op_prom
      from (select z.tamano, z.real_min from public."GV_Picking_Tanda" z where z.legajo = v_pk.legajo
             and z.real_min between 0.5 and 240 and z.lineas > 0 order by z.tp desc
             limit coalesce((c->>'ventana_tandas')::int, 20)) t;
    v_pick := jsonb_build_object(
      'legajo', v_pk.legajo,
      'nombre', (select max(e."Empleado") from public."Empleados" e where e."Legajo"::text = v_pk.legajo),
      'ep', v_pk.ep, 'tp', v_pk.tp,
      'lineas', v_pk.lineas, 'cajas', v_pk.cajas, 'paradas', v_pk.paradas, 'esc', v_pk.esc,
      'n_mx', v_pk.n_mx, 'n_f', v_pk.n_f, 'alturas', v_pk.nh,
      'grado', v_pk.grado, 'nivel', v_pk.nivel, 'dificultad', v_pk.dificultad, 'multiplicador', v_pk.multiplicador,
      'esperado_min', round(v_pk.tamano, 1), 'est_ini_min', round(v_est_pk, 1),
      'bruto_min', round(v_pk.bruto_min, 1), 'pausa_min', round(v_pk.pausa_min, 1),
      'huecos_min', round(v_pk.huecos_min, 1), 'cola_min', round(v_pk.cola_min, 1), 'cola_tipo', v_pk.cola_tipo,
      'real_min', round(v_pk.real_min, 1), 'indice', v_pk.indice,
      'm3_h', round(v_m3 / nullif(v_pk.real_min / 60, 0), 2),
      'cajas_h', round(v_pk.cajas / nullif(v_pk.real_min / 60, 0), 1),
      'lineas_h', round(v_pk.lineas / nullif(v_pk.real_min / 60, 0), 1),
      'seg_linea', round(v_pk.real_min * 60 / nullif(v_pk.lineas, 0), 1),
      'prom_grado', v_gr_prom, 'prom_operario', v_op_prom);
  end if;

  if v_ar.tanda is not null then
    v_arm := jsonb_build_object(
      'legajo', v_ar.legajo,
      'nombre', (select max(e."Empleado") from public."Empleados" e where e."Legajo"::text = v_ar.legajo),
      'ap', v_ar.ep, 'tap', v_ar.tp, 'nps', v_ar.nps, 'lineas', v_ar.lineas, 'cajas', v_ar.cajas,
      'super', v_ar.super, 'grado', v_ar.grado, 'nivel', v_ar.nivel,
      'esperado_min', round(v_ar.tamano, 1), 'est_ini_min', round(v_est_ar, 1),
      'bruto_min', round(v_ar.bruto_min, 1), 'pausa_min', round(v_ar.pausa_min, 1),
      'cola_min', round(v_ar.cola_min, 1), 'real_min', round(v_ar.real_min, 1), 'indice', v_ar.indice,
      'm3_h', round(v_m3 / nullif(v_ar.real_min / 60, 0), 2),
      'cajas_h', round(v_ar.cajas / nullif(v_ar.real_min / 60, 0), 1),
      'prom_grado', (select round(avg(t.indice), 3) from public."GV_Armado_Tanda" t
                      where t.grado = v_ar.grado and not public.es_legajo_test(t.legajo)
                        and t.tp > now() - interval '120 days' and t.real_min > 0));
  end if;

  select exists (select 1 from public."GV_Picking_Paso_Evento" z where upper(btrim(z.tanda)) = v_t)
    into v_paso_hay;

  with pk0 as (
    select upper(btrim(split_part(r.texto, '|', 2))) crudo,
           regexp_replace(regexp_replace(regexp_replace(upper(btrim(split_part(r.texto, '|', 2))),
             '\s+(LK|CH)$', ''), '([0-9E])L$', '\1'), '^0+(?=.)', '') ck,
           case when split_part(r.texto, '|', 3) ~ '^[0-9]+(\.[0-9]+)?$' then split_part(r.texto, '|', 3)::numeric end esp,
           case when split_part(r.texto, '|', 4) ~ '^[0-9]+(\.[0-9]+)?$' then split_part(r.texto, '|', 4)::numeric else 0 end re,
           r.ts_cliente t, r.legajo
      from public."Registros_Produccion_Virgilio" r
     where r.opcion = 'PKC' and upper(btrim(split_part(r.texto, '|', 1))) = v_t
       and not public.es_legajo_test(r.legajo)
  ), pk as (
    select p.*, extract(epoch from p.t - lag(p.t) over (partition by p.legajo order by p.t)) seg,
           row_number() over (partition by p.legajo order by p.t) orden
      from pk0 p
  ), b as (select * from public.gv_analisis_cod_base(120)),
  ev as (
    select regexp_replace(regexp_replace(regexp_replace(upper(btrim(e.cod_art)),
             '\s+(LK|CH)$', ''), '([0-9E])L$', '\1'), '^0+(?=.)', '') ck,
           sum(coalesce(e.cajas_falto, 0)) falto
      from public."Entregas_Virgilio" e where upper(btrim(e.tanda)) = v_t group by 1
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'orden', pk.orden, 'cod', pk.crudo, 'ck', pk.ck,
           'desc', (select max(n.descripcion) from public.vista_nombres_articulos n
                     where regexp_replace(upper(btrim(n.cod)), '^0+(?=.)', '') = pk.ck),
           'ts', pk.t, 'pedidas', pk.esp, 'cajas', pk.re,
           'seg', round(pk.seg::numeric, 1),
           'seg_caja', round((pk.seg / nullif(pk.re, 0))::numeric, 2),
           'base_n', b.n, 'base_seg', b.base_seg, 'med_seg', b.med_seg, 'med_seg_caja', b.med_seg_caja,
           'esp_seg', case when b.base_seg is not null then round(greatest(b.base_seg, 5) + 3.74 * least(pk.re, 30), 1) end,
           'ratio', case when b.base_seg is not null and pk.seg is not null
                         then round((pk.seg / nullif(greatest(b.base_seg, 5) + 3.74 * least(pk.re, 30), 0))::numeric, 2) end,
           'seg_vista', ps.seg_vista, 'visitas', ps.visitas, 'confirmaciones', ps.confirmaciones,
           'sector', ps.sector, 'es_exc', ps.es_exc, 'accion', ps.accion_final,
           'falto_armado', ev.falto)
         order by pk.orden), '[]'::jsonb)
    into v_lin
    from pk left join b on b.ck = pk.ck
            left join ev on ev.ck = pk.ck
            left join lateral (
              select s.sector, s.es_exc, s.visitas, s.confirmaciones, s.accion_final,
                     round(extract(epoch from s.primera_conf - coalesce((select max(m.ts_cliente) from public."GV_Picking_Paso_Evento" m where m.evento = 'mostrado' and upper(btrim(m.tanda)) = v_t and m.paso = s.paso and m.legajo = s.legajo and m.ts_cliente <= s.primera_conf), s.primera_vez))::numeric, 1) seg_vista
                from public.gv_picking_paso s
               where s.tanda = v_t and (s.paso = pk.ck or s.paso = pk.crudo or s.art = pk.crudo or s.art = pk.ck)
               order by (s.paso = pk.crudo) desc, s.primera_conf limit 1) ps on true;

  select i.veces, i.seg_total into v_int_veces, v_int_seg
    from public.gv_picking_interrupcion i where i.tanda = v_t limit 1;

  select coalesce(jsonb_agg(jsonb_build_object('cod', q.cod, 'contado', q.contado, 'esperado', q.esperado,
                                               'dif', q.dif, 'ts', q.ts)), '[]'::jsonb)
    into v_cg
    from (select (public.gv_conteo_picking_calc(r.client_id)).* from public."Registros_Produccion_Virgilio" r
           where r.opcion = 'CG' and upper(btrim(split_part(r.texto, '|', 4))) = v_t) q
   where q.tanda is not null;

  with l as (select x from jsonb_array_elements(coalesce(v_lin, '[]'::jsonb)) x)
  select coalesce(jsonb_agg(z.a order by (z.a->>'peso')::int desc), '[]'::jsonb) into v_av from (
    select jsonb_build_object('tipo', 'paso_relampago', 'sev', 'alta', 'peso', 90,
             'texto', 'Hay ' || count(*) || ' codigo(s) confirmados a menos de 2 segundos de que la pantalla los mostro: '
                      || string_agg((x->>'cod') || ' (' || (x->>'seg_vista') || ' s, ' || (x->>'cajas') || ' cj)', ' - ')) a
      from l where (x->>'seg_vista') is not null and (x->>'seg_vista')::numeric between 0 and 1.999 and (x->>'cajas')::numeric >= 3
     having count(*) > 0
    union all
    select jsonb_build_object('tipo', 'paso_imposible', 'sev', 'alta', 'peso', 85,
             'texto', 'Hay ' || count(*) || ' codigo(s) con menos de 1 segundo por caja desde que la pantalla los mostro: '
                      || string_agg((x->>'cod') || ' (' || (x->>'cajas') || ' cj en ' || (x->>'seg_vista') || ' s)', ' - '))
      from l where (x->>'seg_vista') is not null and (x->>'seg_vista')::numeric >= 0 and (x->>'cajas')::numeric >= 5
        and (x->>'seg_vista')::numeric / nullif((x->>'cajas')::numeric, 0) < 1
     having count(*) > 0
    union all
    select jsonb_build_object('tipo', 'falto_en_armado', 'sev', 'alta', 'peso', 95,
             'texto', 'El picking dio por completo ' || count(*) || ' codigo(s) que el armado despues declaro faltante: '
                      || string_agg((x->>'cod') || ' (faltaron ' || (x->>'falto_armado') || ' cj)', ' - '))
      from l where (x->>'falto_armado') is not null and (x->>'falto_armado')::numeric > 0
        and (x->>'pedidas') is not null and (x->>'cajas')::numeric >= (x->>'pedidas')::numeric
     having count(*) > 0
    union all
    select jsonb_build_object('tipo', 'confirmacion_rapida', 'sev', 'baja', 'peso', 40,
             'texto', count(*) || ' codigo(s) se confirmaron a menos de 1 segundo por caja. Ojo: el PKC guarda '
                      || 'cuando se toco OK, no cuando se levanto la caja: mirarlo junto con el resto, no solo.')
      from l where (x->>'seg') is not null and (x->>'cajas')::numeric >= 5
        and (x->>'seg')::numeric / nullif((x->>'cajas')::numeric, 0) < 1
     having count(*) > 0
    union all
    select jsonb_build_object('tipo', 'linea_lenta', 'sev', 'media', 'peso', 50,
             'texto', count(*) || ' codigo(s) tardaron mas de 6 veces lo normal: '
                      || string_agg((x->>'cod') || ' (' || (x->>'seg') || ' s contra ' || (x->>'esp_seg') || ' s)', ' - '))
      from l where (x->>'ratio') is not null and (x->>'ratio')::numeric > 6 and (x->>'seg')::numeric > 300
     having count(*) > 0
    union all
    select jsonb_build_object('tipo', 'sin_stock', 'sev', 'media', 'peso', 60,
             'texto', v_pk.n_mx || ' codigo(s) sin stock en gondola al empezar el picking (fue, busco y no estaba). '
                      || 'Eso ya esta contemplado en el tiempo esperado.')
     where coalesce(v_pk.n_mx, 0) > 0
    union all
    select jsonb_build_object('tipo', 'sin_gondola', 'sev', 'media', 'peso', 55,
             'texto', v_pk.n_f || ' codigo(s) sin celda de gondola en el Mapa.')
     where coalesce(v_pk.n_f, 0) > 0
    union all
    select jsonb_build_object('tipo', 'huecos', 'sev', 'media', 'peso', 45,
             'texto', 'El picking tiene ' || round(v_pk.huecos_min) || ' min en huecos de mas de 5 minutos sin confirmar nada. '
                      || 'No cuentan en el tiempo real.')
     where coalesce(v_pk.huecos_min, 0) >= 5
    union all
    select jsonb_build_object('tipo', 'bloqueado', 'sev', 'baja', 'peso', 30,
             'texto', 'El celular estuvo bloqueado o la app en segundo plano ' || v_int_veces || ' vez/veces, '
                      || round(v_int_seg / 60.0) || ' min en total.')
     where coalesce(v_int_seg, 0) >= 120
    union all
    select jsonb_build_object('tipo', 'reconfirmado', 'sev', 'baja', 'peso', 25,
             'texto', count(*) || ' codigo(s) se confirmaron mas de una vez (se corrigio la cantidad).')
      from l where (x->>'confirmaciones') is not null and (x->>'confirmaciones')::int > 1
     having count(*) > 0
    union all
    select jsonb_build_object('tipo', 'ritmo_bajo', 'sev', 'media', 'peso', 70,
             'texto', 'El picking tardo ' || round(100 / nullif(v_pk.indice, 0)) || ' % de lo esperado para su dificultad ('
                      || lower(v_pk.nivel) || ', grado ' || v_pk.grado || ').')
     where v_pk.indice is not null and v_pk.indice < 0.7
    union all
    select jsonb_build_object('tipo', 'ritmo_alto', 'sev', 'media', 'peso', 75,
             'texto', 'El picking se hizo en ' || round(100 / nullif(v_pk.indice, 0)) || ' % de lo esperado para su dificultad ('
                      || lower(v_pk.nivel) || ', grado ' || v_pk.grado || '). Mirar el detalle.')
     where v_pk.indice is not null and v_pk.indice > 1.8
    union all
    select jsonb_build_object('tipo', 'conteo', 'sev', 'alta', 'peso', 80,
             'texto', 'El conteo de gondola de este picking no coincide con el sistema: '
                      || string_agg((y->>'cod') || ' conto ' || (y->>'contado') || ' y el sistema dice ' || (y->>'esperado'), ' - '))
      from jsonb_array_elements(coalesce(v_cg, '[]'::jsonb)) y
     where (y->>'dif') is not null and abs((y->>'dif')::numeric) >= 1
     having count(*) > 0
  ) z(a);

  return jsonb_build_object(
    'tanda', v_t, 'cabecera', v_cab, 'picking', v_pick, 'armado', v_arm,
    'lineas', coalesce(v_lin, '[]'::jsonb), 'avisos', v_av, 'conteo', v_cg,
    'registro_por_paso', v_paso_hay,
    'nota_paso', case when v_paso_hay then null
                      else 'Esta tanda no tiene el registro por paso (empezo el 05/10/2026): los avisos fuertes de tiempo '
                        || 'no se pueden calcular y el s/caja del PKC solo dice cuando se toco OK.' end);
end $$;
revoke all on function public.gv_analisis_tanda(text, text) from public;
grant execute on function public.gv_analisis_tanda(text, text) to anon, authenticated;

-- ─────────────────────────── 5. centinelas ───────────────────────────
-- ⚠ El patrón se elige del CÓDIGO, nunca de un comentario (el centinela los saca antes de buscar):
-- por eso gv_analisis_acceso_ok declara v_regla como constante y no como comentario de línea.
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
select * from (values
 ('gv_analisis_acceso_ok', 'funcion', 'v29\.64-acceso',
  'El Analisis Productivo lo ven el supervisor y los legajos activos de GV_Analisis_Acceso (Juan, 8).',
  'Luis 13/10/2026', 'v29.64'),
 ('gv_analisis_tanda', 'funcion', 'falto_en_armado',
  'El aviso que NO depende del reloj: el picking dio completo un codigo que el armado declaro faltante.',
  'Luis 13/10/2026', 'v29.64'),
 ('gv_analisis_tanda', 'funcion', 'seg_vista',
  'Los avisos fuertes de tiempo salen del registro por paso (mostrado->ok), no del ts del PKC.',
  'Luis 13/10/2026', 'v29.64')) v(o, c, p, r, q, ver)
 where not exists (select 1 from public."GV_Reglas_Centinela" z where z.objeto = v.o and z.patron = v.p);

-- Chequeo:
--   select public.gv_analisis_lista(14, '8');
--   select public.gv_analisis_tanda('<TANDA>', '8');
--   select * from public.gv_reglas_perdidas;
