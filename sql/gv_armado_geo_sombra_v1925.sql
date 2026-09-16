-- ============================================================================================
-- v19.25 · ARMADO DE TANDAS POR CERCANÍA REAL — MODO SOMBRA
--
-- Pedido de Luis (16/09/2026), con los tres valores que aprobó: radio 3,5 km CABA / 5 km GBA,
-- 3 días hábiles de espera, y el techo de 8 h RETIENE.
--
-- ⚠ NADA DE ESTO TOCA EL ARMADO VIVO. `ppp_web_armar_tandas` sigue igual y `geo_armado_activo`
--   está en 0. Estas funciones sólo CALCULAN y devuelven el plan; ninguna escribe en
--   PPP_Web_Programacion. La comparación contra lo que hay se corre con:
--
--       select * from public.gv_ppp_web_sombra('2026-09-08','2026-09-23');
--       select * from public.gv_ppp_web_sombra_detalle('2026-09-08','2026-09-23');
--
-- Contexto y diagnóstico: docs/PROPUESTA-ARMADO-TANDAS-GEO.md · doc de Supabase §3.ih
-- ============================================================================================

-- ---------------------------------------------------------------------------- 1) parámetros
insert into public."PPP_Web_Config" (clave, valor, descripcion, actualizado) values
 ('geo_armado_activo',      0,           'v19.25 SOMBRA. 1 = las tandas se arman por CERCANIA REAL en vez de la cadena barrio->sector->camion. 0 = sistema de sectores de hoy.', now()),
 ('geo_fallback_tabla',     1,           'v19.25. Parada sin ubicacion: 1 = cae al sistema de sectores; 0 = queda en A Programar con motivo sin_ubicacion.', now()),
 ('radio_tanda_km',         3.5,         'v19.25 (Luis 16/09). Radio para juntar dos paradas en una TANDA, en CABA. Lo fija el par Boedo/Pompeya del dueno: 3,3 km entre centroides.', now()),
 ('radio_tanda_km_gba',     5.0,         'v19.25. Idem fuera de CABA.', now()),
 ('tanda_diam_max_km',      6.0,         'v19.25. Diametro maximo de una tanda.', now()),
 ('radio_viaje_km',         12.0,        'v19.25. Radio para compartir CAMION (viaje). Mucho mas grande que el de tanda: la tanda es picking, el viaje es ruta.', now()),
 ('radio_viaje_km_gba',     25.0,        'v19.25. Idem fuera de CABA.', now()),
 ('viaje_corta_por_ruta',   1,           'v19.25. 1 = un viaje no mezcla la ruta Sur/Centro/Oeste (zonas 1-4) con la Norte (5-7), igual que _pppRutaZona del front.', now()),
 ('radio_dia_km',           8.0,         'v19.25. Distancia al centroide de un camion ya programado para engancharse a ESE dia (CABA).', now()),
 ('radio_dia_km_gba',       15.0,        'v19.25. Idem fuera de CABA.', now()),
 ('dia_espera_max_habiles', 3,           'v19.25 (Luis 16/09). Dias habiles que se puede posponer un pedido esperando el camion de su zona.', now()),
 ('ruta_horas_guard',       1,           'v19.25 (Luis 16/09): RETIENE. 1 = el armado no agrega paradas a un camion-dia que pasaria jornada_horas_max.', now()),
 ('deposito_lat',          -34.6157998,  'v19.25. Deposito Virgilio 2788. Antes solo existia en PPP_Geo, escrito por el front.', now()),
 ('deposito_lng',          -58.5252267,  'v19.25. Idem, longitud.', now())
on conflict (clave) do nothing;

