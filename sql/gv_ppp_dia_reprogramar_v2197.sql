-- v21.97 (Luis, 23/09): pop-up al programar a mano un pedido en un dia que YA tiene programacion.
--   p_modo = 'correr'     -> opcion 3: todo lo programado desde p_fecha se corre 1 dia con reparto.
--   p_modo = 'automatico' -> opcion 2: lo PENDIENTE de p_fecha se reprograma con la logica automatica
--                            (gv_ppp_web_dia_grupo, a partir del dia siguiente).
--   (la opcion 1, "sumarlo", no mueve nada: no pasa por aca)
--   NO se mueven (Luis): los SUPER y los RETIRA ya fijos ese dia (se avisa, se hacen a mano), y una
--   tanda EN PROCESO (pickeo o armado empezado y sin terminar). Armada, facturada o pendiente: se mueve,
--   CON SU MISMO CODIGO (gv_ppp_tanda_mover con p_tanda_destino null: el papel del pallet sigue valiendo).
--   p_simular = true (default) NO escribe: devuelve lo que haria, para el reporte del pop-up.
--   Ejecutando es ATOMICO: si una tanda no se puede mover, no se mueve ninguna.
drop function if exists public.gv_ppp_dia_reprogramar(date, text, boolean, text);
create or replace function public.gv_ppp_dia_reprogramar(p_fecha date, p_modo text, p_simular boolean default true,
                                                         p_por text default null)
returns table(tanda text, fecha_actual date, fecha_nueva date, accion text, motivo text,
              m3 numeric, zona text, entrada date, vence boolean, vencia boolean)
language plpgsql set search_path to 'public', 'pg_temp' as $function$
declare
  r record;
  v_n date;
  v_min date;
  v_lim date;
  v_g int;
begin
  if not public.gv_es_supervisor_o_servicio() then
    raise exception 'Sólo supervisores pueden reprogramar días.';
  end if;
  if p_fecha is null then raise exception 'Falta el día.'; end if;
  if coalesce(p_modo, '') not in ('correr', 'automatico') then raise exception 'Modo inválido: %', p_modo; end if;

  drop table if exists _dr_t;
  create temp table _dr_t on commit drop as
  with x as (
    select upper(btrim(w.tanda)) t, w.fecha_entrega f, coalesce(w.zona, '') z, coalesce(w.m3, 0) m3,
           public.gv_es_super(w.empresa, w.cod_cliente) sup,
           coalesce(w.direccion, '') ~* '^\s*exp\.' expr,
           w.fecha_recep ent
      from public."PPP_Web_Programacion" w
     where w.fecha_entrega >= p_fecha and coalesce(nullif(btrim(w.tanda), ''), '') <> ''
    union all
    select upper(btrim(i.tanda)), left(btrim(i.fecha_entrega::text), 10)::date, coalesce(i.zona, ''), coalesce(i.m3, 0),
           public.gv_es_super_np(i.np, i.cod) or coalesce(i.tipo, '') = 'KRIKOS', false,
           case when btrim(coalesce(i.fecha_recep, '')) ~ '^\d{4}-\d{2}-\d{2}' then left(btrim(i.fecha_recep), 10)::date end
      from public.gv_ppp_programacion_diaria i
     where btrim(i.fecha_entrega::text) ~ '^\d{4}-\d{2}-\d{2}'
       and left(btrim(i.fecha_entrega::text), 10)::date >= p_fecha
       and coalesce(nullif(btrim(i.tanda), ''), '') <> '')
  select x.t, min(x.f) f, min(x.z) z, sum(x.m3) m3, bool_or(x.sup) sup,
         bool_or(x.z ~* '^\s*retira') ret, bool_or(x.expr) expr, min(x.ent) ent,
         (select array_agg(distinct r2.opcion) from public."Registros_Produccion_Virgilio" r2
           where upper(btrim(split_part(r2.texto, '|', 1))) = x.t
             and coalesce(btrim(r2.legajo), '') not in ('0', '1')
             and r2.opcion in ('EP','PK','PKC','TP','AP','TAL','TAP','CC','CCN','CRN')) ev
    from x group by x.t;

  if p_modo = 'automatico' then delete from _dr_t where f <> p_fecha; end if;

  for r in select * from _dr_t order by f desc, t loop
    tanda := r.t; fecha_actual := r.f; m3 := r.m3; zona := r.z; entrada := r.ent; fecha_nueva := r.f;
    if r.sup then
      accion := 'fijo'; motivo := 'súper: queda en su día (moverlo a mano si hace falta)';
    elsif r.ret then
      accion := 'fijo'; motivo := 'retira: queda en el día pactado (moverlo a mano si hace falta)';
    elsif r.ev && array['CC','CCN','CRN'] then
      accion := 'fijo'; motivo := 'ya se cargó / salió';
    elsif r.ev && array['EP','PK','PKC','TP','AP','TAL'] and not (r.ev && array['TAP']) then
      accion := 'fijo'; motivo := 'en proceso (picking o armado sin terminar): no se toca';
    elsif p_modo = 'automatico' and coalesce(cardinality(r.ev), 0) > 0 then
      accion := 'fijo'; motivo := 'ya armada: la lógica automática sólo reprograma lo pendiente';
    else
      -- proximo dia con reparto
      v_n := r.f + 1; v_g := 0;
      while not public.gv_es_dia_con_reparto(v_n) and v_g < 15 loop v_n := v_n + 1; v_g := v_g + 1; end loop;
      if p_modo = 'automatico' then
        fecha_nueva := coalesce(public.gv_ppp_web_dia_grupo(r.z, coalesce(r.ent, current_date), r.expr, v_n, r.m3), v_n);
        if fecha_nueva <= p_fecha then fecha_nueva := v_n; end if;
      else
        fecha_nueva := v_n;
      end if;
      accion := 'mueve';
      motivo := case when r.ev && array['TAP'] then 'armada: se mueve con su mismo código' else 'pendiente' end;
    end if;
    -- vence: plazo = entrada + 14 (expreso + 13), al dia con reparto anterior
    vence := false; vencia := false;
    if r.ent is not null then
      v_lim := r.ent + case when r.expr then 13 else 14 end; v_g := 0;
      while not public.gv_es_dia_con_reparto(v_lim) and v_g < 15 loop v_lim := v_lim - 1; v_g := v_g + 1; end loop;
      vence := fecha_nueva > v_lim; vencia := r.f > v_lim;
    end if;
    if not p_simular and accion = 'mueve' and fecha_nueva <> r.f then
      -- forzar: lo EN PROCESO ya se filtro arriba; lo que queda (armado, anulado, pendiente) se mueve con su codigo
      perform public.gv_ppp_tanda_mover(r.t, fecha_nueva, p_por, true, null);
    end if;
    return next;
  end loop;
end
$function$;
revoke all on function public.gv_ppp_dia_reprogramar(date, text, boolean, text) from anon;
grant execute on function public.gv_ppp_dia_reprogramar(date, text, boolean, text) to authenticated;

-- El trigger que aplicaba la regla DEROGADA "mismo cliente, mismo dia" (frenaba estos movimientos y
-- arrastraba solos los otros pedidos del cliente). Apagado el 23/09. Rollback: enable trigger.
alter table public."PPP_Web_Programacion" disable trigger gv_web_cliente_un_solo_dia;
-- Probado en transaccion abortada (30/09, correr): 21 tandas movidas, 5 fijas; gv_ppp_tanda_dos_dias 0->0,
-- gv_stock_tanda_pickeado_negativo 2->2, gv_ppp_tanda_camion_mezclado 1->1, gv_reglas_perdidas 0->0.
