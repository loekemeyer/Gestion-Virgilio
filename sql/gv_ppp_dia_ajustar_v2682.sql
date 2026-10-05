-- v26.82 (Luis, 05/10/2026) — POP-UP DE DÍA OCUPADO, opción 2 = «REACOMODAR EN BASE A LO NUEVO».
--
-- Luis: "supongamos que programo un súper para un día que haría que se zarpe en m3 y/o camiones.
--        quiero que el pop up ... me pregunte si quiero programarlo así de todos modos, me diga de
--        correr todo el resto de la programación un día para adelante o si quiero que reprograme
--        automáticamente en base a la programación de ese súper".
--
-- Las opciones 1 (sumarlo) y 3 (correr) ya existían (v21.97, gv_ppp_dia_reprogramar 'correr').
-- La opción 2 ('automatico') sacaba del día TODO lo pendiente, entrara o no. Esta función la reemplaza
-- en el pop-up: lo NUEVO (p_nuevo) queda fijo en p_fecha y del pendiente del día se mueve SÓLO lo que
-- no entra, y siempre de a GRUPO DE ZONAS ENTERO (partirlo = dos camiones para la misma mercadería):
--   1) hasta quedar en jornada_camiones (2). Un súper es su propio camión. Z2+Z3 juntas si c/u < 1 m³.
--   2) hasta quedar en p_cupo m³ (4,30 por defecto, el APR_DO_CUPO del front).
-- Sale primero el grupo que menos apura (el plazo de 14 corridos / expreso 13 más lejano) y va al día
-- que le da el armado (gv_ppp_web_dia_grupo), UNO por grupo. Sin tablas temporales: un día son ~15 tandas.
-- NO se mueven: súper, retira, lo que ya salió, lo EN PROCESO y lo ya armado (todo lo que tiene
-- eventos). p_simular = true no escribe. gv_ppp_dia_reprogramar NO se tocó (su modo 'automatico'
-- queda vivo, sin puerta en el pop-up).
--
-- Rollback: drop function if exists public.gv_ppp_dia_ajustar(date, jsonb, boolean, text, numeric, text);
-- Publicado en el front con la v26.85 (main avanzó a la v26.84 mientras tanto). Los centinelas dicen
-- v26.82: es la versión con que se aplicó en la base, no cambiarla.

create or replace function public.gv_ppp_dia_ajustar(
  p_fecha date,
  p_nuevo jsonb default '[]'::jsonb,
  p_simular boolean default true,
  p_por text default null,
  p_cupo numeric default 4.30,
  p_excluir text default null)
returns table(tanda text, fecha_actual date, fecha_nueva date, accion text, motivo text, m3 numeric,
              zona text, entrada date, vence boolean, es_super boolean)
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
#variable_conflict use_column
declare
  r record;
  v_max int;
  v_n date;
  v_g int;
  v_lim date;
  v_m3 numeric;
  v_cam int;
  v_cand text;
  v_ex text := upper(btrim(coalesce(p_excluir, '')));
  v_t jsonb;                    -- las tandas del día (sin tablas temporales: un día son ~15 filas)
  v_nv jsonb;                   -- lo NUEVO, que queda fijo en el día
  v_out_cam text[] := '{}';     -- tandas que salen para bajar camiones
  v_out_m3 text[] := '{}';      -- tandas que salen para bajar m³
  v_dest jsonb := '{}'::jsonb;  -- grupo que sale -> su día nuevo
  v_d date;