-- ⚠ CALIBRADO el 16/09 corriendo la sombra sobre los 12 dias reales (ver el bloque de medicion
--   al final): con radio de viaje 12/25 los dias 16 y 22/09 EMPEORABAN, porque el radio parte
--   corredores que estan "en el camino" (Lujan-Moreno, Pilar-San Isidro). Valores que quedaron:
update public."PPP_Web_Config" set valor = 20  where clave = 'radio_viaje_km';
update public."PPP_Web_Config" set valor = 60  where clave = 'radio_viaje_km_gba';
--   Y con radio de tanda 3,5/5 y diametro 6 la tanda quedaba mas compacta pero mas vacia
--   (91 tandas de 0,60 m3 contra 79 de 0,77 hoy). Con 5/8 y diametro 9: 77 tandas de 0,79.
update public."PPP_Web_Config" set valor = 5.0 where clave = 'radio_tanda_km';
update public."PPP_Web_Config" set valor = 8.0 where clave = 'radio_tanda_km_gba';
update public."PPP_Web_Config" set valor = 9.0 where clave = 'tanda_diam_max_km';

-- ---------------------------------------------------------------------------- 2) piezas base
-- (definiciones vivas, sacadas con pg_get_functiondef despues de aplicarlas)

CREATE OR REPLACE FUNCTION public.gv_km(p_lat1 double precision, p_lng1 double precision, p_lat2 double precision, p_lng2 double precision)
 RETURNS double precision
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  select case when p_lat1 is null or p_lat2 is null or p_lng1 is null or p_lng2 is null then null
         else 2 * 6371.0 * asin(sqrt(
              power(sin(radians(p_lat2 - p_lat1) / 2), 2)
            + cos(radians(p_lat1)) * cos(radians(p_lat2))
            * power(sin(radians(p_lng2 - p_lng1) / 2), 2))) end;
$function$;

-- ⚠ El paso 3 (paracaidas por codigo) EXIGE el mismo barrio. Sin eso, "Donofrio 128- Ciudadela"
--    de Jazquel (3814) — que no matchea por texto con "Donofrio 128" — caia en la sucursal de
--    Balvanera y el armado metia las dos en la misma tanda: el caso D69F que prohibe Luis.
--    El front (_pppGeoDe de index.html) TODAVIA tiene ese defecto: problema abierto.
CREATE OR REPLACE FUNCTION public.gv_ppp_web_punto(p_cod text, p_direccion text, p_barrio text, p_zona text DEFAULT NULL::text)
 RETURNS TABLE(lat double precision, lng double precision, "precision" text)
 LANGUAGE sql
 STABLE
AS $function$
  with q as (select btrim(coalesce(p_cod,'')) cod, lower(btrim(coalesce(p_direccion,''))) dir,
                    public._norm_barrio(p_barrio) bn, coalesce(p_zona,'') zona)
  select v.lat, v.lng, v.pr from q, lateral (
    select * from (
      select 1 o, g.lat, g.lng, 'exacta'::text pr, 0 us
        from public."GV_Geo_Cliente" g, q
       where g.cod = q.cod and q.cod <> '' and lower(btrim(g.direccion)) = q.dir and q.dir <> ''
      union all
      select 2, p.lat, p.lng, 'exacta', 0
        from public."PPP_Geo" p, q
       where lower(btrim(p.direccion)) = q.dir and q.dir <> '' and p.lat is not null
      union all
      -- 3) por codigo de cliente, SOLO si es el mismo barrio (si no, es OTRA sucursal)
      select 3, g.lat, g.lng, 'cliente', coalesce(g.usos,0)
        from public."GV_Geo_Cliente" g, q
       where g.cod = q.cod and q.cod <> ''
         and (q.bn = '' or public._norm_barrio(g.barrio) = q.bn)
      union all
      select 4, avg(g.lat), avg(g.lng), 'barrio', 0
        from public."GV_Geo_Cliente" g, q
       where public._norm_barrio(g.barrio) = q.bn and q.bn <> ''
       having count(*) >= 2
    ) c where c.lat is not null order by c.o, c.us desc limit 1
  ) v
  where q.zona !~* 'retir';
$function$;

