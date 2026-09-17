-- =====================================================================
-- v19.46 — EL ANCLA DEL EXPRESO  (rama claude/dreamy-bell-29izan)
-- =====================================================================
-- Luis, 17/09/2026, sobre el informe de puntos de expreso (§3.jc):
--   "— ¿Le damos ancla propia al sur?  — Sí, dásela."
--
-- Por que: el expreso es el 46 % de las paradas y el 53 % del m3 del feed
-- del modelo (239 de 522 paradas, 113,4 de 213,4 m3 en 90 dias), y esta
-- todo en el mismo corredor — 94 % del m3 dentro de 8 km del centro de
-- Soldati. Pero con el radio de CABA (3,5 km) Barracas NO alcanza a
-- Soldati (6,8 km) y el corredor se parte en dos o tres camiones.
--
--   distancia al centro de Soldati   puntos  paradas   m3
--     <= 4 km                          33      155    75,7   (67 %)
--     4 - 8 km                         19       67    30,2   (27 %)
--     8 - 15 km                         3        8     3,2
--     > 15 km                           4        9     4,3
--
-- ⚠ Sigue sin correr solo: `ancla_activo` sigue en 0 y lo unico ejecutable
--   es el simulador, que no escribe.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. EL PRIMER INTENTO SALIO PEOR, Y ES LA LECCION QUE HAY QUE GUARDAR
-- ---------------------------------------------------------------------
-- Lo obvio era darle al expreso un POOL APARTE: tipo 'EXPRESO', una parada
-- de expreso solo se junta con expreso. Medido sobre los mismos 90 dias:
--
--                          anclas   de 1 parada   km     paradas/camion
--   v19.40 (sin nada)        86         12       4.221       6,07
--   pool aparte              93         16       4.628       5,61   <- PEOR
--   iman (lo que quedo)      80         13       4.277       6,53
--
-- Por que fallo: los galpones ya se venian juntando con clientes A DOMICILIO
-- de CABA que les quedan cerca. Separarlos en su propio pool no les dio
-- compania nueva — les SACO la que ya tenian. 33 de las 38 anclas con
-- expreso del modelo final son MIXTAS (expreso + domicilio); solo 5 son de
-- expreso puro.
--
--   ⇒ El ancla del expreso es un IMAN, no un corralito: lo que cambia es que
--     cuando el ancla YA lleva expreso, el radio para sumarle otra parada de
--     expreso pasa a ser el del corredor (8 km) en vez del de CABA (3,5).
--     Es estrictamente MAS permisivo que la v19.40, asi que no puede perder
--     nada de lo que ya funcionaba.
--
-- Y la regla general que deja: un cambio que "aisla" un subconjunto hay que
-- medirlo contra el anterior ANTES de escribirlo lindo. Este se aplico, se
-- corrio, dio peor, y se reescribio — leerlo no lo habria mostrado.


-- ---------------------------------------------------------------------
-- 2. CONFIGURACION (dos claves nuevas)
-- ---------------------------------------------------------------------
insert into public."PPP_Web_Config" (clave, valor, valor_texto) values
  ('ancla_expreso_activo',   1,   null),   -- 0 = se comporta exactamente como la v19.40
  ('ancla_expreso_radio_km', 8.0, null)    -- el tamano del corredor, no un valor tuneado
on conflict (clave) do nothing;

-- ⚠ POR QUE 8 Y NO 12 O 15. En 90 dias el barrido da 3,5→86 · 6→86 · 8→80 ·
--   10→85 · 12→78 · 15→77: NO es monotono, o sea que la diferencia entre 8 y
--   15 es ruido del orden greedy, no senal. Mes a mes empatan o gana 8:
--     septiembre  8 km → 20 camiones / 1.106 km   ·  12 km → 20 / 1.106
--     agosto      8 km → 28 camiones / 1.549 km   ·  12 km → 29 / 1.551
--   8 km es ademas el unico valor que sale de la geografia y no de tunear:
--   es el tamano del corredor (Soldati-Pompeya-Barracas-P.Patricios miden
--   6,9 km de punta a punta) y cubre el 94 % del m3 de expreso.


