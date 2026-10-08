-- v28.58 (Luis, 08/10/2026): CONTEO DE GÓNDOLA DURANTE EL PICKING → reporte en la landing del admin
-- con ✓ (ajustar la góndola) / ✕ (rechazar).
--
-- El picking ya pedía contar un artículo al azar (evento CG, idea 3798) y sólo avisaba por Telegram.
-- Ahora:
--   * el operario cuenta DESPUÉS de pickear (lo que quedó en la celda) y el CG lleva la tanda:
--     texto = COD|contado||TANDA  (el 3er campo vacío = sin snapshot; formato viejo COD|contado|snap sigue andando)
--   * la diferencia se mide contra la góndola AL MOMENTO DE CONTAR, así lo que pase después no la ensucia:
--       esperado_al_contar = Σ delta terminado con hora efectiva <= hora del conteo
--       hora efectiva de un movimiento 'picking' = el PKC de esa tanda+artículo (el cron escribe la fila
--       minutos después); el picking de la MISMA tanda del conteo cuenta siempre como anterior.
--       dif = contado − esperado_al_contar  (no cambia con movimientos posteriores)
--       contado_hoy = contado + (saldo_hoy − esperado_al_contar)   ← lo que ve el admin (ej. contó 50, se pickearon 30 → 20)
--   * ✓ = ajuste de dif en terminado ('Stock ajustado por conteo durante picking'); ✕ = rechazado. Los dos sacan la fila.
-- Forward-facing: Stock_Config.conteo_picking_desde (los conteos viejos no entran).

create table if not exists public."GV_Conteo_Picking_Resol" (
  client_id   text primary key,
  estado      text not null check (estado in ('ajustado','rechazado')),
  cod         text,
  dif         numeric,
  saldo_antes numeric,
  mov_id      bigint,
  por         text,
  at          timestamptz not null default now()
);
alter table public."GV_Conteo_Picking_Resol" enable row level security;
revoke all on public."GV_Conteo_Picking_Resol" from anon, authenticated;

insert into public."Stock_Config" (clave, valor, actualizado)
values ('conteo_picking_desde', to_char(now(), 'YYYY-MM-DD"T"HH24:MI:SSOF'), now())
on conflict (clave) do nothing;

create or replace function public.gv_conteo_picking_calc(p_cid text)
returns table (client_id text, ts timestamptz, legajo text, cod text, cod_base text, empresa text, tanda text,
               contado numeric, esperado numeric, dif numeric, saldo_hoy numeric, contado_hoy numeric)
language plpgsql stable security definer set search_path = public, pg_temp
as $fn$
declare
  r record; p text[]; v_cod text; v_base text; v_emp text; v_tanda text; v_cont numeric;
  v_esp numeric; v_hoy numeric;
begin
  -- v28.58-conteo-picking
  select * into r from public."Registros_Produccion_Virgilio" x where x.client_id = p_cid and x.opcion = 'CG';
  if not found then return; end if;
  p := string_to_array(r.texto, '|');
  if coalesce(array_length(p, 1), 0) < 2 then return; end if;
  v_cod  := upper(btrim(p[1]));
  v_cont := nullif(btrim(p[2]), '')::numeric;
  if v_cont is null then return; end if;
  v_tanda := upper(nullif(btrim(coalesce(p[4], '')), ''));
  v_emp  := upper(substring(v_cod from '\s+(LK|CH|LOKE)$'));
  v_base := regexp_replace(upper(btrim(regexp_replace(v_cod, '\s+(LK|CH|LOKE)$', ''))), '^0+(?=.)', '');

  with m as (
    select ms.delta, ms.tipo, upper(btrim(split_part(coalesce(ms.ref, ''), '|', 1))) as tref, ms.ts
      from public."Movimientos_Stock" ms
     where regexp_replace(upper(btrim(ms.cod_art)), '^0+(?=.)', '') = v_base
       and ms.deposito = 'terminado'
       and (v_emp is null or upper(coalesce(ms.empresa, '')) = v_emp)
  ), pk as (
    select upper(btrim(split_part(e.texto, '|', 1))) as tref, min(e.ts_cliente) as tpk
      from public."Registros_Produccion_Virgilio" e
     where e.opcion = 'PKC'
       and e.ts_cliente >= r.ts_cliente - interval '2 days'
       and regexp_replace(upper(btrim(split_part(e.texto, '|', 2))), '^0+(?=.)', '') = v_base
     group by 1
  )
  select coalesce(sum(m.delta) filter (where
            case when m.tipo = 'picking' and v_tanda is not null and m.tref = v_tanda then true
                 when m.tipo = 'picking' then coalesce(pk.tpk, m.ts) <= r.ts_cliente
                 else m.ts <= r.ts_cliente end), 0),
         coalesce(sum(m.delta), 0)
    into v_esp, v_hoy
    from m left join pk on pk.tref = m.tref and m.tipo = 'picking';

  client_id := r.client_id; ts := r.ts_cliente; legajo := r.legajo; cod := v_cod; cod_base := v_base;
  empresa := v_emp; tanda := v_tanda; contado := v_cont;
  esperado := round(v_esp); saldo_hoy := round(v_hoy);
  dif := round(v_cont - v_esp);
  contado_hoy := round(v_cont + (v_hoy - v_esp));
  return next;