CREATE OR REPLACE FUNCTION public.gv_ppp_ruta_orden(p_pts jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_lat double precision[] := '{}'; v_lng double precision[] := '{}'; v_use boolean[] := '{}';
  v_out jsonb := '[]'::jsonb;
  v_cx double precision; v_cy double precision;
  v_best int; v_bd double precision; i int; k int; n int;
begin
  select coalesce((select valor from public."PPP_Web_Config" where clave='deposito_lat'), -34.6157998),
         coalesce((select valor from public."PPP_Web_Config" where clave='deposito_lng'), -58.5252267)
    into v_cx, v_cy;
  for i in 0 .. coalesce(jsonb_array_length(p_pts),0) - 1 loop
    if (p_pts->i->>'lat') is not null and (p_pts->i->>'lng') is not null then
      v_lat := v_lat || (p_pts->i->>'lat')::double precision;
      v_lng := v_lng || (p_pts->i->>'lng')::double precision;
      v_use := v_use || true;
    end if;
  end loop;
  n := coalesce(array_length(v_lat,1), 0);
  for k in 1 .. n loop
    select t.idx, t.d into v_best, v_bd
      from (select g.i idx, public.gv_km(v_cx, v_cy, v_lat[g.i], v_lng[g.i]) d
              from generate_series(1, n) g(i) where v_use[g.i] order by 2 limit 1) t;
    exit when v_best is null;
    v_use[v_best] := false;
    v_out := v_out || jsonb_build_object('lat', v_lat[v_best], 'lng', v_lng[v_best], 'km', round(v_bd::numeric,3));
    v_cx := v_lat[v_best]; v_cy := v_lng[v_best];
  end loop;
  return v_out;
end $function$;

-- Misma cuenta que _pppJornadaCam de index.html. Diferencia medida: 2,40 h contra 2,39 del front,
-- por el modo de redondeo del ultimo decimal (Postgres redondea medio arriba). La formula es la misma.
CREATE OR REPLACE FUNCTION public.gv_ppp_ruta_horas(p_pts jsonb, p_paradas integer DEFAULT NULL::integer)
 RETURNS TABLE(km numeric, horas numeric, paradas integer, h_viaje numeric, h_descarga numeric)
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_kmh numeric  := coalesce((select valor from public."PPP_Web_Config" where clave='jornada_km_h'), 28);
  v_fact numeric := coalesce((select valor from public."PPP_Web_Config" where clave='jornada_factor_ruta'), 1.35);
  v_minp numeric := coalesce((select valor from public."PPP_Web_Config" where clave='jornada_min_parada'), 15);
  v_dlat double precision := coalesce((select valor from public."PPP_Web_Config" where clave='deposito_lat'), -34.6157998);
  v_dlng double precision := coalesce((select valor from public."PPP_Web_Config" where clave='deposito_lng'), -58.5252267);
  v_ord jsonb; v_km numeric := 0; v_n int; i int; v_h numeric;
begin
  v_ord := public.gv_ppp_ruta_orden(p_pts);
  v_n := coalesce(jsonb_array_length(v_ord), 0);
  for i in 0 .. v_n - 1 loop v_km := v_km + (v_ord->i->>'km')::numeric; end loop;
  if v_n > 0 then
    v_km := v_km + public.gv_km((v_ord->(v_n-1)->>'lat')::double precision,
                                (v_ord->(v_n-1)->>'lng')::double precision, v_dlat, v_dlng)::numeric;
  end if;
  km         := round(v_km * v_fact, 2);
  paradas    := coalesce(p_paradas, v_n);
  v_h        := case when v_kmh > 0 then (v_km * v_fact) / v_kmh else 0 end + paradas * v_minp / 60.0;
  h_viaje    := round(case when v_kmh > 0 then (v_km * v_fact) / v_kmh else 0 end, 3);
  h_descarga := round(paradas * v_minp / 60.0, 3);
  horas      := round(v_h, 2);
  return next;
end $function$;

-- ---------------------------------------------------------------------------- 3) el núcleo
-- ⚠ Los regex de zona van con ([^0-9]|$) y NO con \b: en Postgres \b es BACKSPACE, no limite de
--   palabra (eso es \y). Escrito con \b no matcheaba NUNCA, asi que todo corria con los radios de
--   GBA y el corte de ruta quedaba en '?'. Se descubrio corriendo la sombra, no leyendo el codigo.
CREATE OR REPLACE FUNCTION public.gv_ppp_web_agrupar_geo(p_paradas jsonb)
 RETURNS TABLE(viaje integer, tanda_ix integer, orden integer, key text, cod text, m3 numeric, lat double precision, lng double precision, es_super boolean, ruta text, motivo text)
 LANGUAGE plpgsql
