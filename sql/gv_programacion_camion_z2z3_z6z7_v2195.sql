-- v21.95 (Luis, 23/09): reglas de CAMION al elegir el dia (pase (g) del armador).
--   * Z2 y Z3 van en el MISMO camion si cada una suma < 1 m3 ese dia. Si una llega a >= 1 m3, va sola.
--   * Z6 y Z7 van SIEMPRE juntas (GBA Norte). Z7 sola solo si en su plazo no hay dia con Z6/Z7.
--   Las TANDAS no mezclan zonas distintas de camion: gv_ppp_web_camion sigue dando una etiqueta
--   por zona (Capital Centro / Capital Oeste / GBA Norte / GBA Norte Lejos). La union es del
--   CAMION, no del picking: si una zona pasa de 1 m3 despues, cambia la cuenta de camiones y
--   ningun pallet se toca.
--   El m3 se mide con TODO lo programado ese dia (web + ISIS). Retira no cuenta (no va en camion:
--   su zona no es 'Zona N'). Prioridad (Luis): max entrega con la menor cantidad de camiones.
drop function if exists public.gv_ppp_web_dia_grupo(text, date, boolean, date);
create or replace function public.gv_ppp_web_dia_grupo(p_zona text, p_entrada date, p_expreso boolean,
                                                       p_min date, p_m3 numeric default 0)
returns date language plpgsql set search_path to 'public', 'pg_temp' as $function$
declare
  v_grp   text := public.gv_ppp_web_camion(p_zona, null::text);
  v_lim   date := coalesce(p_entrada, current_date) + case when p_expreso then 13 else 14 end;
  v_m3    numeric := coalesce(p_m3, 0);
  v_otro  text;
  v_hasta date;
  v_d     date;
  v_g     int := 0;
begin
  if v_grp is null or coalesce(p_zona, '') !~ '^\s*Zona\s*[0-9]+' then return null; end if;
  -- v21.95: Z6+Z7 son un solo camion
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

  drop table if exists _gdg_oc;
  create temp table _gdg_oc on commit drop as
  select g2::date as dia,
         coalesce((select sum(z.m3) from _gdg_z z where z.dia = g2::date and z.g = v_grp), 0) as m3_propio,
         (select z.m3 from _gdg_z z where z.dia = g2::date and z.g = v_otro) as m3_otro,
         exists (select 1 from _gdg_z z where z.dia = g2::date and z.g = v_grp) as tiene_propio,
         -- camiones del dia: un grupo = un camion, salvo Z2+Z3 que cuentan UNO si las dos < 1 m3
         (select count(*) from _gdg_z z where z.dia = g2::date)
         - case when (select count(*) from _gdg_z z where z.dia = g2::date
                        and z.g in ('Capital Centro','Capital Oeste') and z.m3 < 1) = 2 then 1 else 0 end
           as camiones
    from generate_series(p_min, v_hasta, interval '1 day') g2
   where public.gv_es_dia_con_reparto(g2::date);

  -- (1) un dia del plazo donde ya sale SU camion (sin mirar el cupo). Para Z2/Z3 tambien el dia
  --     de la otra zona si las dos quedan < 1 m3 con este pedido adentro.
  select min(dia) into v_d from _gdg_oc
   where dia <= v_lim
     and (tiene_propio
          or (v_otro is not null and m3_otro is not null and m3_otro < 1 and m3_propio + v_m3 < 1));
  if v_d is not null then return v_d; end if;

  -- (2) el ULTIMO dia libre del plazo
  select max(dia) into v_d from _gdg_oc where dia <= v_lim and camiones = 0;
  if v_d is not null then return v_d; end if;

  -- (3) gana el cliente: el dia con menos camiones
  if p_min <= v_lim then
    select dia into v_d from _gdg_oc where dia <= v_lim order by camiones, dia limit 1;
    if v_d is not null then return v_d; end if;
  end if;

  -- (4) ya vencido -> lo antes posible; dentro de los 2 primeros dias con reparto se prefiere
  --     uno donde ya va su camion o libre (el rezagado no se traba).
  select dia into v_d from (select *, row_number() over (order by dia) rn from _gdg_oc) q
   where rn <= 2
   order by (tiene_propio or camiones = 0) desc, dia
   limit 1;
  return coalesce(v_d, p_min);
end
$function$;
revoke all on function public.gv_ppp_web_dia_grupo(text, date, boolean, date, numeric) from anon;

-- armador: le pasa el m3 del pedido (idempotente, sobre la definicion viva)
do $t$ declare d text; begin
  select pg_get_functiondef(p.oid) into d from pg_proc p where proname = 'gv_ppp_web_armar_pendientes';
  if position('v21.95-m3' in d) > 0 then return; end if;
  d := replace(d, 'v_fecha := public.gv_ppp_web_dia_grupo(r.zona, r.entrada, r.expreso, v_min);',
    'v_fecha := public.gv_ppp_web_dia_grupo(r.zona, r.entrada, r.expreso, v_min,
        (select coalesce(sum(case when e->>''m3'' ~ ''^[0-9]+(\.[0-9]+)?$'' then (e->>''m3'')::numeric end), 0)
           from jsonb_array_elements(r.filas) e));  -- v21.95-m3');
  if position('v21.95-m3' in d) = 0 then raise exception 'armador: no matchea la llamada a gv_ppp_web_dia_grupo'; end if;
  execute d;
end $t$;