-- ---------------------------------------------------------------------
-- 3. EL MOTOR  (definicion VIVA, traida con pg_get_functiondef)
-- ---------------------------------------------------------------------
-- Cambia la firma (dos parametros nuevos) y el RETURNS TABLE (es_expreso,
-- paradas_exp), asi que va DROP + CREATE. La firma vieja de 7 argumentos se
-- dropea a proposito, para que ningun llamador viejo resuelva a la vieja en
-- silencio — mismo criterio que la v18.87 con gv_ppp_web_tanda_abierta_cliente.
drop function if exists public.gv_ancla_simular(date,date,numeric,int,int,numeric,boolean);

CREATE OR REPLACE FUNCTION public.gv_ancla_simular(
  p_desde date, p_hasta date,
  p_radio_km numeric DEFAULT NULL::numeric,
  p_ventana integer DEFAULT NULL::integer,
  p_offset integer DEFAULT NULL::integer,
  p_cupo_m3_dia numeric DEFAULT NULL::numeric,
  p_centroide_movil boolean DEFAULT NULL::boolean,
  p_expreso_activo boolean DEFAULT NULL::boolean,
  p_expreso_radio_km numeric DEFAULT NULL::numeric)
 RETURNS TABLE(ancla_id integer, fecha date, tipo text, zona text, es_expreso boolean,
               lat double precision, lng double precision, m3 numeric, paradas integer,
               paradas_exp integer, movida boolean, sin_lugar boolean,
               km numeric, horas numeric, diam_km numeric)
 LANGUAGE plpgsql
AS $function$
declare
  v_radio  numeric := coalesce(p_radio_km,    public.gv_ancla_cfg('ancla_radio_km',     3.5));
  v_vent   int     := coalesce(p_ventana,     public.gv_ancla_cfg('ancla_ventana_dias', 13)::int);
  v_off    int     := coalesce(p_offset,      public.gv_ancla_cfg('ancla_dia_offset',   13)::int);
  v_cupo   numeric := coalesce(p_cupo_m3_dia, public.gv_ancla_cfg('ancla_cupo_m3_dia',  10.0));
  v_cent   boolean := coalesce(p_centroide_movil,
                        public.gv_ancla_cfg('ancla_centroide_movil', 1) = 1);
  -- ⚠ EL ANCLA DEL EXPRESO ES UN IMAN, NO UN CORRALITO (v19.46, Luis 17/09).
  --   Primer intento: pool aparte, una parada de expreso solo con expreso. Salio
  --   PEOR (93 anclas contra 86, 4.628 km contra 4.221): los galpones ya se venian
  --   juntando con clientes a domicilio de CABA, y separarlos les saco opciones.
  --   Lo que sirve es AGRANDAR el radio cuando el ancla ya lleva expreso: el
  --   corredor sur entero (Soldati-Pompeya-Barracas-P.Patricios, 6,9 km de punta a
  --   punta) pasa a ser UN ancla, sin perder nada de lo que ya funcionaba.
  v_eact   boolean := coalesce(p_expreso_activo,
                        public.gv_ancla_cfg('ancla_expreso_activo', 1) = 1);
  v_erad   numeric := coalesce(p_expreso_radio_km,
                        public.gv_ancla_cfg('ancla_expreso_radio_km', 8.0));
  v_tope   numeric := public.gv_ancla_cfg('camion_m3_tope',   6.00);
  v_maxcam int     := public.gv_ancla_cfg('jornada_camiones',  2)::int;
  v_hmax   numeric := public.gv_ancla_cfg('jornada_horas_max', 8);
  r record; a record; v_dia date; v_k int; v_id int := 0; v_ok boolean; v_f date; v_i int;
  v_pts jsonb; v_h numeric; v_exp boolean;