AS $function$
#variable_conflict use_column
declare
  v_rt      numeric := coalesce((select valor from public."PPP_Web_Config" where clave='radio_tanda_km'), 3.5);
  v_rt_gba  numeric := coalesce((select valor from public."PPP_Web_Config" where clave='radio_tanda_km_gba'), 5.0);
  v_rv      numeric := coalesce((select valor from public."PPP_Web_Config" where clave='radio_viaje_km'), 12.0);
  v_rv_gba  numeric := coalesce((select valor from public."PPP_Web_Config" where clave='radio_viaje_km_gba'), 25.0);
  v_diam    numeric := coalesce((select valor from public."PPP_Web_Config" where clave='tanda_diam_max_km'), 6.0);
  v_m3cam   numeric := coalesce((select valor from public."PPP_Web_Config" where clave='camion_m3_tope'), 6.0);
  v_m3tan   numeric := coalesce((select valor from public."PPP_Web_Config" where clave='tanda_m3_max_mezcla'), 1.0);
  v_hmax    numeric := coalesce((select valor from public."PPP_Web_Config" where clave='jornada_horas_max'), 8);
  v_guard   boolean := coalesce((select valor from public."PPP_Web_Config" where clave='ruta_horas_guard'), 1) <> 0;
  v_xruta   boolean := coalesce((select valor from public."PPP_Web_Config" where clave='viaje_corta_por_ruta'), 1) <> 0;
  v_dlat double precision := coalesce((select valor from public."PPP_Web_Config" where clave='deposito_lat'), -34.6157998);
  v_dlng double precision := coalesce((select valor from public."PPP_Web_Config" where clave='deposito_lng'), -58.5252267);
  v_vi int := 0; r record; c record; t record;
  v_h numeric; v_ok boolean; v_gr int; v_tix int; v_acum numeric; v_nuevo boolean;
