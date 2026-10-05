-- v26.88 (Luis, 05/10/2026) — POP-UP DE DÍA OCUPADO, opción 2: lo FIJO no se mueve y SIN tope de camiones.
--
-- Luis: "no debería mover los fijos (los programados a mano, supers, retira con fecha)"
--       "olvidate del 2 camiones por día".
--
-- Sobre la v26.82 (sql/gv_ppp_dia_ajustar_v2682.sql), dos cambios:
--   1) lo programado o movido A MANO queda fijo, con el MISMO criterio que el cron de las 18:00
--      (gv_ppp_reprogramar_sin_factura, 'aviso_manual'): una NP web con creado_por <> 'sistema' o
--      gv_manual_por, o un override de ISIS con gv_manual_por. Súper y retira ya eran fijos.
--      Como se saca siempre un GRUPO de zonas entero, un grupo con una tanda fija no sale.
--   2) se borra el corte por camiones (jornada_camiones): del pendiente sale sólo lo que no entra en
--      p_cupo m³ (4,30). Sale primero el grupo que menos apura y, a igual apuro, el más grande.
--
-- Medido el 05/10 sobre lo programado desde hoy: 57 tandas web, 45 a mano (41 creadas por el sistema
-- y movidas desde el panel), 3 súper, 4 retira. Libres para mover: 9 tandas, 6,05 m³.
--
-- Aplicado el 05/10 en la base. Los comentarios DENTRO de la función viva dicen v26.86 (main pasó por la v26.86 y
-- la v26.87 de otra sesión mientras tanto); los centinelas 320 y 324 dicen v26.88, la versión del front.
--
-- Rollback: volver a correr sql/gv_ppp_dia_ajustar_v2682.sql (la función entera) y los dos updates
-- de centinela del final con los valores viejos.

create or replace function public.gv_ppp_dia_ajustar(
  p_fecha date,
  p_nuevo jsonb default '[]'::jsonb,
  p_simular boolean default true,
  p_por text default null,
  p_cupo numeric default 4.30,
  p_excluir text default null)
 returns table(tanda text, fecha_actual date, fecha_nueva date, accion text, motivo text, m3 numeric, zona text,
               entrada date, vence boolean, es_super boolean)
 language plpgsql
 set search_path to 'public', 'pg_temp'
as $function$
#variable_conflict use_column
declare
  r record;
  v_n date;
  v_g int;
  v_lim date;
  v_m3 numeric;
  v_cand text;
  v_ex text := upper(btrim(coalesce(p_excluir, '')));
  v_t jsonb;                    -- las tandas del día (sin tablas temporales: un día son ~15 filas)
  v_nv jsonb;                   -- lo NUEVO, que queda fijo en el día
  v_out text[] := '{}';         -- tandas que salen para bajar m³
  v_dest jsonb := '{}'::jsonb;  -- grupo que sale -> su día nuevo
  v_d date;
