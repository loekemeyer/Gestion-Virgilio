-- =====================================================================
-- gv_ancla — armado de tandas por ANCLAS GEOGRAFICAS  (v19.40)
-- =====================================================================
-- Regla de Luis, 17/09/2026:
--
--   Cuando entra un pedido, el sistema mira si en los proximos N dias
--   habiles ya hay una entrega programada CERCA. Si la hay, se suma a
--   ese dia. Si no, se programa para el dia 13 y ese pedido queda como
--   ANCLA de ese dia: todo lo que entre despues y caiga cerca se le pega.
--   Llegado el dia, el camion sale con lo que junto — aunque sea un solo
--   pedido. Nadie espera mas de 14 dias.
--
--   CERCA = a menos de 3,5 km del centro del ancla, en Capital.
--           En provincia = misma zona (Norte / Oeste / Sur), sin limite.
--   El centro del ancla se RECENTRA con cada pedido que entra (centroide
--   movil), asi un pedido del borde de la ciudad no deja medio circulo
--   tirado en provincia.
--
--   Supermercados y retiros quedan AFUERA: no cuentan camion.
--
-- ⚠ TODO ESTE ARCHIVO ES CODIGO NUEVO CON PREFIJO gv_ancla_*.
--   No reemplaza ni toca ninguna funcion del armado que corre hoy.
--   El interruptor `ancla_activo` nace en 0: nada de esto se ejecuta
--   solo. Lo unico que se puede correr es el SIMULADOR, que no escribe.
--
-- Medicion que lo respalda (532 pedidos cliente-dia, 19/06 a 18/09/2026):
--   septiembre real 36 camiones  ->  modelo 22   (-39%)
--   camiones de 1 sola parada    11 (31%) -> 3 (14%)
--   0 camiones fuera de la jornada de 8 h, 0 en fin de semana,
--   0 dias pidiendo un tercer camion, 0 desbordes de cupo.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. CONFIGURACION  (claves nuevas, prefijo ancla_)
-- ---------------------------------------------------------------------
insert into public."PPP_Web_Config" (clave, valor, valor_texto) values
  ('ancla_activo',          0,    null),   -- interruptor maestro. 0 = nada corre solo
  ('ancla_radio_km',        3.5,  null),   -- radio en CABA
  ('ancla_ventana_dias',    13,   null),   -- dias corridos que se miran hacia adelante
  ('ancla_dia_offset',      13,   null),   -- el ancla cae al dia 13 (entrega al 14)
  ('ancla_cupo_m3_dia',     10.0, null),   -- m3 que el deposito arma por dia (p90 real = 10,33)
  ('ancla_centroide_movil', 1,    null)    -- 1 = el centro se recentra con cada pedido
on conflict (clave) do nothing;

-- El tope por camion, la cantidad de camiones por dia y la jornada NO se
-- duplican: se leen de las claves que ya existen y que usa el armado vivo
--   camion_m3_tope = 6.00 · jornada_camiones = 2 · jornada_horas_max = 8


-- ---------------------------------------------------------------------
-- 2. MAPEO DE LOCALIDAD -> ZONA DE GBA
-- ---------------------------------------------------------------------
-- Editable a proposito, igual que GV_Region_Vecina: si aparece una
-- localidad nueva se agrega una fila y no se toca codigo.
create table if not exists public."GV_Ancla_Localidad" (
  localidad   text primary key,          -- normalizada: minuscula, sin acentos
  region      text not null,             -- GBA-N | GBA-O | GBA-S
  nota        text,
  creado_en   timestamptz not null default now()
);
alter table public."GV_Ancla_Localidad" enable row level security;

drop policy if exists "GV_Ancla_Localidad lectura" on public."GV_Ancla_Localidad";
create policy "GV_Ancla_Localidad lectura" on public."GV_Ancla_Localidad"
  for select to anon, authenticated using (true);