begin
  drop table if exists _geo_p; drop table if exists _geo_g; drop table if exists _geo_t;
  create temp table _geo_p on commit drop as
  select (x->>'key')::text kk, coalesce(nullif(x->>'cod',''),'?') ccod,
         coalesce((x->>'m3')::numeric,0) pm3,
         nullif(x->>'lat','')::double precision plat, nullif(x->>'lng','')::double precision plng,
         public._norm_barrio(x->>'barrio') bn, coalesce(x->>'zona','') zona,
         coalesce((x->>'super')::boolean,false) sup,
         (coalesce(x->>'zona','') !~ '^\s*Zona\s*[123]([^0-9]|$)') gba,
         case when coalesce((x->>'super')::boolean,false) then 'sup'
              when coalesce(x->>'zona','') ~ '^\s*Zona\s*[1-4]([^0-9]|$)' then 'so'
              when coalesce(x->>'zona','') ~ '^\s*Zona\s*[5-7]([^0-9]|$)' then 'n'
              else '?' end rt,
         null::int grp
    from jsonb_array_elements(p_paradas) x;

  -- (1) GRUPO = cliente, partido si sus sucursales estan a mas de un radio de TANDA o si cambian
  --     de ruta (Luis v18.87, medido en km en vez de por etiqueta de camion)
  v_gr := 0;
  for r in select distinct ccod from _geo_p order by 1 loop
    for c in select kk, plat, plng, gba, rt from _geo_p where ccod = r.ccod order by plat nulls last, plng loop
      update _geo_p s set grp = (
        select g.grp from _geo_p g
         where g.ccod = r.ccod and g.grp is not null and g.rt = c.rt
           and (g.plat is null or c.plat is null
                or public.gv_km(g.plat, g.plng, c.plat, c.plng) <= case when c.gba then v_rt_gba else v_rt end)
         order by g.grp limit 1)
       where s.kk = c.kk;
      if (select grp from _geo_p where kk = c.kk) is null then
        v_gr := v_gr + 1; update _geo_p set grp = v_gr where kk = c.kk;
      end if;
    end loop;
  end loop;

  create temp table _geo_g on commit drop as
  select grp, min(ccod) ccod, sum(pm3) gm3, bool_or(sup) sup, bool_or(gba) gba, min(rt) rt,
         avg(plat) glat, avg(plng) glng, count(*) paradas,
         max(public.gv_km(v_dlat, v_dlng, plat, plng)) km_dep, null::int vj
    from _geo_p group by grp;

  -- (2) VIAJE = camion. Semilla: el grupo mas LEJOS del deposito (arrancando por el cercano, el
  --     lejano queda solo, que es el problema a resolver). Crece por el mas cercano.
  loop
    select g.* into r from _geo_g g where g.vj is null order by g.km_dep desc nulls last, g.grp limit 1;
    exit when r.grp is null;
    v_vi := v_vi + 1;
    update _geo_g set vj = v_vi where grp = r.grp;
    if not r.sup then
      loop
        v_ok := false;
        for c in
          select g.*, (select min(public.gv_km(g.glat, g.glng, p.plat, p.plng))
                         from _geo_p p join _geo_g gg on gg.grp = p.grp where gg.vj = v_vi) dmin
            from _geo_g g where g.vj is null and not g.sup and (not v_xruta or g.rt = r.rt)
           order by dmin nulls last, g.km_dep desc
        loop
          if exists (select 1 from _geo_p a join _geo_g ga on ga.grp = a.grp
                       join _geo_p b on b.grp = c.grp
                       join public."GV_Barrios_Pares" bp
                         on bp.barrio_a = least(a.bn, b.bn) and bp.barrio_b = greatest(a.bn, b.bn)
                      where ga.vj = v_vi and not bp.permitido) then continue; end if;
          if c.dmin is null or c.dmin > (case when c.gba then v_rv_gba else v_rv end) then continue; end if;
          if (select coalesce(sum(g.gm3),0) from _geo_g g where g.vj = v_vi) + c.gm3 > v_m3cam then continue; end if;
          if v_guard then
            select h.horas into v_h from public.gv_ppp_ruta_horas(
              (select coalesce(jsonb_agg(jsonb_build_object('lat', p.plat, 'lng', p.plng)) filter (where p.plat is not null), '[]'::jsonb)
                 from _geo_p p join _geo_g g on g.grp = p.grp where g.vj = v_vi or p.grp = c.grp),
              (select count(*)::int from _geo_p p join _geo_g g on g.grp = p.grp where g.vj = v_vi or p.grp = c.grp)) h;
            if v_h > v_hmax then continue; end if;
          end if;
          update _geo_g set vj = v_vi where grp = c.grp;
          v_ok := true; exit;
        end loop;
        exit when not v_ok;
      end loop;
    end if;
  end loop;

  -- (3) TANDA = picking. Dentro del viaje, en ORDEN DE RUTA, corta por m3, radio y diametro.
  create temp table _geo_t (grp int primary key, tix int) on commit drop;
  for r in select distinct vj from _geo_g order by 1 loop
    v_tix := 0; v_acum := 0;
    for t in
      with ruta as (
        select public.gv_ppp_ruta_orden(
          (select coalesce(jsonb_agg(jsonb_build_object('lat', p.plat, 'lng', p.plng)) filter (where p.plat is not null), '[]'::jsonb)
             from _geo_p p join _geo_g g on g.grp = p.grp where g.vj = r.vj)) ord
      ), pos as (
        select (e.v->>'lat')::double precision plat, (e.v->>'lng')::double precision plng, e.i
          from ruta cross join lateral jsonb_array_elements(ruta.ord) with ordinality e(v,i)
      )
      select g.grp, g.gm3, g.glat, g.glng, g.gba, min(coalesce(po.i, 999)) ord_grp
        from _geo_g g join _geo_p p on p.grp = g.grp
        left join pos po on po.plat = p.plat and po.plng = p.plng
       where g.vj = r.vj
       group by g.grp, g.gm3, g.glat, g.glng, g.gba
       order by 6, 1
    loop
      v_nuevo := v_tix = 0
              or v_acum + t.gm3 > v_m3tan
              or coalesce((select min(public.gv_km(t.glat, t.glng, p.plat, p.plng))
                             from _geo_p p join _geo_t x on x.grp = p.grp
                            where x.tix = v_tix and p.plat is not null), 0)
                 > (case when t.gba then v_rt_gba else v_rt end)
              or coalesce((select max(public.gv_km(t.glat, t.glng, p.plat, p.plng))
                             from _geo_p p join _geo_t x on x.grp = p.grp
                            where x.tix = v_tix and p.plat is not null), 0) > v_diam;
      if v_nuevo then v_tix := v_tix + 1; v_acum := 0; end if;
      insert into _geo_t (grp, tix) values (t.grp, v_tix);
      v_acum := v_acum + t.gm3;
    end loop;
  end loop;

  return query
  select g.vj::int, x.tix::int,
         row_number() over (partition by g.vj order by x.tix, p.kk)::int,
         p.kk, p.ccod, p.pm3, p.plat, p.plng, p.sup, p.rt,
         case when p.plat is null then 'sin_ubicacion' else null end
    from _geo_p p join _geo_g g on g.grp = p.grp join _geo_t x on x.grp = p.grp
   order by g.vj, x.tix, p.kk;