begin
  if not public.gv_es_supervisor_o_servicio() then
    raise exception 'Sólo supervisores pueden reprogramar días.';
  end if;
  if p_fecha is null then raise exception 'Falta el día.'; end if;
  select coalesce(max(c.valor), 2)::int into v_max from public."PPP_Web_Config" c where c.clave = 'jornada_camiones';
  if coalesce(p_cupo, 0) <= 0 then p_cupo := 4.30; end if;

  -- las tandas del día (web + ISIS), mismo criterio que gv_ppp_dia_reprogramar
  with x as (
    select upper(btrim(w.tanda)) t, coalesce(w.zona, '') z, coalesce(w.m3, 0) m3,
           public.gv_es_super(w.empresa, w.cod_cliente) sup,
           coalesce(w.direccion, '') ~* '^\s*exp\.' expr,
           w.fecha_recep ent
      from public."PPP_Web_Programacion" w
     where w.fecha_entrega = p_fecha and coalesce(nullif(btrim(w.tanda), ''), '') <> ''
    union all
    select upper(btrim(i.tanda)), coalesce(i.zona, ''), coalesce(i.m3, 0),
           public.gv_es_super_np(i.np, i.cod) or coalesce(i.tipo, '') = 'KRIKOS', false,
           case when btrim(coalesce(i.fecha_recep, '')) ~ '^\d{4}-\d{2}-\d{2}' then left(btrim(i.fecha_recep), 10)::date end
      from public.gv_ppp_programacion_diaria i
     where btrim(i.fecha_entrega::text) ~ '^\d{4}-\d{2}-\d{2}'
       and left(btrim(i.fecha_entrega::text), 10)::date = p_fecha
       and coalesce(nullif(btrim(i.tanda), ''), '') <> ''),
  _da_t as (
    select x.t, min(x.z) z, sum(x.m3) m3, coalesce(bool_or(x.sup), false) sup,
           coalesce(bool_or(x.z ~* '^\s*retira'), false) ret, coalesce(bool_or(x.expr), false) expr, min(x.ent) ent,
           (select array_agg(distinct r2.opcion) from public."Registros_Produccion_Virgilio" r2
             where upper(btrim(split_part(r2.texto, '|', 1))) = x.t
               and coalesce(btrim(r2.legajo), '') not in ('0', '1')
               and r2.opcion in ('EP','PK','PKC','TP','AP','TAL','TAP','CC','CCN','CRN')) ev
      from x
     where v_ex = '' or x.t <> v_ex
     group by x.t)
  select coalesce(jsonb_agg(jsonb_build_object(
           't', d.t, 'z', d.z, 'm3', d.m3, 'sup', d.sup, 'ret', d.ret, 'expr', d.expr, 'ent', d.ent,
           'salio',   coalesce(d.ev && array['CC','CCN','CRN'], false),
           'proceso', coalesce(d.ev && array['EP','PK','PKC','TP','AP','TAL'] and not (d.ev && array['TAP']), false),
           'conev',   coalesce(cardinality(d.ev), 0) > 0,
           'grp', case when d.sup then 'SUP:' || d.t
                       when d.ret then null
                       else coalesce('Z' || case when (regexp_match(d.z, 'Zona\s*(\d+)', 'i'))[1] in ('6','7') then '6+7'
                                                 else (regexp_match(d.z, 'Zona\s*(\d+)', 'i'))[1] end, '?') end,
           'lim', d.ent + case when d.expr then 13 else 14 end,
           'mov', not d.sup and not d.ret and coalesce(cardinality(d.ev), 0) = 0)), '[]'::jsonb)
    into v_t
    from _da_t d;

  -- lo nuevo: [{zona, m3, super}] — queda fijo en el día. Un súper es su propio camión.
  select coalesce(jsonb_agg(jsonb_build_object('m3', q.m3, 'grp', q.grp)), '[]'::jsonb) into v_nv
    from (select coalesce(nullif(e.v->>'m3', '')::numeric, 0) m3,
                 case when coalesce((e.v->>'super')::boolean, false) then 'SUP:nuevo' || e.o
                      when coalesce(e.v->>'zona', '') ~* '^\s*retira' then null
                      else coalesce('Z' || case when (regexp_match(coalesce(e.v->>'zona', ''), 'Zona\s*(\d+)', 'i'))[1] in ('6','7') then '6+7'
                                                else (regexp_match(coalesce(e.v->>'zona', ''), 'Zona\s*(\d+)', 'i'))[1] end, '?') end grp
            from jsonb_array_elements(case when jsonb_typeof(p_nuevo) = 'array' then p_nuevo else '[]'::jsonb end)
                 with ordinality e(v, o)) q;

  -- Se saca SIEMPRE un grupo de zonas ENTERO (todas sus tandas movibles y sin nada nuevo de ese grupo):
  -- partir un grupo en dos días es sacar dos camiones para la misma mercadería (principio rector).
  --   1) camiones: mientras pase de jornada_camiones, el grupo que menos apura y, a igual apuro, el más chico.
  --   2) m³: mientras pase de p_cupo, el grupo que menos apura y, a igual apuro, el más grande.
  loop
    with s as (select d.grp, d.m3 from jsonb_to_recordset(v_t) d(t text, grp text, m3 numeric)
                where d.grp is not null and not (d.t = any(v_out_cam || v_out_m3))
               union all
               select n.grp, n.m3 from jsonb_to_recordset(v_nv) n(grp text, m3 numeric) where n.grp is not null),
         g as (select s.grp, sum(s.m3) m3 from s group by s.grp)
    select count(*) - case when exists (select 1 from g where g.grp = 'Z2' and g.m3 < 1)
                            and exists (select 1 from g where g.grp = 'Z3' and g.m3 < 1) then 1 else 0 end
      into v_cam from g;
    select coalesce(sum(s.m3), 0) into v_m3
      from (select d.m3 from jsonb_to_recordset(v_t) d(t text, m3 numeric)
             where not (d.t = any(v_out_cam || v_out_m3))
            union all
            select n.m3 from jsonb_to_recordset(v_nv) n(m3 numeric)) s;
    exit when v_cam <= v_max and v_m3 <= p_cupo;
    select q.grp into v_cand
      from (select d.grp, min(d.lim) lim, sum(d.m3) m3, bool_and(d.mov) mov
              from jsonb_to_recordset(v_t) d(t text, grp text, m3 numeric, lim date, mov boolean)
             where d.grp is not null and d.grp not like 'SUP:%' and not (d.t = any(v_out_cam || v_out_m3))
               and not exists (select 1 from jsonb_to_recordset(v_nv) n(grp text) where n.grp = d.grp)
             group by d.grp) q
     where q.mov
     order by q.lim desc nulls first,
              case when v_cam > v_max then q.m3 else -q.m3 end
     limit 1;
    exit when v_cand is null;
    if v_cam > v_max then
      select v_out_cam || coalesce(array_agg(d.t), '{}') into v_out_cam
        from jsonb_to_recordset(v_t) d(t text, grp text) where d.grp = v_cand;
    else
      select v_out_m3 || coalesce(array_agg(d.t), '{}') into v_out_m3
        from jsonb_to_recordset(v_t) d(t text, grp text) where d.grp = v_cand;
    end if;
  end loop;

  -- el día de cada grupo que sale: el del armado (gv_ppp_web_dia_grupo), UNO por grupo, con el plazo de su
  -- tanda más urgente y los m³ del grupo entero, así el grupo no se parte en dos días
  v_n := p_fecha + 1; v_g := 0;
  while not public.gv_es_dia_con_reparto(v_n) and v_g < 15 loop v_n := v_n + 1; v_g := v_g + 1; end loop;
  for r in select d.grp, (array_agg(d.z order by d.lim nulls last))[1] z, (array_agg(d.ent order by d.lim nulls last))[1] ent,
                  (array_agg(d.expr order by d.lim nulls last))[1] expr, sum(d.m3) m3
             from jsonb_to_recordset(v_t) d(t text, grp text, z text, ent date, expr boolean, m3 numeric, lim date)
            where d.t = any(v_out_cam || v_out_m3)
            group by d.grp loop
    v_d := coalesce(public.gv_ppp_web_dia_grupo(r.z, coalesce(r.ent, current_date), coalesce(r.expr, false), v_n, r.m3), v_n);
    if v_d <= p_fecha then v_d := v_n; end if;
    v_dest := v_dest || jsonb_build_object(r.grp, v_d);
  end loop;

  for r in select d.* from jsonb_to_recordset(v_t) d(t text, z text, m3 numeric, sup boolean, ret boolean,
                                                       expr boolean, ent date, salio boolean, proceso boolean, conev boolean, grp text)
            order by (d.t = any(v_out_cam || v_out_m3)) desc, d.t loop
    tanda := r.t; fecha_actual := p_fecha; fecha_nueva := p_fecha; m3 := r.m3; zona := r.z;
    entrada := r.ent; es_super := coalesce(r.sup, false);
    if r.sup then
      accion := 'fijo'; motivo := 'súper: queda en su día';
    elsif r.ret then
      accion := 'fijo'; motivo := 'retira: queda en el día pactado';
    elsif r.salio then
      accion := 'fijo'; motivo := 'ya se cargó / salió';
    elsif r.proceso then
      accion := 'fijo'; motivo := 'en proceso (picking o armado sin terminar): no se toca';
    elsif r.conev then
      accion := 'fijo'; motivo := 'ya armada: no se mueve';
    elsif not (r.t = any(v_out_cam || v_out_m3)) then
      accion := 'queda'; motivo := 'pendiente: entra en el día';
    else
      fecha_nueva := coalesce((v_dest ->> r.grp)::date, v_n);
      accion := 'mueve';
      motivo := case when r.t = any(v_out_cam) then 'pendiente: su grupo no entra (más de ' || v_max || ' camiones)'
                     else 'pendiente: su grupo no entra en los ' || replace(trim(to_char(p_cupo, 'FM990D00')), '.', ',') || ' m³ del día' end;
    end if;
    vence := false;
    if r.ent is not null then
      v_lim := r.ent + case when r.expr then 13 else 14 end; v_g := 0;
      while not public.gv_es_dia_con_reparto(v_lim) and v_g < 15 loop v_lim := v_lim - 1; v_g := v_g + 1; end loop;
      vence := fecha_nueva > v_lim;
    end if;
    if not p_simular and accion = 'mueve' and fecha_nueva <> p_fecha then
      perform public.gv_ppp_tanda_mover(r.t, fecha_nueva, p_por, true, null);   -- lo con eventos ya quedó fijo
    end if;
    return next;
  end loop;