insert into public."GV_Ancla_Localidad" (localidad, region) values
  -- ---- SUR (zona de robos: viaja sola, ver regla de Luis 17/09) ----
  ('avellaneda','GBA-S'),('lanus','GBA-S'),('lanus este','GBA-S'),('lanus oeste','GBA-S'),
  ('lomas de zamora','GBA-S'),('banfield','GBA-S'),('temperley','GBA-S'),('turdera','GBA-S'),
  ('llavallol','GBA-S'),('quilmes','GBA-S'),('bernal','GBA-S'),('wilde','GBA-S'),
  ('sarandi','GBA-S'),('berazategui','GBA-S'),('florencio varela','GBA-S'),('f.varela','GBA-S'),
  ('adrogue','GBA-S'),('burzaco','GBA-S'),('monte grande','GBA-S'),('esteban echeverria','GBA-S'),
  ('valentin alsina','GBA-S'),('gerli','GBA-S'),('dock sud','GBA-S'),('rafael calzada','GBA-S'),
  -- ---- OESTE ----
  ('moron','GBA-O'),('haedo','GBA-O'),('ramos mejia','GBA-O'),('castelar','GBA-O'),
  ('ituzaingo','GBA-O'),('padua','GBA-O'),('merlo','GBA-O'),('moreno','GBA-O'),
  ('lujan','GBA-O'),('ciudadela','GBA-O'),('caseros','GBA-O'),('tres de febrero','GBA-O'),
  ('villa sarmiento','GBA-O'),('san justo','GBA-O'),('la matanza','GBA-O'),
  ('gregorio de laferrere','GBA-O'),('laferrere','GBA-O'),('hurlingham','GBA-O'),
  ('el palomar','GBA-O'),('palomar','GBA-O'),('tapiales','GBA-O'),('aldo bonzi','GBA-O'),
  ('villa tesei','GBA-O'),('william morris','GBA-O'),('paso del rey','GBA-O'),
  -- ---- NORTE ----
  ('vicente lopez','GBA-N'),('olivos','GBA-N'),('florida','GBA-N'),('carapachay','GBA-N'),
  ('munro','GBA-N'),('villa adelina','GBA-N'),('boulogne','GBA-N'),('san isidro','GBA-N'),
  ('martinez','GBA-N'),('beccar','GBA-N'),('san fernando','GBA-N'),('tigre','GBA-N'),
  ('benavidez','GBA-N'),('nordelta','GBA-N'),('escobar','GBA-N'),('garin','GBA-N'),
  ('del viso','GBA-N'),('pilar','GBA-N'),('san miguel','GBA-N'),('muniz','GBA-N'),
  ('bella vista','GBA-N'),('jose c paz','GBA-N'),('san martin','GBA-N'),
  ('villa ballester','GBA-N'),('ballester','GBA-N'),('chilavert','GBA-N'),
  ('jose leon suarez','GBA-N'),('villa lynch','GBA-N'),('saenz pena','GBA-N'),
  ('campo de mayo','GBA-N'),('los polvorines','GBA-N'),('grand bourg','GBA-N')
on conflict (localidad) do nothing;

comment on table public."GV_Ancla_Localidad" is
  'Localidad -> zona de GBA para el armado por anclas. Editable: una localidad nueva '
  'se agrega aca, no en el codigo. San Martin / Ballester / Chilavert van a NORTE '
  '(salen por Constituyentes-Marquez), decision del 17/09.';


-- ---------------------------------------------------------------------
-- 3. HELPERS, FEED Y MOTOR
-- ---------------------------------------------------------------------
-- ⚠ Lo que sigue es la definicion VIVA, traida con pg_get_functiondef
--   despues de aplicarla. No es una copia de lo que se penso escribir.

CREATE OR REPLACE FUNCTION public.gv_ancla_cfg(p_clave text, p_default numeric)
 RETURNS numeric
 LANGUAGE sql
 STABLE
AS $function$
  select coalesce((select valor from public."PPP_Web_Config" where clave = p_clave), p_default);
$function$;

CREATE OR REPLACE FUNCTION public.gv_ancla_es_habil(p_dia date)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  select extract(isodow from p_dia) <= 5
     and not exists (select 1 from public."GV_Dias_No_Habiles" d where d.fecha = p_dia);