end
$fn$;
revoke all on function public.gv_conteo_picking_calc(text) from public, anon, authenticated;

create or replace function public.gv_conteo_picking_pendientes()
returns table (client_id text, ts timestamptz, legajo text, nombre text, cod text, empresa text, tanda text,
               gondolas text, contado numeric, esperado numeric, dif numeric, saldo_hoy numeric, contado_hoy numeric)
language plpgsql stable security definer set search_path = public, pg_temp
as $fn$
declare v_desde timestamptz;
begin
  if not public.es_supervisor_virgilio() then raise exception 'SUPERVISOR: hace falta la sesión de supervisor'; end if;
  select nullif(valor, '')::timestamptz into v_desde from public."Stock_Config" where clave = 'conteo_picking_desde';
  return query
  select c.client_id, c.ts, c.legajo,
         (select e."Empleado" from public."Empleados" e where e."Legajo" = c.legajo limit 1)::text,
         c.cod, c.empresa, c.tanda,
         (select string_agg(distinct la.sector, ' · ' order by la.sector) from public.gv_lugar_articulo la
           where la.tipo = 'gondola' and regexp_replace(upper(btrim(la.cod)), '^0+(?=.)', '') = c.cod_base
             and (c.empresa is null or upper(la.empresa) = c.empresa)),
         c.contado, c.esperado, c.dif, c.saldo_hoy, c.contado_hoy
    from public."Registros_Produccion_Virgilio" x
    cross join lateral public.gv_conteo_picking_calc(x.client_id) c
   where x.opcion = 'CG'
     and x.ts_cliente >= coalesce(v_desde, now() - interval '7 days')
     and not public.es_legajo_test(x.legajo)
     and not exists (select 1 from public."GV_Conteo_Picking_Resol" z where z.client_id = x.client_id)
     and abs(c.dif) >= 1
   order by abs(c.dif) desc, c.ts;
end
$fn$;
revoke all on function public.gv_conteo_picking_pendientes() from public, anon;
grant execute on function public.gv_conteo_picking_pendientes() to authenticated;

create or replace function public.gv_conteo_picking_resolver(p_cid text, p_ajustar boolean)
returns jsonb
language plpgsql volatile security definer set search_path = public, pg_temp
as $fn$
declare c record; v_mail text; v_raw text; v_emp text; v_mov bigint; v_nom text; v_delta numeric;
begin
  if not public.es_supervisor_virgilio() then raise exception 'SUPERVISOR: hace falta la sesión de supervisor'; end if;
  perform pg_advisory_xact_lock(hashtext('conteo_picking:' || coalesce(p_cid, '')));
  if exists (select 1 from public."GV_Conteo_Picking_Resol" z where z.client_id = p_cid) then
    return jsonb_build_object('ok', false, 'motivo', 'ya_resuelto');
  end if;
  select * into c from public.gv_conteo_picking_calc(p_cid);
  if c.client_id is null then return jsonb_build_object('ok', false, 'motivo', 'no_existe'); end if;
  v_mail := 'sup:' || coalesce(lower(auth.jwt() ->> 'email'), '?');

  -- la góndola no queda en negativo: si después del conteo salió más de lo contado, se lleva a 0
  v_delta := case when c.saldo_hoy + c.dif < 0 then -greatest(c.saldo_hoy, 0) else c.dif end;
  if p_ajustar and v_delta <> 0 then
    -- la grafía del código como ya está en el libro de stock (más usada), si no la del conteo
    select ms.cod_art into v_raw from public."Movimientos_Stock" ms
     where regexp_replace(upper(btrim(ms.cod_art)), '^0+(?=.)', '') = c.cod_base and ms.deposito = 'terminado'
     group by ms.cod_art order by count(*) desc limit 1;
    v_emp := coalesce(c.empresa, public.gv_empresa_de_articulo(c.cod_base));
    select e."Empleado" into v_nom from public."Empleados" e where e."Legajo" = c.legajo limit 1;
    insert into public."Movimientos_Stock" (ts, cod_art, descripcion, deposito, delta, tipo, ref, legajo, empresa, client_id)
    values (now(), coalesce(v_raw, c.cod_base),
            'Stock ajustado por conteo durante picking (' || coalesce(v_nom, 'legajo ' || c.legajo) || ' contó '
              || c.contado || ' el ' || to_char(c.ts at time zone 'America/Argentina/Buenos_Aires', 'DD/MM HH24:MI')
              || coalesce(' en ' || c.tanda, '') || '; sistema ' || c.esperado || ')',
            'terminado', v_delta, 'ajuste', 'CONTEO PICKING', v_mail, v_emp, 'cgaj_' || p_cid)
    returning id into v_mov;
  end if;

  insert into public."GV_Conteo_Picking_Resol" (client_id, estado, cod, dif, saldo_antes, mov_id, por)
  values (p_cid, case when p_ajustar then 'ajustado' else 'rechazado' end, c.cod, case when p_ajustar then v_delta else c.dif end, c.saldo_hoy, v_mov, v_mail);
  return jsonb_build_object('ok', true, 'estado', case when p_ajustar then 'ajustado' else 'rechazado' end,
                            'dif', v_delta, 'saldo_antes', c.saldo_hoy, 'saldo_despues', c.saldo_hoy + case when p_ajustar then v_delta else 0 end);