begin
  create temp table if not exists _anc (
    id int, fecha date, tipo text, zona text, es_exp boolean,
    lat double precision, lng double precision, m3 numeric, paradas int, par_exp int,
    movida boolean, sin_lugar boolean, pts jsonb) on commit drop;
  delete from _anc;

  for r in select * from public.gv_ancla_paradas(p_desde, p_hasta) order by fs, cod loop
    v_exp := v_eact and r.via_expreso;
    v_ok := false;
    for v_k in 1 .. v_vent loop
      v_dia := r.fs + v_k;
      continue when not public.gv_ancla_es_habil(v_dia);
      continue when (select coalesce(sum(t.m3),0) from _anc t where t.fecha = v_dia) + r.m3 > v_cupo;
      for a in
        select t.* from _anc t
         where t.fecha = v_dia and t.m3 + r.m3 <= v_tope
           and ( -- la regla de siempre, por tipo
                 (case when r.tipo = 'CABA'
                       then t.tipo = 'CABA' and public.gv_km(r.lat, r.lng, t.lat, t.lng) <= v_radio
                       else t.tipo = r.tipo and t.zona is not distinct from r.zona end)
                 -- y ademas: si la parada va por expreso y el ancla ya lleva expreso,
                 -- el radio es el del corredor (8 km), no el de CABA (3,5)
              or (v_exp and t.par_exp > 0
                        and public.gv_km(r.lat, r.lng, t.lat, t.lng) <= v_erad))
         order by public.gv_km(r.lat, r.lng, t.lat, t.lng)
      loop
        -- ⚠ GUARD DE JORNADA: la parada entra solo si el camion sigue entrando en 8 h.
        v_pts := a.pts || jsonb_build_array(jsonb_build_object('lat', r.lat, 'lng', r.lng));
        select h.horas into v_h from public.gv_ppp_ruta_horas(v_pts, a.paradas + 1) h;
        continue when coalesce(v_h, 0) > v_hmax;
        update _anc t set
          lat = case when v_cent then (t.lat*t.paradas + r.lat)/(t.paradas+1) else t.lat end,
          lng = case when v_cent then (t.lng*t.paradas + r.lng)/(t.paradas+1) else t.lng end,
          m3 = t.m3 + r.m3, paradas = t.paradas + 1,
          par_exp = t.par_exp + (case when r.via_expreso then 1 else 0 end), pts = v_pts
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
    insert into _anc values (v_id, v_f, r.tipo, r.zona, r.via_expreso, r.lat, r.lng, r.m3, 1,
      case when r.via_expreso then 1 else 0 end, v_i > 0,
      (select count(*) from _anc t where t.fecha = v_f) >= v_maxcam
        or (select coalesce(sum(t.m3),0) from _anc t where t.fecha = v_f) + r.m3 > v_cupo,
      jsonb_build_array(jsonb_build_object('lat', r.lat, 'lng', r.lng)));
  end loop;

  return query
    select t.id, t.fecha, t.tipo, t.zona, (t.par_exp > 0), t.lat, t.lng, t.m3, t.paradas, t.par_exp,
           t.movida, t.sin_lugar,
           round(h.km::numeric, 1), round(h.horas::numeric, 2),
           round((select coalesce(max(public.gv_km(
                    (x->>'lat')::float8, (x->>'lng')::float8,
                    (y->>'lat')::float8, (y->>'lng')::float8)), 0)
                   from jsonb_array_elements(t.pts) x, jsonb_array_elements(t.pts) y)::numeric, 1)
      from _anc t left join lateral public.gv_ppp_ruta_horas(t.pts, t.paradas) h on true
     order by t.fecha, t.id;
end $function$;


-- ---------------------------------------------------------------------
-- 4. EL COMPARADOR, con una fila mas: cuantos camiones llevan expreso
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.gv_ancla_comparar(p_desde date, p_hasta date)
 RETURNS TABLE(metrica text, real_ numeric, modelo numeric, dif_pct numeric)
 LANGUAGE plpgsql
AS $function$
declare
  r_cam int; r_ped int; r_m3 numeric; r_solos int; r_exp int;
  m_cam int; m_ped int; m_m3 numeric; m_solos int; m_exp int;
begin
  -- LO REAL: camion = prefijo de la tanda (E09A -> E09) por dia, con las mismas exclusiones
  with p as (select * from public.gv_ancla_paradas(p_desde, p_hasta)),
       c as (select fs, cam_real, count(*) clientes, sum(m3) m3,
                    count(*) filter (where via_expreso) ex from p group by 1,2)
  select count(*), (select count(*) from p), (select round(sum(m3),2) from p),
         count(*) filter (where clientes = 1), count(*) filter (where ex > 0)
    into r_cam, r_ped, r_m3, r_solos, r_exp
    from c;

  -- EL MODELO
  with a as (select * from public.gv_ancla_simular(p_desde, p_hasta))
  select count(*), sum(paradas), round(sum(m3),2), count(*) filter (where paradas = 1),
         count(*) filter (where es_expreso)
    into m_cam, m_ped, m_m3, m_solos, m_exp
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
                                    round(100.0*(m_solos-r_solos)/nullif(r_solos,0),1)
  union all select 'camiones que llevan expreso', r_exp::numeric, m_exp::numeric,
                                    round(100.0*(m_exp-r_exp)/nullif(r_exp,0),1);