end
$function$;

revoke execute on function public.gv_ppp_dia_ajustar(date, jsonb, boolean, text, numeric, text) from public, anon;
grant execute on function public.gv_ppp_dia_ajustar(date, jsonb, boolean, text, numeric, text) to authenticated, service_role;

-- centinelas: la regla vive en el CÓDIGO
--   1) el corte: lo nuevo queda fijo y se saca hasta entrar en camiones Y en m³
--   2) un destino por GRUPO de zonas (el grupo no se parte en dos días)
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
select v.objeto, 'funcion', v.patron, v.regla, 'Luis', 'v26.82'
  from (values
    ('gv_ppp_dia_ajustar', 'exit when v_cam <= v_max and v_m3 <= p_cupo',
     'opción 2 del pop-up de día ocupado: lo nuevo queda fijo y del pendiente se mueve sólo lo que no entra (camiones y m³)'),
    ('gv_ppp_dia_ajustar', 'v_dest := v_dest \|\| jsonb_build_object\(r\.grp',
     'opción 2 del pop-up: se mueve el GRUPO de zonas entero y a UN día (partirlo = dos camiones para la misma mercadería)')
  ) v(objeto, patron, regla)
 where not exists (select 1 from public."GV_Reglas_Centinela" c where c.objeto = v.objeto and c.patron = v.patron);