begin
  if not public.gv_es_supervisor_o_servicio() then
    raise exception 'Sólo supervisores pueden reprogramar días.';
  end if;
  if p_fecha is null then raise exception 'Falta el día.'; end if;
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
               and r2.opcion in ('EP','PK','PKC','TP','AP','TAL','TAP','CC','CCN','CRN')) ev,
           -- v26.88: programada o movida A MANO (mismo criterio que el cron de las 18:00)
           (exists (select 1 from public."PPP_Web_Programacion" w2
                     where upper(btrim(w2.tanda)) = x.t
                       and (coalesce(w2.creado_por, 'sistema') <> 'sistema' or w2.gv_manual_por is not null))
            or exists (select 1 from public."GV_PPP_Prog_Override" o2
                        where upper(btrim(o2.tanda)) = x.t and o2.gv_manual_por is not null)) man
      from x
     where v_ex = '' or x.t <> v_ex
     group by x.t)
  select coalesce(jsonb_agg(jsonb_build_object(
           't', d.t, 'z', d.z, 'm3', d.m3, 'sup', d.sup, 'ret', d.ret, 'expr', d.expr, 'ent', d.ent, 'man', d.man,
           'salio',   coalesce(d.ev && array['CC','CCN','CRN'], false),
           'proceso', coalesce(d.ev && array['EP','PK','PKC','TP','AP','TAL'] and not (d.ev && array['TAP']), false),
           'conev',   coalesce(cardinality(d.ev), 0) > 0,
           'grp', case when d.sup then 'SUP:' || d.t
                       when d.ret then null
                       else coalesce('Z' || case when (regexp_match(d.z, 'Zona\s*(\d+)', 'i'))[1] in ('6','7') then '6+7'
                                                 else (regexp_match(d.z, 'Zona\s*(\d+)', 'i'))[1] end, '?') end,
           'lim', d.ent + case when d.expr then 13 else 14 end,
           'mov', not d.sup and not d.ret and not d.man and coalesce(cardinality(d.ev), 0) = 0)), '[]'::jsonb)
    into v_t
    from _da_t d;

  -- lo nuevo: [{zona, m3, super}] — queda fijo en el día.
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
  -- v26.88 (Luis: "olvidate del 2 camiones por día"): sólo m³. Mientras pase de p_cupo, sale el grupo que
  -- menos apura y, a igual apuro, el más grande. Un grupo con una tanda fija (a mano, armada…) no sale.
  loop
    select coalesce(sum(s.m3), 0) into v_m3
      from (select d.m3 from jsonb_to_recordset(v_t) d(t text, m3 numeric)
             where not (d.t = any(v_out))
            union all
            select n.m3 from jsonb_to_recordset(v_nv) n(m3 numeric)) s;
    exit when v_m3 <= p_cupo;
    select q.grp into v_cand
      from (select d.grp, min(d.lim) lim, sum(d.m3) m3, bool_and(d.mov) mov
              from jsonb_to_recordset(v_t) d(t text, grp text, m3 numeric, lim date, mov boolean)
             where d.grp is not null and d.grp not like 'SUP:%' and not (d.t = any(v_out))
               and not exists (select 1 from jsonb_to_recordset(v_nv) n(grp text) where n.grp = d.grp)
             group by d.grp) q
     where q.mov
     order by q.lim desc nulls first, q.m3 desc
     limit 1;
    exit when v_cand is null;
    select v_out || coalesce(array_agg(d.t), '{}') into v_out
      from jsonb_to_recordset(v_t) d(t text, grp text) where d.grp = v_cand;
  end loop;

  -- el día de cada grupo que sale: el del armado (gv_ppp_web_dia_grupo), UNO por grupo, con el plazo de su
  -- tanda más urgente y los m³ del grupo entero, así el grupo no se parte en dos días
  v_n := p_fecha + 1; v_g := 0;
  while not public.gv_es_dia_con_reparto(v_n) and v_g < 15 loop v_n := v_n + 1; v_g := v_g + 1; end loop;
  for r in select d.grp, (array_agg(d.z order by d.lim nulls last))[1] z, (array_agg(d.ent order by d.lim nulls last))[1] ent,
                  (array_agg(d.expr order by d.lim nulls last))[1] expr, sum(d.m3) m3
             from jsonb_to_recordset(v_t) d(t text, grp text, z text, ent date, expr boolean, m3 numeric, lim date)
            where d.t = any(v_out)
            group by d.grp loop
    v_d := coalesce(public.gv_ppp_web_dia_grupo(r.z, coalesce(r.ent, current_date), coalesce(r.expr, false), v_n, r.m3), v_n);
    if v_d <= p_fecha then v_d := v_n; end if;
    v_dest := v_dest || jsonb_build_object(r.grp, v_d);
  end loop;

  for r in select d.* from jsonb_to_recordset(v_t) d(t text, z text, m3 numeric, sup boolean, ret boolean, man boolean,
                                                       expr boolean, ent date, salio boolean, proceso boolean, conev boolean, grp text)
            order by (d.t = any(v_out)) desc, d.t loop
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
    elsif r.man then
      accion := 'fijo'; motivo := 'programada o movida a mano: no se mueve';
    elsif not (r.t = any(v_out)) then
      accion := 'queda'; motivo := 'pendiente: entra en el día';
    else
      fecha_nueva := coalesce((v_dest ->> r.grp)::date, v_n);
      accion := 'mueve';
      motivo := 'pendiente: su grupo no entra en los ' || replace(trim(to_char(p_cupo, 'FM990D00')), '.', ',') || ' m³ del día';
    end if;
    vence := false;
    if r.ent is not null then
      v_lim := r.ent + case when r.expr then 13 else 14 end; v_g := 0;
      while not public.gv_es_dia_con_reparto(v_lim) and v_g < 15 loop v_lim := v_lim - 1; v_g := v_g + 1; end loop;
      vence := fecha_nueva > v_lim;
    end if;
    if not p_simular and accion = 'mueve' and fecha_nueva <> p_fecha then
      perform public.gv_ppp_tanda_mover(r.t, fecha_nueva, p_por, true, null);   -- lo fijo ya quedó afuera
    end if;
    return next;
  end loop;
end
$function$;

-- centinelas: el 320 vigilaba el corte por camiones (v_cam), que ya no existe
update public."GV_Reglas_Centinela"
   set patron = 'exit when v_m3 <= p_cupo',
       regla  = 'opción 2 del pop-up de día ocupado: lo nuevo queda fijo y del pendiente se mueve sólo lo que no entra en los m³ del día (sin tope de camiones, Luis 05/10)',
       version = 'v26.88'
 where id = 320;
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
select 'gv_ppp_dia_ajustar', 'funcion', 'not d\.man',
       'opción 2 del pop-up: lo programado o movido a mano no se mueve (además de súper, retira, salido, en proceso y armado)',
       'Luis', 'v26.88'
 where not exists (select 1 from public."GV_Reglas_Centinela" c
                    where c.objeto = 'gv_ppp_dia_ajustar' and c.patron = 'not d\.man');