$function$;

-- Se retrocede, NO se avanza: avanzar se pasaria de los 14 dias que el
-- pedido tiene comprometidos. Tope de 10 vueltas por si alguien carga
-- una semana entera como no habil.
CREATE OR REPLACE FUNCTION public.gv_ancla_habil_atras(p_dia date)
 RETURNS date
 LANGUAGE plpgsql
 STABLE
AS $function$
declare d date := p_dia; i int := 0;
begin
  while not public.gv_ancla_es_habil(d) and i < 10 loop
    d := d - 1; i := i + 1;
  end loop;
  return d;
end $function$;

CREATE OR REPLACE FUNCTION public.gv_ancla_norm(p_txt text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select btrim(lower(unaccent(coalesce(p_txt, ''))));
$function$;

-- CABA se agrupa por DISTANCIA; GBA por ZONA entera (Norte/Oeste/Sur), sin
-- limite de km; OTRO (interior y Buenos Aires sin mapear) no comparte etiqueta
-- util, y lo que lo mantiene en su lugar es el guard de jornada del motor.
CREATE OR REPLACE FUNCTION public.gv_ancla_grupo(p_region text, p_localidad text, p_provincia text)
 RETURNS TABLE(tipo text, zona text)
 LANGUAGE sql
 STABLE
AS $function$
  select case when p_region like 'C%' and p_region <> '?' then 'CABA'
              when z.region is not null then 'GBA' else 'OTRO' end,
         case when p_region like 'C%' and p_region <> '?' then null
              when z.region is not null then z.region
              when p_provincia = 'Buenos Aires' then 'BSAS-?' else 'INTERIOR' end
    from (select 1) _
    left join lateral (select region from public."GV_Ancla_Localidad"
                        where localidad = public.gv_ancla_norm(p_localidad)) z on true;
$function$;

-- Un pedido = un CLIENTE-DIA. Los que se despachan por expreso apuntan al
-- GALPON (dir_expreso), no al domicilio del cliente: 46,6% del total.
-- Deja afuera supermercados (gv_es_super) y retiros (zona_expreso = 'Retira').
CREATE OR REPLACE FUNCTION public.gv_ancla_paradas(p_desde date, p_hasta date)
 RETURNS TABLE(fs date, empresa text, cod text, m3 numeric, tipo text, zona text, lat double precision, lng double precision, prec text, via_expreso boolean, cam_real text)
 LANGUAGE sql
 STABLE
AS $function$
  with f as (
    select f.fecha_salida::date fs, coalesce(f.m3,0) m3, f.cod_cliente cod,
           public.gv_emp_de_np(f.np) emp, upper(btrim(f.tanda)) tanda
      from public."Facturacion_NP" f
     where f.fecha_salida >= p_desde and f.fecha_salida <= p_hasta
       and f.tanda ~ '^[A-Z]+[0-9]+[A-Z]+$'),
  d as (
    select distinct on (empresa, cod) empresa, cod, barrio_entrega, localidad, provincia,
           direccion, dir_expreso, zona_expreso
      from public."GV_Clientes_Direcciones" order by empresa, cod, slot),
  j as (
    select f.fs, f.m3, f.cod, f.emp, f.tanda,
           nullif(btrim(coalesce(d.dir_expreso,'')),'') is not null as via_exp,
           coalesce(nullif(btrim(coalesce(d.dir_expreso,'')),''), d.direccion) dir_ef,
           coalesce(nullif(btrim(coalesce(d.zona_expreso,'')),''), d.barrio_entrega, d.localidad) barrio_ef,
           d.localidad, d.provincia
      from f left join d on d.empresa = f.emp and d.cod = f.cod
     where coalesce(d.zona_expreso,'') <> 'Retira'
       and not public.gv_es_super(f.emp, f.cod)),
  p as (
    select j.*, pt.lat, pt.lng, pt.precision pr,
           public.gv_region_de(j.barrio_ef, null, j.dir_ef) reg
      from j left join lateral public.gv_ppp_web_punto(j.cod, j.dir_ef, j.barrio_ef, null) pt on true)
  select p.fs, p.emp, p.cod, round(sum(p.m3)::numeric, 3),
         (g.tipo)::text, (g.zona)::text, p.lat, p.lng, p.pr, p.via_exp,
         (regexp_match(min(p.tanda), '^([A-Z]+[0-9]+)'))[1]
    from p, lateral public.gv_ancla_grupo(p.reg, p.localidad, p.provincia) g
   where p.lat is not null
   group by p.fs, p.emp, p.cod, g.tipo, g.zona, p.lat, p.lng, p.pr, p.via_exp;
$function$;

-- EL MOTOR. NO ESCRIBE NADA: la temp table se descarta al commit.
-- Es VOLATILE, no STABLE, justamente por esa temp table.
CREATE OR REPLACE FUNCTION public.gv_ancla_simular(p_desde date, p_hasta date, p_radio_km numeric DEFAULT NULL::numeric, p_ventana integer DEFAULT NULL::integer, p_offset integer DEFAULT NULL::integer, p_cupo_m3_dia numeric DEFAULT NULL::numeric, p_centroide_movil boolean DEFAULT NULL::boolean)
 RETURNS TABLE(ancla_id integer, fecha date, tipo text, zona text, lat double precision, lng double precision, m3 numeric, paradas integer, movida boolean, sin_lugar boolean, km numeric, horas numeric, diam_km numeric)
 LANGUAGE plpgsql
AS $function$
declare
  v_radio  numeric := coalesce(p_radio_km,    public.gv_ancla_cfg('ancla_radio_km',     3.5));
  v_vent   int     := coalesce(p_ventana,     public.gv_ancla_cfg('ancla_ventana_dias', 13)::int);
  v_off    int     := coalesce(p_offset,      public.gv_ancla_cfg('ancla_dia_offset',   13)::int);
  v_cupo   numeric := coalesce(p_cupo_m3_dia, public.gv_ancla_cfg('ancla_cupo_m3_dia',  10.0));
  v_cent   boolean := coalesce(p_centroide_movil,
                        public.gv_ancla_cfg('ancla_centroide_movil', 1) = 1);
  v_tope   numeric := public.gv_ancla_cfg('camion_m3_tope',   6.00);
  v_maxcam int     := public.gv_ancla_cfg('jornada_camiones',  2)::int;
  v_hmax   numeric := public.gv_ancla_cfg('jornada_horas_max', 8);
  r record; a record; v_dia date; v_k int; v_id int := 0; v_ok boolean; v_f date; v_i int;
  v_pts jsonb; v_h numeric;
begin
  create temp table if not exists _anc (
    id int, fecha date, tipo text, zona text,
    lat double precision, lng double precision, m3 numeric, paradas int,
    movida boolean, sin_lugar boolean, pts jsonb) on commit drop;
  delete from _anc;

  for r in select * from public.gv_ancla_paradas(p_desde, p_hasta) order by fs, cod loop
    v_ok := false;
    for v_k in 1 .. v_vent loop
      v_dia := r.fs + v_k;
      continue when not public.gv_ancla_es_habil(v_dia);
      continue when (select coalesce(sum(t.m3),0) from _anc t where t.fecha = v_dia) + r.m3 > v_cupo;
      -- candidatas del dia, de la mas cercana a la mas lejana
      for a in
        select t.* from _anc t
         where t.fecha = v_dia and t.tipo = r.tipo and t.m3 + r.m3 <= v_tope
           and (case when r.tipo = 'CABA'
                     then public.gv_km(r.lat, r.lng, t.lat, t.lng) <= v_radio
                     else t.zona is not distinct from r.zona end)
         order by public.gv_km(r.lat, r.lng, t.lat, t.lng)
      loop
        -- ⚠ GUARD DE JORNADA: la parada entra solo si el camion sigue entrando en 8 h.
        --   Sin esto, las paradas de fuera del AMBA se agrupaban entre si y armaban
        --   recorridos de 60 km de diametro y 8,2 h (medido el 17/09).
        v_pts := a.pts || jsonb_build_array(jsonb_build_object('lat', r.lat, 'lng', r.lng));
        select h.horas into v_h from public.gv_ppp_ruta_horas(v_pts, a.paradas + 1) h;
        continue when coalesce(v_h, 0) > v_hmax;
        update _anc t set
          lat = case when v_cent then (t.lat*t.paradas + r.lat)/(t.paradas+1) else t.lat end,
          lng = case when v_cent then (t.lng*t.paradas + r.lng)/(t.paradas+1) else t.lng end,
          m3 = t.m3 + r.m3, paradas = t.paradas + 1, pts = v_pts
        where t.id = a.id;
        v_ok := true; exit;
      end loop;
      exit when v_ok;
    end loop;
    continue when v_ok;

    v_f := public.gv_ancla_habil_atras(r.fs + v_off);
    v_i := 0;
    while v_i < v_off - 1
      and ((select count(*) from _anc t where t.fecha = v_f) >= v_maxcam
        or (select coalesce(sum(t.m3),0) from _anc t where t.fecha = v_f) + r.m3 > v_cupo)
    loop
      v_f := public.gv_ancla_habil_atras(v_f - 1); v_i := v_i + 1;
    end loop;

    v_id := v_id + 1;
    insert into _anc values (v_id, v_f, r.tipo, r.zona, r.lat, r.lng, r.m3, 1, v_i > 0,
      (select count(*) from _anc t where t.fecha = v_f) >= v_maxcam
        or (select coalesce(sum(t.m3),0) from _anc t where t.fecha = v_f) + r.m3 > v_cupo,
      jsonb_build_array(jsonb_build_object('lat', r.lat, 'lng', r.lng)));
  end loop;

  return query
    select t.id, t.fecha, t.tipo, t.zona, t.lat, t.lng, t.m3, t.paradas, t.movida, t.sin_lugar,
           round(h.km::numeric, 1), round(h.horas::numeric, 2),
           round((select coalesce(max(public.gv_km(
                    (x->>'lat')::float8, (x->>'lng')::float8,
                    (y->>'lat')::float8, (y->>'lng')::float8)), 0)
                   from jsonb_array_elements(t.pts) x, jsonb_array_elements(t.pts) y)::numeric, 1)
      from _anc t left join lateral public.gv_ppp_ruta_horas(t.pts, t.paradas) h on true
     order by t.fecha, t.id;
end $function$;

-- Compara, sobre el MISMO conjunto de pedidos, los camiones que salieron de
-- verdad contra los que habria armado el modelo. El camion real se deduce del
-- prefijo de la tanda (E09A -> E09) por dia.
CREATE OR REPLACE FUNCTION public.gv_ancla_comparar(p_desde date, p_hasta date)
 RETURNS TABLE(metrica text, real_ numeric, modelo numeric, dif_pct numeric)
 LANGUAGE plpgsql
AS $function$
declare
  r_cam int; r_ped int; r_m3 numeric; r_solos int;
  m_cam int; m_ped int; m_m3 numeric; m_solos int;
begin
  with p as (select * from public.gv_ancla_paradas(p_desde, p_hasta)),
       c as (select fs, cam_real, count(*) clientes, sum(m3) m3 from p group by 1,2)
  select count(*), (select count(*) from p), (select round(sum(m3),2) from p),
         count(*) filter (where clientes = 1)
    into r_cam, r_ped, r_m3, r_solos
    from c;

  with a as (select * from public.gv_ancla_simular(p_desde, p_hasta))
  select count(*), sum(paradas), round(sum(m3),2), count(*) filter (where paradas = 1)
    into m_cam, m_ped, m_m3, m_solos
    from a;

  return query
  select 'pedidos (cliente-dia)', r_ped::numeric, m_ped::numeric, null::numeric
  union all select 'm3 despachados', r_m3, m_m3, null
  union all select 'CAMIONES', r_cam, m_cam, round(100.0*(m_cam-r_cam)/nullif(r_cam,0),1)
  union all select 'paradas por camion', round(r_ped::numeric/nullif(r_cam,0),2),
                                         round(m_ped::numeric/nullif(m_cam,0),2),
                                         round(100.0*((m_ped::numeric/nullif(m_cam,0))/nullif(r_ped::numeric/nullif(r_cam,0),0)-1),1)
  union all select 'm3 por camion', round(r_m3/nullif(r_cam,0),2), round(m_m3/nullif(m_cam,0),2),
                                    round(100.0*((m_m3/nullif(m_cam,0))/nullif(r_m3/nullif(r_cam,0),0)-1),1)
  union all select 'camiones de 1 sola parada', r_solos::numeric, m_solos::numeric,
                                    round(100.0*(m_solos-r_solos)/nullif(r_solos,0),1);
end $function$;


-- ---------------------------------------------------------------------
-- 4. SEGURIDAD
-- ---------------------------------------------------------------------
-- Ninguna es SECURITY DEFINER: corren como el invocador y respetan la RLS.
-- Igual se les revoca anon, porque leen Facturacion_NP y el padron de
-- direcciones y no las llama el front.
revoke execute on function public.gv_ancla_paradas(date,date) from public, anon;
revoke execute on function public.gv_ancla_simular(date,date,numeric,int,int,numeric,boolean) from public, anon;
revoke execute on function public.gv_ancla_comparar(date,date) from public, anon;
grant  execute on function public.gv_ancla_paradas(date,date) to authenticated, service_role;
grant  execute on function public.gv_ancla_simular(date,date,numeric,int,int,numeric,boolean) to authenticated, service_role;
grant  execute on function public.gv_ancla_comparar(date,date) to authenticated, service_role;


-- =====================================================================
-- COMO SE PRUEBA
-- =====================================================================
--   -- las anclas que se habrian armado en los ultimos 90 dias
--   select * from public.gv_ancla_simular(current_date - 90, current_date);
--
--   -- el resumen contra lo que paso de verdad
--   select * from public.gv_ancla_comparar(date '2026-09-01', date '2026-09-30');
--
--   -- probar otros valores sin tocar la config
--   select count(*) from public.gv_ancla_simular(current_date-90, current_date,
--            p_radio_km => 5.0, p_ventana => 10, p_offset => 10);
--
--   -- los invariantes, que tienen que dar 0 los cuatro
--   select count(*) filter (where horas > 8)                        fuera_de_jornada,
--          count(*) filter (where extract(isodow from fecha) > 5)   en_fin_de_semana,
--          count(*) filter (where sin_lugar)                        sin_lugar,
--          (select count(*) from public.gv_ancla_paradas(current_date-90, current_date))
--            - sum(paradas)                                          paradas_perdidas
--     from public.gv_ancla_simular(current_date - 90, current_date);
--
-- RESULTADO al 17/09/2026 (90 dias, 522 paradas, 213,4 m3):
--   91 anclas · 0 fuera de la jornada de 8 h (max 7,69) · 0 en fin de semana
--   14 de una sola parada · 4.405 km · 522 de 522 paradas asignadas
--   SEPTIEMBRE: 36 camiones reales -> 22 del modelo (-38,9%)
--               paradas por camion 3,28 -> 5,36 · de 1 sola parada 13 -> 3
--
-- ROLLBACK COMPLETO (no deja rastro):
--   drop function if exists public.gv_ancla_comparar(date,date);
--   drop function if exists public.gv_ancla_simular(date,date,numeric,int,int,numeric,boolean);
--   drop function if exists public.gv_ancla_paradas(date,date);
--   drop function if exists public.gv_ancla_grupo(text,text,text);
--   drop function if exists public.gv_ancla_habil_atras(date);
--   drop function if exists public.gv_ancla_es_habil(date);
--   drop function if exists public.gv_ancla_norm(text);
--   drop function if exists public.gv_ancla_cfg(text,numeric);
--   drop table if exists public."GV_Ancla_Localidad";
--   delete from public."PPP_Web_Config" where clave like 'ancla_%';
