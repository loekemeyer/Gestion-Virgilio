-- ============================================================================
-- v28.45 (Luis, 2026-10-07) — «🐊 SACARLO A CUARENTENA» CON LA TANDA ARMADA
--
-- Luis, textual: "Esperemos a que la tanda entera esté armada. Absolutamente nada en
-- proceso. Claro, la NP tiene que salir sola y viajar con la data" · "que no se imprima
-- papel de cuarentena ni nada" · "que cuando se apruebe, si no tenia nada armado que se
-- programe automaticamente bajo las reglas que hay, si corresponde. Si estaba armado, que
-- se quede y salte un cartel que diga que se tiene que revisar y asignar manualmente".
--
-- LOS TRES CASOS, por el estado de la TANDA entera (gv_ppp_estado_grupo sobre TODAS sus NP):
--   · pendiente  -> como siempre: gv_ppp_web_desprogramar (pierde tanda y día).
--   · proceso    -> NO SE PUEDE (EN_PROCESO): picking o armado empezado sin terminar.
--   · armado / facturado -> las NP del pedido salen solas a una TANDA NUEVA SIN DÍA y llevan
--     su registro (TP + TAP, sus Entregas y su porción de a_facturar): es el mismo
--     movimiento de «📅 Cambiar de día» (gv_ppp_pedido_mover con la fecha centinela, v21.10).
--     Queda anotado en GV_Cuarentena_Armado. La tanda vieja sale sin él: no se entrega dos
--     veces la misma tanda.
--
-- A Programar: el pedido figura (con badge) mientras su tanda nueva siga sin día
-- (gv_cuarentena_armado_lista). Aprobado, NO se programa solo: la persona lo suelta en un
-- día y va por gv_cuarentena_armado_asignar_dia, que mueve la tanda nueva entera con su
-- mismo código (no se vuelve a pickear ni armar).
--
-- Sin papel: no se imprime nada.
-- ============================================================================

create table if not exists public."GV_Cuarentena_Armado" (
  id            bigserial primary key,
  empresa       text not null,
  order_id      bigint not null,
  np            text,
  nps           text[],
  tanda_origen  text,
  tanda_nueva   text not null,
  estado        text,
  por           text,
  persona       text,
  creado_at     timestamptz not null default now(),
  cerrado_at    timestamptz,
  cerrado_por   text,
  fecha_asignada date
);
alter table public."GV_Cuarentena_Armado" enable row level security;
revoke all on public."GV_Cuarentena_Armado" from anon, authenticated;   -- se lee y escribe sólo por las RPC
create unique index if not exists gv_cuarentena_armado_vivo_uq
  on public."GV_Cuarentena_Armado" (empresa, order_id) where cerrado_at is null;

-- ¿en qué estado está la TANDA (entera) de un pedido? ---------------------------
create or replace function public.gv_cuarentena_sacar_chequeo(p_np text)
returns table(estado text, tandas text[], nps text[], order_id bigint, empresa text, texto text)
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_np text := regexp_replace(upper(btrim(coalesce(p_np, ''))), '\.0+$', '');
  v_nps text[]; v_tandas text[]; v_all text[]; v_est text; v_oid bigint; v_emp text;
begin
  -- v28.45-cuar-armado
  select array_agg(x.np), array_agg(distinct x.tanda) filter (where x.tanda <> ''),
         min(x.order_id), min(x.empresa)
    into v_nps, v_tandas, v_oid, v_emp
    from public.gv_ppp_pedido_nps(v_np) x;
  if v_nps is null or v_tandas is null then
    return query select 'sin_tanda'::text, v_tandas, v_nps, v_oid, v_emp,
                        'El pedido no está en ninguna tanda.'::text;
    return;
  end if;
  select array_agg(distinct z.n) into v_all from (
    select upper(btrim(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx))) n
      from public."PPP_Web_Programacion" w where upper(btrim(coalesce(w.tanda, ''))) = any (v_tandas)
    union
    select regexp_replace(upper(btrim(d.np)), '\.0+$', '')
      from public.gv_ppp_programacion_diaria d where upper(btrim(coalesce(d.tanda, ''))) = any (v_tandas)
  ) z;
  v_est := public.gv_ppp_estado_grupo(coalesce(v_all, v_nps));
  return query select v_est, v_tandas, v_nps, v_oid, v_emp,
    case v_est
      when 'pendiente' then 'La tanda ' || array_to_string(v_tandas, ', ') || ' no se empezó: sale de la programación (pierde tanda y día).'
      when 'proceso'   then 'La tanda ' || array_to_string(v_tandas, ', ') || ' está EN PROCESO (picking o armado empezado sin terminar). Hay que esperar a que la tanda entera esté armada.'
      else 'La tanda ' || array_to_string(v_tandas, ', ') || ' está armada: el pedido sale SOLO, con su picking y su armado, a una tanda nueva SIN DÍA.'
    end;