end
$fn$;
revoke all on function public.gv_conteo_picking_resolver(text, boolean) from public, anon;
grant execute on function public.gv_conteo_picking_resolver(text, boolean) to authenticated;

-- Telegram: con el formato nuevo (trae la tanda) la diferencia sale de la misma cuenta que el reporte.
create or replace function public.notificar_conteo_gondola_telegram()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  p text[]; cod text; contado numeric; sistema numeric; dif numeric; v_nombre text; base text; msg text; c record;
begin
  if new.opcion <> 'CG' then return new; end if;
  p := string_to_array(new.texto, '|');
  if coalesce(array_length(p,1),0) < 2 then return new; end if;
  cod := btrim(p[1]);
  contado := nullif(btrim(p[2]), '')::numeric;
  if contado is null then return new; end if;

  if coalesce(array_length(p,1),0) >= 4 and nullif(btrim(p[4]), '') is not null then
    -- v28.58: conteo DESPUÉS de pickear → misma cuenta que el reporte del admin (gv_conteo_picking_calc)
    select * into c from public.gv_conteo_picking_calc(new.client_id);
    sistema := c.esperado;
  elsif coalesce(array_length(p,1),0) >= 3 and nullif(btrim(p[3]), '') is not null then
    sistema := round(nullif(btrim(p[3]), '')::numeric);
  else
    base := upper(regexp_replace(regexp_replace(cod, '\s+(LK|CH|LOKE)$', ''), '^0+(.)', '\1'));
    select coalesce(sum(terminado), 0) into sistema
      from public.vista_saldos_stock
     where upper(regexp_replace(regexp_replace(btrim(cod_art), '\s+(LK|CH|LOKE)$', ''), '^0+(.)', '\1')) = base;
    sistema := round(coalesce(sistema, 0));
  end if;
  dif := contado - sistema;

  select "Empleado" into v_nombre from public."Empleados" where "Legajo" = new.legajo limit 1;

  msg := '🔢 CONTEO DE GÓNDOLA — '
      || coalesce(nullif(btrim(coalesce(v_nombre, '')), ''), 'Legajo ' || coalesce(new.legajo, '?'))
      || ' contó hoy ' || round(contado) || ' de ' || cod || '.' || E'\n'
      || 'Sistema: ' || sistema || ' · '
      || case when abs(dif) < 0.5 then '✅ dio IGUAL que el sistema.'
              else '⚠ ' || round(abs(dif)) || ' caja(s) de DIFERENCIA (' || round(contado) || ' contado vs ' || sistema || ' sistema). Se aprueba o rechaza en la landing del admin.' end;

  perform public.tg_enqueue(msg, 'cg_' || coalesce(new.client_id, ''));
  perform public.tg_outbox_flush();
  return new;
exception when others then return new;
end
$function$;

-- Rollback:
--   tabla y funciones nuevas: borrar GV_Conteo_Picking_Resol y las 3 gv_conteo_picking_*;
--   notificar_conteo_gondola_telegram: volver a la definición sin la rama p[4] (backup en el chat de la sesión);
--   un ajuste puntual: insertar el movimiento inverso (ref 'CONTEO PICKING', client_id 'cgaj_<cid>').