end $function$;

-- ------------------------------------------------------------------- 4) la sombra (comparacion)
-- gv_ppp_web_sombra        → una fila 'hoy' y una 'sombra' por dia, con km, horas y fletero-dias.
-- gv_ppp_web_sombra_detalle → el plan parada por parada, para chequear invariantes.
-- 'hoy' toma como camion el PREFIJO del codigo de tanda (LETRA+NN), que es como agrupa el front.
-- Las definiciones completas de estas dos estan aplicadas en la base; se recuperan con:
--   select pg_get_functiondef(oid) from pg_proc where proname in
--     ('gv_ppp_web_sombra','gv_ppp_web_sombra_detalle');

-- ------------------------------------------------------------------------- 5) grants (sombra)
revoke execute on function public.gv_km(double precision,double precision,double precision,double precision) from anon;
revoke execute on function public.gv_ppp_web_punto(text,text,text,text) from anon;
revoke execute on function public.gv_ppp_ruta_orden(jsonb) from anon;
revoke execute on function public.gv_ppp_ruta_horas(jsonb,int) from anon;
revoke execute on function public.gv_ppp_web_agrupar_geo(jsonb) from anon;
revoke execute on function public.gv_ppp_web_sombra(date,date) from anon;
revoke execute on function public.gv_ppp_web_sombra_detalle(date,date) from anon;

-- ------------------------------------------------------------------------- 6) MEDICION 16/09
-- Ventana 2026-09-08 a 2026-09-23 (12 dias con programacion, 140 paradas, web + ISIS, sin Retira):
--
--   escenario | viajes | tandas | m3/tanda |   km  | horas | fletero-dias | flacos | dias >2 fleteros
--   ----------+--------+--------+----------+-------+-------+--------------+--------+-----------------
--   hoy       |   34   |   79   |  0,771   | 1.805 |  99,5 |      19      |   13   |        1
--   sombra    |   25   |   77   |  0,791   | 1.492 |  88,3 |      16      |    6   |        0
--
--   -26% viajes · -17% km · -11% horas · -16% fletero-dias · el dia que no entra en 2 fleteros
--   deja de existir · y la tanda queda MAS llena, no mas vacia.
--
-- Invariantes sobre el plan completo (todos en cero):
--   tandas que mezclan super con clientes .... 0
--   viajes que mezclan super con clientes .... 0
--   tandas que mezclan ruta so/n ............. 0
--   tandas con diametro > tanda_diam_max_km .. 0
--   paradas sin ubicacion .................... 0
--
-- Caso Jazquel (3814) el 21/09, que es el que motivo la regla de Luis: la sombra lo parte en
-- dos tandas de DOS viajes (Balvanera/Once en la ruta so, Ciudadela en la n) el MISMO dia.
--
-- Lo que la sombra TODAVIA no hace: mover el pedido de dia (R5, los 3 dias habiles). Medido
-- aparte, 4 de los 5 viajes flacos que quedan tienen un camion cerca dentro de 3 dias habiles:
-- 08→09/09, 15→16/09, 16→17/09 y 17→21/09. El quinto (22/09) no tiene a donde ir.