end $function$;
grant execute on function public.gv_cuarentena_sacar_chequeo(text) to anon, authenticated;

-- lo que A Programar tiene que seguir mostrando ---------------------------------
create or replace function public.gv_cuarentena_armado_lista()
returns table(empresa text, order_id bigint, np text, tanda_origen text, tanda_nueva text,
              estado text, creado_at timestamptz)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  -- v28.45-cuar-armado: vivo mientras la tanda nueva siga SIN DÍA
  select a.empresa, a.order_id, a.np, a.tanda_origen, a.tanda_nueva, a.estado, a.creado_at
    from public."GV_Cuarentena_Armado" a
   where a.cerrado_at is null
     and exists (select 1 from public."PPP_Web_Programacion" w
                  where w.empresa = a.empresa and w.order_id = a.order_id
                    and upper(btrim(coalesce(w.tanda, ''))) = upper(a.tanda_nueva)
                    and w.fecha_entrega is null);
$function$;
grant execute on function public.gv_cuarentena_armado_lista() to anon, authenticated;

-- aprobado: se le asigna el día A MANO, con su mismo código -----------------------
create or replace function public.gv_cuarentena_armado_asignar_dia(p_empresa text, p_order_id text,
                                                                   p_fecha date, p_por text default null)
returns table(tanda text, fecha date, aviso text)
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_a public."GV_Cuarentena_Armado"; v_t text; v_f date; v_av text; v_np text;
begin
  -- v28.45-cuar-armado
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede programar un pedido.' using errcode = '42501';
  end if;
  if p_fecha is null then raise exception 'Falta el día.'; end if;
  select * into v_a from public."GV_Cuarentena_Armado" a
   where a.empresa = lower(p_empresa) and a.order_id::text = btrim(p_order_id) and a.cerrado_at is null;
  if v_a.id is null then raise exception 'Ese pedido no está retenido con su armado.'; end if;
  if not exists (select 1 from public.gv_cuarentena_liberados_familia lb
                  where lb.empresa = v_a.empresa
                    and public.gv_cuarentena_clave(lb.order_id) = v_a.order_id::text) then
    raise exception 'CUARENTENA: el pedido % sigue en cuarentena: aprobalo antes de darle día.', v_a.np;
  end if;
  select min(upper(btrim(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx)))) into v_np
    from public."PPP_Web_Programacion" w
   where w.empresa = v_a.empresa and w.order_id = v_a.order_id
     and upper(btrim(coalesce(w.tanda, ''))) = upper(v_a.tanda_nueva);
  if v_np is null then raise exception 'No encontré el pedido en su tanda %.', v_a.tanda_nueva; end if;
  -- la tanda nueva tiene SÓLO este pedido: gv_ppp_pedido_mover la mueve entera con su código
  select m.tanda, m.fecha, m.aviso into v_t, v_f, v_av
    from public.gv_ppp_pedido_mover(v_np, p_fecha, null, coalesce(nullif(btrim(p_por), ''), auth.jwt()->>'email'), false) m;
  update public."GV_Cuarentena_Armado" a
     set cerrado_at = now(), cerrado_por = coalesce(nullif(btrim(p_por), ''), auth.jwt()->>'email'),
         fecha_asignada = p_fecha
   where a.id = v_a.id;
  return query select v_t, v_f, v_av;
end $function$;
grant execute on function public.gv_cuarentena_armado_asignar_dia(text, text, date, text) to authenticated;