end $function$;


-- ---------------------------------------------------------------------
-- 5. SEGURIDAD (la firma cambio: hay que volver a revocar)
-- ---------------------------------------------------------------------
revoke execute on function public.gv_ancla_simular(date,date,numeric,int,int,numeric,boolean,boolean,numeric)
  from public, anon;
grant  execute on function public.gv_ancla_simular(date,date,numeric,int,int,numeric,boolean,boolean,numeric)
  to authenticated, service_role;


-- =====================================================================
-- LO QUE DIO  (medido el 17/09/2026)
-- =====================================================================
--                              real   v19.40   v19.46
--   SEPTIEMBRE  camiones         36     22       20      (-38,9% -> -44,4%)
--               de 1 parada      13      3        4
--               m3 por camion  1,08   1,77     1,94
--               km               —   1.151    1.106      (menos km Y menos camiones)
--
--   AGOSTO      camiones         52     31       28      (-40,4% -> -46,2%)
--               de 1 parada      14      7        4
--               m3 por camion  1,85   3,10     3,43
--               km               —   1.531    1.549      (+1,2%)
--
--   90 DIAS     anclas           —      86       80
--               sin_lugar        —       1        0   <- la v19.46 tapa el unico
--                                                       pendiente que dejo la v19.40
--
--   Las 38 anclas con expreso del modelo: 9,9 paradas y 4,35 m3 de media,
--   diametro medio 7,6 km, 4,28 h de media (max 7,69 sobre un tope de 8).
--   33 de 38 son MIXTAS (expreso + domicilio) y solo 5 de expreso puro:
--   el iman funciono como se esperaba.
--
-- INVARIANTES, los seis en 0:
--   select count(*) filter (where horas > 8)                       fuera_de_jornada,
--          count(*) filter (where extract(isodow from fecha) > 5)  en_fin_de_semana,
--          count(*) filter (where sin_lugar)                       sin_lugar,
--          count(*) filter (where m3 > 6.0)                        pasa_el_camion,
--          (select count(*) from public.gv_ancla_paradas(current_date-90, current_date))
--            - sum(paradas)                                        paradas_perdidas
--     from public.gv_ancla_simular(current_date - 90, current_date);
--   -- 0 · 0 · 0 · 0 · 0  (80 anclas, 522 paradas, h max 7,69)
--   select fecha, count(*), round(sum(m3),2) from public.gv_ancla_simular(current_date-90, current_date)
--    group by 1 having count(*) > 2 or sum(m3) > 10.0;   -- vacio: ni un dia se pasa
--
-- REGRESION: con el interruptor apagado tiene que reproducir la v19.40 exacta.
--   select count(*) from public.gv_ancla_simular(current_date-90, current_date,
--            p_expreso_activo => false);   -- 86, igual que la v19.40/41
--
-- ⚠ LO QUE QUEDA FEO, Y NO ES DE LA REGLA: dos anclas con expreso pasan los
--   15 km de diametro (38,3 y 19,3 km). Las dos las siembra una parada cuyo
--   punto es el CENTROIDE DE AVELLANEDA, que sale de solo 2 clientes
--   geocodificados y cae 12 km al sudeste de donde esta (§3.jc). Con el
--   centroide bien, esas dos anclas miden ~10 km. Es dato, no codigo: no se
--   toco nada del padron.
--
-- ROLLBACK (deja la v19.40 tal cual estaba):
--   drop function if exists public.gv_ancla_simular(date,date,numeric,int,int,numeric,boolean,boolean,numeric);
--   -- y volver a aplicar el bloque 3 de sql/gv_ancla_v1940.sql + su gv_ancla_comparar
--   delete from public."PPP_Web_Config" where clave in ('ancla_expreso_activo','ancla_expreso_radio_km');
-- O, sin tocar nada:
--   update public."PPP_Web_Config" set valor = 0 where clave = 'ancla_expreso_activo';
