-- v30.37 (Luis, 14/10/2026): "si un pedido sale de cuarentena, que se programe automaticamente
-- siguiendo las reglas establecidas en caso de que sea posible (que no espere ser posicionado
-- manualmente por un humano)".
--
-- Medido antes del cambio: de los 44 aprobados del 24/09 al 14/10 SIN armado, los 44 se
-- programaron solos en <= 5 min (cron 73 del armador). Lo único que esperaba a una persona era
-- el pedido sacado a cuarentena YA ARMADO (v28.45): queda en una tanda nueva SIN DÍA
-- (GV_Cuarentena_Armado) y el cartel decía "asignale el día A MANO".
--
-- Ahora: aprobado ese pedido, gv_cuarentena_armado_auto le busca el día con la MISMA regla del
-- armador en modo grupo (gv_ppp_web_dia_grupo: grupo de zonas por día, plazo, día menos cargado)
-- y lo mueve con gv_cuarentena_armado_asignar_dia (conserva tanda, picking y armado). "Si es
-- posible": súper, zona no automática (Retira, expreso sin zona), sin día o un guard que frena
-- (empresa mezclada, día ocupado...) -> queda como antes, para asignar a mano, con el motivo.
-- Corre: (1) el front la llama apenas se aprueba (cuarLiberarConfirmar) y muestra el resultado;
-- (2) cron cada 10 min: aprobación desde el ✅ del pipeline, herencia de pedido partido o un intento
-- que falló. gv_cuarentena_liberar NO se tocó (tiene centinelas 146/154).

create or replace function public.gv_cuarentena_armado_auto(p_empresa text default null, p_order_id text default null)
returns table(r_empresa text, r_order_id bigint, r_np text, r_resultado text, r_tanda text, r_fecha date, r_detalle text)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  a record; v_zona text; v_exp boolean; v_m3 numeric; v_cod text; v_ent date; v_f date;
  v_t text; v_ff date; v_av text; v_vistos bigint[] := array[]::bigint[];
begin
  -- v30.37-cuar-auto
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede programar un pedido.' using errcode = '42501';
  end if;
  for a in
    select x.* from public."GV_Cuarentena_Armado" x
     where x.cerrado_at is null
       and (p_empresa is null or x.empresa = lower(p_empresa))
       and exists (select 1 from public.gv_cuarentena_liberados_familia lb
                    where lb.empresa = x.empresa
                      and public.gv_cuarentena_clave(lb.order_id) = x.order_id::text)
       and exists (select 1 from public."PPP_Web_Programacion" w
                    where w.empresa = x.empresa and w.order_id = x.order_id
                      and upper(btrim(coalesce(w.tanda, ''))) = upper(x.tanda_nueva)
                      and w.fecha_entrega is null)
     order by x.creado_at
  loop
    v_vistos := v_vistos || a.order_id;
    select min(w.zona), bool_or(coalesce(w.direccion, '') ~* '^\s*exp\.'),
           coalesce(sum(coalesce(w.m3, 0)), 0), min(btrim(w.cod_cliente))
      into v_zona, v_exp, v_m3, v_cod
      from public."PPP_Web_Programacion" w
     where w.empresa = a.empresa and w.order_id = a.order_id
       and upper(btrim(coalesce(w.tanda, ''))) = upper(a.tanda_nueva);
    select min(m.fecha_pedido) into v_ent
      from public.lk_pedidos_match m
     where m.empresa = a.empresa and m.order_id::text = a.order_id::text;
    if public.gv_es_super(a.empresa, v_cod) then
      return query select a.empresa, a.order_id, a.np, 'manual'::text, a.tanda_nueva, null::date,
        'es súper: va con su turno, asignale el día a mano'::text;
      continue;
    end if;
    v_f := public.gv_ppp_web_dia_grupo(v_zona, coalesce(v_ent, current_date), coalesce(v_exp, false),
                                       public.gv_ppp_web_dia_minimo(), v_m3);
    if v_f is null then
      return query select a.empresa, a.order_id, a.np, 'manual'::text, a.tanda_nueva, null::date,
        ('la zona ' || coalesce(v_zona, '(sin zona)') || ' no se programa sola: asignale el día a mano')::text;
      continue;
    end if;
    begin
      select d.tanda, d.fecha, d.aviso into v_t, v_ff, v_av
        from public.gv_cuarentena_armado_asignar_dia(a.empresa, a.order_id::text, v_f,
               'auto: salió de cuarentena') d;
      return query select a.empresa, a.order_id, a.np, 'programado'::text, coalesce(v_t, a.tanda_nueva),
        coalesce(v_ff, v_f), v_av;
    exception when others then
      return query select a.empresa, a.order_id, a.np, 'manual'::text, a.tanda_nueva, null::date,
        ('no se pudo programar solo (' || sqlerrm || '): asignale el día a mano')::text;
    end;
  end loop;
  -- el que pidió por un pedido y ya lo programó otra corrida (p. ej. el cron)
  if p_order_id is not null then
    return query
      select x.empresa, x.order_id, x.np, 'programado'::text, x.tanda_nueva, x.fecha_asignada,
             null::text
        from public."GV_Cuarentena_Armado" x
       where (p_empresa is null or x.empresa = lower(p_empresa))
         and x.order_id::text = public.gv_cuarentena_clave(p_order_id)
         and x.cerrado_at > now() - interval '15 minutes'
         and not (x.order_id = any (v_vistos))
       order by x.cerrado_at desc limit 1;
  end if;
end $function$;

revoke all on function public.gv_cuarentena_armado_auto(text, text) from public, anon;
grant execute on function public.gv_cuarentena_armado_auto(text, text) to authenticated, service_role;

-- red: aprobación heredada (pedido partido) o un intento que falló
select cron.schedule('gv-cuarentena-armado-auto', '*/10 * * * *',
  $c$select public.gv_cuarentena_armado_auto()$c$);

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version, activo)
values
 ('gv_cuarentena_armado_auto', 'funcion', 'gv_ppp_web_dia_grupo',
  'El día del armado que sale de cuarentena lo da la misma regla del armador (grupo de zonas por día)', 'Luis', 'v30.37', true),
 ('gv_cuarentena_armado_auto', 'funcion', 'gv_cuarentena_liberados_familia',
  'Sólo se programa solo lo APROBADO por un humano (fila en Liberados, con herencia de pedido partido)', 'Luis', 'v30.37', true);