-- devolver: los tres casos -------------------------------------------------------
create or replace function public.gv_cuarentena_devolver(p_empresa text, p_np text, p_clave text DEFAULT NULL::text, p_comentario text DEFAULT NULL::text, p_por text DEFAULT NULL::text, p_persona text DEFAULT NULL::text)
 RETURNS TABLE(np_sacadas integer, detalle text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- v17.53 (Luis): la clave se normaliza AL ESCRIBIR (gv_cuarentena_clave), no solo al leer.
declare
  v_np text := btrim(coalesce(p_np,''));
  v_clave text := public.gv_cuarentena_clave(nullif(btrim(coalesce(p_clave, p_np, '')), ''));
  v_quien text; v_persona text; v_n integer := 0; v_det text; v_cod text; v_rs text;
  v_chk record; v_mv record; v_txt text;
begin
  -- v17.20 — "Enviar a → Cuarentena": devolver el pedido a Cuarentena de verdad.
  -- v28.45-cuar-armado (Luis, 07/10): según el estado de la TANDA entera —
  --   pendiente -> sale de la programación (como siempre) · proceso -> NO (EN_PROCESO) ·
  --   armado/facturado -> sus NP salen SOLAS a una tanda nueva SIN DÍA con su registro
  --   (gv_ppp_pedido_mover, v21.10) y queda en GV_Cuarentena_Armado. Sin papel.
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede devolver un pedido a cuarentena.' using errcode='42501';
  end if;
  if v_np = '' then raise exception 'No me pasaste la NP.'; end if;
  v_quien   := nullif(lower(coalesce(nullif(btrim(p_por),''), auth.jwt()->>'email','')),'');
  v_persona := nullif(btrim(p_persona),'');
  if v_persona is null then
    raise exception 'Falta indicar quién devuelve el pedido a cuarentena.' using errcode='22023';
  end if;

  if v_np ~* '^(LK|CH)\s*\d+' then
    select * into v_chk from public.gv_cuarentena_sacar_chequeo(v_np) c;
    if v_chk.estado = 'proceso' then
      raise exception 'EN_PROCESO: %', v_chk.texto using errcode = '23514';
    elsif v_chk.estado in ('armado', 'facturado') then
      select * into v_mv from public.gv_ppp_pedido_mover(v_np, public.gv_ppp_espera_fecha(), null, v_quien, false) m;
      insert into public."GV_Cuarentena_Armado" (empresa, order_id, np, nps, tanda_origen, tanda_nueva, estado, por, persona)
      values (lower(p_empresa), v_chk.order_id, v_np, v_mv.nps, array_to_string(v_chk.tandas, ','),
              v_mv.tanda, v_chk.estado, v_quien, v_persona)
      on conflict (empresa, order_id) where cerrado_at is null do update
         set tanda_nueva = excluded.tanda_nueva, nps = excluded.nps, estado = excluded.estado,
             por = excluded.por, persona = excluded.persona, creado_at = now();
      v_n := coalesce(array_length(v_mv.nps, 1), 0);
      v_det := v_np || ' salió de ' || array_to_string(v_chk.tandas, ',') || ' a la tanda ' || v_mv.tanda
            || ' SIN DÍA, con su picking y su armado. Separá sus cajas del pallet de '
            || array_to_string(v_chk.tandas, ',') || ': ' || array_to_string(v_chk.tandas, ',')
            || ' sale sin este pedido.';
      v_txt := '↩ Vuelto a Cuarentena con su ARMADO: tanda ' || v_mv.tanda || ' sin día (salió de '
            || array_to_string(v_chk.tandas, ',') || ')';
    else
      select w.np_sacadas into v_n from public.gv_ppp_web_desprogramar(v_np, v_quien) w;
      v_det := v_np;
    end if;
  else
    select i.np_sacadas, i.detalle into v_n, v_det
      from public.gv_ppp_isis_desprogramar(array[v_np],
             'vuelta a Cuarentena' || coalesce(': ' || nullif(btrim(p_comentario),''), ''), v_quien) i;
  end if;

  execute replace($q$QQB from public."GV_Cuarentena_Liberados" lb
   where lb.empresa = $1 and public.gv_cuarentena_clave(lb.order_id) = $2$q$, 'QQB', 'de'||'lete')
    using lower(p_empresa), v_clave;

  insert into public."GV_Cuarentena_Comentarios" (empresa, order_id, np, texto, por, persona)
  values (lower(p_empresa), v_clave, v_np,
          coalesce(v_txt, '↩ Vuelto a Cuarentena (sacado de la programación)') ||
          coalesce(': ' || nullif(btrim(p_comentario),''), '.'), v_quien, v_persona);

  select l.cod, l.razon_social into v_cod, v_rs
    from public."GV_Cuarentena_Log" l
   where l.empresa = lower(p_empresa) and public.gv_cuarentena_clave(l.clave) = v_clave
   order by l.at desc, l.id desc limit 1;

  insert into public."GV_Cuarentena_Log" (empresa, clave, np, cod, razon_social, evento, persona, por, comentario)
  values (lower(p_empresa), v_clave, v_np, v_cod, v_rs, 'devuelto', v_persona, v_quien,
          nullif(btrim(p_comentario),''));

  return query select coalesce(v_n,0), coalesce(v_det, v_np);
end;
$function$;
